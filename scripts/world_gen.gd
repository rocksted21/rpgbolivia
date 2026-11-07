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
const PATH := 13
const BRIDGE := 14
const ROAD := 15
const TREE := 16 # árvore sólida: a party contorna, em vez de atravessar
const MAX_LEVEL := 3
const START_CLEARING := 2 # raio sem obstáculos em volta do início
# Entortar as coordenadas tira das manchas o desenho do ruído: bordas de bioma, rios e serras ficam orgânicos.
const WARP := 7.0
# Um só pedaço de cada bioma: fatias em volta do centro do mapa. Na volta, neve e deserto nunca
# se tocam (só no próprio centro). Cada fronteira é uma curva única, então não sobra ilha de bioma.
const BIOME_RING := ["neve", "floresta", "deserto", "selva"]
const BIOME_CENTER_DISTANCE := 24.0 # o encontro dos biomas fica longe do início da viagem
const BIOME_SHIFT := 0.22 # quanto cada fatia pode ganhar ou perder, em radianos
const BORDER_WANDER := 14.0 # quanto a fronteira serpenteia, em casas
const BORDER_MAX_ANGLE := 0.34 # limite do serpentear: duas fronteiras nunca se cruzam
const BORDER_FREQUENCY := 0.035
# Planaltos: manchas largas de terra alta, com bordas em penhasco. Sobem em até três degraus.
const LEVEL_OFFSET := 0.16
const LEVEL_STEP := 0.15
# O rio é a linha onde o ruído passa por zero. A largura é a distância real até essa linha
# (valor dividido pela inclinação): sem isso, onde o ruído é plano o rio incha e vira lago.
const RIVER_HALF_WIDTH := 0.85 # em casas, para cada lado da linha: 1 a 2 casas de largura
const RIVER_SKIP := 0.06 # longe assim de zero, nem calcula a inclinação
const FORD_LIMIT := 0.42 # acima disso o rio dá passagem (vau); ele nunca corta o mundo em dois
# Lagos: manchas do ruído de relevo, com a beira tremida por um ruído fino (sem linha reta).
# A forma é só do lago: a água fica no nível 0 e rebaixa a margem até SHORE_LEVEL, em vez de
# o lago ser cortado pelo penhasco (era isso que fazia losangos).
const WATER_COST := 45.0 # cada casa de ponte vale uma volta longa: a rota contorna o lago
const LAKE_RAISE := 0.13 # somado ao "water" do bioma: lagos menores
const LAKE_EDGE := 0.07 # quanto o ruído fino entorta a beira
# A margem desce em degraus de um nível: perto do limiar do lago, no máximo 1; um pouco além, 2.
const SHORE_STEPS := [[0.07, 1], [0.15, 2]]
const LAKE_MIN_NEIGHBORS := 2 # casa d'água com menos vizinhas d'água vira terra (sem poça solta)
const RANGE_START := 0.5 # serra: o miolo é montanha, a beira vira colinas e pedras
const RANGE_BAND := 0.08
const MOUNTAIN_CHANCE := 0.4
const PASS_LIMIT := 0.28 # as serras têm desfiladeiros por onde passar
const TREE_CHANCE := 0.3 # nas matas, só parte das casas tem árvore: sobra por onde passar
const FOREST_EDGE := 0.05 # na borda, as árvores rareiam em vez de parar em linha reta
const SITE_LIMIT := 0.5 # ruínas: enfeites juntos em um lugar, não espalhados pelo mapa
const SITE_DECOR := 0.45
const SITE_BUILDING := 0.03
const FIELD_DECOR := 0.012
const DECOR_DETAIL := 0.1 # abaixo disso a arte põe um enfeite (ver biome_art.gd)
# Borda do mapa da expedição: depois do raio, uma muralha de serra (ou mata) que não se atravessa.
# A beira serpenteia até BOUND_WANDER casas para fora, nunca para dentro do raio.
const BOUND_WANDER := 3.0
const BOUND_TREE_CHANCE := 0.45 # nos biomas de mata, parte da muralha é árvore

