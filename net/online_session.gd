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
## Jogador -> {tipo do herói: [nós]}. Só o dono guarda; a partida usa match_builds().
var player_builds := {}
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
	player_builds.clear()
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
	player_builds = {relay.my_id: HeroProgress.all_builds()}
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
	# Quem entra usa os heróis do dono da sala: níveis, árvore e itens vêm do save dele.
	_send({type = "hello", name = player_name}, true)
	notice = "Aguardando confirmação do dono…"
	changed.emit()

func _send(message: Dictionary, to_host := false) -> void:
	relay.send(1 if to_host else 0, var_to_bytes(message))

func _roster() -> void:
	_send({type = "roster", players = players, owners = owners, picks = picks})
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
	_send({type = "start", owners = owners, players = players, party = party_types, save = SaveGame.capture(state)})
	match_started.emit()

## Só o dono: troca o mapa da partida (cidade -> expedição -> cidade) e manda para todos.
func relocate(new_state) -> void:
	if not playing or not relay.is_master:
		return
	state = new_state
	state.split_fights = true
	revision = 0
	_send({type = "relocate", save = SaveGame.capture(state)})
	relocated.emit()

## Todos os heróis usam a árvore do save do dono da sala: {índice na party: [nós]}.
func match_builds() -> Dictionary:
	var builds := {}
	var saved: Dictionary = player_builds.get(relay.my_id, {})
	for i in party_types.size():
		builds[i] = Skills.sanitize(party_types[i], saved.get(party_types[i], []))
	return builds


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
	_send({type = "start", to = to, owners = owners, players = players, party = party_types, save = SaveGame.capture(state)})


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
		return
	if sender != original_host: return
	match kind:
		"roster":
			players = message.players
			owners = message.owners
			picks = message.get("picks", {})
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
			relocated.emit()
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
		player_builds.erase(id)
		for hero in heroes_of(id): picks.erase(hero)
		for i in owners.size():
			if owners[i] == id: owners[i] = relay.my_id
		_roster()
