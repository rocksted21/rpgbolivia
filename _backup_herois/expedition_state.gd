extends "res://scripts/world_state.gd"
## Uma expedição: a party explora um mapa novo, sobe de nível, visita locais especiais e
## termina ao derrotar o guardião do farol ou ao cair inteira. O que fica entre uma expedição
## e outra está em town_progress.gd; `result()` diz o que esta rende.

const Exp = preload("res://scripts/expedition_data.gd")
const Content = preload("res://scripts/town_content.gd")
const Layout = preload("res://scripts/expedition_layout.gd")
const AbandonedCamp = preload("res://scripts/abandoned_camp.gd")
const SuburbsGen = preload("res://scripts/suburbs_map.gd")
const SuburbsLayout = preload("res://scripts/suburbs_layout.gd")
const HeroBag = preload("res://scripts/hero_bag.gd")

const SPOT_WALK := 1200 # pontos de movimento até onde os guardas podem nascer

var layout # zonas, passagens e platôs do mapa
var fort = preload("res://scripts/expedition_fort.gd").new()
var camps = AbandonedCamp.new()
var landmarks := {} # casa: {kind, state ("idle", "fighting" ou "done"), guards, resident}
var orbs_found := 0 # Orbes de Talento achados nesta expedição (já guardados nas bolsas)
var terrain_override := {}
var beacon_cell: Vector2i
var boss = null
var defeated_boss := false
var brasas := 0
var xp := 0
var level := 1
var rescued := []
var memories := []
var known_residents := []
var known_memories := 0
var potions := 0
var free_potions := 0 # as primeiras poções usadas são as de graça: não saem da mochila
var potions_used := 0
var far_compass := false
var brasa_bonus := false
var rest_bonus := 0 # Padaria: vida a mais por passo fora de combate
var reveal_hidden := false # Torre de Mapas nível 2: a bússola mostra os baús escondidos
var xp_pct := 0 # Arquivo: experiência a mais, em %
var potion_pct := 0 # Laboratório: cura a mais das poções, em %
var brasa_pct := 0 # Destilaria do Laboratório: brasas a mais, em %
var items := []
var tally := {"ruins": 0, "ambushes": 0, "villages": 0, "fountains": 0, "memories": 0, "chests": 0, "lanterns": 0}
var town_setup := {} # o que a cidade deu à party; o save refaz a expedição com ele
var biome := "" # a expedição inteira acontece neste bioma (town["biome"], ou Exp.DEFAULT_BIOME)
var fixed_map := false # mapa desenhado à mão (Subúrbios): a planta manda, a semente só varia os locais


## `town`: o que a cidade dá à party, de TownProgress.expedition_setup().
## `town["biome"]`: a região escolhida (chave de Data.BIOMES); sem ela, Exp.DEFAULT_BIOME.
func _init(heroes: Variant, world_seed: int, builds: Variant = {}, town: Dictionary = {}) -> void:
	town_setup = town.duplicate(true) # antes do super: _prepare_world() precisa do bioma
	super(heroes, world_seed, builds)
	gen.set_bounds(start_cell, _route_radius())
	known_residents = town.get("rescued", [])
	known_memories = town.get("memories", 0)
	for member in party:
		member.max_hp += town.get("hp", 0)
		member.hp = member.max_hp
		member.atk += town.get("atk", 0)
		member.def += town.get("def", 0)
	potions = town.get("potions", 0)
	free_potions = town.get("free_potions", 0)
	far_compass = town.get("far_compass", 0) > 0 or town.get("maps", 0) >= 1
	brasa_bonus = town.get("brasa_bonus", 0) > 0
	rest_bonus = town.get("rest_heal", 0)
	reveal_hidden = town.get("maps", 0) >= 2
	xp_pct = town.get("xp_pct", 0)
	potion_pct = town.get("potion_pct", 0)
	brasa_pct = town.get("brasa_pct", 0)
	items = town.get("items", [])
	if fixed_map:
		layout = SuburbsLayout.new(gen, start_cell)
		_place_fixed_landmarks()
	else:
		layout = Layout.new(gen, start_cell, _route_radius())
		_place_landmarks()
		layout.check_map(landmarks.keys())
	for cell in landmarks:
		if landmarks[cell]["kind"] == "emboscada":
			camps.place(self, cell)
	if not fixed_map:
		_place_ruin_scenes() # no mapa fixo, as cenas já estão na planta
	if town_setup.get("first_stage", true):
		town_setup["fort_layout"] = town_setup.get("fort_layout", 2)
		if fixed_map:
			_place_fixed_fort()
		else:
			fort.place(self)


## Ruínas continuam com seus prêmios; a travessia usa uma ponte real e alcançável.
func _place_ruin_scenes() -> void:
	var themes := ["garden", "shrine"]
	for cell in landmarks:
		if themes.is_empty():
			break
		if landmarks[cell]["kind"] == "ruina" and camps.place(self, cell, themes[0]):
			themes.pop_front()
	var reachable: Dictionary = layout.walk_area()
	var bridges: Array = reachable.keys().filter(func(cell):
		return (gen.sample(cell)["terrain"] == gen.BRIDGE and Hex.distance(cell, start_cell) >= 8
			and landmarks.keys().all(func(other): return Hex.distance(cell, other) > 3)))
	bridges.sort_custom(func(a, b):
		var da := Hex.distance(a, start_cell)
		var db := Hex.distance(b, start_cell)
		return da < db or (da == db and a < b))
	for cell in bridges:
		if camps.place(self, cell, "crossing"):
			break


