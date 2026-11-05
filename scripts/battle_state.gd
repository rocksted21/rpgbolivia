extends RefCounted
## Regras do combate, sem nada de tela.
##
## Cada unidade tem um relógio; age sempre quem tem o menor. Toda ação (inclusive
## um único passo) adianta o relógio de quem agiu, então o inimigo pode reagir
## entre dois passos. As ações devolvem uma lista de eventos para a tela animar.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Unit = preload("res://scripts/unit.gd")

const TAUNT_ACTIONS := 3 # ações em que a IA persegue quem a provocou

var terrain: Array
var elevation: Array
var units := []
var next_uid := 1
var builds_used: Variant = {} # nós da árvore usados ao criar os heróis; o save refaz a party com eles


func _init(map_terrain: Array = Data.MAP_TERRAIN, map_elevation: Array = Data.MAP_ELEVATION) -> void:
	terrain = map_terrain
	elevation = map_elevation


func add_unit(type_id: String, team: int, pos: Vector2i, build: Array = []):
	var unit = Unit.new(type_id, team, pos, build)
	unit.uid = next_uid
	next_uid += 1
	unit.clock = time_for(Data.STEP_TIME, unit)
	units.append(unit)
	return unit


## `builds` traz os nós comprados: {índice em Data.BATTLE_UNITS: [nós]}.
static func from_data(builds := {}):
	var state = new()
	state.builds_used = builds.duplicate(true)
	for i in Data.BATTLE_UNITS.size():
		var entry: Array = Data.BATTLE_UNITS[i]
		state.add_unit(entry[0], entry[1], entry[2], builds.get(i, []))
	return state


# --- Consultas ---------------------------------------------------------------

func rows() -> int:
	return terrain.size()


func cols() -> int:
	return terrain[0].size()


func unit_by_uid(uid: int):
	for unit in units:
		if unit.uid == uid:
			return unit
	return null