var world_seed: int
var height_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var feature_noise := FastNoiseLite.new()
var range_noise := FastNoiseLite.new()
var river_noise := FastNoiseLite.new()
var crossing_noise := FastNoiseLite.new()
var site_noise := FastNoiseLite.new()
var path_noise := FastNoiseLite.new()
var path_cross_noise := FastNoiseLite.new()
var trail_noise := FastNoiseLite.new()
var path_cells := {}
var road_cells := {}
var carved := {} # casa: {direção: true se esse trecho é estrada}, abertos por carve()
var layout_levels := {} # casa: altura imposta pela forma tática da expedição (expedition_layout.gd)
var layout_terrain := {} # casa: terreno imposto; os caminhos têm prioridade
var warp_x_noise := FastNoiseLite.new()
var warp_y_noise := FastNoiseLite.new()
var border_noise := FastNoiseLite.new()
var biome_turn := 0
var biome_angles: Array[float] = []
var biome_center := Vector2.ZERO
var cache := {}
var raw_levels := {}
var clearing_center := Vector2i.ZERO
var has_clearing := false
var fixed_biome := "" # expedição: o mapa todo é deste bioma; vazio usa as fatias em volta do encontro
var bound_center := Vector2i.ZERO
var bound_radius := -1 # menor que zero: mundo sem borda
## Caminhos desenhados pelo ruído. A expedição desliga: lá só existem os abertos por carve(),
## que contornam as serras e passam pelas passagens, em vez de cortá-las.
var noise_paths := true
var walls := {} # casas que nenhum caminho aberto atravessa (a serra da expedição)
var lake_values := {} # cache do valor do lago por casa (o limiar fica fora, varia com o bioma)


func _init(p_seed: int) -> void:
	world_seed = p_seed
	_setup(height_noise, p_seed, 0.017, 3)
	_setup(moisture_noise, p_seed + 1, 0.028, 3)
	_setup(feature_noise, p_seed + 2, 0.05, 2)
	_setup(range_noise, p_seed + 5, 0.007, 3)
	range_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(river_noise, p_seed + 6, 0.007, 2)
	_setup(crossing_noise, p_seed + 7, 0.11, 1)
	_setup(site_noise, p_seed + 8, 0.045, 1)
	_setup(warp_x_noise, p_seed + 9, 0.025, 2)
	_setup(warp_y_noise, p_seed + 10, 0.025, 2)
	# Duas famílias de curvas: onde elas se cruzam, nasce uma encruzilhada.
	_setup(path_noise, p_seed + 11, 0.0065, 1)
	_setup(path_cross_noise, p_seed + 12, 0.0045, 1)
	# As trilhas são mais curtas e mais frequentes que as estradas.
	_setup(trail_noise, p_seed + 13, 0.021, 1)
	_setup(border_noise, p_seed + 14, BORDER_FREQUENCY, 2)
	var dice := RandomNumberGenerator.new()
	dice.seed = p_seed + 15
	biome_turn = dice.randi_range(0, BIOME_RING.size() - 1)
	biome_center = Vector2.from_angle(dice.randf() * TAU) * BIOME_CENTER_DISTANCE
	var start := dice.randf() * TAU
	for i in BIOME_RING.size():
		biome_angles.append(start + i * TAU / BIOME_RING.size() + dice.randf_range(-BIOME_SHIFT, BIOME_SHIFT))


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
	if outside_bounds(cell):
		return _wall(cell)
	var wx := x + warp_x_noise.get_noise_2d(x, y) * WARP
	var wy := y + warp_y_noise.get_noise_2d(x, y) * WARP
	var roll := _roll(cell)
	var biome := biome_of(cell)
	var level: int = layout_levels.get(cell, _level(cell))
	if not layout_levels.has(cell):
		level = mini(level, _shore_cap(cell, Data.BIOMES[biome]))
	var spot := {"elevation": level, "biome": biome, "detail": fmod(roll * 97.0, 1.0)}
	_shape(cell, wx, wy, level, Data.BIOMES[biome], roll, spot)
	if layout_terrain.has(cell) and not is_path(cell):
		spot["terrain"] = layout_terrain[cell]
		spot["elevation"] = level
		spot.erase("decor")
		if spot["detail"] < DECOR_DETAIL:
			spot["detail"] = DECOR_DETAIL + spot["detail"] * 9.0
	return spot