func _prepare_world() -> void:
	biome = town_setup.get("biome", "")
	if not Data.BIOMES.has(biome):
		biome = Exp.DEFAULT_BIOME
	town_setup["biome"] = biome
	if biome == SuburbsGen.BIOME:
		fixed_map = true
		gen = SuburbsGen.new(gen.world_seed) # a planta no lugar do ruído; a semente continua a mesma
	gen.fixed_biome = biome
	gen.noise_paths = false # os caminhos da expedição são abertos depois, respeitando as serras


# --- Locais especiais ----------------------------------------------------------

func terrain_id_at(cell: Vector2i) -> int:
	return terrain_override.get(cell, super(cell))


func floor_id_at(cell: Vector2i) -> int:
	if fort.cells.has(cell):
		return 12 # calçamento do pátio
	return camps.cells[cell]["floor"] if camps.cells.has(cell) else super(cell)


func tile_name_at(cell: Vector2i) -> String:
	if fort.cells.has(cell):
		return "Forte da Vigília · dominado" if landmarks[fort.center]["state"] == "done" else "Forte da Vigília"
	var scene_label: String = camps.label_at(cell)
	if scene_label != "":
		return scene_label
	if cell == beacon_cell:
		return "Farol"
	if landmarks.has(cell):
		if landmarks[cell]["kind"] == "lanterna":
			return "Lanterna acesa" if landmarks[cell]["state"] == "done" else "Lanterna apagada"
		return Exp.LANDMARKS[landmarks[cell]["kind"]]["label"]
	if fixed_map and not terrain_override.has(cell):
		var label: String = gen.label_at(cell)
		if label != "":
			return label
	return super(cell)


## Bairro dos Subúrbios em que a casa fica ("" no mapa sorteado).
func district_at(cell: Vector2i) -> String:
	return gen.district_at(cell) if fixed_map else ""


## Chão calçado: o pátio do forte e, nos Subúrbios, as praças, cais e ruas da planta.
func paved_at(cell: Vector2i) -> bool:
	return fort.cells.has(cell) or (fixed_map and gen.is_paved(cell))


## Arte que a planta põe nesta casa; null quando vale a arte do terreno (BiomeArt.props).
func map_art(cell: Vector2i) -> Variant:
	if not fixed_map or terrain_override.has(cell):
		return null
	if landmarks.has(cell) and landmarks[cell]["kind"] == "fonte":
		return [gen.fountain_art(cell)] # a Fonte de luz: a única com água em todo o subúrbio
	return gen.art_at(cell)


## No mapa fixo o perigo sobe mais depressa: ele é menor que o sorteado e o farol fica mais perto.
func danger() -> int:
	if not fixed_map:
		return super()
	return mini(1 + farthest / Exp.FIXED_DANGER_DISTANCE, Data.WORLD["danger_max"])


func _place_landmarks() -> void:
	var reachable := _reachable_cells(_route_radius() - Exp.EDGE_MARGIN)
	var candidates: Array = reachable.keys()
	candidates.sort() # a ordem do dicionário não pode decidir o mapa de uma semente
	var beacon_ring: Array = candidates.filter(func(cell): return Hex.distance(cell, start_cell) <= Exp.BEACON_DISTANCE + Exp.BEACON_SPREAD)
	beacon_cell = _pick_beacon(beacon_ring, reachable)
	terrain_override[beacon_cell] = Exp.TERRAIN_BEACON
	landmarks[beacon_cell] = {"kind": "farol", "state": "idle", "guards": []}
	gen.carve(gen.route(start_cell, {beacon_cell: true}, start_cell, _route_radius()), true)
	# Os locais se espalham pelas zonas do mapa e ficam fora da estrada: quem chega entra por uma trilha.
	var pools := _zone_pools(candidates)
	var order: Array = pools.keys()
	order.sort()
	_shuffle(order)
	var placed: Array = [beacon_cell]
	_place_lanterns(candidates, reachable, placed)
	var turn := 0
	for kind in Exp.LANDMARKS:
		var data: Dictionary = Exp.LANDMARKS[kind]
		var hidden: int = data.get("hidden", 0)
		var spacing: int = Exp.CHEST_SPACING if kind == "bau" else Exp.LANDMARK_SPACING
		for i in data["count"]:
			var cell: Variant = null
			if i < hidden:
				cell = _plateau_spot(placed, spacing, reachable) # o baú escondido é o prêmio de quem sobe
			for tries in order.size():
				if cell != null:
					break
				var zone: int = order[(turn + tries) % order.size()]
				cell = _next_landmark_cell(pools[zone], placed, spacing)
				if cell != null:
					turn += tries + 1
			if cell == null:
				continue
			placed.append(cell)
			landmarks[cell] = {"kind": kind, "state": "idle", "guards": [], "hidden": i < hidden}
			if kind == "vila":
				landmarks[cell]["resident"] = _next_resident()
				terrain_override[cell] = Exp.TERRAIN_VILLAGE
	_carve_trails()


