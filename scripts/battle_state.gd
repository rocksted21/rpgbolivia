extends RefCounted
## Regras do combate, sem nada de tela.
##
## Cada unidade tem um relógio; age sempre quem tem o menor. Toda ação (inclusive
## um único passo) adianta o relógio de quem agiu, então o inimigo pode reagir
## entre dois passos. As ações devolvem uma lista de eventos para a tela animar.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Unit = preload("res://scripts/unit.gd")

const TAUNT_ACTIONS := 2 # turnos em que a IA persegue quem a provocou
const NO_MOVE := Vector2i(-99999, -99999)

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


## Tempo de uma ação: igual a time_for, mas mais lento se a unidade pulou neste turno.
func action_time(base: int, unit) -> int:
	return time_for(roundi(base * jump_penalty(unit)), unit)


func jump_penalty(unit) -> float:
	if not unit.jumped:
		return 1.0
	return Data.JUMP_PENALTY.get(unit.type_id, Data.JUMP_PENALTY_DEFAULT)


## Há fila de turnos agora? A batalha fixa está sempre em combate.
func in_combat() -> bool:
	return true


## Esta unidade anda por turnos agora (gasta movimento)? Na exploração online, quem está
## longe da luta continua andando livre.
func turn_based(_unit) -> bool:
	return in_combat()


## Quem entra na fila de turnos. Na exploração, só o herói e quem está em combate com ele.
func takes_turns(unit) -> bool:
	return unit.alive()


func active_unit():
	var best = null
	for unit in units:
		if takes_turns(unit) and (best == null or unit.clock < best.clock):
			best = unit
	return best


## Próximas unidades a agir, supondo que cada turno dure TURN_TIME.
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
		clocks[best] += time_for(Data.TURN_TIME, best)
	return out


## Quantos turnos dos outros acontecem antes da vez de `unit` (com a mesma suposição
## da fila). Para quem carrega magia, é a contagem até ela sair.
func actions_until(unit, extra := {}) -> int:
	return timeline(units.size() * 6, extra).find(unit)


## A mesma contagem, prevista para antes de carregar a magia.
func cast_wait(unit, ability_id: String) -> int:
	return actions_until(unit, {unit: cast_time_for(unit, ability_id)})


func cast_time_for(unit, ability_id: String) -> int:
	var ability: Dictionary = unit.ability(ability_id)
	return action_time(ability.get("cast_time", ability["time"]), unit)


func recovery_time_for(unit, ability_id: String) -> int:
	# Subtrair os tempos já arredondados conserva exatamente o custo total.
	return maxi(0, action_time(unit.ability(ability_id)["time"], unit) -cast_time_for(unit, ability_id))


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
	if Hex.distance(unit.pos, to) == 2:
		return jump_cells(unit).has(to)
	if Hex.distance(unit.pos, to) != 1 or not can_enter(unit.pos, to):
		return false
	return not turn_based(unit) or step_cost(unit.pos, to) <= move_left(unit)


## Só heróis em combate pulam (a IA e a exploração andam como antes).
func can_jump(unit) -> bool:
	return unit.team == Data.Team.PLAYER and turn_based(unit)


## Onde dá para pular agora: {casa: custo}. Qualquer casa livre a 2 de distância,
## passando por cima do que houver no meio (gente, água, buraco).
func jump_cells(unit) -> Dictionary:
	var out := {}
	if not can_jump(unit):
		return out
	for near in Hex.neighbors(unit.pos):
		for cell in Hex.neighbors(near):
			if out.has(cell) or Hex.distance(unit.pos, cell) != 2 or not can_enter(unit.pos, cell):
				continue
			var cost := jump_cost(unit.pos, cell)
			if cost <= move_left(unit):
				out[cell] = cost
	return out


func jump_cost(from: Vector2i, to: Vector2i) -> int:
	var cost: int = Data.JUMP_TIME + tile_at(to)["cost"]
	if elevation_at(to) > elevation_at(from):
		cost += Data.CLIMB_TIME
	return cost


func move_points(unit) -> int:
	var tiles: int = Data.UNIT_TYPES.get(unit.type_id, {}).get("move", 0)
	# Classe com movimento próprio (ex.: magos andam 2); senão, depende da velocidade.
	var points: int = tiles * Data.STEP_TIME if tiles > 0 else Data.MOVE_BASE + unit.speed * Data.MOVE_PER_SPEED
	points += int(unit.passive("move_bonus", 0)) * Data.STEP_TIME
	if unit.has_status("slow"):
		points -= Data.SLOW_MOVE
	return maxi(0, points)