## Fecha o mundo em volta de `center`: tudo a mais de `radius` casas vira muralha.
func set_bounds(center: Vector2i, radius: int) -> void:
	bound_center = center
	bound_radius = radius
	# Dentro do raio nada muda: só esquece o que já foi gerado do lado de fora.
	for table in [cache, path_cells]:
		for cell in table.keys():
			if Hex.distance(cell, center) > radius:
				table.erase(cell)


## A casa fica além da borda? A beira varia entre radius + 1 e radius + 1 + BOUND_WANDER.
func outside_bounds(cell: Vector2i) -> bool:
	if bound_radius < 0:
		return false
	var gap := Hex.distance(cell, bound_center)
	if gap <= bound_radius:
		return false
	if gap > bound_radius + 1 + int(BOUND_WANDER):
		return true
	var x := cell.x + (cell.y & 1) * 0.5
	var y := cell.y * 0.866
	var wander := (border_noise.get_noise_2d(x * 2.0, y * 2.0) + 1.0) * 0.5 * BOUND_WANDER
	return gap > bound_radius + 1 + wander


func _wall(cell: Vector2i) -> Dictionary:
	var roll := _roll(cell)
	var biome := biome_of(cell)
	var level := _level(cell)
	var terrain := MOUNTAIN
	if biome in ["floresta", "selva"] and fmod(roll * 37.0, 1.0) < BOUND_TREE_CHANCE:
		terrain = TREE
	return {"terrain": terrain, "elevation": level, "biome": biome, "detail": DECOR_DETAIL + fmod(roll * 97.0, 1.0) * 0.9, "wall": true}


func clear_cache() -> void:
	cache.clear()


func forget(cell: Vector2i) -> void:
	cache.erase(cell)


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
		# Entortada como o resto: sem isso o penhasco segue a grade e sai em retas de 60 graus.
		var wx := x + warp_x_noise.get_noise_2d(x, y) * WARP
		var wy := y + warp_y_noise.get_noise_2d(x, y) * WARP
		raw_levels[cell] = clampi(floori((height_noise.get_noise_2d(wx, wy) + LEVEL_OFFSET) / LEVEL_STEP), 0, MAX_LEVEL)
	return raw_levels[cell]


## O bioma é a fatia em que a casa cai. Cada fronteira só depende da distância ao encontro:
## por isso é uma linha contínua, e o bioma nunca aparece em dois pedaços.
func biome_of(cell: Vector2i) -> String:
	if fixed_biome != "":
		return fixed_biome
	var away := Vector2(cell.x + (cell.y & 1) * 0.5, cell.y * 0.866) - biome_center
	var distance := away.length()
	var angle := away.angle()
	var sector := BIOME_RING.size() - 1
	for i in BIOME_RING.size():
		if _angle_after(angle, _border_angle(i, distance), _border_angle((i + 1) % BIOME_RING.size(), distance)):
			sector = i
			break
	return BIOME_RING[(sector + biome_turn) % BIOME_RING.size()]


func _border_angle(index: int, distance: float) -> float:
	var reach := minf(BORDER_MAX_ANGLE, BORDER_WANDER / maxf(distance, 1.0))
	return biome_angles[index] + border_noise.get_noise_2d(distance, index * 53.0) * reach


## O ângulo está entre `from` e `to`, andando no sentido crescente?
func _angle_after(angle: float, from: float, to: float) -> bool:
	return fposmod(angle - from, TAU) < fposmod(to - from, TAU)


