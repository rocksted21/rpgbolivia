extends SceneTree
## Joga uma expedição pela tela de verdade e salva capturas. Rodar sem --headless:
## godot --path . --script tests/expedition_smoke.gd -- <pasta-das-capturas>

const Hex = preload("res://scripts/hex.gd")
const AI = preload("res://scripts/ai.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")

const TIMEOUT_SECONDS := 240.0

var view
var dir := ""
var failed := false


func _initialize() -> void:
	dir = OS.get_cmdline_user_args()[0]
	# Uma partida de teste não pode mexer no save de verdade.
	HeroProgress.path = "user://test_progress_expedition.cfg"
	TownProgress.path = "user://test_town_smoke.cfg"
	DirAccess.remove_absolute(HeroProgress.path)
	DirAccess.remove_absolute(TownProgress.path)
	create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(func():
		print("TIMEOUT")
		quit(2))
	_run()


func _expect(ok: bool, text: String) -> void:
	if not ok:
		failed = true
		print("FALHOU: ", text)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])


func _wait_frames(count: int) -> void:
	for i in count:
		await process_frame


func _idle() -> void:
	await process_frame
	var guard := 0
	while (view.busy or not view.walk_paths.is_empty() or not view.moving.is_empty()) and view.state.winner() < 0 and guard < 6000:
		await process_frame
		guard += 1


func _open_town() -> Node:
	var scene: Node = load("res://scenes/town.tscn").instantiate()
	root.add_child(scene)
	await _wait_frames(5)
	return scene


func _run() -> void:
	var town := await _open_town()
	await _shot("1_cidade_inicio")
	_expect(town.party.size() == 4, "cidade começa com party montada")
	_expect(town.start_button.text.contains("4 de 4"), "botão mostra a party")
	town.free()

	root.set_meta("world_hero", ["guardiao", "duelista", "mago", "druida"])
	root.set_meta("expedition", true)
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	await _idle()
	await _wait_frames(30)
	var state = view.state
	_expect(state.has_method("result"), "a cena abre uma expedição")
	await _shot("2_inicio_expedicao")
	_expect(view.hud.objective.text.contains("Farol"), "a bússola aponta o farol")

	# Ruínas: marca no mapa, recompensa e a marca some.
	var ruin: Variant = _cell_of(state, "ruina")
	await _bring_party(state, ruin, 3)
	await _wait_frames(30)
	await _shot("3_marca_no_mapa")
	_expect(view.landmark_nodes.has(ruin), "as ruínas têm marca no mapa")
	await _bring_party(state, ruin, 1)
	view._perform([])
	await _idle()
	await _shot("4_ruinas")
	_expect(state.landmarks[ruin]["state"] == "done", "visitar ruínas funciona pela tela")
	_expect(not view.landmark_nodes.has(ruin), "a marca some depois da visita")
	_expect(state.brasas > 0, "ganhou brasas")

	var memory: Variant = _cell_of(state, "memoria")
	await _bring_party(state, memory, 1)
	view._perform([])
	await _idle()
	await _wait_frames(4)
	await _shot("5_memoria")
	_expect(state.memories.size() == 1, "encontrou a memória")

	# Vila: luta contra os guardas até o resgate.
	var village: Variant = _cell_of(state, "vila")
	await _bring_party(state, village, 1)
	view._perform([])
	await _idle()
	await _wait_frames(4)
	await _shot("6_vila_atacada")
	_expect(state.in_combat(), "a vila começa um combate")
	await _fight(state)
	await _shot("7_vila_salva")
	_expect(not state.rescued.is_empty(), "a vila resgatou um morador")

	# Farol: o chefe e a vitória.
	await _bring_party(state, state.beacon_cell, 2)
	await _wait_frames(10)
	await _shot("8_farol")
	view._perform([])
	await _idle()
	await _wait_frames(10)
	await _shot("9_chefe")
	_expect(state.boss != null and view.views.has(state.boss), "o chefe aparece na tela")
	_expect(state.in_combat(), "o chefe começa o combate")
	# Duas ações reais contra o chefe e depois encurta a luta: testa a tela, não o equilíbrio.
	for i in 2:
		await _one_action(state)
	state.boss.hp = 1
	for member in state.alive_party():
		member.hp = member.max_hp
	await _fight(state)
	var waited := 0
	while not view.hud.end_panel.visible and waited < 2000:
		await process_frame
		waited += 1
	await _wait_frames(4)
	await _shot("10_vitoria")
	_expect(state.winner() == view.Data.Team.PLAYER, "derrotar o chefe vence")
	_expect(view.hud.end_panel.visible, "tela de fim aparece")
	_expect(view.hud.end_label.text.contains("farol"), "o fim fala do farol")
	_expect(TownProgress.beacons() == 1 and TownProgress.brasas() > 0, "o resultado foi salvo")
	_expect(not TownProgress.rescued().is_empty(), "o morador foi salvo na cidade")
	view.queue_free()
	await _wait_frames(3)

	town = await _open_town()
	await _shot("11_cidade_depois")
	_expect(town.status.text.contains("Faróis acesos: 1"), "a cidade mostra o farol")
	var resident: String = TownProgress.rescued()[0]
	var before := TownProgress.brasas()
	TownProgress.record({"won": false, "brasas": 100, "rescued": [], "memories": 0})
	town._refresh()
	await _wait_frames(2)
	_expect(TownProgress.buy(resident), "dá para comprar a melhoria")
	_expect(TownProgress.brasas() < before + 100, "a melhoria cobra brasas")
	print("Expedição: ", "FALHOU" if failed else "OK")
	DirAccess.remove_absolute(HeroProgress.path)
	DirAccess.remove_absolute(TownProgress.path)
	quit(1 if failed else 0)


func _cell_of(state, kind: String) -> Variant:
	for cell in state.landmarks:
		if state.landmarks[cell]["kind"] == kind:
			return cell
	return null


## Leva a party para perto de um local sem andar o caminho todo.
func _bring_party(state, cell: Vector2i, gap: int) -> void:
	for unit in state.foes():
		if not state.engaged.has(unit):
			state.units.erase(unit)
			view._remove_view(unit)
	state.steps_until_spawn = 999.0
	var ring: Array = state.area_of(cell, gap + 2).filter(func(spot):
		return state.tile_at(spot)["walkable"] and Hex.distance(spot, cell) >= gap and state.unit_at(spot) == null)
	ring.sort_custom(func(a, b): return Hex.distance(a, cell) < Hex.distance(b, cell))
	for i in state.party.size():
		var member = state.party[i]
		member.pos = ring[i]
		view.views[member].position = view.feet_of(member.pos)
		view.views[member].z_index = view._z(view._row(member.pos)) + 5
		view.battle_camera.set_elevation(view._cell_elevation(member.pos), view.views[member])
	view._follow(view.selected)
	view._sync_world(view.camera_cell)
	view._update_journey()
	await process_frame


func _one_action(state) -> void:
	var hero = state.active_unit()
	var action: Dictionary = AI.decide(state, hero)
	if action["kind"] == "ability":
		view._perform(state.do_ability(hero, action["id"], action["cell"]))
	elif action["kind"] == "step":
		view._perform(state.do_step(hero, action["cell"]))
	else:
		view._perform(state.do_wait(hero))
	await _idle()


func _fight(state) -> void:
	var actions := 0
	while state.in_combat() and state.winner() < 0 and actions < 300:
		actions += 1
		for member in state.alive_party():
			member.hp = member.max_hp # aqui a luta só precisa terminar
		await _one_action(state)
	await _idle()
