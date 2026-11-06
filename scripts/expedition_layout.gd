extends RefCounted
## A forma tática do mapa da expedição: zonas separadas por serras, passagens estreitas entre
## elas e um platô com rampa em cada uma. Só muda altura e terreno em world_gen.gd; as regras
## de movimento continuam as mesmas. Tudo sai da semente, na mesma ordem.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

const MAX_ZONES := 9
const ZONE_SPACING := 20 # distância mínima entre os centros
const CENTER_TRIES := 400
const BAND := 2.3 # largura da serra entre duas zonas
const BORDER_WARP := 6.0 # a fronteira serpenteia em vez de ser uma reta
const KEEP_CLEAR := 6 # em volta do início e dos centros nada nasce bloqueando
const PASS_HALF_WIDTH := 1.25 # garante ao menos 2 casas de largura em qualquer ângulo
const PASS_REACH := 2.0 # até onde, de cada lado da serra, a boca da passagem fica livre
const WET_MOUTH_PENALTY := 12.0 # a passagem prefere não nascer dentro de um lago
const EXTRA_LINK_CHANCE := 0.4
const MAX_EXTRA_LINKS := 2
const PLATEAU_RADIUS := 2
const PLATEAU_MIN_LEVEL := 2
# Do lugar ideal ao aceitável: distância máxima do centro, folga da fronteira, evita caminho.
const PLATEAU_SEARCH := [[9, 5, true], [14, 4, true], [18, 3, true], [18, 2, false]]
const PLATEAU_FROM_CENTER := 4
const TREE_IN_RIDGE := 0.3 # em biomas de mata, parte da serra é árvore
const WOODED := ["floresta", "selva"]

var gen
var start: Vector2i
var radius: int
var rng := RandomNumberGenerator.new()
var zones := [] # {center, links: [zona], passages: [casas], plateau: [casas], top, ramp: [casas]}
var owner_of := {} # casa: índice da zona
var border := {} # casa: {pair: [zona, zona], gap}
var ridge := {} # casas da serra
var repairs := 0 # caminhos que a verificação precisou abrir
var zone_cells := [] # por zona, suas casas em ordem
var sorted_border := []


func _init(p_gen, p_start: Vector2i, p_radius: int) -> void:
	gen = p_gen
	start = p_start
	radius = p_radius
	rng.seed = gen.world_seed + 16
	_pick_centers()
	_divide_cells()
	var sorted_cells: Array = owner_of.keys()
	sorted_cells.sort()
	for zone in zones:
		zone_cells.append([])
	for cell in sorted_cells:
		zone_cells[owner_of[cell]].append(cell)
	sorted_border = border.keys()
	sorted_border.sort()
	_link_zones()
	_raise_ridges()
	gen.walls = ridge # o mesmo dicionário: o que um reparo tira da serra volta a ser passável
	for zone in zones:
		_add_plateau(zone)
	gen.clear_cache()
	check_map([])


func zone_at(cell: Vector2i) -> int:
	return owner_of.get(cell, -1)


# --- Zonas ---------------------------------------------------------------------

func _pick_centers() -> void:
	zones.append(_new_zone(start))
	for i in CENTER_TRIES:
		if zones.size() >= MAX_ZONES:
			break
		var cell := start + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if Hex.distance(cell, start) > radius - KEEP_CLEAR:
			continue
		if zones.all(func(zone): return Hex.distance(cell, zone["center"]) >= ZONE_SPACING):
			zones.append(_new_zone(cell))


func _new_zone(center: Vector2i) -> Dictionary:
	return {"center": center, "links": [], "passages": [], "plateau": [], "ramp": [], "top": 0}


## Cada casa fica com o centro mais perto; onde os dois mais perto quase empatam, é fronteira.
func _divide_cells() -> void:
	var centers := []
	for zone in zones:
		centers.append(_flat(zone["center"]))
	for row in range(start.y - radius, start.y + radius + 1):
		for col in range(start.x - radius - 1, start.x + radius + 2):
			var cell := Vector2i(col, row)
			if Hex.distance(cell, start) > radius:
				continue
			var point := _flat(cell)
			point += Vector2(gen.warp_x_noise.get_noise_2d(point.x, point.y), gen.warp_y_noise.get_noise_2d(point.x, point.y)) * BORDER_WARP
			var first := -1
			var second := -1
			var near := INF
			var next := INF
			for i in centers.size():
				var gap: float = point.distance_to(centers[i])
				if gap < near:
					next = near
					second = first
					near = gap
					first = i
				elif gap < next:
					next = gap
					second = i
			owner_of[cell] = first
			if second >= 0 and next - near < BAND:
				border[cell] = {"pair": [mini(first, second), maxi(first, second)], "gap": next - near}