## Define terreno, altura e detalhe da casa. Primeiro o que forma a paisagem (rios e serras),
## depois o que a preenche (lagos, matas e colinas) e, por último, os enfeites.
func _shape(cell: Vector2i, x: float, y: float, level: int, biome: Dictionary, roll: float, spot: Dictionary) -> void:
	var field := FIELD_A if roll < 0.5 else FIELD_B
	spot["terrain"] = field
	if is_path(cell):
		# O caminho vem antes de tudo, para nunca se partir: cruza a água por uma ponte.
		# Passagem, platô e rampa foram limpos pelo mapa: ali é chão, não há água para ponte.
		var wet := DRY if layout_levels.has(cell) else _water_kind(cell, x, y, level, biome)
		# Sobre rio, fica na altura da água (a rota foi traçada assim). Sobre lago, fica na
		# altura da margem, que nunca passa de 1: a ponte é um deque e encosta na beira.
		if wet == RIVER:
			spot["elevation"] = maxi(level - 1, 0)
		if wet != DRY and _water_beside(cell):
			spot["terrain"] = BRIDGE
		else:
			spot["terrain"] = ROAD if is_road(cell) else PATH
		return
	if has_clearing and Hex.distance(cell, clearing_center) <= START_CLEARING:
		return
	var crossing := crossing_noise.get_noise_2d(x, y)
	if _river_at(x, y):
		if crossing < FORD_LIMIT:
			spot["terrain"] = WATER
			spot["elevation"] = maxi(level - 1, 0)
		return
	var ridge := range_noise.get_noise_2d(x, y)
	if ridge > RANGE_START + RANGE_BAND and crossing < PASS_LIMIT:
		# Serra de blocos soltos, sem degrau em volta de cada um: não vira um muro de casas iguais.
		if fmod(roll * 61.0, 1.0) < MOUNTAIN_CHANCE:
			spot["terrain"] = MOUNTAIN
		else:
			spot["terrain"] = HILLS if roll < 0.5 else (ROCKS if roll < 0.75 else field)
		return
	if ridge > RANGE_START:
		spot["terrain"] = HILLS if roll < 0.55 else (ROCKS if roll < 0.8 else field)
		return
	var feature := feature_noise.get_noise_2d(x, y)
	if _water_kind(cell, x, y, level, biome) == LAKE:
		spot["terrain"] = WATER
		spot["elevation"] = 0
		return
	var moisture := moisture_noise.get_noise_2d(x, y)
	if moisture > biome["forest"] or (moisture > biome["forest"] - FOREST_EDGE and roll > 0.65):
		if fmod(roll * 53.0, 1.0) < TREE_CHANCE:
			spot["terrain"] = TREE
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


const DRY := 0
const RIVER := 1
const LAKE := 2


## Que água a casa teria sem caminho em cima: DRY, RIVER ou LAKE. `x` e `y` já entortados.
func _water_kind(cell: Vector2i, x: float, y: float, level: int, biome: Dictionary) -> int:
	if _river_at(x, y):
		return RIVER if crossing_noise.get_noise_2d(x, y) < FORD_LIMIT else DRY
	if not _raw_lake(cell, biome):
		return DRY
	if range_noise.get_noise_2d(x, y) > RANGE_START:
		return DRY
	var wet := 0
	for next in Hex.neighbors(cell):
		if _raw_lake(next, biome):
			wet += 1
	return LAKE if wet >= LAKE_MIN_NEIGHBORS else DRY


## A casa (coordenadas já entortadas) fica a menos de RIVER_HALF_WIDTH casas da linha do rio?
func _river_at(x: float, y: float) -> bool:
	var value := river_noise.get_noise_2d(x, y)
	if absf(value) > RIVER_SKIP:
		return false
	var dx := river_noise.get_noise_2d(x + 0.5, y) - river_noise.get_noise_2d(x - 0.5, y)
	var dy := river_noise.get_noise_2d(x, y + 0.5) - river_noise.get_noise_2d(x, y - 0.5)
	var slope := sqrt(dx * dx + dy * dy)
	return absf(value) < slope * RIVER_HALF_WIDTH


## A mancha do lago, só pelo ruído (sem olhar vizinhos): beira tremida, sem degrau de altura.
func _raw_lake(cell: Vector2i, biome: Dictionary) -> bool:
	return _lake_value(cell) > biome["water"] + LAKE_RAISE


