extends "res://scripts/battle_state.gd"
## Regras da exploração: mapa sem bordas, um herói e inimigos que surgem pelo caminho.
## Fora de combate o herói anda livre e não há fila. O combate começa quando um inimigo
## vê o herói ou é atacado, e as ações dentro dele são as de battle_state.gd.

const WorldGen = preload("res://scripts/world_gen.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")

var gen
var party := [] # os heróis, sempre no começo de units e na mesma ordem
var hero # o primeiro da party; quem precisa de um só (testes, capturas) usa este
var rng := RandomNumberGenerator.new()
var start_cell: Vector2i
var kills := 0
var farthest := 0
var steps_until_spawn := 0.0
var heading := Vector2.ZERO # direção da caminhada: os grupos surgem preferindo a frente
var last_walker # quem andou por último: os grupos surgem perto dele
var engaged := {} # inimigos em combate com a party; os outros ainda não a viram
var known := {} # toda unidade já vista, por uid: eventos podem citar quem já saiu do mapa


## `heroes`: tipos dos heróis, ou um só. `builds`: nós da árvore, por índice na party,
## ou a lista de nós quando há um herói só.
func _init(heroes: Variant, world_seed: int, builds: Variant = {}) -> void:
	super()
	builds_used = builds.duplicate(true)
	rng.seed = world_seed
	gen = WorldGen.new(world_seed)
	start_cell = gen.find_start()
	var types: Array = heroes if heroes is Array else [heroes]
	var spots: Array = [start_cell] + Hex.neighbors(start_cell).filter(func(cell): return gen.walkable(cell))
	for i in types.size():
		var build: Array = builds if builds is Array else builds.get(i, [])
		var member = add_unit(types[i], Data.Team.PLAYER, spots[i % spots.size()], build)
		member.abilities = member.abilities + Data.WORLD_EXTRA_ABILITIES.get(types[i], [])
		party.append(member)
	hero = party[0]
	last_walker = hero
	steps_until_spawn = float(Data.WORLD["first_spawn_steps"])


func add_unit(type_id: String, team: int, pos: Vector2i, build: Array = []):
	var unit = super(type_id, team, pos, build)
	known[unit.uid] = unit
	return unit


func unit_by_uid(uid: int):
	return known.get(uid)


func is_hero(unit) -> bool:
	return party.has(unit)


func alive_party() -> Array:
	return party.filter(func(u): return u.alive())


func foes() -> Array:
	return units.filter(func(u): return u.alive() and not party.has(u))


## Distância até o herói vivo mais perto.
func party_distance(cell: Vector2i) -> int:
	var best := 999999
	for member in party:
		if member.hp > 0:
			best = mini(best, Hex.distance(member.pos, cell))
	if best == 999999: # todos caídos: a conta ainda precisa de uma resposta
		best = Hex.distance(hero.pos, cell)
	return best


# --- Mapa sem bordas ---------------------------------------------------------

func exists(_cell: Vector2i) -> bool:
	return true


## "Dentro do jogo" é a área em volta da party: limita a busca de caminho da IA.
func in_bounds(cell: Vector2i) -> bool:
	return party_distance(cell) <= Data.WORLD["active_radius"]


func terrain_id_at(cell: Vector2i) -> int:
	return gen.sample(cell)["terrain"]


func tile_at(cell: Vector2i) -> Dictionary:
	return Data.TERRAIN[terrain_id_at(cell)]


## Peças de piso que ligam esta casa às vizinhas: caminho, margem e transição de bioma.
func ground_overlays(cell: Vector2i) -> Array:
	return BiomeArt.overlays(biome_at(cell), terrain_id_at(cell), elevation_at(cell), gen.path_links(cell), func(dir: int) -> Dictionary:
		var next: Vector2i = Hex.neighbor(cell, dir)
		return {"biome": biome_at(next), "terrain": terrain_id_at(next), "elevation": elevation_at(next)}, gen.road_links(cell))


## O piso desenhado na casa. Na cidade, o chão continua aparecendo embaixo do que bloqueia.
func floor_id_at(cell: Vector2i) -> int:
	return terrain_id_at(cell)


