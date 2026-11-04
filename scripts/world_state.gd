extends "res://scripts/battle_state.gd"
## Regras da exploração: mapa sem bordas, um herói e inimigos que surgem pelo caminho.
## Fora de combate o herói anda livre e não há fila. O combate começa quando um inimigo
## vê o herói ou é atacado, e as ações dentro dele são as de battle_state.gd.

const WorldGen = preload("res://scripts/world_gen.gd")

var gen
var hero
var rng := RandomNumberGenerator.new()
var start_cell: Vector2i
var kills := 0
var farthest := 0
var steps_until_spawn := 0
var heading := Vector2.ZERO # direção da caminhada: os grupos surgem preferindo a frente
var engaged := {} # inimigos em combate com o herói; os outros ainda não o viram


func _init(hero_type: String, world_seed: int, build: Array = []) -> void:
	super()
	rng.seed = world_seed
	gen = WorldGen.new(world_seed)
	start_cell = gen.find_start()
	hero = add_unit(hero_type, Data.Team.PLAYER, start_cell, build)
	hero.abilities = hero.abilities + Data.WORLD_EXTRA_ABILITIES.get(hero_type, [])
	steps_until_spawn = Data.WORLD["first_spawn_steps"]


# --- Mapa sem bordas ---------------------------------------------------------

func exists(_cell: Vector2i) -> bool:
	return true


## "Dentro do jogo" é a área em volta do herói: limita a busca de caminho da IA.
func in_bounds(cell: Vector2i) -> bool:
	return Hex.distance(cell, hero.pos) <= Data.WORLD["active_radius"]


func terrain_id_at(cell: Vector2i) -> int:
	return gen.sample(cell)["terrain"]


func tile_at(cell: Vector2i) -> Dictionary:
	return Data.TERRAIN[terrain_id_at(cell)]


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

## A exploração nunca é vencida: ela acaba quando o herói cai.
func winner() -> int:
	return -1 if hero.alive() else Data.Team.ENEMY


func danger() -> int:
	return mini(1 + farthest / int(Data.WORLD["danger_distance"]), Data.WORLD["danger_max"])


# --- Exploração e combate ----------------------------------------------------

func in_combat() -> bool:
	return not engaged.is_empty()


func takes_turns(unit) -> bool:
	return unit.alive() and (unit == hero or engaged.has(unit))


## Coloca inimigos em combate. O relógio de cada um parte do atual, para ninguém ganhar
## uma fila de ações de graça. Se o herói foi visto (`surprised`), ele também espera a
## sua vez: age primeiro quem for mais rápido. Se foi ele quem atacou, ele sai na frente.
func engage(foes: Array, surprised: bool) -> Array:
	var joining := foes.filter(func(u): return u.alive() and not engaged.has(u))
	if joining.is_empty():
		return []
	var starting := not in_combat()
	if starting and surprised:
		hero.clock += time_for(Data.STEP_TIME, hero)
	var base: int = hero.clock - (time_for(Data.STEP_TIME, hero) if starting and surprised else 0)
	for unit in joining:
		engaged[unit] = true
		unit.clock = base + time_for(Data.STEP_TIME, unit)
	return [{"type": "combat_start" if starting else "combat_join", "units": joining, "surprised": surprised}]


## Quem vê o herói agora, junto com os companheiros próximos de quem viu.
func _spotters() -> Array:
	var idle: Array = enemies_of(hero).filter(func(u): return not engaged.has(u))
	var seen: Array = idle.filter(func(u): return Hex.distance(u.pos, hero.pos) <= Data.WORLD["sight_radius"])
	if seen.is_empty():
		return []
	return idle.filter(func(u):
		return seen.any(func(s): return Hex.distance(u.pos, s.pos) <= Data.WORLD["group_radius"]))


func sight_cells(unit) -> Array:
	return area_of(unit.pos, Data.WORLD["sight_radius"])


## O ataque do herói a quem não o viu começa o combate antes de o golpe sair.
func do_ability(unit, ability_id: String, cell: Vector2i) -> Array:
	var intro := []
	var kind: String = unit.ability(ability_id)["kind"]
	if unit == hero and not in_combat() and (kind == "attack" or kind == "charge"):
		var radius: int = int(unit.ability(ability_id).get("radius", 0)) + Data.WORLD["group_radius"]
		intro = engage(enemies_of(hero).filter(func(u): return Hex.distance(u.pos, cell) <= radius), false)
	return intro + super(unit, ability_id, cell)


