extends "res://scripts/world_state.gd"
## Uma expedição: a party explora um mapa novo, sobe de nível, visita locais especiais e
## termina ao derrotar o guardião do farol ou ao cair inteira. O que fica entre uma expedição
## e outra está em town_progress.gd; `result()` diz o que esta rende.

const Exp = preload("res://scripts/expedition_data.gd")

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


## `town`: o que a cidade dá à party, de TownProgress.expedition_setup().
func _init(heroes: Variant, world_seed: int, builds: Variant = {}, town: Dictionary = {}) -> void:
	super(heroes, world_seed, builds)
	known_residents = town.get("rescued", [])
	known_memories = town.get("memories", 0)
	for member in party:
		member.max_hp += town.get("hp", 0)
		member.hp = member.max_hp
		member.atk += town.get("atk", 0)
	_place_landmarks()


# --- Locais especiais ----------------------------------------------------------

func terrain_id_at(cell: Vector2i) -> int:
	return terrain_override.get(cell, super(cell))


func tile_name_at(cell: Vector2i) -> String:
	if cell == beacon_cell:
		return "Farol"
	if landmarks.has(cell):
		return Exp.LANDMARKS[landmarks[cell]["kind"]]["label"]
	return super(cell)


func _place_landmarks() -> void:
	var reachable := _reachable_cells(Exp.BEACON_DISTANCE + Exp.BEACON_SPREAD)
	var candidates: Array = reachable.keys()
	candidates.sort() # a ordem do dicionário não pode decidir o mapa de uma semente
	beacon_cell = _pick_beacon(candidates, reachable)
	terrain_override[beacon_cell] = Exp.TERRAIN_BEACON
	landmarks[beacon_cell] = {"kind": "farol", "state": "idle", "guards": []}
	var along := candidates.filter(func(cell): return _near_route(cell))
	_shuffle(along)
	var placed: Array = [beacon_cell]
	for kind in Exp.LANDMARKS:
		for i in Exp.LANDMARKS[kind]["count"]:
			var cell: Variant = _next_landmark_cell(along, placed)
			if cell == null:
				continue
			placed.append(cell)
			landmarks[cell] = {"kind": kind, "state": "idle", "guards": []}
			if kind == "vila":
				landmarks[cell]["resident"] = _next_resident()
				terrain_override[cell] = Exp.TERRAIN_VILLAGE


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


func _near_route(cell: Vector2i) -> bool:
	var a := _flat(start_cell)
	var b := _flat(beacon_cell)
	var point := _flat(cell)
	var along: float = clampf((point - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
	return point.distance_to(a.lerp(b, along)) <= Exp.ROUTE_WIDTH and Hex.distance(cell, start_cell) >= Exp.LANDMARK_MIN


func _next_landmark_cell(pool: Array, placed: Array) -> Variant:
	for cell in pool:
		if placed.all(func(other): return Hex.distance(cell, other) >= Exp.LANDMARK_SPACING):
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
	var open: Array = landmarks.keys().filter(func(cell): return cell != beacon_cell and landmarks[cell]["state"] != "done")
	open.sort_custom(func(a, b): return Hex.distance(a, from) < Hex.distance(b, from))
	return open


func landmark_label(cell: Vector2i) -> String:
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
	var healed: int = mini(Exp.REST_HEAL, unit.max_hp - unit.hp)
	unit.hp += healed
	events.append({"type": "regen", "unit": unit, "amount": healed, "hp": unit.hp, "quiet": true})


## O que a expedição rende para a cidade. Quem foi resgatado continua salvo mesmo na derrota.
func result() -> Dictionary:
	var won := winner() == Data.Team.PLAYER
	return {
		"won": won,
		"brasas": brasas if won else floori(brasas * Exp.DEFEAT_BRASAS),
		"rescued": rescued.duplicate(),
		"memories": memories.size(),
	}


# --- Experiência ---------------------------------------------------------------

func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	var was_alive: bool = target.alive()
	super(target, amount, events, info)
	if not was_alive or target.alive() or is_hero(target):
		return
	if target == boss:
		defeated_boss = true
		brasas += Exp.BOSS["brasas"]
		_gain_xp(Exp.BOSS["xp"], events)
		return
	_gain_xp(Exp.KILL_XP, events)


func _gain_xp(amount: int, events: Array) -> void:
	xp += amount
	while level < Exp.LEVEL_XP.size() and xp >= Exp.LEVEL_XP[level]:
		level += 1
		for member in party:
			member.max_hp += Exp.LEVEL_HP
			member.atk += Exp.LEVEL_ATK
			if member.alive():
				member.hp += Exp.LEVEL_HP
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
		elif Exp.LANDMARKS[entry["kind"]].has("guards"):
			_wake_guards(cell, entry, Exp.LANDMARKS[entry["kind"]]["guards"], events)
		else:
			_complete(cell, events)
		if in_combat():
			return


func _wake_guards(cell: Vector2i, entry: Dictionary, count: int, events: Array) -> void:
	var guards := []
	for spot in _spots_around(cell, count):
		var unit = _spawn_enemy(_pick_type(), spot)
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


func _wake_beacon(cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var spots := _spots_around(cell, Exp.BOSS["escort"] + 1)
	if spots.is_empty():
		return
	boss = _spawn_enemy(Exp.BOSS["type"], spots[0])
	boss.display_name = Exp.BOSS["name"]
	boss.max_hp = roundi(boss.max_hp * Exp.BOSS["hp_mult"])
	boss.hp = boss.max_hp
	boss.atk = roundi(boss.atk * Exp.BOSS["atk_mult"])
	boss.speed = Exp.BOSS["speed"]
	boss.abilities = Exp.BOSS["abilities"].duplicate()
	events.append({"type": "spawn", "unit": boss})
	var guards := [boss]
	for i in range(1, spots.size()):
		var unit = _spawn_enemy(_pick_type(), spots[i])
		guards.append(unit)
		events.append({"type": "spawn", "unit": unit})
	entry["state"] = "fighting"
	entry["guards"] = [boss]
	events.append({"type": "landmark", "cell": cell, "title": Exp.BOSS["name"], "detail": "Derrote o guardião para acender o farol.", "done": false, "color": Color(1.0, 0.45, 0.35)})
	events.append_array(engage(guards, true))


## Casas livres perto do local, as mais distantes da party primeiro.
func _spots_around(cell: Vector2i, count: int) -> Array:
	var spots: Array = area_of(cell, 3).filter(func(spot):
		return spot != cell and tile_at(spot)["walkable"] and unit_at(spot) == null and party_distance(spot) >= 2)
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
	var title: String = data["label"]
	var detail := ""
	match kind:
		"vila":
			var resident: String = entry.get("resident", "")
			if resident != "":
				rescued.append(resident)
				title = "%s resgatado!" % Exp.RESIDENTS[resident]["name"]
				if resident == "curandeira":
					title = "Curandeira resgatada!"
				detail = "Abre: %s na Cidade-Farol." % Exp.RESIDENTS[resident]["service"]
			else:
				title = "Vila salva"
				detail = "Os moradores agradecem com as brasas que restaram."
		"ruina", "emboscada":
			title = "+%d brasas" % data["brasas"]
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
