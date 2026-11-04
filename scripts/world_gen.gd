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
# Frio e calor ficam longe um do outro: entre neve e deserto sempre há outro bioma.
const BIOME_COLD := -0.2
const BIOME_HOT := 0.14
const BIOME_BORDER := 0.05 # borda irregular entre biomas, para não virar uma linha reta

var world_seed: int
var height_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var feature_noise := FastNoiseLite.new()
var temperature_noise := FastNoiseLite.new()
var humidity_noise := FastNoiseLite.new()
var cache := {}
var clearing_center := Vector2i.ZERO
var has_clearing := false


func _init(p_seed: int) -> void:
	world_seed = p_seed
	_setup(height_noise, p_seed, 0.045)
	_setup(moisture_noise, p_seed + 1, 0.07)
	_setup(feature_noise, p_seed + 2, 0.11)
	_setup(temperature_noise, p_seed + 3, 0.022)
	_setup(humidity_noise, p_seed + 4, 0.035)


func _setup(noise: FastNoiseLite, noise_seed: int, frequency: float) -> void:
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE


## {"terrain": id em Data.TERRAIN, "elevation": nível, "biome": chave em Data.BIOMES, "detail": 0 a 1 para variar a arte}.
func sample(cell: Vector2i) -> Dictionary:
	if not cache.has(cell):
		cache[cell] = _generate(cell)
	return cache[cell]


func _generate(cell: Vector2i) -> Dictionary:
	# Coordenadas reais do hexágono, para o ruído não formar faixas na grade.
	var x := cell.x + (cell.y & 1) * 0.5
	var y := cell.y * 0.866
	var level := clampi(floori((height_noise.get_noise_2d(x, y) + 0.32) / 0.2), 0, MAX_LEVEL)
	var biome := _biome(x, y, _roll(cell))
	return {"terrain": _terrain(cell, x, y, level, Data.BIOMES[biome]), "elevation": level, "biome": biome, "detail": fmod(_roll(cell) * 97.0, 1.0)}


func _biome(x: float, y: float, roll: float) -> String:
	var border := (roll - 0.5) * BIOME_BORDER
	var temperature := temperature_noise.get_noise_2d(x, y) + border
	if temperature < BIOME_COLD:
		return "neve"
	if temperature < BIOME_HOT:
		return "floresta"
	return "selva" if humidity_noise.get_noise_2d(x, y) + border > 0.0 else "deserto"


func _terrain(cell: Vector2i, x: float, y: float, level: int, biome: Dictionary) -> int:
	var roll := _roll(cell)
	var field := FIELD_A if roll < 0.5 else FIELD_B
	if has_clearing and Hex.distance(cell, clearing_center) <= START_CLEARING:
		return field
	var feature := feature_noise.get_noise_2d(x, y)
	var moisture := moisture_noise.get_noise_2d(x, y)
	if level == 0 and feature > biome["water"]:
		return WATER
	if level == MAX_LEVEL and feature > 0.05:
		return MOUNTAIN
	if roll > 0.992:
		return HOUSE if roll > 0.996 else TOWER
	if moisture > biome["forest"]:
		return FOREST
	if level >= 1 and feature < biome["hills"]:
		return HILLS
	if moisture < biome["rocks"] and roll > 0.45:
		return ROCKS
	return field


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
