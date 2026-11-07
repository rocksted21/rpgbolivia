extends SceneTree
## Capturas das lanternas do mapa (Tarefa 10b): apagada, área no chão, elite e acesa.
## Rodar sem --headless: godot --path . --script tests/lantern_shots.gd -- <modo> <arquivo.png>
## modo: apagada | area | elite | acesa
const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const SEED := 77
var view


func _initialize() -> void:
	HeroProgress.path = "user://test_lantern_heroes.cfg"
	TownProgress.path = "user://test_lantern_town.cfg"
	var mode: String = OS.get_cmdline_user_args()[0]
	var state = ExpeditionState.new(Data.DEFAULT_PARTY, SEED)
	state.steps_until_spawn = 9999.0
	var lantern: Vector2i = state.lantern_cells()[0]
	if mode == "elite":
		_visit(state, lantern)
	elif mode == "acesa":
		_visit(state, lantern)
		for unit in state.landmarks[lantern]["guards"]:
			state._apply_damage(unit, 99999, [], {})
		state.tick()
	root.set_meta("world_hero", Data.DEFAULT_PARTY)
	root.set_meta("load_save", SaveGame.capture(state))
	root.set_meta("expedition", true)
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run(mode)


func _visit(state, cell: Vector2i) -> void:
	for next in Hex.neighbors(cell):
		if state.tile_at(next)["walkable"]:
			state.hero.pos = next
			break
	state.tick()


func _run(mode: String) -> void:
	await process_frame
	while view.busy:
		await process_frame
	var state = view.state
	state.steps_until_spawn = 9999.0
	var lantern: Vector2i = state.lantern_cells()[0]
	var center := lantern
	if mode == "elite":
		center = state.landmarks[lantern]["guards"][0].pos # a Sentinela no meio da tela
	if mode == "area":
		# a party na beira da área, olhando para dentro
		var target: Dictionary = state.lantern_target(lantern)
		var edge: Array = state.area_of(target["cell"], target["radius"] + 2).filter(func(cell): return state.gen.walkable(cell) and Hex.distance(cell, target["cell"]) == target["radius"] + 1 and Hex.distance(cell, lantern) > 5)
		center = edge[0]
	if mode in ["apagada", "area", "acesa"]:
		# a party um pouco à frente do local, sem pisar nele
		var spots: Array = state.area_of(center, 4).filter(func(cell): return state.gen.walkable(cell) and Hex.distance(cell, center) >= 3 and cell.y > center.y)
		if spots.size() < state.party.size():
			spots = state.area_of(center, 4).filter(func(cell): return state.gen.walkable(cell) and Hex.distance(cell, center) >= 3)
		for i in state.party.size():
			var member = state.party[i]
			member.pos = spots[i]
			view.views[member].position = view.feet_of(member.pos)
			view.views[member].z_index = view._z(view._row(member.pos)) + 5
			view.battle_camera.set_elevation(view._cell_elevation(member.pos), view.views[member])
	view.board.position = view._camera_target(center)
	view._set_camera(center)
	view._sync_world(center)
	view._update_journey()
	for i in 30:
		await process_frame
	print("alvo: ", state.lantern_target(lantern), " câmera: ", view.camera_cell, " marcas: ", view.board_art.area_marks.size(), " radar: ", view.hud.overview_radar.pins.map(func(p): return p.get("spread")))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[1])
	quit()