## Pontos de movimento que ainda restam neste turno.
func move_left(unit) -> int:
	return maxi(0, move_points(unit) - unit.moved)


## Quantas casas planas ainda dá para andar, para mostrar na tela.
func steps_left(unit) -> int:
	return move_left(unit) / Data.STEP_TIME


## Casas ao alcance neste turno: {casa: custo}, sem contar onde a unidade está.
func move_cells(unit) -> Dictionary:
	var reach: Dictionary = search(unit, move_left(unit))["cost"]
	reach.erase(unit.pos)
	return reach


## A casa mais barata de onde `unit` consegue atacar `target` depois de andar; `NO_MOVE` se não houver.
func approach_cell(unit, target) -> Vector2i:
	var best := NO_MOVE
	var best_cost := 999999
	var reach := move_cells(unit)
	for cell in reach:
		if reach[cell] >= best_cost:
			continue
		for id in unit.abilities:
			var ability: Dictionary = unit.ability(id)
			var dist := Hex.distance(cell, target.pos)
			if ability["kind"] == "attack" and dist >= ability["min_range"] and dist <= ability["range"]:
				best = cell
				best_cost = reach[cell]
				break
	return best


## Pula para uma casa a 2 de distância (ver jump_cells). Devolve [] se não der.
func do_jump(unit, to: Vector2i) -> Array:
	if not jump_cells(unit).has(to):
		return []
	return do_step(unit, to)


## Anda até uma casa do alcance, passo a passo. Quem sofre um golpe no caminho e cai para ali.
func do_move(unit, goal: Vector2i) -> Array:
	var found := search(unit, move_left(unit))
	var events := []
	for cell in straight_path(found, unit.pos, goal):
		events.append_array(do_step(unit, cell))
		if not unit.alive():
			break
	return events


func step_cost(from: Vector2i, to: Vector2i) -> int:
	var cost: int = Data.STEP_TIME + tile_at(to)["cost"]
	if elevation_at(to) > elevation_at(from):
		cost += Data.CLIMB_TIME
	return cost


## Dijkstra a partir da unidade: {"cost": {célula: custo}, "prev": {célula: anterior}}.
## Usa um heap e um mapa de quem ocupa cada casa: a IA e os cliques chamam isto o tempo todo.
## `limit` corta a busca nesse custo: o alcance de um turno é bem menor que o mapa.
func search(unit, limit := 999999) -> Dictionary:
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
			if total > limit:
				continue
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
	var jump := Hex.distance(from, to) == 2 # passos andando são sempre de 1 casa
	unit.guarding = false
	if jump:
		unit.moved += jump_cost(from, to)
		unit.jumped = true
	elif turn_based(unit):
		unit.moved += step_cost(from, to)
	else:
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
	events.append({"type": "move", "unit": unit, "from": from, "to": to, "jump": jump})
	return events


## Encerra o turno sem agir: quem só andou atrasa menos que quem atacou.
func do_wait(unit) -> Array:
	unit.guarding = false
	unit.clock += time_for(Data.MOVE_ONLY_TIME if unit.moved > 0 else Data.WAIT_TIME, unit)
	unit.moved = 0
	unit.jumped = false
	var events := [{"type": "wait", "unit": unit}]
	# Postura: quem encerra o turno sem agir fica em Guarda.
	if unit.passive("wait_guard", false) and turn_based(unit):
		unit.guarding = true
		events.append({"type": "guard", "unit": unit, "ability": "guarda"})
	_end_turn(unit, events)
	return events


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
					if not ability.get("dash", false) or dash_cell(unit, cell) != NO_MOVE:
						out.append(cell)
			"heal":
				if occupant != null and occupant.team == unit.team and occupant.hp < occupant.max_hp:
					out.append(cell)
			"buff":
				if occupant != null and occupant.team == unit.team:
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


## Casa onde quem usa uma investida (dash) cai, colada no alvo: a vizinha livre mais perto
## de quem salta. Se já está colado, fica onde está. `NO_MOVE` se não há onde cair.
func dash_cell(unit, target_cell: Vector2i) -> Vector2i:
	if Hex.distance(unit.pos, target_cell) == 1:
		return unit.pos
	var best := NO_MOVE
	var best_dist := 999999
	for cell in Hex.neighbors(target_cell):
		if not in_bounds(cell) or not tile_at(cell)["walkable"]:
			continue
		if unit_at(cell) != null or absi(elevation_at(cell) - elevation_at(target_cell)) > 1:
			continue
		var dist := Hex.distance(unit.pos, cell)
		if dist < best_dist:
			best = cell
			best_dist = dist
	return best


