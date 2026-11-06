extends RefCounted
## IA simples: usa a melhor habilidade disponível; se não houver alvo, anda um
## passo rumo à casa mais próxima de onde conseguiria atacar.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

const KILL_BONUS := 20
const CHARGE_HIT_SCORE := 12
const CHARGE_FRIENDLY_PENALTY := 18
const HEAL_BELOW := 0.6
const STATUS_SCORE := 4 # efeito novo no alvo (marca, lentidão, veneno...)
const PUSH_SCORE := 2
const BUFF_SCORE := 8
# Escolha de alvo no começo do turno (ver _choose_focus).
const FRAGILE_DEF := 2 # defesa até isso conta como alvo frágil
const FRAGILE_SCORE := 6
const BACKLINE_SCORE := 4 # quem ataca de longe (mago, besteiro, druida) vale mais
const WOUNDED_SCORE := 6 # proporcional à vida que já falta
const RISK_WEIGHT := 1.0 # quanto pesa cada ponto de dano de oportunidade levado no caminho
const DIVE_CHANCE := 0.5 # passar pelo tanque nem sempre: às vezes o inimigo prefere a briga certa


## Devolve {"kind": "ability", "id", "cell"}, {"kind": "step", "cell"} ou {"kind": "wait"}.
static func decide(state, unit) -> Dictionary:
	var taunter = unit.taunted_by if unit.taunted_by != null and unit.taunted_by.alive() else null
	if taunter != null:
		var forced := _act(state, unit, taunter)
		if not forced.is_empty():
			return forced
		# Sem caminho até quem provocou: a provocação não pode travar a unidade.
		unit.taunted_by = null
	# O alvo do turno é escolhido uma vez, antes do primeiro passo.
	if unit.moved == 0:
		unit.ai_focus = _choose_focus(state, unit)
	if unit.ai_focus != null and unit.ai_focus.alive():
		var chosen := _act(state, unit, unit.ai_focus)
		if not chosen.is_empty():
			return chosen
	unit.ai_focus = null
	var free := _act(state, unit, null)
	return free if not free.is_empty() else {"kind": "wait"}


## Melhor habilidade (só contra `focus`, se houver); senão um passo rumo a onde dá para
## atacar. {} quando não há o que fazer.
static func _act(state, unit, focus) -> Dictionary:
	var best := {}
	var best_score := 0
	for id in unit.abilities:
		for cell in state.valid_targets(unit, id):
			if focus != null and not _hits(unit, id, cell, focus):
				continue
			var score := _score(state, unit, id, cell)
			if score > best_score:
				best_score = score
				best = {"kind": "ability", "id": id, "cell": cell}
	if not best.is_empty():
		return best

	# Quase sempre o alvo está ao alcance deste turno; a busca pelo mapa todo fica para quando não está.
	var found: Dictionary = state.search(unit, state.move_left(unit))
	var goal = _nearest_spot(state, unit, found, focus)
	if goal == null:
		found = state.search(unit)
		goal = _nearest_spot(state, unit, found, focus)
	if goal != null and goal != unit.pos:
		var next: Vector2i = state.path_from_search(found, goal)[0]
		return {"kind": "step", "cell": next} if state.can_step(unit, next) else {"kind": "wait"}
	return {}


## Quem vale a pena atacar neste turno, entre os alvos que dá para alcançar andando.
## Prefere os frágeis e feridos. Se o caminho passa colado num inimigo (ataque de
## oportunidade do Guardião, por exemplo), só vai quando o golpe compensa o dano levado,
## não morre no caminho e, mesmo assim, só às vezes. null: segue a regra simples.
static func _choose_focus(state, unit):
	if not unit.pending.is_empty() or not unit.abilities.any(func(id): return unit.ability(id)["kind"] == "attack"):
		return null
	var stay := 0 # o melhor que dá para fazer sem sair do lugar
	for id in unit.abilities:
		for cell in state.valid_targets(unit, id):
			stay = maxi(stay, _score(state, unit, id, cell))
	var found: Dictionary = state.search(unit, state.move_left(unit))
	var best = null
	var best_net := 0.0
	var best_risk := 0
	for target in state.enemies_of(unit):
		var goal = _nearest_spot(state, unit, found, target)
		if goal == null:
			continue
		var path: Array = [] if goal == unit.pos else state.path_from_search(found, goal)
		var risk := _path_risk(state, unit, path)
		if risk * 2 >= unit.hp:
			continue
		var net := float(_attack_value(state, unit, target) + _fragility(target)) - risk * RISK_WEIGHT - stay
		if net > best_net:
			best_net = net
			best = target
			best_risk = risk
	if best != null and best_risk > 0 and _roll(state) > DIVE_CHANCE:
		return null
	return best


