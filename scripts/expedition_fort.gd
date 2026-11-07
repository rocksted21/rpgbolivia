extends RefCounted
## Uma fortificação com seis bastiões, com pátio e acessos pela estrada.
const Hex = preload("res://scripts/hex.gd")
const RADIUS := 7
const LEGACY_RADIUS := 3
const WALL := "res://assets/scenes/garden_wall.png"
const TOWER := "res://assets/town/ilustrado/torre_madeira.png"
const SUPPLIES := "res://assets/scenes/camp_caixas.png"
const KEEP := "res://assets/town/ilustrado/mansao.png"
const BARRACKS := "res://assets/town/ilustrado/abrigo.png"
const FORGE := "res://assets/town/ilustrado/forja.png"
var cells := {}
var center: Vector2i


func place(state) -> void:
	var legacy: bool = state.town_setup.get("fort_layout", 2) == 1
	var radius := LEGACY_RADIUS if legacy else RADIUS
	var reach: Dictionary = state.layout.walk_area()
	var choices := []
	for p in reach:
		var distance := Hex.distance(p, state.start_cell)
		if distance < (9 if legacy else 14) or distance > (38 if legacy else 49):
			continue
		if state.landmarks.keys().any(func(c): return Hex.distance(c, p) <= radius + (2 if legacy else 3)):
			continue
		var score := absi(distance - 17) + (0 if state.gen.is_road(p) else 12)
		choices.append([score, p])
	choices.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for choice in choices:
		if _build(state, choice[1], reach, radius, legacy):
			return
	push_error("Sem espaço acessível para o forte nesta expedição.")


func _build(state, site: Vector2i, before: Dictionary, radius: int, legacy: bool) -> bool:
	var gen = state.gen
	var area: Array = state.area_of(site, radius)
	var height: int = state.elevation_at(site)
	var gates := []
	var corners := []
	for dir in 6:
		var corner := site
		for step in radius:
			corner = Hex.neighbor(corner, dir)
		if not legacy:
			var tip := Hex.neighbor(corner, dir)
			area.append(tip)
			area.append(Hex.neighbor(corner, (dir + 1) % 6))
			area.append(Hex.neighbor(corner, (dir + 5) % 6))
			corner = tip
		corners.append(corner)
	if area.any(func(c): return state.camps.cells.has(c) or state.layout.ridge.has(c)):
		return false
	var perimeter := {}
	for cell in area:
		if Hex.neighbors(cell).any(func(p): return not area.has(p)):
			perimeter[cell] = true
	for cell in area:
		if perimeter.has(cell) and before.has(cell):
			gates.append(cell)
	if gates.is_empty():
		return false
	gates.sort_custom(func(a, b): return Hex.distance(a, state.start_cell) < Hex.distance(b, state.start_cell))
	var interior := {} if legacy else _courtyard(site)
	var original_levels := {}
	var original_terrain := {}
	for cell in area:
		if gen.layout_levels.has(cell):
			original_levels[cell] = gen.layout_levels[cell]
		if gen.layout_terrain.has(cell):
			original_terrain[cell] = gen.layout_terrain[cell]
		var path := ""
		if perimeter.has(cell) and cell != gates[0] and cell != gates.back() and not gen.is_path(cell):
			path = TOWER if corners.has(cell) else WALL
		elif interior.has(cell) and not gen.is_path(cell):
			path = interior[cell]
		elif cell == Hex.neighbor(site, 5):
			path = SUPPLIES
		gen.layout_levels[cell] = height
		gen.layout_terrain[cell] = gen.HOUSE if path in [WALL, TOWER, KEEP, BARRACKS, FORGE] else gen.FIELD_A
		gen.forget(cell)
		cells[cell] = path
	# Uma muralha não pode cortar um caminho para outro ponto da expedição.
	var after: Dictionary = state.layout.walk_area()
	if after.has(site) and (legacy or (cells.values().has(KEEP) and cells.values().count(TOWER) >= 4)) and before.keys().all(func(c): return cells.has(c) or after.has(c)):
		center = site
		state.landmarks[site] = {"kind": "forte", "state": "idle", "guards": [], "hidden": false}
		return true
	for cell in area:
		gen.layout_levels.erase(cell)
		gen.layout_terrain.erase(cell)
		gen.forget(cell)
	gen.layout_levels.merge(original_levels)
	gen.layout_terrain.merge(original_terrain)
	cells.clear()
	return false


## Praça central livre para o combate. A segunda muralha protege a sede ao norte.
func _courtyard(site: Vector2i) -> Dictionary:
	var props := {}
	props[site + Vector2i(0, -5)] = KEEP
	for side in [-1, 1]:
		props[site + Vector2i(2 * side, -3)] = TOWER
		props[site + Vector2i(3 * side, -3)] = WALL
		props[site + Vector2i(4 * side, -3)] = WALL
		props[site + Vector2i(4 * side, 1)] = BARRACKS if side < 0 else FORGE
		props[site + Vector2i(4 * side, 3)] = SUPPLIES
	return props


func art_at(cell: Vector2i, conquered: bool) -> Array:
	var path: String = cells[cell]
	if cell == center:
		path = "res://assets/biomes/comum/bau_aberto.png" if conquered else "res://assets/biomes/comum/bau_fechado.png"
	if path.is_empty():
		return []
	var size := 1.65 if path == WALL else (1.25 if path == TOWER else 1.0)
	if path == KEEP:
		size = 2.15
	return [{"path": path, "scale": size, "flip": path == WALL and cell.x > center.x, "ground_y": 118, "depth": 3, "layer": "main", "fixed": true}]