func in_bounds(cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < rows() and cell.x >= 0 and cell.x < cols()


## Se a casa faz parte do mapa, mesmo longe da área em jogo.
func exists(cell: Vector2i) -> bool:
	return in_bounds(cell)


func terrain_id_at(cell: Vector2i) -> int:
	return terrain[cell.y][cell.x]


func tile_at(cell: Vector2i) -> Dictionary:
	return Data.TERRAIN[terrain[cell.y][cell.x]]


func tile_name_at(cell: Vector2i) -> String:
	return tile_at(cell)["name"]


func elevation_at(cell: Vector2i) -> int:
	return elevation[cell.y][cell.x]


func unit_at(cell: Vector2i):
	for unit in units:
		if unit.alive() and unit.pos == cell:
			return unit
	return null


func enemies_of(unit) -> Array:
	return units.filter(func(u): return u.alive() and u.team != unit.team)


func allies_of(unit) -> Array:
	return units.filter(func(u): return u.alive() and u.team == unit.team)


func time_for(base: int, unit) -> int:
	return maxi(1, roundi(base * 10.0 / unit.speed))


## Há fila de turnos agora? A batalha fixa está sempre em combate.
func in_combat() -> bool:
	return true


## Quem entra na fila de turnos. Na exploração, só o herói e quem está em combate com ele.
func takes_turns(unit) -> bool:
	return unit.alive()


func active_unit():
	var best = null
	for unit in units:
		if takes_turns(unit) and (best == null or unit.clock < best.clock):
			best = unit
	return best


## Próximas unidades a agir, supondo que cada uma gaste um passo.
## `extra` adianta o relógio de algumas unidades ({unidade: tempo}), para prever uma ação.
func timeline(count: int, extra := {}) -> Array:
	var clocks := {}
	for unit in units:
		if takes_turns(unit):
			clocks[unit] = unit.clock + extra.get(unit, 0)
	var out := []
	while out.size() < count and not clocks.is_empty():
		var best = null
		for unit in units:
			if clocks.has(unit) and (best == null or clocks[unit] < clocks[best]):
				best = unit
		out.append(best)
		clocks[best] += time_for(Data.STEP_TIME, best)
	return out


## Quantas ações dos outros acontecem antes da vez de `unit` (supondo um passo
## cada, como a fila). Para quem carrega magia, é a contagem até ela sair.
func actions_until(unit, extra := {}) -> int:
	return timeline(units.size() * 6, extra).find(unit)


## A mesma contagem, prevista para antes de carregar a magia.
func cast_wait(unit, ability_id: String) -> int:
	return actions_until(unit, {unit: cast_time_for(unit, ability_id)})


func cast_time_for(unit, ability_id: String) -> int:
	var ability: Dictionary = unit.ability(ability_id)
	return time_for(ability.get("cast_time", ability["time"]), unit)


func recovery_time_for(unit, ability_id: String) -> int:
	# Subtrair os tempos já arredondados conserva exatamente o custo total.
	return maxi(0, time_for(unit.ability(ability_id)["time"], unit) - cast_time_for(unit, ability_id))


## Unidades vivas na ordem em que vão agir: a primeira é a ativa.
func turn_order() -> Array:
	var order := units.filter(func(u): return takes_turns(u))
	var index := {}
	for i in units.size():
		index[units[i]] = i
	order.sort_custom(func(a, b):
		return a.clock < b.clock if a.clock != b.clock else index[a] < index[b])
	return order


func winner() -> int:
	var player_alive := units.any(func(u): return u.alive() and u.team == Data.Team.PLAYER)
	var enemy_alive := units.any(func(u): return u.alive() and u.team == Data.Team.ENEMY)
	if player_alive and enemy_alive:
		return -1
	return Data.Team.PLAYER if player_alive else Data.Team.ENEMY


# --- Movimento ---------------------------------------------------------------

func can_enter(from: Vector2i, to: Vector2i) -> bool:
	if not in_bounds(to) or not tile_at(to)["walkable"] or unit_at(to) != null:
		return false
	return absi(elevation_at(to) - elevation_at(from)) <= 1


func can_step(unit, to: Vector2i) -> bool:
	return Hex.distance(unit.pos, to) == 1 and can_enter(unit.pos, to)


func step_cost(from: Vector2i, to: Vector2i) -> int:
	var cost: int = Data.STEP_TIME + tile_at(to)["cost"]
	if elevation_at(to) > elevation_at(from):
		cost += Data.CLIMB_TIME
	return cost


## Dijkstra a partir da unidade: {"cost": {célula: custo}, "prev": {célula: anterior}}.
## Usa um heap e um mapa de quem ocupa cada casa: a IA e os cliques chamam isto o tempo todo.
func search(unit) -> Dictionary:
	var cost := {unit.pos: 0}
	var prev := {}
	var occupied := {}
	for other in units:
		if other.alive():
			occupied[other.pos] = true
	var heap: Array = [[0, 0, unit.pos]] # [custo, ordem de chegada, casa]
	var order := 0
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var current: Vector2i = top[2]
		if top[0] > cost[current]:
			continue
		var height := elevation_at(current)
		for next in Hex.neighbors(current):
			if occupied.has(next) or not in_bounds(next) or not tile_at(next)["walkable"]:
				continue
			var next_height := elevation_at(next)
			if absi(next_height - height) > 1:
				continue
			var total: int = top[0] + Data.STEP_TIME + tile_at(next)["cost"] + (Data.CLIMB_TIME if next_height > height else 0)
			if not cost.has(next) or total < cost[next]:
				cost[next] = total
				prev[next] = current
				order += 1
				_heap_push(heap, [total, order, next])
	return {"cost": cost, "prev": prev}


static func _heap_less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if not _heap_less(heap[i], heap[parent]):
			break
		var swap: Array = heap[i]
		heap[i] = heap[parent]
		heap[parent] = swap
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < heap.size() and _heap_less(heap[left], heap[smallest]):
				smallest = left
			if right < heap.size() and _heap_less(heap[right], heap[smallest]):
				smallest = right
			if smallest == i:
				break
			var swap: Array = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = swap
			i = smallest
	return top


func path_from_search(found: Dictionary, goal: Vector2i) -> Array:
	var out := []
	if not found["cost"].has(goal):
		return out
	var cell := goal
	while found["prev"].has(cell):
		out.push_front(cell)
		cell = found["prev"][cell]
	return out


## O mesmo custo de path_from_search, mas entre os caminhos empatados escolhe o mais perto da
## reta até o destino. Numa grade de hexágonos há muitos, e o escolhido ao acaso faz curvas à toa.
func straight_path(found: Dictionary, from: Vector2i, goal: Vector2i) -> Array:
	var out := []
	if not found["cost"].has(goal):
		return out
	var start := _flat_spot(from)
	var line := (_flat_spot(goal) - start).normalized()
	var cell := goal
	while cell != from:
		out.push_front(cell)
		var best = null
		var best_gap := INF
		for prior in Hex.neighbors(cell):
			if not found["cost"].has(prior) or not _links(prior, cell):
				continue
			if found["cost"][prior] + step_cost(prior, cell) != found["cost"][cell]:
				continue
			var away := _flat_spot(prior) - start
			var gap := absf(away.cross(line))
			if gap < best_gap:
				best_gap = gap
				best = prior
		if best == null: # não deve acontecer; o caminho comum sempre existe
			return path_from_search(found, goal)
		cell = best
	return out


func _links(from: Vector2i, to: Vector2i) -> bool:
	return absi(elevation_at(to) - elevation_at(from)) <= 1


func _flat_spot(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + (cell.y & 1) * 0.5, cell.y * 0.866)


func do_step(unit, to: Vector2i) -> Array:
	var events := []
	var from: Vector2i = unit.pos
	unit.guarding = false
	unit.clock += time_for(step_cost(from, to), unit)

	# Ataque de oportunidade: sair do alcance corpo a corpo de quem está colado.
	for enemy in enemies_of(unit):
		if Hex.distance(enemy.pos, from) == 1 and Hex.distance(enemy.pos, to) > 1 and _can_react(enemy) and not unit.passive("opportunity_immune", false):
			var amount := maxi(1, roundi(enemy.atk * Data.OPPORTUNITY_POWER * enemy.passive("opportunity_mult", 1.0)) - unit.def)
			events.append({"type": "attack", "unit": enemy, "target": unit, "label": "oportunidade"})
			_apply_damage(unit, amount, events, {"opportunity": true})
			if not unit.alive():
				return events

	unit.pos = to
	events.append({"type": "move", "unit": unit, "from": from, "to": to})
	return events


func do_wait(unit) -> Array:
	unit.guarding = false
	unit.clock += time_for(Data.WAIT_TIME, unit)
	return [{"type": "wait", "unit": unit}]


func _can_react(unit) -> bool:
	if not unit.pending.is_empty():
		return false
	return unit.abilities.any(func(id):
		var ability: Dictionary = unit.ability(id)
		return ability["kind"] == "attack" and ability["min_range"] == 1)


# --- Habilidades -------------------------------------------------------------

## Casas dentro do alcance da habilidade, a partir de onde a unidade está.
func cells_in_range(unit, ability_id: String) -> Array:
	var ability: Dictionary = unit.ability(ability_id)
	var out := []
	for row in rows():
		for col in cols():
			var cell := Vector2i(col, row)
			var dist := Hex.distance(unit.pos, cell)
			if dist >= ability["min_range"] and dist <= ability["range"]:
				out.append(cell)
	return out


func valid_targets(unit, ability_id: String) -> Array:
	var ability: Dictionary = unit.ability(ability_id)
	var out := []
	for cell in cells_in_range(unit, ability_id):
		var occupant = unit_at(cell)
		match ability["kind"]:
			"attack":
				if occupant != null and occupant.team != unit.team:
					out.append(cell)
			"heal":
				if occupant != null and occupant.team == unit.team and occupant.hp < occupant.max_hp:
					out.append(cell)
			"guard", "charge":
				out.append(cell)
	return out


## Casas que a unidade consegue acertar de onde está, contando a área das magias.
func attack_reach(unit) -> Array:
	var reach := {}
	for id in unit.abilities:
		var ability: Dictionary = unit.ability(id)
		if ability["kind"] != "attack" and ability["kind"] != "charge":
			continue
		for cell in cells_in_range(unit, id):
			for hit in area_of(cell, ability.get("radius", 0)):
				reach[hit] = true
	reach.erase(unit.pos)
	return reach.keys()


## Dano que um ataque causaria agora, com os motivos (a tela mostra antes do clique).
func preview_attack(attacker, ability_id: String, target) -> Dictionary:
	var ability: Dictionary = attacker.ability(ability_id)
	var flank := false
	var mult := 1.0
	if ability["range"] == 1:
		flank = is_flanked(attacker, target)
		if flank:
			mult *= attacker.passive("flank_mult", Data.FLANK_MULT)
	var height: int = clampi(elevation_at(attacker.pos) - elevation_at(target.pos), -2, 2)
	mult *= 1.0 + Data.HEIGHT_MULT_PER_LEVEL * height
	mult *= tile_at(target.pos)["damage"]
	mult *= _protection_mult(target)
	if target.hp * 2 <= target.max_hp:
		mult *= attacker.passive("execute", 1.0)
	var defense: int = 0 if ability.get("pierce", false) else target.def
	var amount := maxi(1, roundi(attacker.atk * ability["power"] * mult) - defense)
	return {"amount": amount, "flank": flank, "height": height, "guard": target.guarding, "cover": tile_at(target.pos)["damage"] < 1.0}


## Redução de dano por Guarda própria e por aliado vizinho com Proteção.
func _protection_mult(target) -> float:
	var mult := 1.0
	if target.guarding:
		mult *= target.passive("guard_mult", Data.GUARD_MULT)
	for ally in allies_of(target):
		if ally != target and ally.guarding and ally.passives.has("guard_aura") and Hex.distance(ally.pos, target.pos) == 1:
			mult *= ally.passives["guard_aura"]
			break
	return mult


## Flanqueio: um aliado do atacante está do lado exatamente oposto do alvo.
func is_flanked(attacker, target) -> bool:
	var dir := Hex.direction_to(target.pos, attacker.pos)
	if dir < 0:
		return false
	var other = unit_at(Hex.neighbor(target.pos, (dir + 3) % 6))
	return other != null and other.team == attacker.team


func do_ability(unit, ability_id: String, cell: Vector2i) -> Array:
	var ability: Dictionary = unit.ability(ability_id)
	unit.guarding = false
	var events := []
	match ability["kind"]:
		"attack":
			var target = unit_at(cell)
			var result := preview_attack(unit, ability_id, target)
			unit.clock += time_for(ability["time"], unit)
			events.append({"type": "attack", "unit": unit, "target": target, "ability": ability_id, "label": ability["name"]})
			_apply_damage(target, result["amount"], events, result)
			if target.alive():
				target.clock += ability.get("delay", 0)
				_counter(unit, target, ability, events)
			else:
				_on_kill(unit, events)
		"heal":
			unit.clock += time_for(ability["time"], unit)
			var total := 0
			for target in units:
				if target.alive() and target.team == unit.team and Hex.distance(target.pos, cell) <= ability.get("radius", 0):
					total += _heal(unit, target, ability["heal"], events)
					if unit.passive("heal_guard", false):
						target.guarding = true
			if unit.passives.has("heal_self") and total > 0:
				_heal(unit, unit, roundi(total * unit.passives["heal_self"]), events)
		"guard":
			unit.clock += time_for(ability["time"], unit)
			unit.guarding = true
			if ability.has("taunt"):
				for enemy in enemies_of(unit):
					if Hex.distance(enemy.pos, unit.pos) <= ability["taunt"]:
						enemy.taunted_by = unit
						enemy.taunt_actions = TAUNT_ACTIONS
			events.append({"type": "guard", "unit": unit, "ability": ability_id})
		"charge":
			unit.clock += cast_time_for(unit, ability_id)
			unit.pending = {"ability": ability_id, "tile": cell}
			events.append({"type": "cast_start", "unit": unit, "ability": ability_id, "tile": cell})
	return events


## Solta a magia carregada: acerta quem estiver na área agora, aliado ou não.
func resolve_pending(unit) -> Array:
	var ability_id: String = unit.pending["ability"]
	var ability: Dictionary = unit.ability(ability_id)
	var tile: Vector2i = unit.pending["tile"]
	unit.pending = {}
	unit.clock += recovery_time_for(unit, ability_id)
	var events := [{"type": "cast_resolve", "unit": unit, "ability": ability, "id": ability_id, "tile": tile, "cells": area_of(tile, ability["radius"])}]
	for target in units.duplicate():
		if target.alive() and Hex.distance(target.pos, tile) <= ability["radius"]:
			var mult: float = tile_at(target.pos)["damage"] * _protection_mult(target)
			var amount := maxi(1, roundi(unit.atk * ability["power"] * mult) - target.def)
			_apply_damage(target, amount, events, {})
			if not target.alive() and target.team != unit.team:
				_on_kill(unit, events)
	return events


func area_of(tile: Vector2i, radius: int) -> Array:
	var out := []
	for row in rows():
		for col in cols():
			var cell := Vector2i(col, row)
			if Hex.distance(cell, tile) <= radius:
				out.append(cell)
	return out


func _heal(unit, target, amount: int, events: Array) -> int:
	var healed := mini(amount, target.max_hp - target.hp)
	target.hp += healed
	events.append({"type": "heal", "unit": unit, "target": target, "amount": healed, "hp": target.hp})
	return healed


func _on_kill(unit, events: Array) -> void:
	if unit.alive() and unit.passives.has("kill_heal"):
		_heal(unit, unit, unit.passives["kill_heal"], events)


## Contragolpe de quem está em Guarda ao apanhar corpo a corpo.
func _counter(attacker, target, ability: Dictionary, events: Array) -> void:
	if not target.guarding or not target.passives.has("counter") or ability["range"] != 1:
		return
	var amount := maxi(1, roundi(target.atk * target.passives["counter"]) - attacker.def)
	events.append({"type": "attack", "unit": target, "target": attacker, "label": "contragolpe"})
	_apply_damage(attacker, amount, events, {"opportunity": true})


func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	target.hp = maxi(0, target.hp - amount)
	var event := {"type": "damage", "target": target, "amount": amount, "hp": target.hp}
	event.merge(info)
	events.append(event)
	if not target.alive():
		target.pending = {}
		events.append({"type": "death", "target": target})
