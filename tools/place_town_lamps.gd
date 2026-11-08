extends SceneTree
## Sugere onde pôr os lampiões da Cidade-Farol: casas de chão andável na beira das ruas, longe
## de prédios, árvores, enfeites e moradores, e longe uns dos outros. Imprime as posições na cena.
## Rodar: godot --headless --path . --script tools/place_town_lamps.gd

const Hex = preload("res://scripts/hex.gd")
const Town = preload("res://scripts/town_data.gd")
const SPACING := 5


func _initialize() -> void:
	var scene: Node = load(Town.SCENE).instantiate()
	var ground: TileMapLayer = scene.get_node("Chao")
	var plan: Dictionary = Town.read_scene(scene)
	var roads := {}
	for cell in plan["roads"]:
		roads[cell] = true
	var busy := {}
	for building in plan["buildings"]:
		for cell in _disc(building["cell"], building["radius"] + 1):
			busy[cell] = true
	for group in ["trees", "decor", "people"]:
		for piece in plan[group]:
			for cell in [piece["cell"]] + Hex.neighbors(piece["cell"]):
				busy[cell] = true
	for cell in plan["route"]:
		busy[cell] = true
	for cell in _disc(plan["plaza"], 2):
		busy[cell] = true
	var rows: Array = plan["map"]
	var candidates := []
	for row in rows.size():
		var line: String = rows[row]
		for col in line.length():
			var cell := Vector2i(col, row)
			if line[col] in ["~", "#"] or roads.has(cell) or busy.has(cell):
				continue
			if not Hex.neighbors(cell).any(func(n): return roads.has(n)):
				continue
			candidates.append(cell)
	candidates.sort_custom(func(a, b): return Hex.distance(a, plan["plaza"]) < Hex.distance(b, plan["plaza"]))
	var chosen := []
	for cell in candidates:
		if chosen.all(func(other): return Hex.distance(other, cell) >= SPACING):
			chosen.append(cell)
	for cell in chosen:
		var spot: Vector2 = ground.map_to_local(cell) + ground.position
		print("LAMP %d %d %.1f %.1f" % [cell.x, cell.y, spot.x, spot.y])
	scene.free()
	quit()


func _disc(center: Vector2i, radius: int) -> Array:
	var out := []
	for row in range(center.y - radius, center.y + radius + 1):
		for col in range(center.x - radius - 1, center.x + radius + 2):
			if Hex.distance(Vector2i(col, row), center) <= radius:
				out.append(Vector2i(col, row))
	return out