## Árvore que liga todas as zonas pelo caminho mais curto, mais uma ou duas ligações que
## fecham voltas: nem tudo é corredor único.
func _link_zones() -> void:
	var touching := {}
	for cell in sorted_border:
		touching[border[cell]["pair"]] = true
	var pairs: Array = touching.keys()
	pairs.sort_custom(func(a, b):
		var gap_a: int = _pair_length(a)
		var gap_b: int = _pair_length(b)
		return gap_a < gap_b or (gap_a == gap_b and a < b))
	var group := {}
	for i in zones.size():
		group[i] = i
	var extras := []
	for pair in pairs:
		if group[pair[0]] != group[pair[1]]:
			var old: int = group[pair[1]]
			for i in group:
				if group[i] == old:
					group[i] = group[pair[0]]
			_open_passage(pair)
		else:
			extras.append(pair)
	var added := 0
	for pair in extras:
		if added < MAX_EXTRA_LINKS and rng.randf() < EXTRA_LINK_CHANCE:
			added += 1
			_open_passage(pair)


func _pair_length(pair: Array) -> int:
	return Hex.distance(zones[pair[0]]["center"], zones[pair[1]]["center"])


## A serra toma toda a fronteira, menos perto dos caminhos que já cortam o mapa.
func _raise_ridges() -> void:
	for cell in sorted_border:
		if border[cell].get("open", false) or _near_center(cell) or _near_path(cell):
			continue
		ridge[cell] = true
		var woods: bool = gen.biome_of(cell) in WOODED and rng.randf() < TREE_IN_RIDGE
		gen.layout_terrain[cell] = gen.TREE if woods else gen.MOUNTAIN


## Abre um corredor de 2 casas onde a fronteira das duas zonas fica mais perto do meio do caminho.
func _open_passage(pair: Array) -> void:
	var a: Vector2 = _flat(zones[pair[0]]["center"])
	var b: Vector2 = _flat(zones[pair[1]]["center"])
	var middle := (a + b) / 2.0
	var mouth = null
	var best := INF
	for cell in sorted_border:
		if border[cell]["pair"] != pair:
			continue
		var score: float = _flat(cell).distance_to(middle) + (WET_MOUTH_PENALTY if _is_wet(cell) else 0.0)
		if score < best:
			best = score
			mouth = cell
	if mouth == null:
		return
	var line := (b - a).normalized()
	var origin := _flat(mouth)
	var level: int = gen._level(mouth)
	var strip := []
	var reach := int(BAND + PASS_REACH) + 2
	for row in range(mouth.y - reach, mouth.y + reach + 1):
		for col in range(mouth.x - reach, mouth.x + reach + 1):
			var cell := Vector2i(col, row)
			var away := _flat(cell) - origin
			if absf(away.cross(line)) <= PASS_HALF_WIDTH and absf(away.dot(line)) <= BAND + PASS_REACH:
				strip.append(cell)
	for cell in strip:
		if border.has(cell):
			border[cell]["open"] = true
		_clear(cell)
		gen.layout_levels[cell] = level
	zones[pair[0]]["links"].append(pair[1])
	zones[pair[1]]["links"].append(pair[0])
	zones[pair[0]]["passages"].append(strip)
	zones[pair[1]]["passages"].append(strip)


func _is_wet(cell: Vector2i) -> bool:
	return gen.sample(cell)["terrain"] == gen.WATER or Hex.neighbors(cell).any(func(next): return gen.sample(next)["terrain"] == gen.WATER)


func _clear(cell: Vector2i) -> void:
	gen.layout_terrain[cell] = gen.FIELD_A if gen._roll(cell) < 0.5 else gen.FIELD_B


func _near_center(cell: Vector2i) -> bool:
	return zones.any(func(zone): return Hex.distance(cell, zone["center"]) <= KEEP_CLEAR)


## O caminho e seus vizinhos ficam livres: a estrada que corta a serra é mais uma passagem.
func _near_path(cell: Vector2i) -> bool:
	if gen.is_path(cell):
		return true
	return Hex.neighbors(cell).any(func(next): return gen.is_path(next))


# --- Platôs --------------------------------------------------------------------

## Procura um lugar livre na zona, sobe um disco e desce uma rampa de 2 casas até o chão.
func _add_plateau(zone: Dictionary) -> void:
	var index := zones.find(zone)
	var center: Vector2i = zone["center"]
	for rule in PLATEAU_SEARCH:
		var options := []
		for cell in zone_cells[index]:
			var gap: int = Hex.distance(cell, center)
			if gap >= PLATEAU_FROM_CENTER and gap <= rule[0] and _fits_plateau(cell, rule[1], rule[2]):
				options.append(cell)
		if not options.is_empty():
			_raise_plateau(zone, options[rng.randi_range(0, options.size() - 1)])
			return


