extends RefCounted
## Regras do combate, sem nada de tela.
##
## Cada unidade tem um relógio; age sempre quem tem o menor. Toda ação (inclusive
## um único passo) adianta o relógio de quem agiu, então o inimigo pode reagir
## entre dois passos. As ações devolvem uma lista de eventos para a tela animar.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Unit = preload("res://scripts/unit.gd")

var terrain: Array
var elevation: Array
var units := []


func _init(map_terrain: Array = Data.MAP_TERRAIN, map_elevation: Array = Data.MAP_ELEVATION) -> void:
	terrain = map_terrain
	elevation = map_elevation


func add_unit(type_id: String, team: int, pos: Vector2i):
	var unit = Unit.new(type_id, team, pos)
	unit.clock = time_for(Data.STEP_TIME, unit)
	units.append(unit)
	return unit


static func from_data():
	var state = new()
	for entry in Data.BATTLE_UNITS:
		state.add_unit(entry[0], entry[1], entry[2])
	return state


# --- Consultas ---------------------------------------------------------------

func rows() -> int:
	return terrain.size()


func cols() -> int:
	return terrain[0].size()


func in_bounds(cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < rows() and cell.x >= 0 and cell.x < cols()


func tile_at(cell: Vector2i) -> Dictionary:
	return Data.TERRAIN[terrain[cell.y][cell.x]]


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


func active_unit():
	var best = null
	for unit in units:
		if unit.alive() and (best == null or unit.clock < best.clock):
			best = unit
	return best


## Próximas unidades a agir, supondo que cada uma gaste um passo.
## `extra` adianta o relógio de algumas unidades ({unidade: tempo}), para prever uma ação.
func timeline(count: int, extra := {}) -> Array:
	var clocks := {}
	for unit in units:
		if unit.alive():
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
	var ability: Dictionary = Data.ABILITIES[ability_id]
	return time_for(ability.get("cast_time", ability["time"]), unit)


func recovery_time_for(unit, ability_id: String) -> int:
	# Subtrair os tempos já arredondados conserva exatamente o custo total.
	return maxi(0, time_for(Data.ABILITIES[ability_id]["time"], unit) - cast_time_for(unit, ability_id))


## Unidades vivas na ordem em que vão agir: a primeira é a ativa.
func turn_order() -> Array:
	var order := units.filter(func(u): return u.alive())
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
func search(unit) -> Dictionary:
	var cost := {unit.pos: 0}
	var prev := {}
	var open := [unit.pos]
	while not open.is_empty():
		var current: Vector2i = open[0]
		for cell in open:
			if cost[cell] < cost[current]:
				current = cell
		open.erase(current)
		for next in Hex.neighbors(current):
			if not can_enter(current, next):
				continue
			var total: int = cost[current] + step_cost(current, next)
			if not cost.has(next) or total < cost[next]:
				cost[next] = total
				prev[next] = current
				if not open.has(next):
					open.append(next)
	return {"cost": cost, "prev": prev}


func path_from_search(found: Dictionary, goal: Vector2i) -> Array:
	var out := []
	if not found["cost"].has(goal):
		return out
	var cell := goal
	while found["prev"].has(cell):
		out.push_front(cell)
		cell = found["prev"][cell]
	return out


func do_step(unit, to: Vector2i) -> Array:
	var events := []
	var from: Vector2i = unit.pos
	unit.guarding = false
	unit.clock += time_for(step_cost(from, to), unit)

	# Ataque de oportunidade: sair do alcance corpo a corpo de quem está colado.
	for enemy in enemies_of(unit):
		if Hex.distance(enemy.pos, from) == 1 and Hex.distance(enemy.pos, to) > 1 and _can_react(enemy):
			var amount := maxi(1, roundi(enemy.atk * Data.OPPORTUNITY_POWER) - unit.def)
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
		var ability: Dictionary = Data.ABILITIES[id]
		return ability["kind"] == "attack" and ability["min_range"] == 1)


# --- Habilidades -------------------------------------------------------------

## Casas dentro do alcance da habilidade, a partir de onde a unidade está.
func cells_in_range(unit, ability_id: String) -> Array:
	var ability: Dictionary = Data.ABILITIES[ability_id]
	var out := []
	for row in rows():
		for col in cols():
			var cell := Vector2i(col, row)
			var dist := Hex.distance(unit.pos, cell)
			if dist >= ability["min_range"] and dist <= ability["range"]:
				out.append(cell)
	return out


