extends SceneTree
## Captura reproduzível do acampamento com os heróis e o chão da expedição.
const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const SaveGame = preload("res://scripts/save_game.gd")
var view

func _initialize() -> void:
	HeroProgress.path = "user://test_camp_heroes.cfg"
	TownProgress.path = "user://test_camp_town.cfg"
	root.set_meta("world_hero", Data.DEFAULT_PARTY)
	root.set_meta("load_save", SaveGame.capture(ExpeditionState.new(Data.DEFAULT_PARTY, 77)))
	root.set_meta("expedition", true)
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()

func _run() -> void:
	await process_frame
	while view.busy:
		await process_frame
	var state = view.state
	print("Camps: ", state.camps.centers)
	if state.camps.centers.is_empty():
		quit(1)
		return
	var center: Vector2i = state.camps.centers[0]
	state.steps_until_spawn = 9999.0
	var spots: Array = state.area_of(center, 2).filter(func(cell): return state.gen.walkable(cell) and cell != center)
	spots.sort_custom(func(a, b): return a.y > b.y or (a.y == b.y and a.x < b.x))
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
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	root.get_texture().get_image().save_png(args[0])
	quit()
