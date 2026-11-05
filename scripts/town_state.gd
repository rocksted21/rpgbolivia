extends "res://scripts/world_state.gd"
## A Cidade-Farol: um mapa fixo, sem inimigos, por onde a party anda entre as expedições.
## Os prédios e os moradores dependem de quem já foi resgatado (town_progress.gd).

const Town = preload("res://scripts/town_data.gd")

const TERRAIN_GRASS := 1
const TERRAIN_GRASS_B := 9
const TERRAIN_BUILT := 10
const TERRAIN_WATER := 5
const TERRAIN_STONE := 12
const TERRAIN_ROCK := 6
const BUILDING_GROUND := 138
const PERSON_GROUND := 160
const BEHIND_UNIT := 3

var ground := {}
var floor := {} # o piso que aparece, mesmo embaixo do que bloqueia a casa
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
	start_cell = Town.PLAZA
	var spots := [Town.PLAZA] + Hex.neighbors(Town.PLAZA)
	for i in party.size():
		party[i].pos = spots[i]


func _build_ground() -> void:
	for row in Town.MAP.size():
		var line: String = Town.MAP[row]
		for col in line.length():
			var cell := Vector2i(col, row)
			var mark := line[col]
			if mark == "~":
				continue
			if mark == "#":
				ground[cell] = TERRAIN_ROCK # morro alto ao fundo: só se vê, não se sobe
				levels[cell] = Town.ROCK_LEVEL
			elif mark == "p":
				ground[cell] = TERRAIN_STONE
				levels[cell] = Town.PLAZA_LEVEL
			else:
				ground[cell] = TERRAIN_GRASS if _roll(cell) < 0.5 else TERRAIN_GRASS_B
				levels[cell] = int(mark)
	for road in Town.ROADS:
		for cell in _line(road[0], road[1]):
			if ground.has(cell):
				ground[cell] = TERRAIN_STONE
	for cell in ground:
		floor[cell] = TERRAIN_GRASS if ground[cell] == TERRAIN_ROCK else ground[cell]


func _build_places() -> void:
	for building in Town.BUILDINGS:
		var ready: bool = building.get("needs", "") == "" or building["needs"] in rescued
		for cell in _disc(building["cell"], building["radius"]):
			ground[cell] = TERRAIN_BUILT
		var path: String = (Town.TOWN_ROOT % building["art"]) if ready else Town.RUBBLE
		_put(building["cell"], path, BUILDING_GROUND)
	for decor in Town.DECOR:
		var cell: Vector2i = decor["cell"]
		if ground.has(cell) and ground[cell] != TERRAIN_WATER and decor.get("solid", true):
			ground[cell] = TERRAIN_BUILT
		_put(cell, Town.TOWN_ROOT % decor["art"], PERSON_GROUND, decor.get("offset", 0))
	for person in Town.PEOPLE:
		people[person["cell"]] = person
		if person.get("needs", "") == "" or person["needs"] in rescued:
			ground[person["cell"]] = TERRAIN_BUILT
			_put(person["cell"], Town.TOWN_ROOT % person["art"], PERSON_GROUND)


## Uma casa pode ter mais de um objeto: o prédio, uma tocha na beira e quem mora ali.
func _put(cell: Vector2i, path: String, ground_y: int, offset := 0, depth := BEHIND_UNIT, flip := false) -> void:
	if not props.has(cell):
		props[cell] = []
	props[cell].append({"path": path, "ground_y": ground_y, "depth": depth, "layer": "main", "fixed": true, "offset_x": offset, "flip": flip})


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


func floor_id_at(cell: Vector2i) -> int:
	return floor.get(cell, TERRAIN_WATER)


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


## A cidade é desenhada à mão: não usa as peças de ligação do mapa gerado.
## Só a margem contorna a água. Pedra e grama se encontram numa linha limpa, como na imagem.
func ground_overlays(cell: Vector2i) -> Array:
	var out := []
	if floor_id_at(cell) != TERRAIN_WATER:
		return out
	for dir in 6:
		if floor_id_at(Hex.neighbor(cell, dir)) != TERRAIN_WATER:
			out.append(BiomeArt.ROOT % ["floresta", "margem_%d" % dir])
	return out


## Objetos em pé desta casa. A cidade é toda planejada: fora da planta, só chão.
func art_at(cell: Vector2i) -> Array:
	return props.get(cell, [])


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