func valid_targets(unit, ability_id: String) -> Array:
	var ability: Dictionary = Data.ABILITIES[ability_id]
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
		var ability: Dictionary = Data.ABILITIES[id]
		if ability["kind"] != "attack" and ability["kind"] != "charge":
			continue
		for cell in cells_in_range(unit, id):
			for hit in area_of(cell, ability.get("radius", 0)):
				reach[hit] = true
	reach.erase(unit.pos)
	return reach.keys()


## Dano que um ataque causaria agora, com os motivos (a tela mostra antes do clique).
func preview_attack(attacker, ability_id: String, target) -> Dictionary:
	var ability: Dictionary = Data.ABILITIES[ability_id]
	var flank := false
	var mult := 1.0
	if ability["range"] == 1:
		flank = is_flanked(attacker, target)
		if flank:
			mult *= Data.FLANK_MULT
	var height: int = clampi(elevation_at(attacker.pos) - elevation_at(target.pos), -2, 2)
	mult *= 1.0 + Data.HEIGHT_MULT_PER_LEVEL * height
	mult *= tile_at(target.pos)["damage"]
	if target.guarding:
		mult *= Data.GUARD_MULT
	var amount := maxi(1, roundi(attacker.atk * ability["power"] * mult) - target.def)
	return {"amount": amount, "flank": flank, "height": height, "guard": target.guarding, "cover": tile_at(target.pos)["damage"] < 1.0}


## Flanqueio: um aliado do atacante está do lado exatamente oposto do alvo.
func is_flanked(attacker, target) -> bool:
	var dir := Hex.direction_to(target.pos, attacker.pos)
	if dir < 0:
		return false
	var other = unit_at(Hex.neighbor(target.pos, (dir + 3) % 6))
	return other != null and other.team == attacker.team


func do_ability(unit, ability_id: String, cell: Vector2i) -> Array:
	var ability: Dictionary = Data.ABILITIES[ability_id]
	unit.guarding = false
	var events := []
	match ability["kind"]:
		"attack":
			var target = unit_at(cell)
			var result := preview_attack(unit, ability_id, target)
			unit.clock += time_for(ability["time"], unit)
			events.append({"type": "attack", "unit": unit, "target": target, "ability": ability_id, "label": ability["name"]})
			_apply_damage(target, result["amount"], events, result)
		"heal":
			var target = unit_at(cell)
			unit.clock += time_for(ability["time"], unit)
			var healed := mini(ability["heal"], target.max_hp - target.hp)
			target.hp += healed
			events.append({"type": "heal", "unit": unit, "target": target, "amount": healed, "hp": target.hp})
		"guard":
			unit.clock += time_for(ability["time"], unit)
			unit.guarding = true
			events.append({"type": "guard", "unit": unit, "ability": ability_id})
		"charge":
			unit.clock += cast_time_for(unit, ability_id)
			unit.pending = {"ability": ability_id, "tile": cell}
			events.append({"type": "cast_start", "unit": unit, "ability": ability_id, "tile": cell})
	return events


## Solta a magia carregada: acerta quem estiver na área agora, aliado ou não.
func resolve_pending(unit) -> Array:
	var ability_id: String = unit.pending["ability"]
	var ability: Dictionary = Data.ABILITIES[ability_id]
	var tile: Vector2i = unit.pending["tile"]
	unit.pending = {}
	unit.clock += recovery_time_for(unit, ability_id)
	var events := [{"type": "cast_resolve", "unit": unit, "ability": ability, "id": ability_id, "tile": tile, "cells": area_of(tile, ability["radius"])}]
	for target in units.duplicate():
		if target.alive() and Hex.distance(target.pos, tile) <= ability["radius"]:
			var mult: float = tile_at(target.pos)["damage"]
			if target.guarding:
				mult *= Data.GUARD_MULT
			var amount := maxi(1, roundi(unit.atk * ability["power"] * mult) - target.def)
			_apply_damage(target, amount, events, {})
	return events


func area_of(tile: Vector2i, radius: int) -> Array:
	var out := []
	for row in rows():
		for col in cols():
			var cell := Vector2i(col, row)
			if Hex.distance(cell, tile) <= radius:
				out.append(cell)
	return out


func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	target.hp = maxi(0, target.hp - amount)
	var event := {"type": "damage", "target": target, "amount": amount, "hp": target.hp}
	event.merge(info)
	events.append(event)
	if not target.alive():
		target.pending = {}
		events.append({"type": "death", "target": target})