## Dano que um ataque causaria agora, com os motivos (a tela mostra antes do clique).
## A investida conta de onde vai cair (flanco e altura).
func preview_attack(attacker, ability_id: String, target) -> Dictionary:
	var ability: Dictionary = attacker.ability(ability_id)
	var from: Vector2i = attacker.pos
	if ability.get("dash", false):
		var land := dash_cell(attacker, target.pos)
		if land != NO_MOVE:
			from = land
	var flank := false
	var mult := 1.0
	if ability["range"] == 1 or ability.get("dash", false):
		flank = is_flanked(attacker, target, from)
		if flank:
			mult *= attacker.passive("flank_mult", Data.FLANK_MULT)
	var height: int = clampi(elevation_at(from) - elevation_at(target.pos), -2, 2)
	mult *= 1.0 + Data.HEIGHT_MULT_PER_LEVEL * height
	mult *= tile_at(target.pos)["damage"]
	mult *= _protection_mult(target)
	mult *= _status_mult(attacker, target)
	if target.hp * 2 <= target.max_hp:
		mult *= attacker.passive("execute", 1.0)
	var defense: int = 0 if ability.get("pierce", false) else target.def
	var amount := maxi(1, roundi(attacker.atk * ability["power"] * mult) - defense)
	return {"amount": amount, "flank": flank, "height": height, "guard": target.guarding, "cover": tile_at(target.pos)["damage"] < 1.0}


## Redução de dano por Guarda própria, por Véu de Fumaça, por aliado vizinho com Proteção
## (em Guarda) e por aliado vizinho com Névoa (sempre).
func _protection_mult(target) -> float:
	var mult := 1.0
	if target.guarding:
		mult *= target.passive("guard_mult", Data.GUARD_MULT)
	if target.has_status("veil"):
		mult *= Data.VEIL_MULT
	mult *= _neighbor_passive(target, "guard_aura", true)
	mult *= _neighbor_passive(target, "ward")
	return mult


## Multiplicador de um aliado vizinho de `unit` que tem a passiva `key` (o primeiro que achar).
func _neighbor_passive(unit, key: String, needs_guard := false) -> float:
	for ally in allies_of(unit):
		if ally != unit and ally.passives.has(key) and (ally.guarding or not needs_guard) and Hex.distance(ally.pos, unit.pos) == 1:
			return ally.passives[key]
	return 1.0


## Fortalecido bate mais (e quem está ao lado do Estandarte), Cego bate menos; Marcado apanha
## mais (e quem está colado em inimigo com Distração, e o Cego para quem tem Golpe no Escuro).
func _status_mult(attacker, target) -> float:
	var mult := 1.0
	if attacker != null:
		if attacker.has_status("might"):
			mult *= Data.MIGHT_MULT
		if attacker.has_status("blind"):
			mult *= Data.BLIND_MULT
		if target.has_status("blind"):
			mult *= attacker.passive("blind_hunter", 1.0) # Golpe no Escuro
		mult *= _neighbor_passive(attacker, "inspire")
	for foe in enemies_of(target):
		if foe.passives.has("expose") and Hex.distance(foe.pos, target.pos) == 1:
			mult *= foe.passives["expose"]
			break
	if target.has_status("mark"):
		mult *= Data.MARK_MULT
	return mult


## Flanqueio: um aliado do atacante está do lado exatamente oposto do alvo.
## `from` é de onde o golpe sai (a investida bate de onde cai).
func is_flanked(attacker, target, from: Vector2i = NO_MOVE) -> bool:
	if from == NO_MOVE:
		from = attacker.pos
	var dir := Hex.direction_to(target.pos, from)
	if dir < 0:
		return false
	var other = unit_at(Hex.neighbor(target.pos, (dir + 3) % 6))
	return other != null and other != attacker and other.team == attacker.team