func _raise_plateau(zone: Dictionary, site: Vector2i) -> void:
	var disc := _disc(site, PLATEAU_RADIUS)
	var top := PLATEAU_MIN_LEVEL
	for cell in disc:
		top = maxi(top, mini(gen._level(cell) + 1, gen.MAX_LEVEL))
	for cell in disc:
		gen.layout_levels[cell] = top
		_clear(cell)
	zone["plateau"] = disc
	zone["top"] = top
	_add_ramp(zone, site, top)


func _fits_plateau(site: Vector2i, margin: int, avoid_path: bool) -> bool:
	if Hex.distance(site, start) <= KEEP_CLEAR + PLATEAU_RADIUS:
		return false
	for cell in _disc(site, PLATEAU_RADIUS + 1):
		if not owner_of.has(cell) or gen.layout_levels.has(cell):
			return false
		if avoid_path and (_near_path(cell) or gen.sample(cell)["terrain"] == gen.WATER):
			return false
	for cell in _disc(site, margin):
		if border.has(cell):
			return false
	return true


## Rampa virada para o centro da zona: cada degrau desce um nível, até encostar no chão.
func _add_ramp(zone: Dictionary, site: Vector2i, top: int) -> void:
	var dir := Hex.direction_to(site, zone["center"])
	var side := (dir + 1) % 6
	var rim := site
	for i in PLATEAU_RADIUS:
		rim = Hex.neighbor(rim, dir)
	var near := Hex.neighbor(rim, dir)
	var far := Hex.neighbor(near, side)
	var level := top - 1
	while level >= 0:
		for step in [near, far]:
			gen.layout_levels[step] = level
			_clear(step)
			zone["ramp"].append(step)
		if absi(gen._level(near) - level) <= 1 and absi(gen._level(far) - level) <= 1:
			break
		level -= 1
		near = Hex.neighbor(near, dir)
		far = Hex.neighbor(far, dir)


func _disc(center: Vector2i, size: int) -> Array:
	var out := []
	for row in range(center.y - size, center.y + size + 1):
		for col in range(center.x - size - 1, center.x + size + 2):
			var cell := Vector2i(col, row)
			if Hex.distance(cell, center) <= size:
				out.append(cell)
	return out


# --- Verificação ---------------------------------------------------------------

## Casas alcançáveis a pé a partir do início, com a mesma regra de degrau do movimento.
func walk_area() -> Dictionary:
	var seen := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		var height: int = gen.sample(current)["elevation"]
		for next in Hex.neighbors(current):
			if seen.has(next) or Hex.distance(next, start) > radius or not gen.walkable(next):
				continue
			if absi(gen.sample(next)["elevation"] - height) > 1:
				continue
			seen[next] = true
			frontier.append(next)
	return seen


## Confere se tudo o que a expedição precisa é alcançável; o que não for ganha um caminho.
## `extra`: mais casas a ligar (locais especiais). Quem é ocupado por construção vale pela vizinha.
func check_map(extra: Array) -> void:
	var goals := extra.duplicate()
	for zone in zones:
		goals.append(zone["center"])
		if not zone["plateau"].is_empty():
			goals.append(zone["plateau"][zone["plateau"].size() / 2])
		for strip in zone["passages"]:
			goals.append(strip[strip.size() / 2])
	var seen := walk_area()
	for goal in goals:
		if seen.has(goal) or Hex.neighbors(goal).any(func(next): return seen.has(next)):
			continue
		print_verbose("reparo em ", goal)
		_open_way(goal, seen)
		repairs += 1
		seen = walk_area()


## Abre o caminho mais curto de `goal` até a área alcançável, nivelando degrau por degrau.
func _open_way(goal: Vector2i, seen: Dictionary) -> void:
	var came := {goal: goal}
	var frontier := [goal]
	var found = null
	while not frontier.is_empty() and found == null:
		var current: Vector2i = frontier.pop_front()
		for next in Hex.neighbors(current):
			if came.has(next) or Hex.distance(next, start) > radius:
				continue
			came[next] = current
			if seen.has(next):
				found = next
				break
			frontier.append(next)
	if found == null:
		return
	var level: int = gen.sample(found)["elevation"]
	var cell: Vector2i = came[found]
	while true:
		var target: int = gen.sample(cell)["elevation"]
		level = clampi(target, level - 1, level + 1)
		var next: Vector2i = came[cell]
		# Duas casas de largura: o reparo não pode virar um corredor de uma só.
		var beside := Hex.neighbor(cell, (Hex.direction_to(cell, next) + 1) % 6) if cell != goal else cell
		for spot in [cell, beside]:
			ridge.erase(spot)
			gen.layout_levels[spot] = level
			_clear(spot)
			gen.forget(spot)
		if cell == goal:
			break
		cell = next


static func _flat(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + (cell.y & 1) * 0.5, cell.y * 0.866)