func _lake_value(cell: Vector2i) -> float:
	if not lake_values.has(cell):
		var x := cell.x + (cell.y & 1) * 0.5
		var y := cell.y * 0.866
		var wx := x + warp_x_noise.get_noise_2d(x, y) * WARP
		var wy := y + warp_y_noise.get_noise_2d(x, y) * WARP
		var edge := crossing_noise.get_noise_2d(wx * 1.7, wy * 1.7) * LAKE_EDGE
		lake_values[cell] = feature_noise.get_noise_2d(wx, wy) + edge
	return lake_values[cell]


## Altura máxima perto de lago: o valor do ruído cresce aos poucos até o lago, então a
## distância no valor vira distância no mapa e a margem desce degrau por degrau.
func _shore_cap(cell: Vector2i, biome: Dictionary) -> int:
	var gap: float = biome["water"] + LAKE_RAISE - _lake_value(cell)
	for step in SHORE_STEPS:
		if gap < step[0]:
			return step[1]
	return MAX_LEVEL


## Ponte só onde há água de verdade ao lado; num fio d'água isolado, o caminho passa por cima.
func _water_beside(cell: Vector2i) -> bool:
	for next in Hex.neighbors(cell):
		if not is_path(next) and sample(next)["terrain"] == WATER:
			return true
	return false


## O caminho é a linha onde o ruído troca de sinal: a borda de uma mancha é contínua e tem
## uma casa de largura, então ele nunca vira um borrão nem sobra em pedaços.
## Além da borda não há caminho: _on_line já confere, e os abertos por carve() ficam no raio.
func is_path(cell: Vector2i) -> bool:
	return carved.has(cell) or _on_line(cell)


## Estrada, a via larga. O que não é estrada, mas é caminho, é trilha.
func is_road(cell: Vector2i) -> bool:
	if carved.has(cell) and carved[cell].values().has(true):
		return true
	return noise_paths and _on_road_line(cell)


func _on_line(cell: Vector2i) -> bool:
	if not path_cells.has(cell):
		path_cells[cell] = noise_paths and not outside_bounds(cell) and (_on_road_line(cell) or _on_noise_line(trail_noise, cell))
	return path_cells[cell]


func _on_road_line(cell: Vector2i) -> bool:
	if not road_cells.has(cell):
		road_cells[cell] = _on_noise_line(path_noise, cell) or _on_noise_line(path_cross_noise, cell)
	return road_cells[cell]


func _on_noise_line(noise: FastNoiseLite, cell: Vector2i) -> bool:
	if _path_value(noise, cell) < 0.0:
		return false
	for next in Hex.neighbors(cell):
		if _path_value(noise, next) < 0.0:
			return true
	return false


func _path_value(noise: FastNoiseLite, cell: Vector2i) -> float:
	var x := cell.x + (cell.y & 1) * 0.5
	var y := cell.y * 0.866
	return noise.get_noise_2d(x + warp_x_noise.get_noise_2d(x, y) * WARP, y + warp_y_noise.get_noise_2d(x, y) * WARP)


## Quão perto do centro da linha a casa está. Menor é mais perto.
func _path_rank(cell: Vector2i) -> float:
	return minf(minf(absf(_path_value(path_noise, cell)), absf(_path_value(path_cross_noise, cell))), absf(_path_value(trail_noise, cell)))


## Direções (0 a 5) em que o caminho desta casa continua. Quando três casas se tocam,
## o lado entre as duas mais longe da linha sai: fica um traço, não um triângulo.
func path_links(cell: Vector2i) -> Array:
	var links := []
	if not is_path(cell):
		return links
	for dir in 6:
		if _linked(cell, dir):
			links.append(dir)
	return links


## As direções de path_links em que o caminho segue como estrada; nas outras é trilha.
func road_links(cell: Vector2i) -> Array:
	return path_links(cell).filter(func(dir): return _is_road_edge(cell, dir))


