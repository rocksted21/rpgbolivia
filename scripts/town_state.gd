extends "res://scripts/world_state.gd"
## A Cidade-Farol: um mapa fixo, sem inimigos, por onde a party anda entre as expedições.
## Os prédios e os moradores dependem de quem já foi resgatado (town_progress.gd).

const Town = preload("res://scripts/town_data.gd")

const TERRAIN_GRASS := 1
const TERRAIN_GRASS_B := 9
const TERRAIN_BUILT := 10
const TERRAIN_WATER := 5
const TERRAIN_STONE := 12
const BUILDING_GROUND := 138
const PERSON_GROUND := 160
const BEHIND_UNIT := 3

var ground := {}
var levels := {}
var props := {}
var people := {}
var rescued := []


## `town`: de TownProgress.expedition_setup().
func _init(heroes: Variant, world_seed: int, builds: Variant = {}, town: Dictionary = {}) -> void:
	super(heroes, world_seed, builds)
	rescued = town.get("rescued", [])
	_build_ground()
	_build_places()
	_relief()
	start_cell = Town.PLAZA
	var spots := [Town.PLAZA] + Hex.neighbors(Town.PLAZA)
	for i in party.size():
		party[i].pos = spots[i]


func _build_ground() -> void:
	for land in Town.LAND:
		for cell in _disc(land[0], land[1]):
			ground[cell] = TERRAIN_GRASS if _roll(cell) < 0.5 else TERRAIN_GRASS_B
			levels[cell] = 1
	for cell in _disc(Town.PLAZA, Town.PLAZA_RADIUS):
		ground[cell] = TERRAIN_STONE
	for road in Town.ROADS:
		for cell in _line(road[0], road[1]):
			ground[cell] = TERRAIN_STONE
	for high in Town.HIGH_GROUND:
		for cell in _disc(high[0], high[1]):
			if ground.has(cell):
				levels[cell] = maxi(levels[cell], high[2])


func _build_places() -> void:
	for building in Town.BUILDINGS:
		var ready: bool = building.get("needs", "") == "" or building["needs"] in rescued
		for cell in _disc(building["cell"], building["radius"]):
			ground[cell] = TERRAIN_BUILT
		var path: String = (Town.TOWN_ROOT % building["art"]) if ready else Town.RUBBLE
		_put(building["cell"], path, BUILDING_GROUND)
	for decor in Town.DECOR:
		if not ground.has(decor["cell"]):
			ground[decor["cell"]] = TERRAIN_WATER
		elif ground[decor["cell"]] != TERRAIN_WATER:
			ground[decor["cell"]] = TERRAIN_BUILT
		_put(decor["cell"], Town.TOWN_ROOT % decor["art"], PERSON_GROUND)
	for cell in Town.HOUSES:
		ground[cell] = TERRAIN_BUILT
		_put(cell, Town.HOUSE_ART, BUILDING_GROUND)
	for i in Town.TREES.size():
		var cell: Vector2i = Town.TREES[i]
		ground[cell] = TERRAIN_BUILT
		_put(cell, Town.TREE_ART % ("a" if i % 2 == 0 else "b"), BUILDING_GROUND)
	for stairs in Town.STAIRS:
		props[stairs["cell"]] = {"path": Town.TOWN_ROOT % stairs["art"], "ground_y": PERSON_GROUND, "depth": 1, "layer": "main", "fixed": true}
	for person in Town.PEOPLE:
		people[person["cell"]] = person
		if person.get("needs", "") == "" or person["needs"] in rescued:
			ground[person["cell"]] = TERRAIN_BUILT
			_put(person["cell"], Town.TOWN_ROOT % person["art"], PERSON_GROUND)


func _put(cell: Vector2i, path: String, ground_y: int) -> void:
	props[cell] = {"path": path, "ground_y": ground_y, "depth": BEHIND_UNIT, "layer": "main", "fixed": true}


## Dois vizinhos nunca diferem mais de um nível: dá para andar por toda a cidade.
func _relief() -> void:
	var changed := true
	while changed:
		changed = false
		for cell in levels:
			var lowest := 99
			for next in Hex.neighbors(cell):
				lowest = mini(lowest, levels.get(next, 0))
			if levels[cell] > lowest + 1:
				levels[cell] = lowest + 1
				changed = true


func _line(from: Vector2i, to: Vector2i) -> Array:
	var out := []
	var a := _flat(from)
	var b := _flat(to)
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps + 1:
		var point: Vector2 = a.lerp(b, float(i) / steps)
		var row := roundi(point.y / 0.866)
		var cell := Vector2i(roundi(point.x - (row & 1) * 0.5), row)
		if cell not in out:
			out.append(cell)
	return out


func _roll(cell: Vector2i) -> float:
	return gen._roll(cell)


# --- Mapa ----------------------------------------------------------------------

func terrain_id_at(cell: Vector2i) -> int:
	return ground.get(cell, TERRAIN_WATER)


func elevation_at(cell: Vector2i) -> int:
	return levels.get(cell, 0)


func biome_at(_cell: Vector2i) -> String:
	return "floresta"


func detail_at(cell: Vector2i) -> float:
	return fmod(_roll(cell) * 97.0, 1.0)


func tile_at(cell: Vector2i) -> Dictionary:
	return Data.TERRAIN[terrain_id_at(cell)]


func tile_name_at(cell: Vector2i) -> String:
	return tile_at(cell)["name"]


## Objetos em pé desta casa. A cidade é toda planejada: fora da planta, só chão.
func art_at(cell: Vector2i) -> Array:
	return [props[cell]] if props.has(cell) else []


# --- Moradores -----------------------------------------------------------------

func is_present(person: Dictionary) -> bool:
	return person.get("needs", "") == "" or person["needs"] in rescued


## Com quem esta casa está perto o bastante para conversar; {} se não há ninguém.
func person_near(cell: Vector2i) -> Dictionary:
	var best := {}
	var best_gap := Town.VISIT_RADIUS + 1
	for spot in people:
		var gap := Hex.distance(cell, spot)
		if gap < best_gap:
			best_gap = gap
			best = people[spot]
	return best


# --- Andamento -----------------------------------------------------------------

func tick() -> Array:
	return [] # na cidade não aparece inimigo


func danger() -> int:
	return 0