func elevation_at(cell: Vector2i) -> int:
	return gen.sample(cell)["elevation"]


func biome_at(cell: Vector2i) -> String:
	return gen.sample(cell)["biome"]


func detail_at(cell: Vector2i) -> float:
	return gen.sample(cell)["detail"]


## A regra da casa não muda com o bioma; só o nome (Floresta vira Cactos no deserto).
func tile_name_at(cell: Vector2i) -> String:
	return Data.BIOMES[biome_at(cell)]["names"].get(terrain_id_at(cell), super(cell))


func cells_in_range(unit, ability_id: String) -> Array:
	var ability: Dictionary = unit.ability(ability_id)
	return _disc(unit.pos, ability["range"]).filter(func(cell):
		return Hex.distance(unit.pos, cell) >= ability["min_range"])


func area_of(tile: Vector2i, radius: int) -> Array:
	return _disc(tile, radius)


func _disc(center: Vector2i, radius: int) -> Array:
	var out := []
	for row in range(center.y - radius, center.y + radius + 1):
		for col in range(center.x - radius - 1, center.x + radius + 2):
			var cell := Vector2i(col, row)
			if Hex.distance(cell, center) <= radius:
				out.append(cell)
	return out


# --- Fim de jogo e progresso -------------------------------------------------

## A exploração nunca é vencida: ela acaba quando a party inteira cai.
func winner() -> int:
	return -1 if not alive_party().is_empty() else Data.Team.ENEMY


func danger() -> int:
	return mini(1 + farthest / int(Data.WORLD["danger_distance"]), Data.WORLD["danger_max"])


# --- Exploração e combate ----------------------------------------------------

func in_combat() -> bool:
	return not engaged.is_empty()


func takes_turns(unit) -> bool:
	return unit.alive() and (party.has(unit) or engaged.has(unit))


## Coloca inimigos em combate. Fora de combate cada herói andou no seu ritmo, então os
## relógios recomeçam juntos e ninguém ganha uma fila de ações de graça. Se a party foi
## vista (`surprised`), age primeiro quem for mais rápido; se foi ela quem atacou, `opener`
## sai na frente. Quem chega a um combate já em andamento espera um passo.
func engage(foes_list: Array, surprised: bool, opener = null) -> Array:
	var joining := foes_list.filter(func(u): return u.alive() and not engaged.has(u))
	if joining.is_empty():
		return []
	var starting := not in_combat()
	var now: int = 0
	var opening := []
	if starting:
		opening = _deploy(joining, opener)
		for member in alive_party():
			now = maxi(now, member.clock)
		for member in alive_party():
			member.clock = now if member == opener else now + time_for(Data.STEP_TIME, member)
	else:
		now = active_unit().clock
	for unit in joining:
		engaged[unit] = true
		unit.clock = now + time_for(Data.STEP_TIME, unit)
	return opening + [{"type": "combat_start" if starting else "combat_join", "units": joining, "surprised": surprised}]


## Quando o combate começa, a fila se desfaz: cada herói anda até uma casa próxima, separado
## dos outros, mas ainda perto. Quem luta de perto vai à frente; quem ataca de longe fica atrás. Quem abriu o
## ataque não sai do lugar, porque já mirou.
func _deploy(foes_list: Array, opener) -> Array:
	var events := []
	if party.size() < 2:
		return events
	for member in alive_party():
		if member == opener:
			continue
		var best: Vector2i = member.pos
		var best_score := _deploy_score(member, member.pos, foes_list) + 0.5 # só sai se valer a pena
		for cell in _cells_within(member, Data.WORLD["deploy_steps"]):
			var score := _deploy_score(member, cell, foes_list)
			if score > best_score:
				best_score = score
				best = cell
		if best != member.pos:
			events.append({"type": "deploy", "unit": member, "from": member.pos, "to": best})
			member.pos = best
	return events


