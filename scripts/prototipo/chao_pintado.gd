extends RefCounted
## Protótipo "cenário pintado": onde dá para pisar numa imagem inteira.
## As áreas ficam em assets/prototipo/areas.json (polígonos em pixels da imagem):
## "chao" e "ligacoes" (escadas) somam, "bloqueios" tiram. Sem nós de cena.

const AREAS := "res://assets/prototipo/areas.json"
const CELL := 8 # tamanho da casinha invisível do caminho, em pixels da imagem

var data: Dictionary = {}
var grid := AStarGrid2D.new()
var image_size := Vector2i(2000, 1116)


func _init(path := AREAS) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	grid.region = Rect2i(0, 0, image_size.x / CELL + 1, image_size.y / CELL + 1)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var open := _polygons("chao") + _polygons("ligacoes")
	var closed := _polygons("bloqueios")
	for y in grid.region.size.y:
		for x in grid.region.size.x:
			var spot := Vector2(x * CELL, y * CELL)
			grid.set_point_solid(Vector2i(x, y), not (_inside_any(spot, open) and not _inside_any(spot, closed)))


func _polygons(group: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var areas: Dictionary = data.get(group, {})
	var names := areas.keys()
	names.sort() # ordem fixa, não a do Dictionary
	for area_name in names:
		var points := PackedVector2Array()
		for xy in areas[area_name]:
			points.append(Vector2(xy[0], xy[1]))
		result.append(points)
	return result


static func _inside_any(spot: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(spot, polygon):
			return true
	return false


func cell_of(spot: Vector2) -> Vector2i:
	return Vector2i(roundi(spot.x / CELL), roundi(spot.y / CELL))


func walkable(spot: Vector2) -> bool:
	var cell := cell_of(spot)
	return grid.is_in_boundsv(cell) and not grid.is_point_solid(cell)


## Casa livre mais perto de `spot` (para um clique na parede virar um passo até ela).
func nearest_walkable(spot: Vector2, reach := 12) -> Vector2:
	var center := cell_of(spot)
	var best := Vector2(-1, -1)
	var best_distance := INF
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := center + Vector2i(dx, dy)
			if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell) and Vector2(dx, dy).length() < best_distance:
				best_distance = Vector2(dx, dy).length()
				best = Vector2(cell * CELL)
	return best


## Caminho em pixels da imagem; vazio se não há caminho.
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not walkable(from) or not walkable(to):
		return PackedVector2Array()
	return grid.get_point_path(cell_of(from), cell_of(to))


## Ponto inicial dos heróis (centro da praça da esquerda).
func start_spot() -> Vector2:
	return nearest_walkable(Vector2(470, 560))