func do_ability(unit, ability_id: String, cell: Vector2i) -> Array:
	var ability: Dictionary = unit.ability(ability_id)
	unit.guarding = false
	var events := []
	var now: int = unit.clock
	match ability["kind"]:
		"attack":
			var target = unit_at(cell)
			if ability.get("dash", false):
				var land := dash_cell(unit, cell)
				if land != unit.pos and land != NO_MOVE:
					# Salto: não sofre ataque de oportunidade no caminho.
					events.append({"type": "move", "unit": unit, "from": unit.pos, "to": land, "dash": true})
					unit.pos = land
			var result := preview_attack(unit, ability_id, target)
			unit.clock += action_time(ability["time"], unit)
			events.append({"type": "attack", "unit": unit, "target": target, "ability": ability_id, "label": ability["name"]})
			_apply_damage(target, result["amount"], events, result)
			var steal: float = ability.get("lifesteal", 0.0) + unit.passive("lifesteal", 0.0)
			if steal > 0.0 and unit.alive():
				var back := roundi(result["amount"] * steal)
				if back > 0 and unit.hp < unit.max_hp:
					_heal(unit, unit, back, events)
			if target.alive():
				target.clock += ability.get("delay", 0)
				if ability.has("status"):
					_add_status(target, ability["status"], events)
				if unit.passives.has("hit_status"):
					_add_status(target, unit.passives["hit_status"], events)
				_counter(unit, target, ability, events)
				if ability.has("push") and unit.alive():
					_push(unit, target, ability["push"], events)
			else:
				_on_kill(unit, events)
		"buff":
			var target = unit_at(cell)
			unit.clock += time_for(ability["time"], unit)
			events.append({"type": "buff", "unit": unit, "target": target, "ability": ability_id, "label": ability["name"]})
			if ability.get("guard_ally", false):
				target.guarding = true
			if ability.has("haste") and target != unit:
				# Adianta, mas nunca para antes de agora: ninguém volta no tempo.
				target.clock = maxi(now, target.clock - ability["haste"])
			if ability.get("heal", 0) > 0 and target.hp < target.max_hp:
				_heal(unit, target, ability["heal"], events)
			if ability.has("status"):
				# Em si mesmo o fim deste turno já contaria um: soma um para durar o mesmo.
				_add_status(target, ability["status"], events, 1 if target == unit else 0)
		"heal":
			unit.clock += action_time(ability["time"], unit)
			var total := 0
			for target in units:
				if target.alive() and target.team == unit.team and Hex.distance(target.pos, cell) <= ability.get("radius", 0):
					var healed := _heal(unit, target, ability["heal"], events)
					total += healed
					if unit.passive("heal_guard", false):
						target.guarding = true
					if healed > 0 and target != unit and unit.passives.has("heal_haste"):
						target.clock = maxi(now, target.clock - int(unit.passives["heal_haste"]))
			if unit.passives.has("heal_self") and total > 0:
				_heal(unit, unit, roundi(total * unit.passives["heal_self"]), events)
		"guard":
			unit.clock += action_time(ability["time"], unit)
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
	_rush_on_kill(unit, events, now)
	unit.moved = 0 # qualquer ação encerra o turno
	unit.jumped = false
	_end_turn(unit, events)
	return events


## Frenesi: derrubar um inimigo nesta ação adianta a próxima vez, sem voltar antes de `floor_clock`.
func _rush_on_kill(unit, events: Array, floor_clock: int) -> void:
	if not unit.alive() or not unit.passives.has("kill_haste"):
		return
	if events.any(func(e): return e["type"] == "death" and e["target"].team != unit.team):
		unit.clock = maxi(floor_clock, unit.clock - int(unit.passives["kill_haste"]))


## Fim do turno de `unit`: quem regenera recupera vida, veneno e queimadura doem, e os
## efeitos contam um turno a menos. Fora de combate (exploração) o tempo dos efeitos não corre.
func _end_turn(unit, events: Array) -> void:
	if not unit.alive() or not in_combat():
		return
	if unit.passives.has("regen") and unit.hp < unit.max_hp and turn_based(unit):
		var healed := mini(int(unit.passives["regen"]), unit.max_hp - unit.hp)
		unit.hp += healed
		events.append({"type": "regen", "unit": unit, "amount": healed, "hp": unit.hp})
	if unit.statuses.is_empty():
		return
	for id in unit.statuses.keys():
		var status: Dictionary = unit.statuses[id]
		if Data.STATUS[id].get("dot", false) and status.get("amount", 0) > 0:
			_apply_damage(unit, status["amount"], events, {"dot": id})
			if not unit.alive():
				unit.statuses.clear()
				return
		status["turns"] -= 1
		if status["turns"] <= 0:
			unit.statuses.erase(id)
			events.append({"type": "status_end", "target": unit, "status": id})


