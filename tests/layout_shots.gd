extends SceneTree
## Salva capturas de passagens e platôs de um mapa de expedição. Rodar sem --headless:
## godot --path . --script tests/layout_shots.gd -- <pasta-dos-screenshots>

const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const TownProgress = preload("res://scripts/town_progress.gd")

var view


func _initialize() -> void:
	HeroProgress.path = "user://test_progress_layout.cfg"
	TownProgress.path = "user://test_town_layout.cfg"
	root.set_meta("world_hero", Data.DEFAULT_PARTY)
	root.set_meta("expedition", true)
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run(OS.get_cmdline_user_args()[0])


func _run(dir: String) -> void:
	await process_frame
	while view.busy:
		await process_frame
	var state = view.state
	state.steps_until_spawn = 9999.0
	var taken := 0
	for zone in state.layout.zones:
		if taken >= 3:
			break
		if not zone["passages"].is_empty():
			var strip: Array = zone["passages"][0]
			await _shot(dir, "passagem_%d" % taken, strip[strip.size() / 2])
		if not zone["ramp"].is_empty():
			await _shot(dir, "plato_%d" % taken, zone["ramp"][-1])
		taken += 1
	DirAccess.remove_absolute(HeroProgress.path)
	DirAccess.remove_absolute(TownProgress.path)
	quit()


func _shot(dir: String, name: String, cell: Vector2i) -> void:
	var state = view.state
	var spots: Array = [cell] + preload("res://scripts/hex.gd").neighbors(cell).filter(func(next): return state.gen.walkable(next))
	for i in state.party.size():
		var member = state.party[i]
		member.pos = spots[mini(i, spots.size() - 1)]
		view.views[member].position = view.feet_of(member.pos)
		view.views[member].z_index = view._z(view._row(member.pos)) + 5
		view.battle_camera.set_elevation(view._cell_elevation(member.pos), view.views[member])
	view.board.position = view._camera_target(cell)
	view._set_camera(cell)
	view._sync_world(cell)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, name])
