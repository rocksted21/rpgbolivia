extends RefCounted
## A luta da Névoa Densa: o Andarilho da Fumaça antes de entrar no roster (ver recruits.gd).
##   - Ele chega com ilusões: mesmo nome, mesma folha (só um pouco transparentes) e a mesma vida.
##     Qualquer golpe desfaz uma ilusão, mas quem a golpeou de perto ou de longe fica Cego.
##     Magia em área desfaz ilusões sem cegar ninguém: é a resposta de quem pensa.
##   - Ao perder vida ele some na fumaça (VANISH_AT): surgem ilusões novas e ele troca de lugar
##     com uma delas.
##   - Ele não morre. Com YIELD_AT da vida ou menos, se rende: a luta acaba e ele entra no roster.
## Tudo fica no próprio local ("guards": o Andarilho primeiro, depois as ilusões), então volta com o save.

const Exp = preload("res://scripts/expedition_data.gd")
const Data = preload("res://scripts/game_data.gd")

const RIVAL := "fumaca_rival"
const ILLUSION := "fumaca_ilusao"
const HP_MULT := 2.6 # elite: entre a 1ª e a 2ª Sentinela
const ATK_MULT := 1.1
const START_ILLUSIONS := 2
const VANISH_ILLUSIONS := 2 # quantas surgem a cada vez que ele some
const MAX_ILLUSIONS := 4 # nunca mais que isso de pé ao mesmo tempo
const VANISH_AT := [0.7, 0.45] # frações da vida em que ele some e troca de lugar
const YIELD_AT := 0.25
const BLIND := {"id": "blind", "turns": 2}
const FIGHT_COLOR := Color(0.72, 0.62, 0.95)


static func is_illusion(unit) -> bool:
	return unit != null and unit.type_id == ILLUSION


