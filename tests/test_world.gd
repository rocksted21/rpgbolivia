extends SceneTree
## Regras da exploração, sem tela: mapa gerado, surgimento de inimigos e fim de jogo.
## Rodar: godot --headless --path . --script tests/test_world.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const AI = preload("res://scripts/ai.gd")
const WorldState = preload("res://scripts/world_state.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	test_generation()
	test_biomes()
	test_negative_coordinates()
	test_no_trap()
	test_rules()
	test_spawning()
	test_full_runs()
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_generation() -> void:
	var a = WorldGen.new(42)
	var b = WorldGen.new(42)
	var c = WorldGen.new(43)
	var same := true
	var different := false
	var kinds := {}
	for row in range(-60, 60):
		for col in range(-60, 60):
			var cell := Vector2i(col, row)
			same = same and a.sample(cell) == b.sample(cell)
			different = different or a.sample(cell) != c.sample(cell)
			kinds[a.sample(cell)["terrain"]] = kinds.get(a.sample(cell)["terrain"], 0) + 1
			check(Data.TERRAIN.has(a.sample(cell)["terrain"]), "terreno existe nos dados")
	check(same, "mesma semente gera o mesmo mapa")
	check(different, "semente diferente gera outro mapa")
	var total := 120 * 120
	var blocked := 0
	for id in kinds:
		if not Data.TERRAIN[id]["walkable"]:
			blocked += kinds[id]
	check(blocked < total * 0.3, "obstáculos não dominam o mapa (%d%%)" % (blocked * 100 / total))
	check(kinds.size() >= 5, "mapa variado (%d tipos)" % kinds.size())
	print("Terreno em 120x120 (id: %%): ", _percent(kinds, total))


func test_biomes() -> void:
	var counts := {}
	var blocked := {}
	var met_new_biome := 0
	var runs := 30
	for world_seed in runs:
		var gen = WorldGen.new(world_seed * 311 + 3)
		var start: Vector2i = gen.find_start()
		for row in range(-90, 90, 2):
			for col in range(-90, 90, 2):
				var spot: Dictionary = gen.sample(Vector2i(col, row))
				counts[spot["biome"]] = counts.get(spot["biome"], 0) + 1
				if not Data.TERRAIN[spot["terrain"]]["walkable"]:
					blocked[spot["biome"]] = blocked.get(spot["biome"], 0) + 1
		# Uma jornada típica precisa cruzar a fronteira de um bioma.
		var nearby := {}
		for row in range(start.y - 35, start.y + 36, 2):
			for col in range(start.x - 35, start.x + 36, 2):
				nearby[gen.sample(Vector2i(col, row))["biome"]] = true
		met_new_biome += 1 if nearby.size() >= 2 else 0
	var total := 0
	for biome in counts:
		total += counts[biome]
	check(counts.size() == Data.BIOMES.size(), "todos os biomas aparecem")
	for biome in Data.BIOMES:
		var share: float = counts.get(biome, 0) * 100.0 / total
		check(share >= 12.0, "%s ocupa parte do mundo (%.0f%%)" % [biome, share])
		var closed: float = blocked.get(biome, 0) * 100.0 / maxi(counts.get(biome, 0), 1)
		check(closed < 35.0, "%s não fica fechado por obstáculos (%.0f%%)" % [biome, closed])
		print("%s: %.0f%% do mundo, %.0f%% de obstáculos" % [biome, share, closed])
		_check_art(biome)
	check(met_new_biome >= runs * 0.8, "jornadas encontram outro bioma (%d de %d)" % [met_new_biome, runs])
	print("Jornadas com outro bioma a até 35 casas: %d de %d" % [met_new_biome, runs])
	# Bioma muda o nome da casa, não a regra.
	var state = WorldState.new("duelista", 5)
	for row in range(-60, 60):
		for col in range(-60, 60):
			var cell := Vector2i(col, row)
			if state.biome_at(cell) == "deserto" and state.terrain_id_at(cell) == WorldGen.FOREST:
				check(state.tile_name_at(cell) == "Cactos", "floresta no deserto tem outro nome")
				check(state.tile_at(cell)["cost"] == Data.TERRAIN[WorldGen.FOREST]["cost"], "regra igual em todo bioma")
				return


func _check_art(biome: String) -> void:
	check(ResourceLoader.exists(BiomeArt.wall(biome)), "%s tem parede" % biome)
	for id in Data.TERRAIN:
		check(ResourceLoader.exists(BiomeArt.ground(biome, id)), "%s tem piso do terreno %d" % [biome, id])
		for detail in [0.01, 0.05, 0.09, 0.3, 0.8]:
			for prop in BiomeArt.props(biome, id, detail):
				check(ResourceLoader.exists(prop["path"]), "arte existe: %s" % prop["path"])


func _percent(kinds: Dictionary, total: int) -> Dictionary:
	var out := {}
	for id in kinds:
		out[id] = kinds[id] * 100 / total
	return out


func test_negative_coordinates() -> void:
	# Andar e voltar pelas seis direções, em casas com linha e coluna negativas.
	for cell in [Vector2i(-3, -3), Vector2i(-4, -2), Vector2i(0, -1), Vector2i(-1, 0)]:
		for dir in 6:
			var next: Vector2i = Hex.neighbor(cell, dir)
			check(Hex.distance(cell, next) == 1, "vizinha a 1 casa de %s" % cell)
			check(Hex.neighbor(next, (dir + 3) % 6) == cell, "direção oposta volta a %s" % cell)


func test_no_trap() -> void:
	for world_seed in 40:
		var gen = WorldGen.new(world_seed * 977)
		var start: Vector2i = gen.find_start()
		check(gen.walkable(start), "início caminhável, semente %d" % world_seed)
		check(gen.reachable_count(start, 1500) >= 1500, "início não fica preso, semente %d" % world_seed)
		for cell in Hex.neighbors(start):
			check(gen.walkable(cell), "clareira em volta do início, semente %d" % world_seed)


func test_rules() -> void:
	var state = WorldState.new("duelista", 7)
	check(state.winner() == -1, "sozinho no mapa o jogo continua")
	check(state.active_unit() == state.hero, "herói age quando está sozinho")
	check(state.units.size() == 1, "começa só com o herói")
	check(state.area_of(state.hero.pos, 1).size() == 7, "área de raio 1 tem 7 casas")
	check(state.area_of(state.hero.pos, 2).size() == 19, "área de raio 2 tem 19 casas")
	var far := Vector2i(state.hero.pos.x + 200, state.hero.pos.y)
	check(not state.can_step(state.hero, far), "casa distante não é passo")
	check(not state.in_bounds(far), "IA não procura caminho longe do herói")
	check(state.exists(far), "o mapa continua existindo longe do herói")
	var found: Dictionary = state.search(state.hero)
	check(found["cost"].size() <= 1 + 3 * 14 * 15, "busca limitada à área em jogo")
	state.hero.hp = 0
	check(state.winner() == Data.Team.ENEMY, "herói morto encerra a jornada")


func test_spawning() -> void:
	var state = WorldState.new("guardiao", 11)
	check(state.tick().is_empty(), "ninguém surge antes de andar")
	state.steps_until_spawn = 0
	var hero_clock: int = state.hero.clock
	var events: Array = state.tick()
	check(events.size() >= 1 and events[0]["type"] == "spawn", "grupo surge ao completar os passos")
	var foe = events[0]["unit"]
	var dist: int = Hex.distance(foe.pos, state.hero.pos)
	check(dist >= Data.WORLD["spawn_min"] and dist <= Data.WORLD["spawn_max"], "surge fora de alcance imediato (%d casas)" % dist)
	check(foe.clock > hero_clock, "inimigo novo não age antes do herói")
	check(state.tile_at(foe.pos)["walkable"], "surge em casa caminhável")
	check(state.steps_until_spawn >= Data.WORLD["spawn_steps"][0], "contagem recomeça")
	foe.pos = state.hero.pos + Vector2i(40, 0)
	var removed: Array = state.tick().filter(func(e): return e["type"] == "despawn" and e["unit"] == foe)
	check(removed.size() == 1 and not state.units.has(foe), "inimigo muito longe some")
	var dead = state.add_unit("esqueleto", Data.Team.ENEMY, Hex.neighbor(state.hero.pos, 0))
	state.hero.hp = 10
	var hit: Array = []
	dead.hp = 1
	state._apply_damage(dead, 5, hit, {})
	check(state.kills == 1, "abate contado")
	check(state.hero.hp == 10 + Data.WORLD["kill_heal"], "abate recupera vida")
	state.tick()
	check(not state.units.has(dead), "morto sai da lista")
	# O perigo sobe e fortalece quem surge depois.
	var base: int = Data.UNIT_TYPES["esqueleto"]["hp"]
	state.farthest = 100
	check(state.danger() > 1, "perigo sobe com a distância")
	var strong = state._spawn_enemy("esqueleto", state.hero.pos + Vector2i(5, 0))
	check(strong.max_hp > base, "inimigo mais forte longe do início")


## Jogadas completas com o herói guiado pela IA: acha travamentos e mede a dificuldade.
func test_full_runs() -> void:
	var rows := []
	for type_id in Data.WORLD_HEROES:
		var distances := []
		var kills := []
		for world_seed in 12:
			var result := _play_run(type_id, world_seed * 131 + 5)
			check(result["ended"], "%s, semente %d: jornada avança sem travar" % [type_id, world_seed])
			distances.append(result["distance"])
			kills.append(result["kills"])
		distances.sort()
		kills.sort()
		rows.append("%-10s distância mediana %3d (%d–%d) · abates %2d" % [type_id, distances[6], distances[0], distances[11], kills[6]])
	print("\n".join(rows))


func _play_run(type_id: String, world_seed: int) -> Dictionary:
	var state = WorldState.new(type_id, world_seed)
	var actions := 0
	var last_progress := 0
	var last_farthest := 0
	var healed_last := false
	while state.winner() < 0 and actions < 4000 and state.farthest < 400:
		actions += 1
		state.tick()
		var unit = state.active_unit()
		if not unit.pending.is_empty():
			state.resolve_pending(unit)
		elif unit == state.hero and state.enemies_of(unit).is_empty():
			_walk_on(state)
		else:
			var action: Dictionary = AI.decide(state, unit)
			var healing: bool = action["kind"] == "ability" and Data.ABILITIES[action["id"]]["kind"] == "heal"
			# A IA curaria para sempre contra um inimigo fraco; uma pessoa revezaria com o ataque.
			if unit == state.hero and healing and healed_last:
				action = _attack_or_walk(state)
			if unit == state.hero:
				healed_last = healing and not action.is_empty()
			if action.is_empty() or (unit == state.hero and action["kind"] == "wait"):
				_walk_on(state)
			else:
				AI.apply(state, unit, action)
		if state.farthest > last_farthest:
			last_farthest = state.farthest
			last_progress = actions
		if actions - last_progress > 1200:
			return {"ended": false, "distance": state.farthest, "kills": state.kills}
	return {"ended": true, "distance": state.farthest, "kills": state.kills}


func _attack_or_walk(state) -> Dictionary:
	for id in state.hero.abilities:
		if Data.ABILITIES[id]["kind"] == "attack" and not state.valid_targets(state.hero, id).is_empty():
			return {"kind": "ability", "id": id, "cell": state.valid_targets(state.hero, id)[0]}
	return {}


## Anda rumo à casa alcançável mais distante do início.
func _walk_on(state) -> void:
	var found: Dictionary = state.search(state.hero)
	var goal: Vector2i = state.hero.pos
	var best := -1
	for cell in found["cost"]:
		var far: int = Hex.distance(cell, state.start_cell)
		if far > best:
			best = far
			goal = cell
	var path: Array = state.path_from_search(found, goal)
	if path.is_empty():
		state.do_wait(state.hero)
	else:
		state.do_step(state.hero, path[0])