func _deploy_score(member, cell: Vector2i, foes_list: Array) -> float:
	var ally_gap := 999
	for other in alive_party():
		if other != member:
			ally_gap = mini(ally_gap, Hex.distance(other.pos, cell))
	var foe_gap := 999
	for foe in foes_list:
		foe_gap = mini(foe_gap, Hex.distance(foe.pos, cell))
	# O ideal é uma casa livre entre os heróis: separados, mas perto uns dos outros.
	var score := 20.0 if ally_gap == 2 else (10.0 if ally_gap == 3 else (0.0 if ally_gap == 1 else -5.0))
	if foe_gap <= 1:
		score -= 25.0 # ninguém começa a luta colado num inimigo
	score += -foe_gap if _is_melee(member) else mini(foe_gap, 4)
	return score


func _is_melee(unit) -> bool:
	for id in unit.abilities:
		var ability: Dictionary = unit.ability(id)
		if (ability["kind"] == "attack" or ability["kind"] == "charge") and ability["range"] > 1:
			return false
	return true


## Casas livres a até `steps` passos da unidade, respeitando degraus e obstáculos.
func _cells_within(unit, steps: int) -> Array:
	var seen := {unit.pos: true}
	var frontier := [unit.pos]
	for i in steps:
		var next_frontier := []
		for cell in frontier:
			for next in Hex.neighbors(cell):
				if not seen.has(next) and can_enter(cell, next):
					seen[next] = true
					next_frontier.append(next)
		frontier = next_frontier
	seen.erase(unit.pos)
	return seen.keys()


## Quem vê a party agora, junto com os companheiros próximos de quem viu.
func _spotters() -> Array:
	var idle: Array = foes().filter(func(u): return not engaged.has(u))
	var seen: Array = idle.filter(func(u): return party_distance(u.pos) <= Data.WORLD["sight_radius"] and _can_reach_party(u))
	if seen.is_empty():
		return []
	return idle.filter(func(u):
		return seen.any(func(s): return Hex.distance(u.pos, s.pos) <= Data.WORLD["group_radius"]) and _can_reach_party(u))


## Atrás de uma serra ou no alto de um penhasco, o inimigo não entra na luta: ninguém chegaria nele.
func _can_reach_party(unit) -> bool:
	var reach: Dictionary = search(unit, Data.WORLD["sight_walk"])["cost"]
	for member in alive_party():
		if Hex.neighbors(member.pos).any(func(cell): return reach.has(cell)):
			return true
	return false


func sight_cells(unit) -> Array:
	return area_of(unit.pos, Data.WORLD["sight_radius"])


## O ataque do herói a quem não o viu começa o combate antes de o golpe sair.
func do_ability(unit, ability_id: String, cell: Vector2i) -> Array:
	var intro := []
	var kind: String = unit.ability(ability_id)["kind"]
	if party.has(unit) and not in_combat() and (kind == "attack" or kind == "charge"):
		var radius: int = int(unit.ability(ability_id).get("radius", 0)) + Data.WORLD["group_radius"]
		intro = engage(foes().filter(func(u): return Hex.distance(u.pos, cell) <= radius), false, unit)
	return intro + super(unit, ability_id, cell)


func do_step(unit, to: Vector2i) -> Array:
	var from: Vector2i = unit.pos
	var events: Array = super(unit, to)
	if party.has(unit) and unit.alive() and unit.pos == to:
		farthest = maxi(farthest, Hex.distance(start_cell, to))
		heading = _flat(to) - _flat(from)
		last_walker = unit
		if not in_combat():
			steps_until_spawn -= 1.0 / alive_party().size() # conta passos da party, não de cada herói
			_rest(unit, events)
			var walkers := []
			_wander(walkers)
			return walkers + events # andam junto com o herói, não depois dele
	return events


## Inimigo sem caminho até a party e longe dela desiste, para o combate não ficar preso.
func do_wait(unit) -> Array:
	var events: Array = super(unit)
	if engaged.has(unit) and party_distance(unit.pos) > Data.WORLD["give_up_radius"]:
		engaged.erase(unit)
	return events


