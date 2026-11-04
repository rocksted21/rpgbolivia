extends "res://scripts/battle_state.gd"
## Regras da exploração: mapa sem bordas, um herói e inimigos que surgem pelo caminho.
## O combate em si continua sendo o de battle_state.gd.

const WorldGen = preload("res://scripts/world_gen.gd")

var gen
var hero
var rng := RandomNumberGenerator.new()
var start_cell: Vector2i
var kills := 0
var farthest := 0
var steps_until_spawn := 0
var heading := Vector2.ZERO # direção da caminhada: os grupos surgem preferindo a frente


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


func do_step(unit, to: Vector2i) -> Array:
	var from: Vector2i = unit.pos
	var events: Array = super(unit, to)
	if unit == hero and hero.alive() and hero.pos == to:
		farthest = maxi(farthest, Hex.distance(start_cell, to))
		steps_until_spawn -= 1
		heading = _flat(to) - _flat(from)
		_rest(events)
	return events


func _rest(events: Array) -> void:
	if hero.hp >= hero.max_hp:
		return
	for enemy in enemies_of(hero):
		if Hex.distance(enemy.pos, hero.pos) <= Data.WORLD["rest_radius"]:
			return
	var healed: int = mini(Data.WORLD["rest_heal"], hero.max_hp - hero.hp)
	hero.hp += healed
	events.append({"type": "regen", "unit": hero, "amount": healed, "hp": hero.hp})


func _apply_damage(target, amount: int, events: Array, info: Dictionary) -> void:
	super(target, amount, events, info)
	if target.alive() or target == hero:
		return
	kills += 1
	if hero.alive() and hero.hp < hero.max_hp:
		var healed: int = mini(Data.WORLD["kill_heal"], hero.max_hp - hero.hp)
		hero.hp += healed
		events.append({"type": "regen", "unit": hero, "amount": healed, "hp": hero.hp})


# --- Surgimento dos inimigos -------------------------------------------------

## Chamado entre as ações. Remove quem morreu ou ficou para trás e cria novos grupos.
func tick() -> Array:
	var events := []
	for unit in units.duplicate():
		if unit == hero:
			continue
		var lost: bool = Hex.distance(unit.pos, hero.pos) > Data.WORLD["despawn_radius"] and unit.pending.is_empty()
		if not unit.alive() or lost:
			units.erase(unit)
			events.append({"type": "despawn", "unit": unit})
	if steps_until_spawn <= 0:
		var spawn_steps: Array = Data.WORLD["spawn_steps"]
		steps_until_spawn = rng.randi_range(spawn_steps[0], spawn_steps[1])
		events.append_array(_spawn_group())
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
