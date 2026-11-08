extends "res://scripts/battle_state.gd"
## Desafio de Arena: a batalha fixa da arena original, montada a partir de arena_data.gd.
## Os heróis são cópias dos da expedição (vida, atributos, nível e talentos de agora); no fim,
## battle/arena_challenge.gd devolve a vida para os originais. A regra da arena entra no fim
## de cada ação (_end_turn), em quem vence (winner) e no dano (_status_mult).

const Arena = preload("res://scripts/arena_data.gd")

var arena_id := ""
var info := {}
var rule := ""
var heroes := {} # cópia na arena -> herói da expedição
var leader = null # regra "leader": quem precisa cair
var waves := []
var next_wave := 0 # próxima onda de `waves` que ainda não chegou
var arrivals := 0 # quantas levas de reforço já chegaram (a tela avisa quando muda)
var start_time := 0 # relógio da fila no começo: as rodadas contam a partir dele
var last_respawn := 1
var minion_turn := 0
var danger_level := 0 # perigo da expedição: os inimigos crescem como os do mapa
var pools := {} # regra "blood": casa -> última rodada em que a poça de sangue ainda vale
var surrendered := false # regra "blood": o líder se rendeu (vitória sem matar)


## `party`: os heróis da expedição (só os de pé entram). `danger`: ExpeditionState.danger().
func _init(id: String, party: Array, danger: int) -> void:
	super(Arena.terrain_rows(Arena.ARENAS[id]), Arena.height_rows(Arena.ARENAS[id]))
	info = Arena.ARENAS[id]
	arena_id = id
	rule = info["rule"]
	waves = info.get("waves", [])
	danger_level = maxi(0, danger - 1)
	var spots: Array = info["heroes"]
	var standing: Array = party.filter(func(member): return member.hp > 0)
	for i in mini(standing.size(), spots.size()):
		heroes[_add_hero(standing[i], spots[i])] = standing[i]
	for entry in info["enemies"]:
		var unit = _add_enemy(entry)
		if entry.get("leader", false):
			leader = unit
	start_time = _now()
	for cell in info.get("pools", []):
		pools[cell] = round_now() + info["pool_rounds"]


func _add_hero(member, cell: Vector2i):
	var copy = add_unit(member.type_id, Data.Team.PLAYER, cell)
	copy.display_name = member.display_name
	copy.max_hp = member.max_hp
	copy.hp = member.hp
	copy.atk = member.atk
	copy.def = member.def
	copy.speed = member.speed
	copy.abilities = member.abilities.duplicate()
	copy.passives = member.passives.duplicate(true)
	copy.ability_mods = member.ability_mods.duplicate(true)
	copy.clock = time_for(Data.STEP_TIME, copy)
	return copy


## Inimigo da arena, com a força do perigo da expedição (como world_state._spawn_enemy).
func _add_enemy(entry: Dictionary):
	var unit = add_unit(entry["type"], Data.Team.ENEMY, _free_near(entry["cell"]))
	var hp_mult: float = (1.0 + Data.WORLD["danger_hp"] * danger_level) * Arena.ARENA_HP * entry.get("hp", 1.0)
	unit.max_hp = roundi(unit.max_hp * hp_mult)
	unit.hp = unit.max_hp
	unit.atk = roundi(unit.atk * (1.0 + Data.WORLD["danger_atk"] * danger_level) * entry.get("atk", 1.0))
	if entry.has("name"):
		unit.display_name = entry["name"]
	if entry.has("abilities"):
		unit.abilities = entry["abilities"].duplicate()
	if entry.has("lifesteal"):
		unit.passives["lifesteal"] = entry["lifesteal"]
	return unit


## A casa pedida, ou a livre mais perto dela (alguém pode estar parado no ponto de chegada).
func _free_near(cell: Vector2i) -> Vector2i:
	if in_bounds(cell) and tile_at(cell)["walkable"] and unit_at(cell) == null:
		return cell
	var best := cell
	var best_gap := 999999
	for y in rows():
		for x in cols():
			var spot := Vector2i(x, y)
			var gap := Hex.distance(spot, cell)
			if gap < best_gap and tile_at(spot)["walkable"] and unit_at(spot) == null:
				best = spot
				best_gap = gap
	return best


## Reforço no meio da luta: entra no relógio de agora, senão agiria várias vezes seguidas.
func _arrive(entry: Dictionary, events: Array) -> void:
	var unit = _add_enemy(entry)
	unit.clock = _now() + time_for(Data.STEP_TIME, unit)
	events.append({"type": "spawn", "unit": unit})


# --- Tempo e regra ---------------------------------------------------------------

func _now() -> int:
	var unit = active_unit()
	return unit.clock if unit != null else start_time


func round_now() -> int:
	return 1 + floori(maxi(0, _now() - start_time) / float(Arena.ROUND_TIME))


func _enemies_alive() -> bool:
	return units.any(func(unit): return unit.alive() and unit.team == Data.Team.ENEMY)


func _minions_alive() -> int:
	return units.filter(func(unit): return unit.alive() and unit.team == Data.Team.ENEMY and unit != leader).size()