## Quem ainda não viu o herói anda à toa, para o mundo não parecer parado.
func _wander(events: Array) -> void:
	for unit in foes():
		if engaged.has(unit) or rng.randf() > Data.WORLD["wander_chance"]:
			continue
		var options: Array = Hex.neighbors(unit.pos).filter(func(cell): return can_enter(unit.pos, cell))
		if options.is_empty():
			continue
		var to: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		events.append({"type": "wander", "unit": unit, "from": unit.pos, "to": to})
		unit.pos = to


func _distance_to_any_hero(cell: Vector2i) -> int:
	var best := 999999
	for member in party:
		best = mini(best, Hex.distance(member.pos, cell))
	return best


func _rest(unit, events: Array) -> void:
	if unit.hp >= unit.max_hp:
		return
	var healed: int = mini(Data.WORLD["rest_heal"], unit.max_hp - unit.hp)
	unit.hp += healed
	events.append({"type": "regen", "unit": unit, "amount": healed, "hp": unit.hp, "quiet": true})


## O herói pode dar esse passo sem se afastar demais da party? Sempre pode voltar.
func may_roam(unit, to: Vector2i) -> bool:
	for member in alive_party():
		if member == unit:
			continue
		var distance := Hex.distance(member.pos, to)
		if distance > Data.WORLD["party_leash"] and distance >= Hex.distance(member.pos, unit.pos):
			return false
	return true


func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	super(target, amount, events, info)
	if party.has(target):
		return
	if target.alive():
		events.append_array(engage([target], false)) # quem apanha sem ter visto entra na luta
		return
	kills += 1
	var hurt: Array = alive_party().filter(func(u): return u.hp < u.max_hp)
	if hurt.is_empty():
		return
	hurt.sort_custom(func(a, b): return float(a.hp) / a.max_hp < float(b.hp) / b.max_hp)
	var healed: int = mini(Data.WORLD["kill_heal"], hurt[0].max_hp - hurt[0].hp)
	hurt[0].hp += healed
	events.append({"type": "regen", "unit": hurt[0], "amount": healed, "hp": hurt[0].hp})


# --- Surgimento dos inimigos -------------------------------------------------

## Chamado entre as ações: remove quem morreu ou ficou para trás, encerra o combate
## quando não sobra ninguém nele, cria novos grupos e vê quem avistou o herói.
func tick() -> Array:
	var events := []
	var was_fighting := in_combat()
	var escaped := false
	for unit in units.duplicate():
		if party.has(unit):
			continue
		var distance := party_distance(unit.pos)
		# Quem caiu conta: senão o combate acaba ao lado dele, ele levanta ali e tudo recomeça.
		if engaged.has(unit) and unit.alive() and _distance_to_any_hero(unit.pos) > Data.WORLD["flee_radius"] and unit.pending.is_empty():
			engaged.erase(unit)
			escaped = true
		var lost: bool = distance > Data.WORLD["despawn_radius"] and unit.pending.is_empty()
		if not unit.alive() or lost:
			engaged.erase(unit)
			units.erase(unit)
			events.append({"type": "despawn", "unit": unit})
	if was_fighting and not in_combat() and winner() < 0:
		events.append({"type": "combat_end", "fled": escaped})
		_after_combat(events)
	if not in_combat() and steps_until_spawn <= 0:
		var spawn_steps: Array = Data.WORLD["spawn_steps"]
		steps_until_spawn = float(rng.randi_range(spawn_steps[0], spawn_steps[1]))
		events.append_array(_spawn_group())
	if winner() < 0:
		events.append_array(engage(_spotters(), true))
	return events


## Fim do combate: ninguém fica com magia pela metade, e quem caiu volta ferido.
func _after_combat(events: Array) -> void:
	for member in party:
		member.moved = 0
		member.guarding = false
		member.pending = {}
		if not member.alive():
			member.hp = maxi(1, roundi(member.max_hp * Data.WORLD["revive_hp"]))
			events.append({"type": "revive", "unit": member, "hp": member.hp})


