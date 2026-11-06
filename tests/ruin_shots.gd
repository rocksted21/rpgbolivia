extends SceneTree
## Capturas dos três cenários novos no mesmo mapa gerado, sem mexer no save do jogador.
const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Expedition = preload("res://scripts/expedition_state.gd")
const Save = preload("res://scripts/save_game.gd")
var view

func _initialize() -> void:
	HeroProgress.path = "user://test_ruin_heroes.cfg"
	TownProgress.path = "user://test_ruin_town.cfg"
	var args := OS.get_cmdline_user_args()
	var world_seed := int(args[1]) if args.size() > 1 else 9
	root.set_meta("load_save", Save.capture(Expedition.new(Data.DEFAULT_PARTY, world_seed)))
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()

func _run() -> void:
	await process_frame
	while view.busy:
		await process_frame
	var state = view.state
	state.steps_until_spawn = 999999.0
	var output: String = OS.get_cmdline_user_args()[0]
	for center in state.camps.sites:
		var theme: String = state.camps.sites[center]
		if theme == "camp":
			continue
		var spots: Array = state.area_of(center, 3).filter(func(cell):
			return state.gen.walkable(cell) and not state.camps.cells.has(cell))
		spots.sort_custom(func(a, b):
			var da: int = state.Hex.distance(a, center)
			var db: int = state.Hex.distance(b, center)
			return da < db or (da == db and a.y > b.y) or (da == db and a.y == b.y and a.x < b.x))
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
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(theme + ".png"))
		print(theme, " ", center)
	quit()
