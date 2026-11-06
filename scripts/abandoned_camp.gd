extends RefCounted
## Composições de vários hexágonos: acampamento, jardim, santuário e travessia.
## Centros livres e objetos sólidos, sem fechar trilhas, rampas ou gargalos do mapa.

const Hex = preload("res://scripts/hex.gd")
const Art = preload("res://scripts/biome_art.gd")
const ROOT := "res://assets/town/modelos/%s.png"
const THEMES := {
	"camp": {"label": "Acampamento abandonado", "models": ["camp_fogueira", "camp_carroca", "camp_caixas"]},
	"garden": {"label": "Jardim da mansão em ruínas", "models": ["garden_fountain", "garden_gate", "garden_wall"]},
	"shrine": {"label": "Santuário de estrada", "models": ["shrine_candles", "shrine_monument", "shrine_bench"]},
	"crossing": {"label": "Travessia arruinada", "models": ["crossing_markers", "crossing_house", "crossing_pier"]},
}
const PROP_LABELS := {
	"camp_carroca": "Carroça quebrada", "camp_caixas": "Caixas abandonadas",
	"garden_gate": "Portão tomado por hera", "garden_wall": "Muro do jardim",
	"shrine_monument": "Santuário antigo", "shrine_bench": "Banco partido",
	"crossing_house": "Guarita arruinada", "crossing_pier": "Pilar quebrado",
}

var cells := {} # casa: {model, solid, floor}
var centers: Array[Vector2i] = []
var sites := {} # centro: tema; a mesma composição é refeita a partir da semente


func place(state, center: Vector2i, theme := "camp") -> bool:
	if not THEMES.has(theme) or cells.has(center):
		return false
	var gen = state.gen
	var level: int = state.elevation_at(center)
	var area: Array = state.area_of(center, 3)
	var free := {}
	var clearing := []
	for cell in area:
		if gen.walkable(cell):
			free[cell] = true
		var terrain: int = gen.sample(cell)["terrain"]
		if (Hex.distance(cell, center) <= 2 and state.elevation_at(cell) == level
				and not state.landmarks.has(cell) and not cells.has(cell)
				and terrain in [gen.FIELD_A, gen.FIELD_B, gen.FOREST, gen.TREE, gen.ROCKS, gen.HILLS]):
			clearing.append(cell)
			free[cell] = true
	var before := _reachable(center, free, state)
	var protected := {}
	for zone in state.layout.zones:
		var keep: Array = [zone["center"]]
		keep.append_array(zone["ramp"])
		for strip in zone["passages"]:
			keep.append_array(strip)
		for cell in keep:
			protected[cell] = true
			for next in Hex.neighbors(cell):
				protected[next] = true
	var candidates: Array = state.area_of(center, 2).filter(func(cell):
		return (cell != center and before.has(cell) and not gen.is_path(cell)
			and state.elevation_at(cell) == level and not state.landmarks.has(cell)
			and not cells.has(cell) and not protected.has(cell)))
	# A semente varia a posição da carroça; a composição continua igual ao voltar.
	candidates.sort_custom(func(a, b):
		var da := Hex.distance(a, center)
		var db := Hex.distance(b, center)
		return da < db or (da == db and gen._roll(a) < gen._roll(b)))
	var blocked := []
	for cell in candidates:
		free.erase(cell)
		var after := _reachable(center, free, state)
		# Todo acesso que existia continua ligado; cada bloqueio recebe uma volta.
		if after.size() != before.size() - blocked.size() - 1:
			free[cell] = true
			continue
		blocked.append(cell)
		if blocked.size() == 2:
			break
	if blocked.size() != 2 or before.size() < 18:
		return false
	centers.append(center)
	sites[center] = theme
	for cell in clearing:
		_set_prop(state, cell, "", false)
	var models: Array = THEMES[theme]["models"]
	_set_prop(state, center, models[0], false)
	_set_prop(state, blocked[0], models[1], true)
	_set_prop(state, blocked[1], models[2], true)
	return true


func _set_prop(state, cell: Vector2i, model: String, solid: bool) -> void:
	var gen = state.gen
	var floor_id: int = gen.sample(cell)["terrain"]
	if floor_id not in [gen.PATH, gen.ROAD, gen.BRIDGE]:
		floor_id = gen.FIELD_A
	var turn := PI * 0.375 if model.begins_with("garden_") or model.begins_with("shrine_") or model == "crossing_house" else 0.0
	if model == "crossing_markers":
		var links: Array = gen.path_links(cell)
		if not links.is_empty():
			var next: Vector2i = Hex.neighbor(cell, links[0])
			var from := Vector2(cell.x + (cell.y & 1) * 0.5, cell.y * 0.866)
			var to := Vector2(next.x + (next.y & 1) * 0.5, next.y * 0.866)
			turn = (to - from).angle() + PI * 0.5
	cells[cell] = {"model": model, "solid": solid, "floor": floor_id, "turn": turn}
	gen.layout_terrain[cell] = gen.HOUSE if solid else floor_id
	gen.forget(cell)


func label_at(cell: Vector2i) -> String:
	if sites.has(cell):
		return THEMES[sites[cell]]["label"]
	if cells.has(cell):
		return PROP_LABELS.get(cells[cell]["model"], "")
	return ""


func _reachable(center: Vector2i, free: Dictionary, state) -> Dictionary:
	var seen := {center: true}
	var queue := [center]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_back()
		for next in Hex.neighbors(current):
			if not free.has(next) or seen.has(next):
				continue
			if absi(state.elevation_at(next) - state.elevation_at(current)) > 1:
				continue
			seen[next] = true
			queue.append(next)
	return seen


func art_at(cell: Vector2i) -> Array:
	if not cells.has(cell) or cells[cell]["model"] == "":
		return []
	var model: String = cells[cell]["model"]
	return [{"path": "res://assets/scenes/%s.png" % model,
		"ground_y": Art.MIDDLE_Y, "depth": Art.BEHIND_UNIT,
		"layer": "main", "fixed": true}]