func _spawn_group() -> Array:
	var room := max_enemies() - foes().size()
	var count := mini(room, group_size())
	if count <= 0:
		return []
	var spots := _spawn_spots()
	var events := []
	if spots.is_empty():
		return events
	var anchor: Vector2i = spots[0]
	spots.sort_custom(func(a, b): return Hex.distance(a, anchor) < Hex.distance(b, anchor))
	for i in mini(count, spots.size()):
		events.append({"type": "spawn", "unit": _spawn_enemy(_pick_type(), spots[i])})
	return events


## Mais heróis, mais inimigos: cada herói além do primeiro abre vaga e engrossa os grupos.
func max_enemies() -> int:
	return mini(2 + danger() / 2, 6) + (party.size() - 1) * Data.WORLD["party_enemies"]


func group_size() -> int:
	var extra: int = (party.size() - 1) * Data.WORLD["party_group"]
	return rng.randi_range(1 + extra, mini(1 + danger() / 2, 4) + extra)


## Casas válidas na borda da névoa, a mais à frente da caminhada primeiro.
func _spawn_spots() -> Array:
	var found: Dictionary = search(last_walker)
	var spots := []
	for cell in found["cost"]:
		var distance := party_distance(cell)
		if distance < Data.WORLD["spawn_min"] or Hex.distance(cell, last_walker.pos) > Data.WORLD["spawn_max"]:
			continue
		if unit_at(cell) == null:
			spots.append(cell)
	if spots.is_empty():
		return spots
	var scores := {}
	for cell in spots:
		var away: Vector2 = _flat(cell) - _flat(last_walker.pos)
		scores[cell] = away.normalized().dot(heading.normalized()) + rng.randf() * 0.8
	spots.sort_custom(func(a, b): return scores[a] > scores[b])
	return spots


func _flat(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + (cell.y & 1) * 0.5, cell.y * 0.866)


func _pick_type() -> String:
	var allowed: Array = Data.WORLD_SPAWNS.filter(func(entry): return entry["danger"] <= danger())
	var total := 0
	for entry in allowed:
		total += entry["weight"]
	var roll := rng.randi_range(1, total)
	for entry in allowed:
		roll -= entry["weight"]
		if roll <= 0:
			return entry["type"]
	return allowed[0]["type"]


func _spawn_enemy(type_id: String, cell: Vector2i):
	var unit = add_unit(type_id, Data.Team.ENEMY, cell)
	var level := danger() - 1
	unit.max_hp = roundi(unit.max_hp * (1.0 + Data.WORLD["danger_hp"] * level))
	unit.hp = unit.max_hp
	unit.atk = roundi(unit.atk * (1.0 + Data.WORLD["danger_atk"] * level))
	return unit


# --- Rede ----------------------------------------------------------------------
## O dono simula; os outros recebem o estado completo e só animam.

func snapshot() -> Dictionary:
	var rows := []
	for unit in units:
		rows.append({
			uid = unit.uid, type = unit.type_id, pos = unit.pos, hp = unit.hp, max_hp = unit.max_hp, atk = unit.atk,
			clock = unit.clock, moved = unit.moved, guarding = unit.guarding, pending = unit.pending.duplicate(true), engaged = engaged.has(unit),
		})
	return {units = rows, kills = kills, farthest = farthest}


func apply_snapshot(data: Dictionary) -> void:
	var seen := {}
	engaged.clear()
	for row in data.units:
		seen[row.uid] = true
		var unit = known.get(row.uid)
		if unit == null:
			unit = add_unit(row.type, Data.Team.ENEMY, row.pos)
			known.erase(unit.uid)
			unit.uid = row.uid
			known[unit.uid] = unit
		if not units.has(unit):
			units.append(unit)
		unit.pos = row.pos
		unit.hp = row.hp
		unit.max_hp = row.max_hp
		unit.atk = row.atk
		unit.clock = row.clock
		unit.moved = row.moved
		unit.guarding = row.guarding
		unit.pending = row.pending.duplicate(true)
		if row.engaged:
			engaged[unit] = true
	for unit in units.duplicate():
		if not seen.has(unit.uid):
			units.erase(unit)
	kills = data.kills
	farthest = data.farthest