func do_step(unit, to: Vector2i) -> Array:
	var from: Vector2i = unit.pos
	var events: Array = super(unit, to)
	if unit == hero and hero.alive() and hero.pos == to:
		farthest = maxi(farthest, Hex.distance(start_cell, to))
		heading = _flat(to) - _flat(from)
		if not in_combat():
			steps_until_spawn -= 1
			_rest(events)
			var walkers := []
			_wander(walkers)
			return walkers + events # andam junto com o herói, não depois dele
	return events


## Quem ainda não viu o herói anda à toa, para o mundo não parecer parado.
func _wander(events: Array) -> void:
	for unit in enemies_of(hero):
		if engaged.has(unit) or rng.randf() > Data.WORLD["wander_chance"]:
			continue
		var options: Array = Hex.neighbors(unit.pos).filter(func(cell): return can_enter(unit.pos, cell))
		if options.is_empty():
			continue
		var to: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		events.append({"type": "wander", "unit": unit, "from": unit.pos, "to": to})
		unit.pos = to


func _rest(events: Array) -> void:
	if hero.hp >= hero.max_hp:
		return
	var healed: int = mini(Data.WORLD["rest_heal"], hero.max_hp - hero.hp)
	hero.hp += healed
	events.append({"type": "regen", "unit": hero, "amount": healed, "hp": hero.hp})


func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	super(target, amount, events, info)
	if target == hero:
		return
	if target.alive():
		events.append_array(engage([target], false)) # quem apanha sem ter visto entra na luta
		return
	kills += 1
	if hero.alive() and hero.hp < hero.max_hp:
		var healed: int = mini(Data.WORLD["kill_heal"], hero.max_hp - hero.hp)
		hero.hp += healed
		events.append({"type": "regen", "unit": hero, "amount": healed, "hp": hero.hp})


# --- Surgimento dos inimigos -------------------------------------------------

## Chamado entre as ações: remove quem morreu ou ficou para trás, encerra o combate
## quando não sobra ninguém nele, cria novos grupos e vê quem avistou o herói.
func tick() -> Array:
	var events := []
	var was_fighting := in_combat()
	var escaped := false
	for unit in units.duplicate():
		if unit == hero:
			continue
		var distance := Hex.distance(unit.pos, hero.pos)
		if engaged.has(unit) and unit.alive() and distance > Data.WORLD["flee_radius"] and unit.pending.is_empty():
			engaged.erase(unit)
			escaped = true
		var lost: bool = distance > Data.WORLD["despawn_radius"] and unit.pending.is_empty()
		if not unit.alive() or lost:
			engaged.erase(unit)
			units.erase(unit)
			events.append({"type": "despawn", "unit": unit})
	if was_fighting and not in_combat():
		hero.guarding = false
		events.append({"type": "combat_end", "fled": escaped})
	if not in_combat() and steps_until_spawn <= 0:
		var spawn_steps: Array = Data.WORLD["spawn_steps"]
		steps_until_spawn = rng.randi_range(spawn_steps[0], spawn_steps[1])
		events.append_array(_spawn_group())
	events.append_array(engage(_spotters(), true))
	return events


func _spawn_group() -> Array:
	var room := max_enemies() - enemies_of(hero).size()
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


func max_enemies() -> int:
	return mini(2 + danger() / 2, 6)


func group_size() -> int:
	return rng.randi_range(1, mini(1 + danger() / 2, 4))


## Casas válidas na borda da névoa, a mais à frente da caminhada primeiro.
func _spawn_spots() -> Array:
	var found: Dictionary = search(hero)
	var spots := []
	for cell in found["cost"]:
		var dist := Hex.distance(cell, hero.pos)
		var row_gap: int = cell.y - hero.pos.y
		if dist < Data.WORLD["spawn_min"] or dist > Data.WORLD["spawn_max"] or row_gap > 4:
			continue
		if unit_at(cell) == null:
			spots.append(cell)
	if spots.is_empty():
		return spots
	var scores := {}
	for cell in spots:
		var away: Vector2 = _flat(cell) - _flat(hero.pos)
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
	# O relógio começa no do herói: quem surge não ganha uma fila de ações de graça.
	unit.clock = hero.clock + time_for(Data.STEP_TIME, unit)
	var level := danger() - 1
	unit.max_hp = roundi(unit.max_hp * (1.0 + Data.WORLD["danger_hp"] * level))
	unit.hp = unit.max_hp
	unit.atk = roundi(unit.atk * (1.0 + Data.WORLD["danger_atk"] * level))
	return unit