## Mapa fixo: o farol, a rota das lanternas e os locais saem dos candidatos da planta.
## A semente escolhe a rota (oeste ou leste primeiro) e quais candidatos recebem cada local.
## Os segredos sempre guardam um baú escondido, e a cripta sempre guarda uma memória.
func _place_fixed_landmarks() -> void:
	var plan = SuburbsGen.Plan
	beacon_cell = plan.SITES["farol"][0]
	terrain_override[beacon_cell] = Exp.TERRAIN_BEACON
	landmarks[beacon_cell] = {"kind": "farol", "state": "idle", "guards": [], "hidden": false}
	var routes: Array = plan.LANTERN_ROUTES
	var route: Array = routes[rng.randi_range(0, routes.size() - 1)]
	for order in route.size():
		var cell: Vector2i = route[order]
		landmarks[cell] = {"kind": "lanterna", "state": "idle", "guards": [], "hidden": false,
			"order": order, "hint": _lantern_hint(cell, order), "found": false}
	landmarks[beacon_cell]["found"] = false
	var taken: Array = landmarks.keys()
	for kind in Exp.LANDMARKS:
		var want: int = Exp.FIXED_COUNTS.get(kind, 0)
		var pool: Array = plan.SITES.get(kind, []).duplicate()
		_shuffle(pool)
		var placed := 0
		for cell in pool:
			if placed >= want:
				break
			if taken.any(func(other): return Hex.distance(other, cell) < Exp.FIXED_SPACING):
				continue
			landmarks[cell] = {"kind": kind, "state": "idle", "guards": [], "hidden": false}
			if kind == "vila":
				landmarks[cell]["resident"] = _next_resident()
				terrain_override[cell] = Exp.TERRAIN_VILLAGE
			taken.append(cell)
			placed += 1
	for cell in plan.SITES.get("memoria_fixa", []):
		landmarks[cell] = {"kind": "memoria", "state": "idle", "guards": [], "hidden": true}
	for secret in plan.SECRETS:
		landmarks[secret["cell"]] = {"kind": "bau", "state": "idle", "guards": [], "hidden": true, "secret": secret["name"]}


## O Forte da Vigília da primeira expedição é o quartel da planta: o comandante espera no pátio,
## ao lado do cofre. Não se constrói muralha nova: ela já está desenhada.
func _place_fixed_fort() -> void:
	var site: Vector2i = SuburbsGen.Plan.SITES["forte"][0]
	fort.center = site
	fort.cells[site] = ""
	landmarks[site] = {"kind": "forte", "state": "idle", "guards": [], "hidden": false}


## As três lanternas, em faixas de distância do início e longe umas das outras (zigue-zague).
## Se o mapa não deixa, a exigência afrouxa aos poucos, mas nunca abaixo do espaço normal entre locais.
func _place_lanterns(candidates: Array, reachable: Dictionary, placed: Array) -> void:
	var previous := start_cell
	for order in Exp.LANTERNS.size():
		var info: Dictionary = Exp.LANTERNS[order]
		var last: bool = order == Exp.LANTERNS.size() - 1
		var cell: Variant = null
		for widen in [0, 3, 6]:
			var pool: Array = candidates.filter(func(p):
				var distance := Hex.distance(p, start_cell)
				return (distance >= info["min"] - widen and distance <= info["max"] + widen
					and layout.zone_at(p) >= 0 and not gen.is_path(p)
					and Hex.neighbors(p).filter(func(next): return reachable.has(next)).size() >= Exp.BEACON_MIN_EXITS))
			_shuffle(pool)
			for gap in [Exp.LANTERN_GAP, 14, Exp.LANDMARK_SPACING]:
				var best := 999999 # quanto passa do longe ideal: 0 é perfeito
				for p in pool:
					var step := Hex.distance(p, previous)
					var to_beacon := Hex.distance(p, beacon_cell)
					if step < gap or (last and to_beacon < mini(gap, Exp.LANTERN_BEACON_GAP)):
						continue
					if not placed.all(func(other): return Hex.distance(p, other) >= Exp.LANDMARK_SPACING):
						continue
					var excess := maxi(0, step - Exp.LANTERN_GAP_MAX)
					if last:
						excess += maxi(0, to_beacon - Exp.LANTERN_BEACON_MAX)
					if excess < best:
						best = excess
						cell = p
					if best == 0:
						break
				if cell != null:
					break
			if cell != null:
				break
		if cell == null:
			continue
		placed.append(cell)
		landmarks[cell] = {"kind": "lanterna", "state": "idle", "guards": [], "hidden": false,
			"order": order, "hint": _lantern_hint(cell, order), "found": false}
		previous = cell
	landmarks[beacon_cell]["found"] = false


