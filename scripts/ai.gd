extends RefCounted
## IA simples: usa a melhor habilidade disponível; se não houver alvo, anda um
## passo rumo à casa mais próxima de onde conseguiria atacar.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

const KILL_BONUS := 20
const CHARGE_HIT_SCORE := 12
const CHARGE_FRIENDLY_PENALTY := 18
const HEAL_BELOW := 0.6


## Devolve {"kind": "ability", "id", "cell"}, {"kind": "step", "cell"} ou {"kind": "wait"}.
static func decide(state, unit) -> Dictionary:
	var taunter = unit.taunted_by if unit.taunted_by != null and unit.taunted_by.alive() else null
	var best := {}
	var best_score := 0
	for id in unit.abilities:
		for cell in state.valid_targets(unit, id):
			if taunter != null and not _hits(unit, id, cell, taunter):
				continue
			var score := _score(state, unit, id, cell)
			if score > best_score:
				best_score = score
				best = {"kind": "ability", "id": id, "cell": cell}
	if not best.is_empty():
		return best

	var found: Dictionary = state.search(unit)
	var goal = null
	for cell in found["cost"]:
		if _can_hit_from(state, unit, cell, taunter) and (goal == null or found["cost"][cell] < found["cost"][goal]):
			goal = cell
	if goal != null and goal != unit.pos:
		return {"kind": "step", "cell": state.path_from_search(found, goal)[0]}
	if taunter != null:
		# Sem caminho até quem provocou: a provocação não pode travar a unidade.
		unit.taunted_by = null
		return decide(state, unit)
	return {"kind": "wait"}


static func apply(state, unit, action: Dictionary) -> Array:
	unit.taunt_actions -= 1
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
			return amount + (KILL_BONUS if amount >= target.hp else 0)
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
