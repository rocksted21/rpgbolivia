extends SceneTree
const Data = preload("res://scripts/game_data.gd")
const Town = preload("res://scripts/town_state.gd")
const Save = preload("res://scripts/save_game.gd")
var view

func _initialize() -> void:
	preload("res://scripts/hero_progress.gd").path = "user://test_unified_hero.cfg"
	preload("res://scripts/town_progress.gd").path = "user://test_unified_town.cfg"
	root.set_meta("load_save", Save.capture(Town.new(Data.DEFAULT_PARTY, 77, {}, {"rescued": ["ferreiro", "curandeira"]})))
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()

func _run() -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
