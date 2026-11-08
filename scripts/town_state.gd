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
# Pisos só de desenho (o chão que aparece; não muda por onde se anda). A cidade é toda
# calçada: paralelepípedo no bairro, pedra mais escura nas ruas e lajes claras na praça.
const FLOOR_PAVE := 13
const FLOOR_PLAZA := 14
const FLOOR_STREET := 12 # o mesmo id da pedra
const BUILDING_GROUND := 138
const MODEL_GROUND := 107 # centro do hexágono
const PERSON_GROUND := 160
const BEHIND_UNIT := 3

var ground := {}
var floor := {} # o piso que aparece, mesmo embaixo do que bloqueia a casa
var gardens := {} # canteiros de grama em volta das árvores
var levels := {}
var props := {}
var people := {}
var rescued := []
var town_setup := {} # o save refaz a cidade com ele


## `town`: de TownProgress.expedition_setup().
func _init(heroes: Variant, world_seed: int, builds: Variant = {}, town: Dictionary = {}) -> void:
	super(heroes, world_seed, builds)
	town_setup = town.duplicate(true)
	rescued = town.get("rescued", [])
	_build_ground()
	_build_places()
	_paint_floor()
	start_cell = Town.plaza()
	var spots := [start_cell] + Hex.neighbors(start_cell)
	for i in party.size():
		party[i].pos = spots[i]


func _build_ground() -> void:
	var rows: Array = Town.map_rows()
	for row in rows.size():
		var line: String = rows[row]
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
	for cell in Town.road_cells():
		if ground.has(cell):
			ground[cell] = TERRAIN_STONE
	for cell in ground:
		floor[cell] = TERRAIN_GRASS if ground[cell] == TERRAIN_ROCK else ground[cell]


## O piso que aparece: a cidade inteira calçada. Só o morro de pedra ao fundo fica de fora;
## as árvores ganham um canteiro de grama (gardens) por cima da calçada.
func _paint_floor() -> void:
	var rows: Array = Town.map_rows()
	var streets := {}
	for cell in Town.road_cells():
		streets[cell] = true
	for cell in ground:
		if ground[cell] == TERRAIN_ROCK:
			continue
		if rows[cell.y][cell.x] == "p":
			floor[cell] = FLOOR_PLAZA
		elif streets.has(cell):
			floor[cell] = FLOOR_STREET
		else:
			floor[cell] = FLOOR_PAVE
	for tree in Town.trees():
		gardens[tree["cell"]] = true


## Tudo vem de scenes/cidade.tscn (Town.buildings(), trees(), decor(), people()).
func _build_places() -> void:
	for building in Town.buildings():
		var ready: bool = building["needs"] == "" or building["needs"] in rescued
		for cell in _disc(building["cell"], building["radius"]):
			ground[cell] = TERRAIN_BUILT
		if not ready:
			_put(building["cell"], Town.RUBBLE, BUILDING_GROUND)
			continue
		# Desenhos de assets/town/ilustrado têm o pé no centro do hexágono.
		_put_piece(building, MODEL_GROUND if "/ilustrado/" in building["path"] else BUILDING_GROUND)
	for tree in Town.trees():
		if ground.has(tree["cell"]):
			ground[tree["cell"]] = TERRAIN_BUILT
			_put_piece(tree, BUILDING_GROUND)
	for decor in Town.decor():
		var cell: Vector2i = decor["cell"]
		if ground.has(cell) and ground[cell] != TERRAIN_WATER and decor["solid"]:
			ground[cell] = TERRAIN_BUILT
		_put_piece(decor, PERSON_GROUND)
	for person in Town.people():
		people[person["cell"]] = person
		if person["needs"] == "" or person["needs"] in rescued:
			ground[person["cell"]] = TERRAIN_BUILT
			_put_piece(person, PERSON_GROUND)


## Peça da cena: respeita o deslocamento dentro do hexágono, o tamanho e o espelhamento.
func _put_piece(piece: Dictionary, ground_y: int) -> void:
	_put(piece["cell"], piece["path"], ground_y + piece["lift"], piece["offset"], BEHIND_UNIT, piece["flip"])
	var prop: Dictionary = props[piece["cell"]].back()
	prop["scale"] = piece["scale"]
	if piece["art"] in Town.MODEL_DECOR: # o desenho de todos os lados, virado como no editor
		prop["model"] = piece["art"]
		prop["path"] = Town.MODEL_ROOT % piece["art"]
		prop["turn"] = piece.get("turn", 0.0)
		prop["bob"] = piece["art"] == "porto_barco"


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


## Na cidade não há limite de distância: o líder anda sozinho e os outros cuidam da vida.
func may_roam(_unit, _to: Vector2i) -> bool:
	return true


## Põe o líder numa casa (volta da janela da party) e os outros em volta dele.
func place_party_at(cell: Vector2i) -> void:
	if not tile_at(cell)["walkable"]:
		return
	var spots: Array = [cell] + Hex.neighbors(cell) + area_of(cell, 2)
	spots = spots.filter(func(spot): return tile_at(spot)["walkable"])
	var used := []
	for member in party:
		for spot in spots:
			if spot not in used:
				member.pos = spot
				used.append(spot)
				break


func danger() -> int:
	return 0
