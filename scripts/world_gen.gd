extends RefCounted
## Gera o terreno infinito. A mesma semente e a mesma casa dão sempre o mesmo resultado,
## então o mapa não precisa ser guardado: voltar por um caminho mostra o mesmo lugar.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

const FIELD_A := 1
const FIELD_B := 9
const ROCKS := 2
const FOREST := 3
const WATER := 5
const MOUNTAIN := 6
const HILLS := 7
const HOUSE := 10
const TOWER := 11
const MAX_LEVEL := 3
const START_CLEARING := 2 # raio sem obstáculos em volta do início
# Entortar as coordenadas tira das manchas o desenho do ruído: bordas de bioma, rios e serras ficam orgânicos.
const WARP := 7.0
const BIOME_COLD := -0.17
const BIOME_HOT := 0.14 # entre neve e deserto sempre há outro bioma
const BIOME_BORDER := 0.018 # só um pouco de irregularidade na fronteira
const LEVEL_OFFSET := 0.3
const LEVEL_STEP := 0.2 # platôs largos: o relevo sobe em degraus, sem casas soltas
const RIVER_WIDTH := 0.016
const FORD_LIMIT := 0.12 # acima disso o rio dá passagem; ele nunca corta o mundo em dois
const RANGE_START := 0.5 # serra: o miolo é montanha, a beira vira colinas e pedras
const RANGE_BAND := 0.08
const PASS_LIMIT := 0.28 # as serras têm desfiladeiros por onde passar
const FOREST_EDGE := 0.05 # na borda, as árvores rareiam em vez de parar em linha reta
const SITE_LIMIT := 0.5 # ruínas: enfeites juntos em um lugar, não espalhados pelo mapa
const SITE_DECOR := 0.45
const SITE_BUILDING := 0.03
const FIELD_DECOR := 0.012
const DECOR_DETAIL := 0.1 # abaixo disso a arte põe um enfeite (ver biome_art.gd)

var world_seed: int
var height_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var feature_noise := FastNoiseLite.new()
var temperature_noise := FastNoiseLite.new()
var humidity_noise := FastNoiseLite.new()
var range_noise := FastNoiseLite.new()
var river_noise := FastNoiseLite.new()
var crossing_noise := FastNoiseLite.new()
var site_noise := FastNoiseLite.new()
var warp_x_noise := FastNoiseLite.new()
var warp_y_noise := FastNoiseLite.new()
var cache := {}
var raw_levels := {}
var clearing_center := Vector2i.ZERO
var has_clearing := false


func _init(p_seed: int) -> void:
	world_seed = p_seed
	_setup(height_noise, p_seed, 0.022, 4)
	_setup(moisture_noise, p_seed + 1, 0.028, 3)
	_setup(feature_noise, p_seed + 2, 0.05, 2)
	_setup(temperature_noise, p_seed + 3, 0.01, 2)
	_setup(humidity_noise, p_seed + 4, 0.016, 2)
	_setup(range_noise, p_seed + 5, 0.007, 3)
	range_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(river_noise, p_seed + 6, 0.007, 2)
	_setup(crossing_noise, p_seed + 7, 0.11, 1)
	_setup(site_noise, p_seed + 8, 0.045, 1)
	_setup(warp_x_noise, p_seed + 9, 0.025, 2)
	_setup(warp_y_noise, p_seed + 10, 0.025, 2)


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float, octaves: int) -> void:
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves


## {"terrain": id em Data.TERRAIN, "elevation": nível, "biome": chave em Data.BIOMES, "detail": 0 a 1 para variar a arte}.
func sample(cell: Vector2i) -> Dictionary:
	if not cache.has(cell):
		cache[cell] = _generate(cell)
	return cache[cell]


func _generate(cell: Vector2i) -> Dictionary:
	# Coordenadas reais do hexágono, para o ruído não formar faixas na grade.
	var x := cell.x + (cell.y & 1) * 0.5
	var y := cell.y * 0.866
	var wx := x + warp_x_noise.get_noise_2d(x, y) * WARP
	var wy := y + warp_y_noise.get_noise_2d(x, y) * WARP
	var roll := _roll(cell)
	var level := _level(cell)
	var biome := _biome(wx, wy, roll)
	var spot := {"elevation": level, "biome": biome, "detail": fmod(roll * 97.0, 1.0)}
	_shape(cell, wx, wy, level, Data.BIOMES[biome], roll, spot)
	return spot


## Nível de uma casa, igual à maioria da vizinhança: não sobra degrau de uma casa só.
func _level(cell: Vector2i) -> int:
	var levels := [_raw_level(cell)]
	for next in Hex.neighbors(cell):
		levels.append(_raw_level(next))
	levels.sort()
	return levels[3]


