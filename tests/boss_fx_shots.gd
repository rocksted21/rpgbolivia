extends SceneTree
## Captura os efeitos dos chefes (BOSS_FX) na luta padrão. Rodar sem --headless:
## godot --path . --script tests/boss_fx_shots.gd -- <pasta>

const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

var view
var dir := ""


func _initialize() -> void:
	dir = OS.get_cmdline_user_args()[0]
	HeroProgress.path = "user://test_progress_fx.cfg"
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()


func _run() -> void:
	for i in 30:
		await process_frame
	var target = view.state.units[0]
	var feet: Vector2 = view.views[target].position
	for boss in view.BOSS_FX:
		for kind in ["hit", "skill"]:
			view._play_boss_fx(view.BOSS_FX[boss][kind], feet)
			for i in 9:
				await process_frame
			root.get_texture().get_image().save_png("%s/fx_%s_%s.png" % [dir, boss, kind])
			for i in 70:
				await process_frame
	quit()
