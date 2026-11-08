extends SceneTree
## Integração real: relay Node + duas conexões WebSocket + combate do dono.
const Session = preload("res://net/online_session.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
var host
var guest
var view
var failed := false
var previous_config := ""
var config_existed := false

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failed = true

func _until(predicate: Callable, timeout_ms := 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

func _run() -> void:
	config_existed = FileAccess.file_exists("user://online.cfg")
	if config_existed: previous_config = FileAccess.get_file_as_string("user://online.cfg")
	# Cada lado com o próprio save: o Mago vai para o amigo e leva a build dele.
	HeroProgress.path = "user://test_progress_host.cfg"
	DirAccess.remove_absolute(HeroProgress.path)
	HeroProgress.open_branch("mago", 2) # Magma e Casca nascem trancados: o Orbe abriu
	HeroProgress.open_branch("druida", 2)
	HeroProgress.unlock("mago", "fog_rajada")
	HeroProgress.unlock("druida", "dru_vigor")
	# Mago (3) vai para o amigo e Druida (5) fica com o dono.
	host = root.get_node("OnlineSession")
	host.configure(_relay())
	host.player_name = "Dono"
	guest = Session.new()
	root.add_child(guest)
	guest.configure(_relay())
	guest.player_name = "Amigo"
	host.create_room()
	if not await _until(func(): return host.relay.in_room()):
		_check(false, "criar sala no relay real")
		quit(1)
		return
	_check(true, "criar sala confirmada pelo servidor")
	var listed := []
	guest.relay.room_list_changed.connect(func(rooms): listed.assign(rooms))
	guest.relay.refresh_room_list()
	_check(await _until(func(): return not listed.is_empty()), "sala aparece na listagem HTTP")
	HeroProgress.path = "user://test_progress_guest.cfg"
	DirAccess.remove_absolute(HeroProgress.path)
	HeroProgress.open_branch("mago", 1)
	HeroProgress.unlock("mago", "fog_pavio")
	guest.join_room(host.relay.room_code)
	_check(await _until(func(): return host.players.size() == 2 and guest.players.size() == 2), "entrada e nomes sincronizados")
	var host_id: int = host.relay.my_id
	var guest_id: int = guest.relay.my_id
	host.start_match()
	await _until(func(): return guest.playing, 1500)
	_check(not host.playing and not guest.playing, "não inicia antes de todos escolherem")
	guest.pick_hero(3)
	_check(await _until(func(): return guest.picks.get(3) == guest_id), "amigo escolhe o mago pela rede")
	host.pick_hero(3)
	await _until(func(): return host.picks.get(3) != guest_id, 300)
	_check(host.picks.get(3) == guest_id, "herói de outro jogador não pode ser tomado")
	host.pick_hero(5)
	guest.pick_hero(0)
	guest.pick_hero(0)
	_check(await _until(func(): return guest.picks.get(5) == host_id and not guest.picks.has(0)), "escolher e liberar sincronizam")
	_check(host.can_start(), "todos escolheram: pode iniciar")
	HeroProgress.path = "user://test_progress_host.cfg" # quem inicia é o dono: vale o save dele
	host.start_match()
	_check(await _until(func(): return guest.playing), "início compartilhado")
	_check(host.owners == [guest_id, host_id] and host.owners == guest.owners, "só os heróis escolhidos entram na party")
	_check(host.party_types == ["mago", "druida"] and guest.party_types == host.party_types, "mesma party nos dois lados")
	_check(guest.state.start_cell == host.state.start_cell, "mesma semente, mesmo mapa")
	var host_mage = host.state.party[0]
	var guest_mage = guest.state.party[0]
	_check("rajada_calor" in host_mage.abilities and "rajada_calor" in guest_mage.abilities, "herói do amigo usa a build do mundo do dono")
	_check(not host_mage.passives.has("cast_mult") and not guest_mage.passives.has("cast_mult"), "save do amigo não entra no mundo do dono")
	_check(HeroProgress.path == HeroProgress.GUEST_PATH and HeroProgress.unlocked("mago") == ["fog_rajada"], "amigo vê o nível e a árvore do dono")
	_check(host.state.party[1].max_hp == 32 and guest.state.party[1].max_hp == 32, "build do dono chega ao amigo")
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_check(await _until(func(): return not view.busy), "jornada fica pronta")
	_check(view.exploring and view._free_roam(), "online começa explorando no mapa procedural")
	# Exploração: cada um manda só nos próprios heróis, sem ordem de turno.
	var druid = host.state.party[1]
	var cell: Vector2i = Hex.neighbors(host_mage.pos).filter(func(c): return host.state.can_step(host_mage, c) and host.state.can_step(druid, c) or host.state.can_step(host_mage, c))[0]
	view._network_command(host_id, {kind = "travel", cell = cell, hero = host_mage.uid})
	_check(not view.walk_paths.has(host_mage), "dono não anda com o herói do amigo")
	guest.submit({kind = "travel", cell = cell, hero = guest_mage.uid})
	_check(await _until(func(): return host_mage.pos == cell), "amigo anda pela rede")
	var druid_goal: Vector2i = Hex.neighbors(druid.pos).filter(func(c): return host.state.can_step(druid, c))[0]
	view._network_command(host_id, {kind = "travel", cell = druid_goal, hero = druid.uid})
	_check(await _until(func(): return druid.pos == druid_goal), "dono anda com o próprio herói")
	_check(await _until(func(): return not guest.packets.is_empty() and guest.packets.back().revision == host.revision), "passos chegam ao amigo")
	guest.apply_snapshot(guest.packets.back().snapshot)
	_check(guest.snapshot() == host.snapshot(), "estado igual durante a exploração")
	# Combate: um inimigo aparece, a vez é respeitada e o estado continua igual.
	var foe = host.state.add_unit("mumia", Data.Team.ENEMY, Vector2i(host_mage.pos.x + 4, host_mage.pos.y))
	view._add_unit_view(foe)
	host.state.steps_until_spawn = 99
	view._advance()
	_check(await _until(func(): return host.state.in_combat() and not view.busy), "inimigo vê a party e o combate começa")
	var revision: int = host.revision
	var active = host.state.active_unit()
	var clock: int = active.clock
	var owner: int = host.owner_of(active)
	var other: int = guest.relay.my_id if owner == host.relay.my_id else host.relay.my_id
	view._network_command(other, {kind = "wait", cell = Vector2i(-1, -1), revision = revision})
	_check(active.clock == clock, "recusa comando de quem não controla o herói")
	view._network_command(owner, {kind = "wait", cell = Vector2i(-1, -1), revision = revision - 1})
	_check(active.clock == clock, "recusa comando de turno antigo")
	view._network_command(owner, {kind = "step", cell = Vector2i(9999, 9999), revision = revision})
	_check(active.clock == clock, "recusa destino impossível")
	var guest_acted := false
	for i in 10:
		await _until(func(): return not view.busy)
		if not host.state.in_combat(): break
		active = host.state.active_unit()
		clock = active.clock
		owner = host.owner_of(active)
		if owner == guest.relay.my_id:
			guest.revision = host.revision
			guest.submit({kind = "wait", cell = Vector2i(-1, -1)})
			guest_acted = await _until(func(): return active.clock > clock)
			break
		host.submit({kind = "wait", cell = Vector2i(-1, -1)})
	_check(guest_acted, "amigo envia ação real pela rede e dono a executa")
	await _until(func(): return not view.busy and not guest.packets.is_empty() and guest.packets.back().revision == host.revision)
	guest.apply_snapshot(guest.packets.back().snapshot)
	_check(guest.snapshot() == host.snapshot(), "estado final idêntico após turnos e IA")
	var third = Session.new()
	root.add_child(third)
	third.configure(_relay())
	third.join_room(host.relay.room_code)
	_check(await _until(func(): return third.relay.last_error() != ""), "recusa entrada durante combate")
	third.leave()
	third.queue_free()
	guest.leave()
	_check(await _until(func(): return host.players.size() == 1), "saída do convidado detectada")
	_check(not host.owners.has(guest_id), "heróis do convidado passam ao dono")
	view.queue_free()
	await process_frame
	host.leave()
	guest.queue_free()
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.queue_free()
	await process_frame
	var lobby = load("res://scenes/online_lobby.tscn").instantiate()
	root.add_child(lobby)
	lobby.queue_free()
	host.relay.stop_room_list()
	await process_frame
	print("ONLINE: " + ("FAIL" if failed else "PASS"))
	DirAccess.remove_absolute("user://test_progress_host.cfg")
	DirAccess.remove_absolute("user://test_progress_guest.cfg")
	DirAccess.remove_absolute(HeroProgress.GUEST_PATH)
	if config_existed:
		var file := FileAccess.open("user://online.cfg", FileAccess.WRITE)
		file.store_string(previous_config)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://online.cfg"))
	quit(1 if failed else 0)

## COMBATE_RELAY=wss://combate-tatico-relay.fly.dev testa contra o servidor publicado.
func _relay() -> String:
	var address := OS.get_environment("COMBATE_RELAY")
	return "ws://127.0.0.1:18787" if address.is_empty() else address