func _end_turn(unit, events: Array) -> void:
	super(unit, events)
	if rule == "blood":
		_blood_rule(unit, events)
	_apply_rule(events)


## Duelo de sangue: golpear custa vida a ele e deixa uma poça onde ele está. Fim da vez numa
## poça: herói sangra, ele se cura. As poças secam depois de `pool_rounds` rodadas.
func _blood_rule(unit, events: Array) -> void:
	var now_round := round_now()
	for cell in pools.keys():
		if pools[cell] < now_round:
			pools.erase(cell)
	if not unit.alive():
		return
	if unit == leader and not surrendered:
		var struck: bool = events.any(func(e): return e.get("unit") == unit and e["type"] in ["attack", "cast_start"])
		if struck:
			var paid: int = mini(maxi(1, roundi(unit.max_hp * info["blood_cost"])), unit.hp - roundi(unit.max_hp * info["blood_floor"]))
			if paid > 0:
				_apply_damage(unit, paid, events, {"dot": "poison"})
			_add_pool(unit.pos)
			return # a poça que ele acabou de deixar só cura numa vez sem golpe
	if not pools.has(unit.pos):
		return
	if unit == leader and not surrendered:
		var healed: int = mini(info["pool_heal"], unit.max_hp - unit.hp)
		if healed > 0:
			unit.hp += healed
			events.append({"type": "regen", "unit": unit, "amount": healed, "hp": unit.hp})
	elif unit.team == Data.Team.PLAYER:
		_apply_damage(unit, info["pool_damage"], events, {"dot": "poison"})


func _add_pool(cell: Vector2i) -> void:
	pools[cell] = round_now() + info["pool_rounds"]
	while pools.size() > info["pools_max"]: # a mais velha seca primeiro
		var oldest: Vector2i = pools.keys()[0]
		for other in pools:
			if pools[other] < pools[oldest]:
				oldest = other
		pools.erase(oldest)


## Duelo de sangue: o líder nunca cai; com `yield_at` da vida ou menos, se rende.
func _apply_damage(target, amount: int, events: Array, info_extra: Dictionary) -> void:
	if rule == "blood" and target == leader:
		amount = mini(amount, maxi(0, target.hp - 1))
	super(target, amount, events, info_extra)
	if rule == "blood" and target == leader and not surrendered and target.hp <= roundi(target.max_hp * info["yield_at"]):
		surrendered = true


func _apply_rule(events: Array) -> void:
	if not units.any(func(u): return u.alive() and u.team == Data.Team.PLAYER):
		return
	if rule == "leader" and (leader == null or not leader.alive()):
		return
	var now_round := round_now()
	# Ondas: chegam na rodada delas, ou já, se não sobrou ninguém em pé do outro lado.
	while next_wave < waves.size() and (waves[next_wave]["round"] <= now_round or not _enemies_alive()):
		for entry in waves[next_wave]["units"]:
			_arrive(entry, events)
		next_wave += 1
		arrivals += 1
	# Campeão: um lacaio volta a cada tantas rodadas, até o limite em pé.
	if rule == "leader" and now_round >= last_respawn + info["respawn_every"] and _minions_alive() < info["minions_max"]:
		last_respawn = now_round
		var minions: Array = info["minions"]
		_arrive(minions[minion_turn % minions.size()], events)
		minion_turn += 1
		arrivals += 1


func winner() -> int:
	if not units.any(func(u): return u.alive() and u.team == Data.Team.PLAYER):
		return Data.Team.ENEMY
	if rule == "leader" and leader != null:
		return Data.Team.PLAYER if not leader.alive() else -1
	if rule == "blood":
		return Data.Team.PLAYER if surrendered else -1
	if rule == "survive" and round_now() > info["rounds"]:
		return Data.Team.PLAYER
	if _enemies_alive() or next_wave < waves.size():
		return -1
	return Data.Team.PLAYER


## Planalto: a altura entra mais uma vez no dano (a conta normal já a usa uma vez).
func _status_mult(attacker, target) -> float:
	var mult: float = super(attacker, target)
	if rule == "high_ground":
		var height: int = clampi(elevation_at(attacker.pos) - elevation_at(target.pos), -2, 2)
		mult *= 1.0 + Data.HEIGHT_MULT_PER_LEVEL * height
	return mult


## Linha de andamento para a faixa do topo da arena.
func progress_text() -> String:
	var now_round := round_now()
	match rule:
		"survive":
			return "Rodada %d de %d · resista!" % [mini(now_round, info["rounds"]), info["rounds"]]
		"blood":
			return "Rodada %d · %s: %d/%d de vida · se rende com %d%%" % [now_round, leader.display_name, leader.hp, leader.max_hp, roundi(info["yield_at"] * 100)]
		"leader":
			var hp: int = leader.hp if leader != null else 0
			var max_hp: int = leader.max_hp if leader != null else 1
			return "Rodada %d · %s: %d/%d de vida" % [now_round, leader.display_name if leader != null else "Campeão", hp, max_hp]
		"waves":
			if next_wave < waves.size():
				return "Rodada %d · próximos reforços na rodada %d" % [now_round, waves[next_wave]["round"]]
			return "Rodada %d · derrube quem restou" % now_round
	return "Rodada %d · derrube todos" % now_round