## Centro da área que a bússola mostra: perto da lanterna, mas não em cima dela.
## Dado próprio, para a Cartógrafa não mudar o resto do mapa da semente.
func _lantern_hint(cell: Vector2i, order: int) -> Vector2i:
	var dice := RandomNumberGenerator.new()
	dice.seed = gen.world_seed * 31 + order * 7 + 5
	var radius: int = Exp.LANTERN_AREA_FAR if far_compass else Exp.LANTERN_AREA
	var ring: Array = area_of(cell, radius).filter(func(p): return Hex.distance(p, cell) * 2 >= radius)
	ring.sort()
	return ring[dice.randi_range(0, ring.size() - 1)] if not ring.is_empty() else cell


# --- Lanternas -----------------------------------------------------------------

## Lanternas do mapa, na ordem da corrente.
func lantern_cells() -> Array:
	var cells: Array = landmarks.keys().filter(func(cell): return landmarks[cell]["kind"] == "lanterna")
	cells.sort_custom(func(a, b): return landmarks[a]["order"] < landmarks[b]["order"])
	return cells


func lanterns_lit() -> int:
	return lantern_cells().filter(func(cell): return landmarks[cell]["state"] == "done").size()


## A próxima lanterna da corrente (a de menor ordem ainda apagada); null se todas acesas.
func next_lantern() -> Variant:
	for cell in lantern_cells():
		if landmarks[cell]["state"] != "done":
			return cell
	return null


## A bússola só mostra o farol depois da última lanterna, ou se a party já o achou explorando.
## Saves de antes das lanternas não têm nenhuma: o farol aparece como antes.
func beacon_known() -> bool:
	return next_lantern() == null or landmarks[beacon_cell].get("found", true)


## Onde a bússola aponta para a próxima lanterna e o tamanho da área (0 = exata).
func lantern_target(cell: Vector2i) -> Dictionary:
	var entry: Dictionary = landmarks[cell]
	if entry.get("found", false):
		return {"cell": cell, "radius": 0}
	return {"cell": entry["hint"], "radius": Exp.LANTERN_AREA_FAR if far_compass else Exp.LANTERN_AREA}


## Perto de uma lanterna acesa, os locais aparecem na bússola (até os baús escondidos).
func lit_near(cell: Vector2i) -> bool:
	return lantern_cells().any(func(lantern): return landmarks[lantern]["state"] == "done" and Hex.distance(lantern, cell) <= Exp.LANTERN_LIGHT)


## Chegar perto revela a lanterna (ou o farol) exata, mesmo antes da hora.
func _check_found() -> void:
	var watch: Array = lantern_cells()
	watch.append(beacon_cell)
	for cell in watch:
		var entry: Dictionary = landmarks[cell]
		if not entry.get("found", true) and party_distance(cell) <= Exp.LANTERN_EXACT:
			entry["found"] = true


## Segredos da planta (Subúrbios): o primeiro passo dentro de um deles avisa e conta.
## A marca fica no próprio local ("discovered"), então volta com o save.
func _check_secrets(events: Array) -> void:
	for cell in landmarks:
		var entry: Dictionary = landmarks[cell]
		if not entry.has("secret") or entry.get("discovered", false):
			continue
		if party_distance(cell) > Exp.SECRET_RADIUS:
			continue
		entry["discovered"] = true
		tally["secrets"] = tally.get("secrets", 0) + 1
		var detail := "%s · %d de %d segredos dos Subúrbios" % [entry["secret"], secrets_found(), secrets_total()]
		events.append({"type": "secret", "cell": cell, "title": "Segredo encontrado!", "detail": detail, "color": Exp.SECRET_COLOR})


func secrets_found() -> int:
	return landmarks.values().filter(func(entry): return entry.get("discovered", false)).size()


func secrets_total() -> int:
	return landmarks.values().filter(func(entry): return entry.has("secret")).size()


