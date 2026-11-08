extends SceneTree
## Capturas da luz da Cidade-Farol com o progresso: farol, facho e lampiões.
## godot --path . --script tests/town_light_shots.gd -- <pasta> <faróis> <resgatados> [norte]
## "norte" leva a câmera até o farol; sem isso, a captura é na praça.

const Data = preload("res://scripts/game_data.gd")
const TownState = preload("res://scripts/town_state.gd")
const TownData = preload("res://scripts/town_data.gd")
const Save = preload("res://scripts/save_game.gd")
const ORDER := ["ferreiro", "curandeira", "padeira", "cartografa", "arquivista", "alquimista"]
var view
var args: Array


func _initialize() -> void:
	preload("res://scripts/hero_progress.gd").path = "user://test_light_hero.cfg"
	preload("res://scripts/town_progress.gd").path = "user://test_light_town.cfg"
	args = OS.get_cmdline_user_args()
	var setup := {"rescued": ORDER.slice(0, int(args[2])), "beacons": int(args[1])}
	root.set_meta("load_save", Save.capture(TownState.new(Data.DEFAULT_PARTY, 77, {}, setup)))
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()


func _run() -> void:
	for i in 12:
		await process_frame
	var north := args.size() > 3
	if north:
		var beacon: Vector2i = TownData.plaza()
		for building in TownData.buildings():
			if building["art"] == "farol":
				beacon = building["cell"]
		var center: Vector2i = (beacon + TownData.plaza()) / 2
		view._rebase_depth(view._row(center))
		view.board.position = view._camera_target(center)
		view._set_camera(center)
		view._sync_world(center)
	for i in 50:
		await process_frame
	await RenderingServer.frame_post_draw
	var name := "cidade_f%s_r%s%s.png" % [args[1], args[2], "_norte" if north else ""]
	root.get_texture().get_image().save_png("%s/%s" % [args[0], name])
	print("captura ", name, " lampiões acesos: ", view.state.lit_lamps.size(), " de ", TownData.lamps().size())
	quit()
