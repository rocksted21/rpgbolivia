extends RefCounted
## Protótipo "luta do elevador": a arena pintada (assets/prototipo/arena_elevador.jpg)
## vira uma grade de hexágonos deitada no chão isométrico, e a luta usa as regras de
## sempre (battle_state.gd + ai.gd). Sem nós de cena: a tela é luta_elevador.gd.
##
## Geometria: cada casa tem um ponto no chão (u, v); u anda para cima-direita na tela,
## v para baixo-direita. Tela = origem + (u + v, inclinação * (v - u)).

const BattleState = preload("res://scripts/battle_state.gd")
const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

const ARENA := "res://assets/prototipo/arena_elevador.json"
const FLOOR := 2 # "Pedras"
const BLOCKED := 11 # "Torre": não dá para pisar
const HEX_ROW := 0.866

var data: Dictionary = {}
var origin := Vector2.ZERO
var slope := 0.48
var side := 94.0
var u0 := 0.0
var v0 := 0.0
var cols := 0
var rows := 0
var terrain: Array = []
var elevation: Array = []
var lift_cells: Array[Vector2i] = [] # casas em cima da plataforma do elevador


func _init(path := ARENA) -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	var grid: Dictionary = data["grade"]
	origin = Vector2(grid["origem"][0], grid["origem"][1])
	slope = float(grid["inclinacao"])
	side = float(grid["lado"])
	u0 = float(grid["u0"])
	v0 = float(grid["v0"])
	cols = int(grid["colunas"])
	rows = int(grid["linhas"])
	var open := polygons("chao")
	var closed := polygons("bloqueios")
	var hole := _points(data["elevador"]["buraco"])
	for row in rows:
		var terrain_row := []
		var height_row := []
		for col in cols:
			var cell := Vector2i(col, row)
			var spot := cell_to_screen(cell)
			var floor_ok := _inside_any(spot, open) and not _inside_any(spot, closed)
			terrain_row.append(FLOOR if floor_ok else BLOCKED)
			height_row.append(0)
			if floor_ok and Geometry2D.is_point_in_polygon(spot, hole):
				lift_cells.append(cell)
		terrain.append(terrain_row)
		elevation.append(height_row)


# --- Geometria ---------------------------------------------------------------

## Ponto do chão (u, v) → pixel da imagem.
func ground_to_screen(u: float, v: float) -> Vector2:
	return origin + Vector2(u + v, slope * (v - u))


## Pixel da imagem → ponto do chão (u, v).
func screen_to_ground(spot: Vector2) -> Vector2:
	var d := spot - origin
	var k := d.y / slope
	return Vector2((d.x - k) / 2.0, (d.x + k) / 2.0)


## Centro da casa, no chão: (u, v).
func cell_ground(cell: Vector2i) -> Vector2:
	var fx := cell.x + (cell.y & 1) * 0.5
	return Vector2(u0 + cell.y * HEX_ROW * side, v0 + fx * side)


func cell_to_screen(cell: Vector2i) -> Vector2:
	var g := cell_ground(cell)
	return ground_to_screen(g.x, g.y)


## Os 6 cantos do hexágono, já na tela (encolhidos por `shrink`).
func cell_outline(cell: Vector2i, shrink := 0.94) -> PackedVector2Array:
	var g := cell_ground(cell)
	var radius := side / sqrt(3.0) * shrink
	var out := PackedVector2Array()
	for k in 6:
		var angle := deg_to_rad(30.0 + 60.0 * k)
		out.append(ground_to_screen(g.x + radius * sin(angle), g.y + radius * cos(angle)))
	return out


## Casa debaixo de um pixel da imagem; (-1, -1) se for fora da grade.
func screen_to_cell(spot: Vector2) -> Vector2i:
	var g := screen_to_ground(spot)
	var best := Vector2i(-1, -1)
	var best_distance := side * 0.62
	for row in rows:
		for col in cols:
			var cell := Vector2i(col, row)
			var distance := cell_ground(cell).distance_to(g)
			if distance < best_distance:
				best_distance = distance
				best = cell
	return best


func walkable(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows and terrain[cell.y][cell.x] == FLOOR


# --- Luta ----------------------------------------------------------------------

## Monta a luta: heróis na boca da ponte, inimigos em cima do elevador.
func new_battle() -> BattleState:
	var state := BattleState.new(terrain, elevation)
	for entry in data["herois"]:
		state.add_unit(entry[0], Data.Team.PLAYER, Vector2i(entry[1][0], entry[1][1]))
	for entry in data["inimigos"]:
		state.add_unit(entry[0], Data.Team.ENEMY, Vector2i(entry[1][0], entry[1][1]))
	return state


func bridge_path() -> PackedVector2Array:
	return _points(data["ponte"])


func lift_depth() -> float:
	return float(data["elevador"]["profundidade"])


func polygons(group: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var areas: Dictionary = data.get(group, {})
	var names := areas.keys()
	names.sort() # ordem fixa, não a do Dictionary
	for area_name in names:
		result.append(_points(areas[area_name]))
	return result


static func _points(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for xy in list:
		out.append(Vector2(xy[0], xy[1]))
	return out


static func _inside_any(spot: Vector2, list: Array[PackedVector2Array]) -> bool:
	for polygon in list:
		if Geometry2D.is_point_in_polygon(spot, polygon):
			return true
	return false
