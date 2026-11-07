extends "res://scripts/world_state.gd"
## Uma expedição: a party explora um mapa novo, sobe de nível, visita locais especiais e
## termina ao derrotar o guardião do farol ou ao cair inteira. O que fica entre uma expedição
## e outra está em town_progress.gd; `result()` diz o que esta rende.

const Exp = preload("res://scripts/expedition_data.gd")
const Content = preload("res://scripts/town_content.gd")
const Layout = preload("res://scripts/expedition_layout.gd")
const AbandonedCamp = preload("res://scripts/abandoned_camp.gd")

const SPOT_WALK := 1200 # pontos de movimento até onde os guardas podem nascer

var layout # zonas, passagens e platôs do mapa
var fort = preload("res://scripts/expedition_fort.gd").new()
var camps = AbandonedCamp.new()
var landmarks := {} # casa: {kind, state ("idle", "fighting" ou "done"), guards, resident}
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
var tally := {"ruins": 0, "ambushes": 0, "villages": 0, "fountains": 0, "memories": 0, "chests": 0}
var town_setup := {} # o que a cidade deu à party; o save refaz a expedição com ele
var biome := "" # a expedição inteira acontece neste bioma (town["biome"], ou sorteado pela semente)


## `town`: o que a cidade dá à party, de TownProgress.expedition_setup().
## `town["biome"]`: a região escolhida (chave de Data.BIOMES); sem ela, a semente sorteia.
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
	layout = Layout.new(gen, start_cell, _route_radius())
	_place_landmarks()
	layout.check_map(landmarks.keys())
	for cell in landmarks:
		if landmarks[cell]["kind"] == "emboscada":
			camps.place(self, cell)
	_place_ruin_scenes()
	if town_setup.get("first_stage", true):
		town_setup["fort_layout"] = town_setup.get("fort_layout", 2)
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
		var dice := RandomNumberGenerator.new()
		dice.seed = gen.world_seed + 17
		var keys: Array = Data.BIOMES.keys()
		keys.sort()
		biome = keys[dice.randi_range(0, keys.size() - 1)]
	town_setup["biome"] = biome
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
		return Exp.LANDMARKS[landmarks[cell]["kind"]]["label"]
	return super(cell)


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
		var disc: Array = zone["plateau"]
		if disc.is_empty():
			continue
		var top: Vector2i = disc[disc.size() / 2]
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
	var open: Array = landmarks.keys().filter(func(cell): return cell != beacon_cell and landmarks[cell]["state"] != "done" and (reveal_hidden or not landmarks[cell].get("hidden", false)))
	open.sort_custom(func(a, b): return Hex.distance(a, from) < Hex.distance(b, from))
	return open


func landmark_label(cell: Vector2i) -> String:
	if camps.centers.has(cell):
		return camps.label_at(cell)
	return "Farol" if cell == beacon_cell else Exp.LANDMARKS[landmarks[cell]["kind"]]["label"]


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
		brasas += Exp.BOSS["brasas"]
		_gain_xp(Exp.BOSS["xp"], events)
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
	boss.max_hp = roundi(boss.max_hp * Exp.BOSS["hp_mult"])
	boss.hp = boss.max_hp
	boss.atk = roundi(boss.atk * Exp.BOSS["atk_mult"])
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


func _heal_party(share: float, events: Array) -> void:
	for member in alive_party():
		var healed: int = mini(roundi(member.max_hp * share), member.max_hp - member.hp)
		if healed > 0:
			member.hp += healed
			events.append({"type": "regen", "unit": member, "amount": healed, "hp": member.hp})
