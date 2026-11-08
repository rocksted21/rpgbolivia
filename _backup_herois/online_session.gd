extends Node
## O relay só transporta. O dono valida comandos e simula a exploração e o combate;
## os outros recebem o estado e animam.
signal changed
signal match_started
signal packet_received(packet: Dictionary)
signal command_received(sender: int, command: Dictionary)
signal connection_lost(reason: String)
signal relocated # o dono trocou de mapa (cidade <-> expedição): todos refazem a cena
signal player_arrived(id: int) # alguém entrou com a partida rolando: o dono decide o herói dele
signal progress_received(entry: Dictionary) # XP / level up de um herói de outro jogador
signal hero_learned(type_id: String, node_id: String) # o dono confirmou um nó comprado: todos aplicam
signal world_progress # chegou o nível dos heróis do mundo do dono (quem entrou na sala)

const Relay = preload("res://net/relay_connection.gd")
const WorldState = preload("res://scripts/world_state.gd")
const TownState = preload("res://scripts/town_state.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Data = preload("res://scripts/game_data.gd")
const Skills = preload("res://scripts/skill_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const SaveGame = preload("res://scripts/save_game.gd")
var relay
var player_name := "Jogador"
var players := {}
var owners := []
## Herói (índice em Data.WORLD_HEROES) -> jogador que o escolheu na sala.
var picks := {}
var party_types := [] # a party da partida; owners segue a mesma ordem
## Tipo do herói -> {hero, level, fraction, max, points}: o que o dono de cada herói informou.
var hero_progress := {}
var playing := false
var state
var revision := 0
var packets: Array = []
var notice := ""
var original_host := 0
var pending_state = null # partida já em andamento que vai virar sala (open_existing)

func _process(_delta: float) -> void:
	if original_host != 0 and relay.dropped_code != 0:
		_peer_left(original_host)

func _ready() -> void:
	relay = Relay.new()
	add_child(relay)
	relay.connected_as_host.connect(_host_joined)
	relay.connected_as_client.connect(_client_joined)
	relay.frame_received.connect(_receive)
	relay.peer_left.connect(_peer_left)
	relay.join_failed.connect(func(reason): notice = reason; changed.emit())
	var config := ConfigFile.new()
	if config.load("user://online.cfg") == OK:
		player_name = str(config.get_value("online", "name", "Jogador"))

func configure(address: String) -> bool:
	address = address.strip_edges().trim_suffix("/")
	if not (address.begins_with("ws://") or address.begins_with("wss://")):
		return false
	var host := address.substr(address.find("://") + 3)
	if host.is_empty() or "/" in host:
		return false
	relay.stop_room_list()
	relay.secure = address.begins_with("wss://")
	relay.relay_host = host
	return true

func save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("online", "name", player_name)
	config.save("user://online.cfg")

func server_address() -> String:
	return ("wss://" if relay.secure else "ws://") + relay.relay_host

func create_room() -> void:
	relay.stop_room_list()
	var code := "%06X" % (randi() % 0x1000000)
	relay.join_room(code, true, {build = "combate-tatico", title = "Sala de " + player_name, host_name = player_name})
	notice = "Criando sala…"
	changed.emit()

## A jornada que já está rolando vira sala: o dono controla todos os heróis até alguém entrar.
func open_existing(running_state) -> void:
	pending_state = running_state
	create_room()


func join_room(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.is_empty() or code.length() > 32 or not code.is_valid_identifier():
		# Códigos gerados podem começar por um número.
		if code.is_empty() or code.length() > 32 or not ("R" + code).is_valid_identifier():
			notice = "Código de sala inválido."
			changed.emit()
			return
	relay.stop_room_list()
	relay.join_room(code, false)
	notice = "Entrando na sala…"
	changed.emit()

func leave() -> void:
	relay.leave()
	players.clear()
	owners.clear()
	picks.clear()
	party_types.clear()
	hero_progress.clear()
	HeroProgress.use_own()
	playing = false
	state = null
	packets.clear()
	revision = 0
	original_host = 0
	pending_state = null
	notice = ""
	changed.emit()

func _host_joined() -> void:
	original_host = relay.my_id
	players = {relay.my_id: player_name}
	notice = "Aguardando jogadores."
	if pending_state != null:
		state = pending_state
		pending_state = null
		party_types = state.party.map(func(unit): return unit.type_id)
		owners = []
		for unit in state.party:
			owners.append(relay.my_id) # os heróis vêm primeiro em state.units: owners segue essa ordem
		state.split_fights = true
		revision = 0
		playing = true
		relay.set_props({fase = "Jornada"})
		match_started.emit()
	changed.emit()

func _client_joined() -> void:
	original_host = relay.master_id
	# O mundo é do dono: os heróis usam o nível e a árvore do save dele, não o de quem entra.
	_send({type = "hello", name = player_name}, true)
	notice = "Aguardando confirmação do dono…"
	changed.emit()

func _send(message: Dictionary, to_host := false) -> void:
	relay.send(1 if to_host else 0, var_to_bytes(message))

func _roster() -> void:
	_send({type = "roster", players = players, owners = owners, picks = picks, progress = hero_progress})
	changed.emit()

static func hero_count() -> int:
	return Data.WORLD_HEROES.size()

## Jogadores na ordem de entrada; a mesma ordem decide cores e desempates.
func player_order() -> Array:
	var ids: Array = players.keys()
	ids.sort()
	return ids

func heroes_of(id: int) -> Array:
	var result := []
	for hero in picks:
		if picks[hero] == id: result.append(hero)
	return result

## O dono pode começar sozinho: os heróis que ninguém pegou ficam com ele.
func can_start() -> bool:
	return relay.is_master and not picks.is_empty()

## Só entram na party os heróis escolhidos, na ordem da lista: [índice do herói, ...].
func party_heroes() -> Array:
	var chosen: Array = picks.keys()
	chosen.sort()
	return chosen

## Toque num herói livre o pega; toque num herói seu o libera. O dono decide.
func pick_hero(hero: int) -> void:
	if playing or not relay.in_room(): return
	if relay.is_master:
		_toggle_pick(relay.my_id, hero)
	else:
		_send({type = "pick", hero = hero}, true)

func _toggle_pick(id: int, hero: int) -> void:
	if playing or not players.has(id) or hero < 0 or hero >= hero_count(): return
	if picks.get(hero, 0) == id:
		picks.erase(hero)
	elif not picks.has(hero) and picks.size() < Data.PARTY_SIZE:
		picks[hero] = id
	else:
		return
	_roster()

func start_match() -> void:
	if not relay.is_master or playing or not can_start():
		return
	var heroes := party_heroes()
	party_types = heroes.map(func(hero): return Data.WORLD_HEROES[hero])
	owners = heroes.map(func(hero): return picks[hero])
	var builds := match_builds()
	state = TownState.new(party_types, randi(), builds, TownProgress.expedition_setup()) # começa na cidade, como o solo
	state.split_fights = true
	revision = 0
	playing = true
	relay.set_props({fase = "Jornada"}) # a sala segue aberta: dá para entrar no meio
	_send({type = "start", owners = owners, players = players, party = party_types, save = SaveGame.capture(state), progress = HeroProgress.export_all()})
	match_started.emit()

## Só o dono: troca o mapa da partida (cidade -> expedição -> cidade) e manda para todos.
func relocate(new_state) -> void:
	if not playing or not relay.is_master:
		return
	state = new_state
	state.split_fights = true
	revision = 0
	_send({type = "relocate", save = SaveGame.capture(state), progress = HeroProgress.export_all()})
	relocated.emit()

## Todos os heróis usam a árvore do save do dono da sala: {índice na party: [nós]}.
func match_builds() -> Dictionary:
	var builds := {}
	for i in party_types.size():
		builds[i] = HeroProgress.unlocked(party_types[i])
	return builds


## Dono: manda para a sala o nível e a árvore dos heróis do mundo dele.
func share_progress() -> void:
	if playing and relay.is_master:
		_send({type = "world", progress = HeroProgress.export_all()})


func _owner_of_type(type_id: String) -> int:
	if state == null:
		return 0
	for unit in state.party:
		if unit.type_id == type_id:
			return owner_of(unit)
	return 0


## Comprei um nó num herói meu: o dono confere, aplica e avisa todo mundo.
func learn(type_id: String, node_id: String) -> void:
	if not playing:
		return
	if relay.is_master:
		_confirm_learn(relay.my_id, type_id, node_id)
	else:
		_send({type = "learn", hero = type_id, node = node_id}, true)


## O nó vai para o save do dono: o mundo é dele.
func _confirm_learn(sender: int, type_id: String, node_id: String) -> void:
	if _owner_of_type(type_id) != sender or Skills.locate(type_id, node_id).is_empty():
		return
	if not node_id in HeroProgress.unlocked(type_id) and not HeroProgress.unlock(type_id, node_id):
		share_progress() # os pontos não batem: quem comprou volta a ver o que o dono tem
		return
	share_progress()
	_send({type = "learned", hero = type_id, node = node_id})
	hero_learned.emit(type_id, node_id)


## Nível e XP dos meus heróis, para os outros verem: [{hero, level, fraction, max, points, xp, up}].
func report_progress(entries: Array) -> void:
	if not playing or entries.is_empty():
		return
	for entry in entries:
		hero_progress[entry["hero"]] = entry
	if relay.is_master:
		share_progress() # antes do aviso: quem recebe já mostra o nível novo
		_send({type = "progress", from = relay.my_id, entries = entries})
	else:
		_send({type = "progress", entries = entries}, true)


static func clean_progress(entry: Variant) -> Dictionary:
	if not entry is Dictionary or not entry.get("hero") is String or not Skills.has_tree(entry["hero"]):
		return {}
	return {
		hero = entry["hero"], level = clampi(int(entry.get("level", 1)), 1, 99), fraction = clampf(float(entry.get("fraction", 0.0)), 0.0, 1.0),
		max = bool(entry.get("max", false)), points = clampi(int(entry.get("points", 0)), 0, Skills.MAX_POINTS),
		xp = clampi(int(entry.get("xp", 0)), 0, 100000), up = bool(entry.get("up", false)),
	}


## `sender` 0: veio do dono da sala, já conferido.
func _take_progress(entries: Variant, sender: int) -> Array:
	var accepted := []
	if not entries is Array:
		return accepted
	for raw in entries:
		var entry := clean_progress(raw)
		if entry.is_empty() or (sender != 0 and _owner_of_type(entry["hero"]) != sender):
			continue
		hero_progress[entry["hero"]] = entry
		accepted.append(entry)
		progress_received.emit(entry)
	return accepted


## Dono: passa o herói (índice em state.units) para um jogador da sala.
func assign(unit, id: int) -> void:
	if not relay.is_master or not playing or not players.has(id):
		return
	var index: int = state.units.find(unit)
	if index < 0:
		return
	while owners.size() <= index:
		owners.append(relay.my_id)
	owners[index] = id
	_roster()


## Partida completa para quem entrou no meio: o save do momento refaz tudo do lado de lá.
func _send_match(to: int) -> void:
	_send({type = "start", to = to, owners = owners, players = players, party = party_types, save = SaveGame.capture(state), progress = HeroProgress.export_all()})


## Confere o que veio do dono, para uma mensagem estranha não derrubar o cliente.
static func clean_builds(received: Variant, types: Array) -> Dictionary:
	var builds := {}
	if received is Dictionary:
		for i in received:
			if i is int and i >= 0 and i < types.size():
				builds[i] = Skills.sanitize(types[i], received[i])
	return builds


static func clean_party(received: Variant) -> Array:
	if not received is Array or received.is_empty() or received.size() > Data.PARTY_SIZE:
		return []
	for type_id in received:
		if not type_id in Data.WORLD_HEROES:
			return []
	return received


func owner_of(unit) -> int:
	var index: int = state.units.find(unit)
	return int(owners[index]) if index >= 0 and index < owners.size() else 0

func can_control(unit) -> bool:
	return not playing or owner_of(unit) == relay.my_id

func submit(command: Dictionary) -> void:
	command = command.duplicate()
	command.revision = revision
	if relay.is_master:
		command_received.emit(relay.my_id, command)
	else:
		_send({type = "command", command = command}, true)

func snapshot() -> Dictionary:
	return state.snapshot()

func apply_snapshot(data: Dictionary) -> void:
	state.apply_snapshot(data)

func publish(events: Array = [], ready := false, roam := false) -> void:
	if not playing or not relay.is_master:
		return
	revision += 1
	var encoded := []
	for event in events:
		var copy: Dictionary = event.duplicate()
		for key in ["unit", "target"]:
			if copy.has(key): copy[key] = copy[key].uid
		if copy.has("units"):
			copy["units"] = copy["units"].map(func(unit): return unit.uid)
		encoded.append(copy)
	_send({type = "battle", revision = revision, snapshot = snapshot(), events = encoded, ready = ready, roam = roam})

func _receive(sender: int, payload: PackedByteArray) -> void:
	if payload.size() > 262144: return
	var message: Variant = bytes_to_var(payload)
	if not message is Dictionary: return
	var kind: String = str(message.get("type", ""))
	if relay.is_master:
		if sender not in relay.peer_ids: return
		if kind == "hello" and not players.has(sender):
			players[sender] = str(message.get("name", "Jogador")).strip_edges().left(20)
			if playing:
				_send_match(sender)
				player_arrived.emit(sender)
			_roster()
		elif kind == "pick" and message.get("hero") is int:
			_toggle_pick(sender, message.hero)
		elif kind == "command" and playing and players.has(sender) and message.get("command") is Dictionary:
			command_received.emit(sender, message.command)
		elif kind == "learn" and playing and message.get("hero") is String and message.get("node") is String:
			_confirm_learn(sender, message.hero, message.node)
		elif kind == "progress" and playing:
			var accepted := _take_progress(message.get("entries"), sender)
			if not accepted.is_empty():
				_send({type = "progress", from = sender, entries = accepted})
		return
	if sender != original_host: return
	match kind:
		"roster":
			players = message.players
			owners = message.owners
			picks = message.get("picks", {})
			if message.get("progress") is Dictionary:
				for type_id in message.progress:
					var entry := clean_progress(message.progress[type_id])
					if not entry.is_empty() and _owner_of_type(entry["hero"]) != relay.my_id:
						hero_progress[entry["hero"]] = entry
			changed.emit()
		"start":
			if playing or (message.has("to") and message.get("to") != relay.my_id): return
			var types := clean_party(message.get("party"))
			if types.is_empty(): return
			if message.get("save") is Dictionary: # entrou no meio: a partida chega inteira
				state = SaveGame.restore(message.save)
				if state == null or not "party" in state: return
			elif message.get("world_seed") is int:
				state = WorldState.new(types, message.world_seed, clean_builds(message.get("builds", {}), types))
			else:
				return
			HeroProgress.use_host(message.get("progress"))
			playing = true
			players = message.players
			owners = message.owners
			party_types = types
			state.split_fights = true
			revision = 0
			match_started.emit()
		"relocate":
			if not playing or not message.get("save") is Dictionary: return
			var moved = SaveGame.restore(message.save)
			if moved == null or not "party" in moved: return
			state = moved
			state.split_fights = true
			revision = 0
			if message.has("progress"):
				HeroProgress.use_host(message.progress)
			relocated.emit()
		"world":
			if playing:
				HeroProgress.use_host(message.get("progress"))
				world_progress.emit()
		"learned":
			if playing and message.get("hero") is String and message.get("node") is String:
				hero_learned.emit(message.hero, message.node)
		"progress":
			if playing and message.get("from") != relay.my_id:
				_take_progress(message.get("entries"), 0)
		"battle":
			if playing:
				packets.append(message)
				packet_received.emit(message)

func _peer_left(id: int) -> void:
	if id == original_host or not relay.in_room():
		var reason := "A sala foi encerrada ou a conexão caiu."
		leave()
		notice = reason
		connection_lost.emit(reason)
		return
	if relay.is_master:
		players.erase(id)
		for hero in heroes_of(id): picks.erase(hero)
		for i in owners.size():
			if owners[i] == id: owners[i] = relay.my_id
		_roster()
