extends SceneTree
## Salva uma captura de cada bioma, com a casa de resgate e o farol apagado e aceso. Rodar sem --headless:
## godot --path . --script tests/biome_shots.gd -- <pasta-dos-screenshots> [semente]

const Data = preload("res://scripts/game_data.gd")
const Hex = preload("res://scripts/hex.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const TownProgress = preload("res://scripts/town_progress.gd")

var view


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	HeroProgress.path = "user://test_progress_biomes.cfg"
	TownProgress.path = "user://test_town_biomes.cfg"
	root.set_meta("world_hero", Data.DEFAULT_PARTY)
	root.set_meta("expedition", true)
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run(args[0])


func _run(dir: String) -> void:
	await process_frame
	while view.busy:
		await process_frame
	var state = view.state
	state.steps_until_spawn = 9999.0
	state.landmarks.clear()
	for biome in Data.BIOMES:
		var cell = _busiest_cell(state, biome)
		if cell == null:
			print("bioma não encontrado: ", biome)
			continue
		var beacon: Vector2i = cell + Vector2i(3, -3)
		var house: Vector2i = cell + Vector2i(-3, -2)
		state.terrain_override.clear()
		state.terrain_override[beacon] = 11
		state.terrain_override[house] = 10
		state.beacon_cell = beacon
		state.defeated_boss = false
		# Um baú e uma ruína à vista, para conferir a arte dos prêmios.
		var chest: Vector2i = cell + Vector2i(-1, 3)
		var ruin: Vector2i = cell + Vector2i(3, 2)
		state.landmarks.clear()
		state.landmarks[beacon] = {"kind": "farol", "state": "done", "guards": []}
		state.landmarks[chest] = {"kind": "bau", "state": "idle", "guards": []}
		state.landmarks[ruin] = {"kind": "ruina", "state": "idle", "guards": []}
		for member in state.party:
			var i: int = state.party.find(member)
			member.pos = cell + Vector2i(i, 1)
			view.views[member].position = view.feet_of(member.pos)
			view.views[member].z_index = view._z(view._row(member.pos)) + 5
			view.battle_camera.set_elevation(view._cell_elevation(member.pos), view.views[member])
		view.board.position = view._camera_target(cell)
		view._set_camera(cell)
		view._sync_world(cell)
		view._rebuild_cell(beacon)
		view._rebuild_cell(house)
		view._rebuild_cell(chest)
		view._rebuild_cell(ruin)
		view._update_journey()
		await _save(dir, biome)
		state.defeated_boss = true
		view._rebuild_cell(beacon)
		await _save(dir, biome + "_aceso")
		print(biome, " em ", cell)
	DirAccess.remove_absolute(HeroProgress.path)
	DirAccess.remove_absolute(TownProgress.path)
	quit()


func _save(dir: String, shot: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, shot])


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
			if kinds.has(13) and kinds.has(15): # estrada e trilha à vista
				score += 300
			if score > best_score:
				best_score = score
				best = cell
	return best