func _linked(cell: Vector2i, dir: int) -> bool:
	if carved.has(cell) and carved[cell].has(dir):
		return true
	var next := Hex.neighbor(cell, dir)
	if not _on_line(cell) or not _on_line(next) or _triangle_cuts(cell, next, dir):
		return false
	# Um degrau alto não se sobe a pé: o caminho desenhado precisa ser andável.
	return absi(sample(cell)["elevation"] - sample(next)["elevation"]) <= 1


func _is_road_edge(cell: Vector2i, dir: int) -> bool:
	if carved.has(cell) and carved[cell].get(dir, false):
		return true
	return noise_paths and _on_road_line(cell) and _on_road_line(Hex.neighbor(cell, dir))


func _triangle_cuts(a: Vector2i, b: Vector2i, dir: int) -> bool:
	var limit := minf(_path_rank(a), _path_rank(b))
	for side in [Hex.neighbor(a, (dir + 1) % 6), Hex.neighbor(a, (dir + 5) % 6)]:
		if _on_line(side) and _path_rank(side) < limit:
			return true
	return false


# --- Caminhos abertos para ligar lugares -----------------------------------------

## Abre um caminho casa a casa. Árvores e pedras saem da frente; água vira ponte.
func carve(cells: Array, road: bool) -> void:
	for i in range(1, cells.size()):
		var a: Vector2i = cells[i - 1]
		var b: Vector2i = cells[i]
		var dir := _direction(a, b)
		_carve_edge(a, dir, road)
		_carve_edge(b, (dir + 3) % 6, road)
	for cell in cells:
		cache.erase(cell)


func _carve_edge(cell: Vector2i, dir: int, road: bool) -> void:
	if not carved.has(cell):
		carved[cell] = {}
	carved[cell][dir] = carved[cell].get(dir, false) or road


func _direction(a: Vector2i, b: Vector2i) -> int:
	for dir in 6:
		if Hex.neighbor(a, dir) == b:
			return dir
	return 0


## O caminho mais barato de `from` até uma casa de `targets`, sem sair de `radius` casas de
## `center` nem passar por `blocked`. Andar no que já é caminho custa menos, então os novos
## aproveitam os antigos. Vazio se não houver saída.
func route(from: Vector2i, targets: Dictionary, center: Vector2i, radius: int, blocked: Dictionary = {}) -> Array:
	var best := {from: 0.0}
	var came := {}
	var heap := [[0.0, from]]
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var current: Vector2i = top[1]
		if top[0] > best[current]:
			continue
		if targets.has(current) and current != from:
			var cells := [current]
			while came.has(cells[-1]):
				cells.append(came[cells[-1]])
			return cells
		for next in Hex.neighbors(current):
			if blocked.has(next) or Hex.distance(next, center) > radius:
				continue
			var step := _route_cost(current, next)
			if step < 0.0:
				continue
			var total: float = best[current] + step
			if total < best.get(next, INF):
				best[next] = total
				came[next] = current
				_heap_push(heap, [total, next])
	return []


## Custo de abrir caminho em uma casa; negativo onde não dá. O sorteio deixa o traçado sinuoso.
func _route_cost(from: Vector2i, to: Vector2i) -> float:
	if walls.has(to):
		return -1.0
	var spot: Dictionary = sample(to)
	if absi(spot["elevation"] - sample(from)["elevation"]) > 1:
		return -1.0
	var wander := _roll(to) * 1.4
	if is_path(to):
		return 1.0 + wander * 0.2
	match spot["terrain"]:
		MOUNTAIN, HOUSE, TOWER:
			return -1.0
		WATER:
			return WATER_COST + wander
		FOREST, TREE:
			return 5.0 + wander
		HILLS, ROCKS:
			return 4.0 + wander
	return 3.0 + wander


func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent][0] <= heap[i][0]:
			return
		var swap: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var left := i * 2 + 1
		var right := left + 1
		var least := i
		if left < heap.size() and heap[left][0] < heap[least][0]:
			least = left
		if right < heap.size() and heap[right][0] < heap[least][0]:
			least = right
		if least == i:
			return top
		var swap: Array = heap[least]
		heap[least] = heap[i]
		heap[i] = swap
		i = least
	return top


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