func _raw_level(cell: Vector2i) -> int:
	if not raw_levels.has(cell):
		var x := cell.x + (cell.y & 1) * 0.5
		var y := cell.y * 0.866
		raw_levels[cell] = clampi(floori((height_noise.get_noise_2d(x, y) + LEVEL_OFFSET) / LEVEL_STEP), 0, MAX_LEVEL)
	return raw_levels[cell]


func _biome(x: float, y: float, roll: float) -> String:
	var border := (roll - 0.5) * BIOME_BORDER
	var temperature := temperature_noise.get_noise_2d(x, y) + border
	if temperature < BIOME_COLD:
		return "neve"
	if temperature < BIOME_HOT:
		return "floresta"
	return "selva" if humidity_noise.get_noise_2d(x, y) + border > 0.0 else "deserto"


## Define terreno, altura e detalhe da casa. Primeiro o que forma a paisagem (rios e serras),
## depois o que a preenche (lagos, matas e colinas) e, por último, os enfeites.
func _shape(cell: Vector2i, x: float, y: float, level: int, biome: Dictionary, roll: float, spot: Dictionary) -> void:
	var field := FIELD_A if roll < 0.5 else FIELD_B
	spot["terrain"] = field
	if has_clearing and Hex.distance(cell, clearing_center) <= START_CLEARING:
		return
	var crossing := crossing_noise.get_noise_2d(x, y)
	if absf(river_noise.get_noise_2d(x, y)) < RIVER_WIDTH:
		if crossing < FORD_LIMIT:
			spot["terrain"] = WATER
			spot["elevation"] = maxi(level - 1, 0)
		return
	var ridge := range_noise.get_noise_2d(x, y)
	if ridge > RANGE_START + RANGE_BAND and crossing < PASS_LIMIT:
		spot["terrain"] = MOUNTAIN
		spot["elevation"] = mini(level + 1, MAX_LEVEL)
		return
	if ridge > RANGE_START:
		spot["terrain"] = HILLS if roll < 0.55 else (ROCKS if roll < 0.8 else field)
		return
	var feature := feature_noise.get_noise_2d(x, y)
	if level == 0 and feature > biome["water"]:
		spot["terrain"] = WATER
		return
	var moisture := moisture_noise.get_noise_2d(x, y)
	if moisture > biome["forest"] or (moisture > biome["forest"] - FOREST_EDGE and roll > 0.65):
		spot["terrain"] = FOREST
		return
	if feature < biome["hills"]:
		spot["terrain"] = HILLS
		return
	if moisture < biome["rocks"] and roll > 0.6:
		spot["terrain"] = ROCKS
		return
	var in_site := site_noise.get_noise_2d(x, y) > SITE_LIMIT
	if in_site and roll > 1.0 - SITE_BUILDING:
		spot["terrain"] = HOUSE if roll > 1.0 - SITE_BUILDING / 3.0 else TOWER
	elif roll < (SITE_DECOR if in_site else FIELD_DECOR):
		spot["decor"] = true
		spot["detail"] = roll / maxf(SITE_DECOR if in_site else FIELD_DECOR, 0.001) * DECOR_DETAIL * 0.99
	elif spot["detail"] < DECOR_DETAIL:
		spot["detail"] = DECOR_DETAIL + spot["detail"] * 9.0 # enfeite só onde foi escolhido


## Número de 0 a 1 fixo para cada casa e semente.
func _roll(cell: Vector2i) -> float:
	var mixed := (cell.x * 73856093) ^ (cell.y * 19349663) ^ (world_seed * 83492791)
	mixed = (mixed ^ (mixed >> 13)) * 1274126177
	mixed = mixed ^ (mixed >> 16)
	return float(mixed & 0xFFFFF) / float(0x100000)


func walkable(cell: Vector2i) -> bool:
	return Data.TERRAIN[sample(cell)["terrain"]]["walkable"]


## Casas alcançáveis a pé a partir de `from`, parando em `limit` (para testar a saída).
func reachable_count(from: Vector2i, limit: int) -> int:
	var seen := {from: true}
	var frontier := [from]
	while not frontier.is_empty() and seen.size() < limit:
		var current: Vector2i = frontier.pop_back()
		for next in Hex.neighbors(current):
			if seen.has(next) or not walkable(next):
				continue
			if absi(sample(next)["elevation"] - sample(current)["elevation"]) > 1:
				continue
			seen[next] = true
			frontier.append(next)
	return seen.size()


## Escolhe um início com caminho livre e abre uma pequena clareira em volta dele.
func find_start() -> Vector2i:
	var cell := Vector2i.ZERO
	for ring in 200:
		for dir in 6:
			cell = Vector2i(ring * 7, 0) if dir == 0 else Hex.neighbor(cell, dir)
			if walkable(cell) and reachable_count(cell, 1500) >= 1500:
				clearing_center = cell
				has_clearing = true
				for key in cache.keys():
					if Hex.distance(key, cell) <= START_CLEARING:
						cache.erase(key)
				return cell
	return cell
