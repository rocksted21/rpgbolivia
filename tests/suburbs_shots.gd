extends SceneTree
## Capturas dos Subúrbios Apagados, uma por lugar da planta. Rodar sem --headless:
## godot --path . --script tests/suburbs_shots.gd -- <pasta> [lugar ...]
## Lugares: praca vila jardins labirinto cemiterio cripta parque mercado quartel canal capela usina farol

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const SaveGame = preload("res://scripts/save_game.gd")

const PLACES := {
	"praca": Vector2i(0, -1), "vila": Vector2i(-14, -4), "jardins": Vector2i(14, -4),
	"labirinto": Vector2i(12, -1), "cemiterio": Vector2i(-20, -14), "cripta": Vector2i(-24, -16),
	"parque": Vector2i(-6, -12), "mercado": Vector2i(7, -14), "quartel": Vector2i(21, -14),
	"canal": Vector2i(-2, -20), "capela": Vector2i(-17, -29), "usina": Vector2i(17, -29),
	"farol": Vector2i(0, -30), "avenida": Vector2i(0, -10),
}
var view


func _initialize() -> void:
	HeroProgress.path = "user://test_suburbs_heroes.cfg"
	TownProgress.path = "user://test_suburbs_town.cfg"
	var state = ExpeditionState.new(Data.DEFAULT_PARTY, 7)
	state.steps_until_spawn = 9999.0
	root.set_meta("world_hero", Data.DEFAULT_PARTY)
	root.set_meta("load_save", SaveGame.capture(state))
	root.set_meta("expedition", true)
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()


func _run() -> void:
	await process_frame
	while view.busy:
		await process_frame
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0]
	var names: Array = args.slice(1) if args.size() > 1 else PLACES.keys()
	var state = view.state
	state.steps_until_spawn = 9999.0
	for item in names:
		# "lugar@graus" gira a câmera antes da captura
		var place: String = item.split("@")[0].trim_suffix("+")
		if "+" in item: # todas as lanternas acesas: os lampiões das ruas acendem
			for lantern in state.lantern_cells():
				state.landmarks[lantern]["state"] = "done"
		var degrees := float(item.split("@")[1]) if "@" in item else 0.0
		view.view_target = deg_to_rad(degrees)
		view._set_view_angle(deg_to_rad(degrees))
		var center: Vector2i = PLACES[place]
		var spots: Array = state.area_of(center, 3).filter(func(cell): return state.tile_at(cell)["walkable"] and Hex.distance(cell, center) >= 1)
		spots.sort_custom(func(a, b): return Hex.distance(a, center) < Hex.distance(b, center) or (Hex.distance(a, center) == Hex.distance(b, center) and a < b))
		for i in state.party.size():
			var member = state.party[i]
			member.pos = spots[mini(i * 2, spots.size() - 1)]
			view.views[member].position = view.feet_of(member.pos)
			view.views[member].z_index = view._z(view._row(member.pos)) + 5
			view.battle_camera.set_elevation(view._cell_elevation(member.pos), view.views[member])
		view._rebase_depth(view._row(center))
		view.board.position = view._camera_target(center)
		view._set_camera(center)
		view._sync_world(center)
		if "+" in item:
			for cell in state.gen.lamps.keys() + state.lantern_cells():
				view.board_art._rebuild_cell(cell)
		view._update_journey()
		for i in 40:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, item.replace("@", "_").replace("+", "_acesa")])
		print("captura: ", place, " ", center, " ", state.tile_name_at(center))
	quit()