## Aplica um efeito de Data.STATUS. Repetir renova: fica o maior tempo e a maior força.
func _add_status(target, status: Dictionary, events: Array, extra_turns := 0) -> void:
	var id: String = status["id"]
	var turns: int = status["turns"] + extra_turns
	var current: Dictionary = target.statuses.get(id, {})
	target.statuses[id] = {
		"turns": maxi(current.get("turns", 0), turns),
		"amount": maxi(current.get("amount", 0), status.get("amount", 0)),
	}
	events.append({"type": "status", "target": target, "status": id, "turns": target.statuses[id]["turns"]})


## Empurra o alvo colado para longe de quem bateu, casa a casa. Se bater em algo
## (obstáculo, degrau alto, borda ou outra unidade), para e leva PUSH_IMPACT; quem
## estava no caminho leva o mesmo. Ser empurrado não provoca ataque de oportunidade.
func _push(unit, target, steps: int, events: Array) -> void:
	var dir := Hex.direction_to(unit.pos, target.pos)
	if dir < 0:
		return
	var start: Vector2i = target.pos
	var blocked := false
	var blocker = null
	for i in steps:
		var to := Hex.neighbor(target.pos, dir)
		if not can_enter(target.pos, to):
			blocked = true
			blocker = unit_at(to) if in_bounds(to) else null
			break
		target.pos = to
	if target.pos != start:
		# Um evento só, da casa inicial até onde parou: a tela desliza numa tacada.
		events.append({"type": "move", "unit": target, "from": start, "to": target.pos, "push": true, "silent": true})
	if not blocked:
		return
	_apply_damage(target, Data.PUSH_IMPACT, events, {"impact": true})
	if not target.alive() and target.team != unit.team:
		_on_kill(unit, events)
	if blocker != null:
		_apply_damage(blocker, Data.PUSH_IMPACT, events, {"impact": true})
		if not blocker.alive() and blocker.team != unit.team:
			_on_kill(unit, events)


## Solta a magia carregada: acerta quem estiver na área agora, aliado ou não.
func resolve_pending(unit) -> Array:
	var ability_id: String = unit.pending["ability"]
	var ability: Dictionary = unit.ability(ability_id)
	var tile: Vector2i = unit.pending["tile"]
	unit.pending = {}
	var impact: int = unit.clock
	unit.clock += recovery_time_for(unit, ability_id)
	var events := [{"type": "cast_resolve", "unit": unit, "ability": ability, "id": ability_id, "tile": tile, "cells": area_of(tile, ability["radius"])}]
	var spare_allies: bool = unit.passive("aoe_safe", false) # Chama Controlada
	for target in units.duplicate():
		if target.alive() and Hex.distance(target.pos, tile) <= ability["radius"]:
			if spare_allies and target.team == unit.team:
				continue
			var mult: float = tile_at(target.pos)["damage"] * _protection_mult(target) * _status_mult(unit, target)
			var amount := maxi(1, roundi(unit.atk * ability["power"] * mult) - target.def)
			_apply_damage(target, amount, events, {})
			if not target.alive() and target.team != unit.team:
				_on_kill(unit, events)
			elif target.alive():
				if ability.has("status"):
					_add_status(target, ability["status"], events)
				if unit.passives.has("hit_status"):
					_add_status(target, unit.passives["hit_status"], events)
	_rush_on_kill(unit, events, impact)
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


## Revide ao apanhar corpo a corpo: Contragolpe só em Guarda, Riposta sempre.
func _counter(attacker, target, ability: Dictionary, events: Array) -> void:
	if ability["range"] != 1:
		return
	var power := 0.0
	var label := "contragolpe"
	if target.guarding and target.passives.has("counter"):
		power = target.passives["counter"]
	elif target.passives.has("riposte"):
		power = target.passives["riposte"]
		label = "riposta"
	if power <= 0.0:
		return
	var amount := maxi(1, roundi(target.atk * power) - attacker.def)
	events.append({"type": "attack", "unit": target, "target": attacker, "label": label})
	_apply_damage(attacker, amount, events, {"opportunity": true})


func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	target.hp = maxi(0, target.hp - amount)
	var event := {"type": "damage", "target": target, "amount": amount, "hp": target.hp}
	event.merge(info)
	events.append(event)
	if not target.alive():
		target.pending = {}
		events.append({"type": "death", "target": target})