## Dano de oportunidade que a unidade leva andando por este caminho.
static func _path_risk(state, unit, path: Array) -> int:
	if unit.passive("opportunity_immune", false):
		return 0
	var risk := 0
	var from: Vector2i = unit.pos
	for cell in path:
		for enemy in state.enemies_of(unit):
			if Hex.distance(enemy.pos, from) == 1 and Hex.distance(enemy.pos, cell) > 1 and state._can_react(enemy):
				risk += maxi(1, roundi(enemy.atk * Data.OPPORTUNITY_POWER * enemy.passive("opportunity_mult", 1.0)) - unit.def)
		from = cell
	return risk


## O melhor golpe direto contra o alvo, com bônus se mata.
static func _attack_value(state, unit, target) -> int:
	var best := 0
	for id in unit.abilities:
		if unit.ability(id)["kind"] != "attack":
			continue
		var amount: int = state.preview_attack(unit, id, target)["amount"]
		best = maxi(best, amount + (KILL_BONUS if amount >= target.hp else 0))
	return best


static func _fragility(target) -> int:
	var score := roundi(WOUNDED_SCORE * (1.0 - float(target.hp) / target.max_hp))
	if target.def <= FRAGILE_DEF:
		score += FRAGILE_SCORE
	var ranged: bool = target.abilities.any(func(id):
		var ability: Dictionary = target.ability(id)
		return (ability["kind"] == "attack" or ability["kind"] == "heal") and ability["range"] > 1 and not ability.get("dash", false))
	if ranged:
		score += BACKLINE_SCORE
	return score


static func _roll(state) -> float:
	return state.rng.randf() if "rng" in state else randf()


static func _nearest_spot(state, unit, found: Dictionary, taunter):
	var goal = null
	for cell in found["cost"]:
		if _can_hit_from(state, unit, cell, taunter) and (goal == null or found["cost"][cell] < found["cost"][goal]):
			goal = cell
	return goal


static func apply(state, unit, action: Dictionary) -> Array:
	if action["kind"] == "wait":
		unit.taunt_actions -= 1 # conta turnos, não passos
	if action["kind"] == "ability" or unit.taunt_actions <= 0:
		unit.taunted_by = null
	match action["kind"]:
		"ability":
			return state.do_ability(unit, action["id"], action["cell"])
		"step":
			return state.do_step(unit, action["cell"])
	return state.do_wait(unit)


## A habilidade mirada nesta casa atinge `target`?
static func _hits(unit, id: String, cell: Vector2i, target) -> bool:
	var ability: Dictionary = unit.ability(id)
	match ability["kind"]:
		"attack":
			return cell == target.pos
		"charge":
			return Hex.distance(target.pos, cell) <= ability["radius"]
	return false


static func _score(state, unit, id: String, cell: Vector2i) -> int:
	var ability: Dictionary = unit.ability(id)
	match ability["kind"]:
		"attack":
			var target = state.unit_at(cell)
			var amount: int = state.preview_attack(unit, id, target)["amount"]
			if amount >= target.hp:
				return amount + KILL_BONUS
			var extra := 0
			if ability.has("status") and not target.has_status(ability["status"]["id"]):
				extra += STATUS_SCORE
			if ability.has("push"):
				extra += PUSH_SCORE
			if ability.has("lifesteal") and unit.hp < unit.max_hp:
				extra += roundi(amount * ability["lifesteal"])
			return amount + extra
		"buff":
			return _buff_score(state, unit, ability, state.unit_at(cell))
		"heal":
			var target = state.unit_at(cell)
			return ability["heal"] if float(target.hp) / target.max_hp < HEAL_BELOW else 0
		"charge":
			var score := 0
			for other in state.units:
				if other.alive() and Hex.distance(other.pos, cell) <= ability["radius"]:
					score += CHARGE_HIT_SCORE if other.team != unit.team else -CHARGE_FRIENDLY_PENALTY
			return score
	return 0


## Ajuda em aliado só vale perto da briga: Guarda em quem está ferido e colado num
## inimigo, Fortalecer e adiantar quem tem inimigo por perto.
static func _buff_score(state, unit, ability: Dictionary, target) -> int:
	var near: bool = state.enemies_of(target).any(func(enemy): return Hex.distance(enemy.pos, target.pos) <= 2)
	if not near:
		return 0
	var score := 0
	if ability.get("guard_ally", false) and not target.guarding and target.hp * 10 < target.max_hp * 6:
		score += BUFF_SCORE
	if ability.has("haste") and target != unit and target.pending.is_empty():
		score += BUFF_SCORE - 2
	if ability.has("status") and not target.has_status(ability["status"]["id"]):
		score += BUFF_SCORE - 1
	return score


static func _can_hit_from(state, unit, cell: Vector2i, only = null) -> bool:
	for id in unit.abilities:
		var ability: Dictionary = unit.ability(id)
		if ability["kind"] != "attack" and ability["kind"] != "charge":
			continue
		for enemy in ([only] if only != null else state.enemies_of(unit)):
			var dist := Hex.distance(cell, enemy.pos)
			if dist >= ability["min_range"] and dist <= ability["range"]:
				return true
	return false