func _wake_lantern(cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var info: Dictionary = Exp.LANTERNS[entry["order"]]
	var spots := _spots_around(cell, info["escort"] + 1)
	if spots.is_empty():
		return
	var elite = _spawn_enemy(info["elite"], spots[0])
	elite.display_name = Exp.ELITE_NAME
	elite.max_hp = roundi(elite.max_hp * info["hp"])
	elite.hp = elite.max_hp
	elite.atk = roundi(elite.atk * info["atk"])
	events.append({"type": "spawn", "unit": elite})
	var guards := [elite]
	var escort := _pack_types(spots.size() - 1)
	for i in range(1, spots.size()):
		var unit = _spawn_enemy(escort[i - 1], spots[i])
		guards.append(unit)
		events.append({"type": "spawn", "unit": unit})
	entry["state"] = "fighting"
	entry["guards"] = guards
	var title := "Lanterna %d de %d" % [entry["order"] + 1, Exp.LANTERNS.size()]
	events.append({"type": "landmark", "cell": cell, "title": title, "detail": "A %s guarda a chama. Derrote-a para acender a lanterna." % Exp.ELITE_NAME, "done": false, "color": Color(1.0, 0.45, 0.35)})
	events.append_array(engage(guards, true))


## Casas livres para um local, separadas por zona e embaralhadas. Fora da estrada e longe do início.
func _zone_pools(candidates: Array) -> Dictionary:
	var pools := {}
	for cell in candidates:
		var zone: int = layout.zone_at(cell)
		if zone < 0 or gen.is_path(cell) or Hex.distance(cell, start_cell) < Exp.LANDMARK_MIN:
			continue
		if not pools.has(zone):
			pools[zone] = []
		pools[zone].append(cell)
	for zone in pools:
		_shuffle(pools[zone])
	return pools


## O alto de um platô ainda sem local por perto; null se nenhum serve.
func _plateau_spot(placed: Array, spacing: int, reachable: Dictionary) -> Variant:
	var tops := []
	for zone in layout.zones:
		if zone["plateau"].is_empty():
			continue
		var top: Vector2i = zone["peak"]
		if reachable.has(top) and Hex.distance(top, start_cell) >= Exp.LANDMARK_MIN:
			tops.append(top)
	_shuffle(tops)
	return _next_landmark_cell(tops, placed, spacing)


func _route_radius() -> int:
	return Exp.BEACON_DISTANCE + Exp.BEACON_SPREAD + Exp.ROUTE_MARGIN


## Uma trilha de cada local até a rede de caminhos, começando pelos mais perto do início.
## Cada trilha pronta entra na rede: as seguintes podem sair dela, como galhos.
func _carve_trails() -> void:
	var blocked := {}
	for cell in terrain_override:
		blocked[cell] = true
	# Primeiro, toda zona ganha uma trilha do seu centro até a rede: atravessa a serra pela passagem.
	var centers: Array = layout.zones.map(func(zone): return zone["center"])
	centers.sort_custom(func(a, b):
		var gap_a: int = Hex.distance(a, start_cell)
		var gap_b: int = Hex.distance(b, start_cell)
		return gap_a < gap_b or (gap_a == gap_b and a < b))
	for center in centers:
		if center != start_cell and not gen.carved.has(center):
			gen.carve(gen.route(center, gen.carved, start_cell, _route_radius(), blocked), false)
	var open: Array = landmarks.keys().filter(func(cell): return cell != beacon_cell and not landmarks[cell]["hidden"])
	open.sort_custom(func(a, b):
		var gap_a: int = Hex.distance(a, start_cell)
		var gap_b: int = Hex.distance(b, start_cell)
		return gap_a < gap_b or (gap_a == gap_b and a < b))
	for cell in open:
		var free := blocked.duplicate()
		free.erase(cell)
		gen.carve(gen.route(cell, gen.carved, start_cell, _route_radius(), free), false)
	_link_islands(blocked)


## Terra cercada de água ou de serra, grande o bastante para valer a visita, ganha uma trilha
## até a rede (atravessando a água por ponte). Ilhas pequenas ficam como paisagem.
func _link_islands(blocked: Dictionary) -> void:
	var radius := _route_radius() - Exp.EDGE_MARGIN
	var reach := _reachable_cells(radius)
	var cells: Array = area_of(start_cell, radius)
	cells.sort()
	var seen := {}
	for cell in cells:
		if reach.has(cell) or seen.has(cell) or not gen.walkable(cell):
			continue
		var island := [cell]
		seen[cell] = true
		var i := 0
		while i < island.size():
			var current: Vector2i = island[i]
			i += 1
			for next in Hex.neighbors(current):
				if seen.has(next) or reach.has(next) or Hex.distance(next, start_cell) > radius or not gen.walkable(next):
					continue
				if absi(elevation_at(next) - elevation_at(current)) > 1:
					continue
				seen[next] = true
				island.append(next)
		if island.size() < Exp.ISLAND_MIN:
			continue
		island.sort_custom(func(a, b):
			var gap_a: int = Hex.distance(a, start_cell)
			var gap_b: int = Hex.distance(b, start_cell)
			return gap_a < gap_b or (gap_a == gap_b and a < b))
		var way: Array = gen.route(island[0], gen.carved, start_cell, _route_radius(), blocked)
		var wet: int = way.filter(func(cell): return gen.sample(cell)["terrain"] == gen.WATER).size()
		if wet <= Exp.ISLAND_BRIDGE_MAX:
			gen.carve(way, false)


## Casas a pé a partir do início, até `radius`, com o mesmo critério de degrau do movimento.
func _reachable_cells(radius: int) -> Dictionary:
	var seen := {start_cell: true}
	var frontier := [start_cell]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for next in Hex.neighbors(current):
			if seen.has(next) or Hex.distance(next, start_cell) > radius or not gen.walkable(next):
				continue
			if absi(elevation_at(next) - elevation_at(current)) > 1:
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func _pick_beacon(candidates: Array, reachable: Dictionary) -> Vector2i:
	var far := candidates.filter(func(cell): return Hex.distance(cell, start_cell) >= Exp.BEACON_DISTANCE)
	_shuffle(far)
	for cell in far:
		var exits: int = Hex.neighbors(cell).filter(func(next): return reachable.has(next)).size()
		if exits >= Exp.BEACON_MIN_EXITS:
			return cell
	# O início sempre tem caminho longo (find_start), então isto é só uma rede de segurança.
	candidates.sort_custom(func(a, b): return Hex.distance(a, start_cell) > Hex.distance(b, start_cell))
	return candidates[0]


func _next_landmark_cell(pool: Array, placed: Array, spacing: int) -> Variant:
	for cell in pool:
		if placed.all(func(other): return Hex.distance(cell, other) >= spacing):
			return cell
	return null


func _next_resident() -> String:
	for id in Exp.RESIDENT_ORDER:
		if id not in known_residents and not landmarks.values().any(func(entry): return entry.get("resident", "") == id):
			return id
	return ""


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = list[i]
		list[i] = list[j]
		list[j] = swap


## Locais que ainda valem uma visita, do mais perto para o mais longe de `from`.
func open_landmarks(from: Vector2i) -> Array:
	# As lanternas têm a sua própria seta (lantern_target); o farol, a dele.
	var open: Array = landmarks.keys().filter(func(cell): return (cell != beacon_cell and landmarks[cell]["kind"] != "lanterna"
		and landmarks[cell]["state"] != "done" and (reveal_hidden or not landmarks[cell].get("hidden", false) or lit_near(cell))))
	open.sort_custom(func(a, b): return Hex.distance(a, from) < Hex.distance(b, from))
	return open


func landmark_label(cell: Vector2i) -> String:
	if camps.centers.has(cell):
		return camps.label_at(cell)
	if cell == beacon_cell:
		return "Farol"
	if landmarks[cell]["kind"] == "lanterna":
		return "Lanterna %d" % (landmarks[cell]["order"] + 1)
	return Exp.LANDMARKS[landmarks[cell]["kind"]]["label"]


## Lanternas que ficaram apagadas: pesam na força do guardião e no prêmio dele.
func dark_lanterns() -> int:
	return lantern_cells().size() - lanterns_lit()


func is_boss(unit) -> bool:
	return unit != null and unit == boss


# --- Fim e recompensa ----------------------------------------------------------

func winner() -> int:
	if defeated_boss:
		return Data.Team.PLAYER
	return super()


func _rest(unit, events: Array) -> void:
	if unit.hp >= unit.max_hp:
		return
	var healed: int = mini(Exp.REST_HEAL + rest_bonus, unit.max_hp - unit.hp)
	unit.hp += healed
	events.append({"type": "regen", "unit": unit, "amount": healed, "hp": unit.hp, "quiet": true})


## O que a expedição rende para a cidade. Quem foi resgatado continua salvo mesmo na derrota.
func result() -> Dictionary:
	var won := winner() == Data.Team.PLAYER
	var kept: int = brasas if won else floori(brasas * Exp.DEFEAT_BRASAS)
	var bonus := brasa_pct / 100.0
	if brasa_bonus:
		bonus += Content.BRASA_BONUS
	kept += floori(kept * bonus)
	var counted := tally.duplicate()
	counted["kills"] = kills
	counted["beacons"] = 1 if won else 0
	counted["brasas"] = kept
	return {
		"won": won,
		"guardian": boss.type_id if won and boss != null else "", # a história lembra quem caiu
		"brasas": kept,
		"rescued": rescued.duplicate(),
		"memories": memories.size(),
		"items": items.duplicate(),
		"bag_potions_used": maxi(potions_used - free_potions, 0),
		"tally": counted,
	}


## Poção de Luz: cura a party inteira. Não gasta a vez de ninguém.
func use_potion() -> Array:
	var events := []
	if potions <= 0 or alive_party().all(func(member): return member.hp >= member.max_hp):
		return events
	potions -= 1
	potions_used += 1
	_heal_party(Content.POTION_HEAL + potion_pct / 100.0, events)
	return events


# --- Experiência ---------------------------------------------------------------

func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	var was_alive: bool = target.alive()
	super(target, amount, events, info)
	if not was_alive or target.alive() or is_hero(target):
		return
	if target == boss:
		defeated_boss = true
		landmarks[beacon_cell]["state"] = "done"
		brasas += Exp.BOSS["brasas"] + Exp.DARK_BRASAS * dark_lanterns() # prêmio de quem foi sem acender
		_gain_xp(Exp.BOSS["xp"], events)
		grant_talent_orb(events) # o guardião sempre deixa um Orbe de Talento
		return
	_gain_xp(Exp.KILL_XP, events)


func _gain_xp(amount: int, events: Array) -> void:
	xp += amount + floori(amount * xp_pct / 100.0)
	while level < Exp.LEVEL_XP.size() and xp >= Exp.LEVEL_XP[level]:
		level += 1
		for member in party:
			member.max_hp += Exp.LEVEL_HP
			member.atk += Exp.LEVEL_ATK
			if member.alive():
				member.hp = member.max_hp # upar de nível restaura a vida toda
		events.append({"type": "level_up", "level": level})


## Quanto falta para o próximo nível; negativo no nível máximo.
func xp_to_next() -> int:
	return Exp.LEVEL_XP[level] - xp if level < Exp.LEVEL_XP.size() else -1


# --- Andamento -----------------------------------------------------------------

func tick() -> Array:
	var events: Array = super()
	if winner() >= 0:
		return events
	_check_found()
	if fixed_map:
		_check_secrets(events)
	_check_fights(events)
	if not in_combat():
		_check_visits(events)
	return events


## Luta de um local: acaba quando os guardas caem. Se a party fugiu e eles se perderam na
## névoa, o local volta a esperar por ela.
func _check_fights(events: Array) -> void:
	for cell in landmarks:
		var entry: Dictionary = landmarks[cell]
		if entry["state"] != "fighting":
			continue
		var guards: Array = entry["guards"]
		if guards.all(func(unit): return not unit.alive()):
			_complete(cell, events)
		elif guards.any(func(unit): return unit.alive() and not units.has(unit)):
			entry["state"] = "idle"
			entry["guards"] = []


func _check_visits(events: Array) -> void:
	for cell in landmarks:
		var entry: Dictionary = landmarks[cell]
		if entry["state"] != "idle":
			continue
		var radius: int = Exp.BEACON_VISIT_RADIUS if cell == beacon_cell else Exp.VISIT_RADIUS
		if party_distance(cell) > radius:
			continue
		if cell == beacon_cell:
			_wake_beacon(cell, entry, events)
		elif entry["kind"] == "forte":
			_wake_fort(cell, entry, events)
		elif entry["kind"] == "lanterna":
			_wake_lantern(cell, entry, events)
		elif Exp.LANDMARKS[entry["kind"]].has("guards"):
			_wake_guards(cell, entry, Exp.LANDMARKS[entry["kind"]]["guards"], events)
		else:
			_complete(cell, events)
		if in_combat():
			return


func _wake_guards(cell: Vector2i, entry: Dictionary, count: int, events: Array) -> void:
	var guards := []
	var types := _pack_types(count)
	for spot in _spots_around(cell, count):
		var unit = _spawn_enemy(types[guards.size()], spot)
		guards.append(unit)
		events.append({"type": "spawn", "unit": unit})
	if guards.is_empty():
		_complete(cell, events)
		return
	entry["state"] = "fighting"
	entry["guards"] = guards
	var title := "Emboscada!" if entry["kind"] == "emboscada" else "%s sob ataque" % Exp.LANDMARKS[entry["kind"]]["label"]
	events.append({"type": "landmark", "cell": cell, "title": title, "detail": "", "done": false, "color": Color(1.0, 0.45, 0.35)})
	events.append_array(engage(guards, true))


func _wake_fort(cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var spots := _spots_around(cell, 37).filter(func(p): return Hex.distance(p, cell) <= 2)
	if spots.is_empty():
		return
	var captain = _spawn_enemy("boss_jarl", spots[0])
	captain.display_name = "Jarl de Gelo Negro · Comandante"
	captain.max_hp = roundi(captain.max_hp * 1.6)
	captain.hp = captain.max_hp
	entry["guards"] = [captain]
	entry["state"] = "fighting"
	events.append({"type": "spawn", "unit": captain})
	events.append({"type": "landmark", "cell": cell, "title": "Forte da Vigília", "detail": "Derrube o Jarl de Gelo Negro para tomar o forte e abrir o cofre.", "done": false, "color": Exp.LANDMARKS["forte"]["color"]})
	events.append_array(engage([captain], true))


func _wake_beacon(cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var spots := _spots_around(cell, Exp.BOSS["escort"] + 1)
	if spots.is_empty():
		return
	var boss_type: String = Exp.BOSS_BY_BIOME.get(biome_at(cell), Exp.BOSS["type"])
	var own_boss := boss_type != Exp.BOSS["type"]
	boss = _spawn_enemy(boss_type, spots[0])
	boss.display_name = Data.UNIT_TYPES[boss_type]["name"] if own_boss else Exp.BOSS["name"]
	var dark := dark_lanterns() # cada lanterna apagada deixa o guardião mais forte
	boss.max_hp = roundi(boss.max_hp * Exp.BOSS["hp_mult"] * (1.0 + Exp.DARK_HP * dark))
	boss.hp = boss.max_hp
	boss.atk = roundi(boss.atk * Exp.BOSS["atk_mult"] * (1.0 + Exp.DARK_ATK * dark))
	boss.speed = Exp.BOSS["speed"]
	boss.abilities = (Data.UNIT_TYPES[boss_type]["abilities"] if own_boss else Exp.BOSS["abilities"]).duplicate()
	events.append({"type": "spawn", "unit": boss})
	var guards := [boss]
	var escort := _pack_types(spots.size() - 1)
	for i in range(1, spots.size()):
		var unit = _spawn_enemy(escort[i - 1], spots[i])
		guards.append(unit)
		events.append({"type": "spawn", "unit": unit})
	entry["state"] = "fighting"
	entry["guards"] = [boss]
	var detail := "Derrote o guardião para acender o farol."
	if dark > 0:
		detail += "\n%d lanterna%s apagada%s: o guardião está mais forte." % [dark, "s" if dark > 1 else "", "s" if dark > 1 else ""]
	if Exp.BOSS_LINES.has(boss_type):
		detail = "%s\n%s" % [Exp.BOSS_LINES[boss_type], detail]
	events.append({"type": "landmark", "cell": cell, "title": boss.display_name, "detail": detail, "done": false, "color": Color(1.0, 0.45, 0.35)})
	events.append_array(engage(guards, true))


## Casas livres perto do local, as mais distantes da party primeiro.
## Lugares em volta do local por onde a party consegue chegar: quem nasce atrás de uma serra
## ou no alto de um penhasco nunca poderia ser derrotado, e o local ficaria preso em combate.
func _spots_around(cell: Vector2i, count: int) -> Array:
	var walker = last_walker if last_walker != null and last_walker.alive() else hero
	var reach: Dictionary = search(walker, SPOT_WALK)["cost"]
	var spots: Array = area_of(cell, 3).filter(func(spot):
		return spot != cell and reach.has(spot) and party_distance(spot) >= 2)
	spots.sort_custom(func(a, b):
		var gap_a := party_distance(a)
		var gap_b := party_distance(b)
		return gap_a > gap_b or (gap_a == gap_b and a < b))
	return spots.slice(0, count)


func _complete(cell: Vector2i, events: Array) -> void:
	var entry: Dictionary = landmarks[cell]
	var kind: String = entry["kind"]
	var data: Dictionary = Exp.LANDMARKS[kind]
	entry["state"] = "done"
	var counts := {"ruina": "ruins", "emboscada": "ambushes", "vila": "villages", "fonte": "fountains", "memoria": "memories", "bau": "chests"}
	if counts.has(kind):
		tally[counts[kind]] += 1
	var title: String = data["label"]
	var detail := ""
	match kind:
		"lanterna":
			var info: Dictionary = Exp.LANTERNS[entry["order"]]
			tally["lanterns"] = tally.get("lanterns", 0) + 1
			title = "Lanterna %d acesa" % (entry["order"] + 1)
			detail = "A party recupera parte da vida. +%d brasas." % info["brasas"]
			detail += "\nA próxima lanterna aparece na bússola." if next_lantern() != null else "\nO farol aparece na bússola."
			brasas += info["brasas"]
			_heal_party(Exp.LANTERN_HEAL, events)
			_gain_xp(info["xp"], events)
		"forte":
			title = "Forte da Vigília dominado"
			detail = "Cofre conquistado! +%d brasas e +%d XP." % [data["brasas"], data["xp"]]
		"vila":
			var resident: String = entry.get("resident", "")
			if resident != "":
				rescued.append(resident)
				title = Exp.RESIDENTS[resident]["rescued"]
				detail = "Abre: %s na Cidade-Farol." % Exp.RESIDENTS[resident]["service"]
			else:
				title = "Vila salva"
				detail = "Os moradores agradecem com as brasas que restaram."
		"ruina", "emboscada":
			title = "+%d brasas" % data["brasas"]
		"bau":
			title = "+%d brasas" % data["brasas"]
			if rng.randf() < data["potion_chance"]:
				potions += 1
				free_potions += 1 # achada aqui: usá-la não gasta as da mochila
				detail = "Dentro do baú havia uma Poção de Luz."
		"fonte":
			title = "Fonte de luz"
			detail = "A party recupera parte da vida."
			_heal_party(data["heal"], events)
		"memoria":
			title = "Memória recuperada"
			var index: int = known_memories + memories.size()
			if index < Exp.MEMORIES.size():
				detail = Exp.MEMORIES[index]
				memories.append(index)
			else:
				detail = Exp.EMPTY_MEMORY
	brasas += data.get("brasas", 0)
	events.append({"type": "landmark", "cell": cell, "title": title, "detail": detail, "done": true, "color": data["color"]})
	_gain_xp(data.get("xp", 0), events)
	if kind == "forte" \
			or (kind == "lanterna" and rng.randf() < HeroBag.ORB_CHANCE["lanterna"]) \
			or (kind == "bau" and entry.has("secret") and rng.randf() < HeroBag.ORB_CHANCE["segredo"]):
		grant_talent_orb(events)


## Orbe de Talento: vai para a bolsa de um herói da party, sorteado entre os vivos que ainda
## têm ramo trancado (hero_bag.gd). Fica guardado na hora, mesmo se a expedição cair depois.
## Público: qualquer recompensa pode chamar (Desafios de Arena, por exemplo).
## Devolve o tipo de quem ficou com ele ("" = todas as bolsas cheias).
func grant_talent_orb(events: Array) -> String:
	var alive_types := alive_party().map(func(member): return member.type_id)
	var party_types := party.map(func(member): return member.type_id)
	var holder := HeroBag.pick_holder(alive_types, party_types, rng)
	if holder == "":
		events.append({"type": "orb", "type_id": "", "title": "Orbe de Talento perdido", "detail": "As bolsas da party estão cheias.", "color": HeroBag.ORB_COLOR})
		return ""
	HeroBag.add(holder, HeroBag.ORB)
	orbs_found += 1
	var detail := "Guardado na bolsa. Use para abrir um ramo trancado da árvore."
	if not HeroBag.wants_orb(holder):
		detail = "Guardado na bolsa. Fora de combate, passe para quem ainda tem ramo trancado."
	events.append({"type": "orb", "type_id": holder, "title": "Orbe de Talento → %s" % HeroBag.hero_name(holder), "detail": detail, "color": HeroBag.ORB_COLOR})
	return holder


func _heal_party(share: float, events: Array) -> void:
	for member in alive_party():
		var healed: int = mini(roundi(member.max_hp * share), member.max_hp - member.hp)
		if healed > 0:
			member.hp += healed
			events.append({"type": "regen", "unit": member, "amount": healed, "hp": member.hp})
