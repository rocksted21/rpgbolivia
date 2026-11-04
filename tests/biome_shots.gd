extends SceneTree
## Salva uma captura de cada bioma e de cada tipo de terreno nele. Rodar sem --headless:
## godot --path . --script tests/biome_shots.gd -- <pasta-dos-screenshots> [semente]

const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

var view


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	HeroProgress.path = "user://test_progress_biomes.cfg"
	root.set_meta("world_hero", "duelista")
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run(args[0])


func _run(dir: String) -> void:
	await process_frame
	while view.busy:
		await process_frame
	var state = view.state
	for biome in Data.BIOMES:
		var cell = _busiest_cell(state, biome)
		if cell == null:
			print("bioma não encontrado: ", biome)
			continue
		state.hero.pos = cell
		view.views[state.hero].position = view.feet_of(cell)
		view.battle_camera.set_elevation(view._cell_elevation(cell), view.views[state.hero])
		view.board.position = view._camera_target(cell)
		view._set_camera(cell)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, biome])
		print(biome, " em ", cell)
	quit()


## A casa caminhável do bioma com mais variedade de terreno em volta.
func _busiest_cell(state, biome: String):
	var best = null
	var best_score := -1
	for row in range(-160, 160, 3):
		for col in range(-160, 160, 3):
			var cell := Vector2i(col, row)
			if state.biome_at(cell) != biome or not state.tile_at(cell)["walkable"]:
				continue
			var kinds := {}
			var inside := 0
			for dy in range(-5, 6):
				for dx in range(-5, 6):
					var near := cell + Vector2i(dx, dy)
					inside += 1 if state.biome_at(near) == biome else 0
					kinds[state.terrain_id_at(near)] = true
			var score: int = kinds.size() * 40 + inside
			if score > best_score:
				best_score = score
				best = cell
	return best