## Acorda a Névoa Densa: o Andarilho e as primeiras ilusões, em volta do local.
static func wake(state, cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var spots: Array = state._spots_around(cell, START_ILLUSIONS + 1)
	if spots.is_empty():
		return
	var rival = state._spawn_enemy(RIVAL, spots[0])
	rival.max_hp = roundi(rival.max_hp * HP_MULT)
	rival.hp = rival.max_hp
	rival.atk = roundi(rival.atk * ATK_MULT)
	rival.passives["aoe_safe"] = true # a Nuvem Cegante dele não desfaz as próprias ilusões
	events.append({"type": "spawn", "unit": rival})
	var guards := [rival]
	for i in range(1, spots.size()):
		guards.append(_spawn_illusion(state, rival, spots[i], events))
	entry["state"] = "fighting"
	entry["guards"] = guards
	entry["phase"] = 0
	entry["vanish"] = false
	entry["yield"] = false
	events.append({"type": "landmark", "cell": cell, "title": "Andarilho da Fumaça",
		"detail": "Qual deles é o verdadeiro? Golpear uma ilusão deixa você cego.\nMagia em área desfaz as ilusões sem esse risco.",
		"done": false, "color": FIGHT_COLOR})
	events.append_array(state.engage(guards, true))


## Antes do dano: o Andarilho nunca cai, ele se rende (ver after_damage).
static func cap_damage(state, target, amount: int) -> int:
	var entry := _entry_of(state, target)
	if entry.is_empty() or target != entry["guards"][0]:
		return amount
	return mini(amount, maxi(0, target.hp - 1))


## Depois do dano. Devolve true se o alvo era uma ilusão (não conta como abate nem dá experiência).
static func after_damage(state, target, events: Array) -> bool:
	var entry := _entry_of(state, target)
	if entry.is_empty():
		return false
	var rival = entry["guards"][0]
	if target != rival:
		if target.alive(): # qualquer golpe desfaz a ilusão
			target.hp = 0
			target.pending = {}
			events.append({"type": "death", "target": target})
		var attacker = _attacker(events)
		if attacker != null and attacker.alive() and state.is_hero(attacker):
			state._add_status(attacker, BLIND, events)
		return true
	_mirror(state, entry, events)
	var share: float = float(rival.hp) / rival.max_hp
	if share <= YIELD_AT:
		entry["yield"] = true
	elif entry["phase"] < VANISH_AT.size() and share <= VANISH_AT[entry["phase"]]:
		entry["phase"] += 1
		entry["vanish"] = true
	return false


## Entre as ações (ExpeditionState.tick): some na fumaça ou se rende.
static func tick(state, events: Array) -> void:
	for cell in state.landmarks:
		var entry: Dictionary = state.landmarks[cell]
		if entry["kind"] != "andarilho" or entry["state"] != "fighting" or entry["guards"].is_empty():
			continue
		if not state.units.has(entry["guards"][0]):
			continue
		if entry.get("yield", false):
			_surrender(state, cell, entry, events)
		elif entry.get("vanish", false):
			entry["vanish"] = false
			_vanish(state, cell, entry, events)


## Ilusões novas surgem e ele troca de lugar com uma delas: some de um lado, aparece no outro.
static func _vanish(state, cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var rival = entry["guards"][0]
	var standing: Array = _illusions(state, entry)
	var room: int = mini(VANISH_ILLUSIONS, MAX_ILLUSIONS - standing.size())
	var fresh := []
	for spot in state._spots_around(rival.pos, room):
		var unit = _spawn_illusion(state, rival, spot, events)
		entry["guards"].append(unit)
		fresh.append(unit)
	if not fresh.is_empty():
		events.append_array(state.engage(fresh, false))
	var pool: Array = _illusions(state, entry)
	if pool.is_empty():
		return
	var other = pool[state.rng.randi_range(0, pool.size() - 1)]
	# A tela troca as duas figuras de uma vez: some e reaparece (despawn/spawn), sem caminhar.
	events.append({"type": "despawn", "unit": rival})
	events.append({"type": "despawn", "unit": other})
	var spot: Vector2i = rival.pos
	rival.pos = other.pos
	other.pos = spot
	events.append({"type": "spawn", "unit": rival})
	events.append({"type": "spawn", "unit": other})
	events.append({"type": "landmark", "cell": cell, "title": "Fumaça!", "detail": "Ele sumiu entre as ilusões.", "done": false, "color": FIGHT_COLOR})


## Ele se rende: some da luta, e a party ganha o prêmio do local e um herói novo.
static func _surrender(state, cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var was_fighting: bool = state.in_combat()
	for unit in entry["guards"]:
		if state.units.has(unit):
			state.units.erase(unit)
			state.engaged.erase(unit)
			events.append({"type": "despawn", "unit": unit})
	entry["state"] = "done"
	entry["yield"] = false
	var data: Dictionary = Exp.LANDMARKS["andarilho"]
	state.brasas += data["brasas"]
	events.append({"type": "landmark", "cell": cell, "title": "O Andarilho da Fumaça se rende",
		"detail": "\"Chega. Vocês enxergam através da fumaça.\"\nEle agora pode entrar na party, na Cidade-Farol. +%d brasas." % data["brasas"],
		"done": true, "color": FIGHT_COLOR})
	state._gain_xp(data["xp"], events)
	if was_fighting and not state.in_combat() and state.winner() < 0:
		state.reinforce_left = 0
		events.append({"type": "combat_end", "fled": false})
		state._after_combat(events)


static func _spawn_illusion(state, rival, cell: Vector2i, events: Array):
	var unit = state._spawn_enemy(ILLUSION, cell)
	unit.max_hp = rival.max_hp # mesma barra de vida: de longe, não dá para saber
	unit.hp = rival.hp
	events.append({"type": "spawn", "unit": unit})
	return unit


## As ilusões acompanham a vida dele, para a barra não entregar quem é quem.
static func _mirror(state, entry: Dictionary, events: Array) -> void:
	var rival = entry["guards"][0]
	for unit in _illusions(state, entry):
		if unit.hp != rival.hp:
			unit.hp = rival.hp
			events.append({"type": "regen", "unit": unit, "amount": 0, "hp": unit.hp, "quiet": true})


static func _illusions(state, entry: Dictionary) -> Array:
	return entry["guards"].filter(func(unit): return is_illusion(unit) and unit.alive() and state.units.has(unit))


## O local da Névoa Densa em luta que tem esta unidade; {} se ela não é de lá.
static func _entry_of(state, unit) -> Dictionary:
	if unit == null or (unit.type_id != RIVAL and unit.type_id != ILLUSION):
		return {}
	for cell in state.landmarks:
		var entry: Dictionary = state.landmarks[cell]
		if entry["kind"] == "andarilho" and entry["state"] == "fighting" and unit in entry["guards"]:
			return entry
	return {}


## Quem desferiu o golpe que está sendo resolvido: o último ataque direto da lista.
## Magia carregada (cast_resolve) não conta: a área desfaz ilusões sem cegar.
static func _attacker(events: Array):
	for i in range(events.size() - 1, -1, -1):
		var kind: String = events[i].get("type", "")
		if kind == "attack":
			return events[i]["unit"]
		if kind == "cast_resolve":
			return null
	return null
