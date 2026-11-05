extends SceneTree
## Regras da exploração, sem tela: mapa gerado, surgimento de inimigos e fim de jogo.
## Rodar: godot --headless --path . --script tests/test_world.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const AI = preload("res://scripts/ai.gd")
const WorldState = preload("res://scripts/world_state.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")

const SIM_RUNS := 3

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
	test_paths()
	test_negative_coordinates()
	test_no_trap()
	test_rules()
	test_spawning()
	test_party()
	test_network()
	test_combat_flow()
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


## O caminho é uma rede: a ligação vale dos dois lados, nenhuma casa fica solta e dá para andar nele.
func test_paths() -> void:
	const AREA := 110
	for world_seed in [3, 42, 77]:
		var gen = WorldGen.new(world_seed)
		var seen := {}
		var biggest := 0
		var total := 0
		var loose := 0
		for row in range(-AREA, AREA):
			for col in range(-AREA, AREA):
				var cell := Vector2i(col, row)
				if not gen.is_path(cell):
					continue
				total += 1
				var links: Array = gen.path_links(cell)
				check(gen.sample(cell)["terrain"] in [WorldGen.PATH, WorldGen.BRIDGE], "caminho vira terreno de caminho")
				check(gen.walkable(cell), "dá para andar no caminho")
				loose += 1 if links.is_empty() else 0
				for dir in links:
					check(gen.path_links(Hex.neighbor(cell, dir)).has((dir + 3) % 6), "a ligação vale dos dois lados")
				if seen.has(cell):
					continue
				var size := 0
				var frontier := [cell]
				seen[cell] = true
				while not frontier.is_empty():
					var current: Vector2i = frontier.pop_back()
					size += 1
					for dir in gen.path_links(current):
						var next: Vector2i = Hex.neighbor(current, dir)
						if not seen.has(next) and absi(next.x) < AREA and absi(next.y) < AREA:
							seen[next] = true
							frontier.append(next)
				biggest = maxi(biggest, size)
		check(loose == 0, "nenhuma casa de caminho fica solta (%d)" % loose)
		check(biggest >= total / 4, "o caminho forma trechos longos (%d de %d)" % [biggest, total])
		print("Caminho, semente %d: %d casas, maior trecho %d, soltas %d" % [world_seed, total, biggest, loose])
	for biome in Data.BIOMES:
		for piece in ["trilha", "trilha_0", "trilha_5", "borda_0", "borda_5", "margem_0", "margem_5"]:
			check(ResourceLoader.exists(BiomeArt.ROOT % [biome, piece]), "%s tem a peça %s" % [biome, piece])
	for piece in ["ponte", "ponte_0", "ponte_5"]:
		check(ResourceLoader.exists(BiomeArt.COMMON % piece), "existe a peça %s" % piece)


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
	var events: Array = state.tick()
	check(events.size() >= 1 and events[0]["type"] == "spawn", "grupo surge ao completar os passos")
	var foe = events[0]["unit"]
	var dist: int = Hex.distance(foe.pos, state.hero.pos)
	check(dist >= Data.WORLD["spawn_min"] and dist <= Data.WORLD["spawn_max"], "surge fora de alcance imediato (%d casas)" % dist)
	check(not state.takes_turns(foe), "quem surge não entra na fila antes de ver a party")
	check(state.tile_at(foe.pos)["walkable"], "surge em casa caminhável")
	check(state.steps_until_spawn >= Data.WORLD["spawn_steps"][0], "contagem recomeça")
	foe.pos = state.hero.pos + Vector2i(40, 0)
	var removed: Array = state.tick().filter(func(e): return e["type"] == "despawn" and e["unit"] == foe)
	check(removed.size() == 1 and not state.units.has(foe), "inimigo muito longe some")
	var dead = state.add_unit("esqueleto", Data.Team.ENEMY, Hex.neighbor(state.hero.pos, 0))
	state.engage([dead], false)
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


## Um inimigo a `distance` casas do herói, na mesma linha.
func _foe_at(state, distance: int, type_id := "esqueleto"):
	return state.add_unit(type_id, Data.Team.ENEMY, state.hero.pos + Vector2i(distance, 0))


func _kinds(events: Array) -> Array:
	return events.map(func(e): return e["type"])


func test_party() -> void:
	var state = WorldState.new(Data.DEFAULT_PARTY, 31)
	check(state.party.size() == 4 and state.units.size() == 4, "party com 4 heróis")
	var spots := {}
	for member in state.party:
		spots[member.pos] = true
		check(state.tile_at(member.pos)["walkable"], "herói em casa caminhável")
	check(spots.size() == 4, "cada herói na sua casa")
	# Andar sozinho e voltar.
	var loner = state.party[1]
	var other = state.party[0]
	loner.pos = other.pos + Vector2i(Data.WORLD["party_leash"], 0)
	var away: Vector2i = loner.pos + Vector2i(1, 0)
	var back: Vector2i = loner.pos - Vector2i(1, 0)
	check(not state.may_roam(loner, away), "herói não se afasta além do limite")
	check(state.may_roam(loner, back), "herói sempre pode voltar")
	loner.pos = state.party[2].pos + Vector2i(0, 1)
	# Qualquer herói é visto.
	var foe = state.add_unit("esqueleto", Data.Team.ENEMY, state.party[3].pos + Vector2i(Data.WORLD["sight_radius"], 0))
	var events: Array = state.tick()
	check(_kinds(events).has("combat_start"), "ver qualquer herói inicia o combate")
	check(state.turn_order().size() == 5, "toda a party entra na fila (%d)" % state.turn_order().size())
	# Queda e fim.
	state.party[1].hp = 0
	check(state.winner() == -1, "a jornada continua com heróis de pé")
	check(not state.turn_order().has(state.party[1]), "quem caiu sai da fila")
	foe.hp = 0
	var ended: Array = state.tick()
	check(_kinds(ended).has("combat_end"), "combate termina")
	check(_kinds(ended).has("revive") and state.party[1].alive(), "quem caiu volta ao fim do combate")
	check(state.party[1].hp == roundi(state.party[1].max_hp * Data.WORLD["revive_hp"]), "volta ferido")
	for member in state.party:
		member.hp = 0
	check(state.winner() == Data.Team.ENEMY, "party inteira caída encerra a jornada")
	var doomed: Array = state.tick()
	check(not _kinds(doomed).has("revive"), "sem volta se todos caíram")
	_test_deploy()
	_test_straight_path()
	# O ataque de um herói faz dele o primeiro a agir de novo só depois do custo.
	var ambush = WorldState.new(Data.DEFAULT_PARTY, 32)
	var mage = ambush.party[2]
	var prey = ambush.add_unit("mumia", Data.Team.ENEMY, mage.pos + Vector2i(3, 0))
	ambush.party[2].clock = 500
	ambush.do_ability(mage, "faisca", prey.pos)
	check(ambush.in_combat() and prey.clock >= 500, "relógios recomeçam juntos no combate")
	# Abate cura o mais ferido.
	var heal = WorldState.new(Data.DEFAULT_PARTY, 33)
	heal.party[0].hp = 10
	heal.party[1].hp = heal.party[1].max_hp - 1
	var target = heal.add_unit("diabrete", Data.Team.ENEMY, heal.party[0].pos + Vector2i(4, 0))
	heal.engage([target], false)
	target.hp = 1
	var hit: Array = []
	heal._apply_damage(target, 5, hit, {})
	check(heal.party[0].hp == 10 + Data.WORLD["kill_heal"], "abate cura o herói mais ferido")


## Procura um trecho aberto do mapa, para a fila ter onde se abrir.
func _open_ground(state) -> Vector2i:
	for row in range(-40, 40, 3):
		for col in range(-40, 40, 3):
			var center := Vector2i(col, row)
			var clear := true
			for cell in state.area_of(center, 5):
				var near_center: bool = state.elevation_at(cell) == state.elevation_at(center) and state.tile_at(cell)["walkable"]
				clear = clear and near_center
			if clear:
				return center
	return Vector2i.ZERO


func _adjacent_pairs(state) -> int:
	var pairs := 0
	for i in state.party.size():
		for j in range(i + 1, state.party.size()):
			if Hex.distance(state.party[i].pos, state.party[j].pos) == 1:
				pairs += 1
	return pairs


func _test_deploy() -> void:
	var state = WorldState.new(Data.DEFAULT_PARTY, 34)
	var center := _open_ground(state)
	# A party em fila, um colado no outro.
	for i in state.party.size():
		state.party[i].pos = center + Vector2i(i - 2, 0)
	check(_adjacent_pairs(state) == 3, "fila com heróis colados")
	var from: Array = state.party.map(func(u): return u.pos)
	var foe = state.add_unit("esqueleto", Data.Team.ENEMY, state.party[3].pos + Vector2i(Data.WORLD["sight_radius"], 0))
	var events: Array = state.engage([foe], true)
	var deployed: Array = events.filter(func(e): return e["type"] == "deploy")
	check(not deployed.is_empty(), "o combate faz a fila abrir")
	check(_kinds(events).find("deploy") < _kinds(events).find("combat_start"), "abre junto com o aviso")
	check(_adjacent_pairs(state) == 0, "ninguém fica colado depois de abrir (%d pares)" % _adjacent_pairs(state))
	for event in deployed:
		check(Hex.distance(event["from"], event["to"]) <= Data.WORLD["deploy_steps"], "anda no máximo o limite")
		check(state.tile_at(event["to"])["walkable"], "abre para casa caminhável")
		check(event["unit"].pos == event["to"], "posição atualizada")
	var spots := {}
	for member in state.party:
		spots[member.pos] = true
		check(Hex.distance(member.pos, foe.pos) > 1, "ninguém começa colado no inimigo")
	check(spots.size() == 4, "cada herói na sua casa")
	var cost: Array = state.party.map(func(u): return u.pos)
	check(cost != from, "os heróis mudaram de lugar")
	# Quem luta de perto fica à frente de quem ataca de longe, mantendo o que era possível.
	var tank_gap: int = Hex.distance(state.party[0].pos, foe.pos)
	check(tank_gap >= 2, "tanque pronto para avançar")
	# Quem abre o ataque não sai da mira.
	var strike = WorldState.new(Data.DEFAULT_PARTY, 35)
	var ground := _open_ground(strike)
	for i in strike.party.size():
		strike.party[i].pos = ground + Vector2i(i - 2, 0)
	var mage = strike.party[2]
	var mage_at: Vector2i = mage.pos
	var prey = strike.add_unit("mumia", Data.Team.ENEMY, mage.pos + Vector2i(3, 0))
	var hit: Array = strike.do_ability(mage, "faisca", prey.pos)
	check(mage.pos == mage_at, "quem atacou continua no lugar")
	check(_kinds(hit).has("combat_start") and _kinds(hit).has("attack"), "ataque segue depois da abertura")
	check(_adjacent_pairs(strike) < 3, "os outros abrem mesmo assim")
	# Combate em andamento não reabre a formação.
	var extra = strike.add_unit("mumia", Data.Team.ENEMY, ground + Vector2i(-5, 0))
	var at: Array = strike.party.map(func(u): return u.pos)
	var joined: Array = strike.engage([extra], true)
	check(not _kinds(joined).has("deploy") and at == strike.party.map(func(u): return u.pos), "quem chega depois não muda a formação")
	# Sozinho não há fila para abrir.
	var solo = WorldState.new("duelista", 36)
	var lone = solo.add_unit("esqueleto", Data.Team.ENEMY, solo.hero.pos + Vector2i(3, 0))
	var at_solo: Vector2i = solo.hero.pos
	solo.engage([lone], true)
	check(solo.hero.pos == at_solo, "herói sozinho fica onde está")


func _test_straight_path() -> void:
	var state = WorldState.new("duelista", 37)
	var center := _open_ground(state)
	state.hero.pos = center
	var found: Dictionary = state.search(state.hero)
	# Destino alcançável e não alinhado com a grade, onde há muitos caminhos empatados.
	var goal: Vector2i = center
	for cell in found["cost"]:
		if Hex.distance(center, cell) == 5 and absi(cell.y - center.y) == 3:
			goal = cell
			break
	check(goal != center, "há destino para testar o caminho reto")
	var straight: Array = state.straight_path(found, center, goal)
	var usual: Array = state.path_from_search(found, goal)
	check(straight.size() == usual.size(), "caminho reto não fica mais longo")
	check(straight.back() == goal, "caminho reto chega ao destino")
	var at := center
	var line: Vector2 = (state._flat_spot(goal) - state._flat_spot(center)).normalized()
	for cell in straight:
		check(Hex.distance(at, cell) == 1, "caminho reto anda de casa em casa")
		check(absf((state._flat_spot(cell) - state._flat_spot(center)).cross(line)) < 0.9, "caminho reto não se afasta da linha")
		at = cell


func test_network() -> void:
	var host = WorldState.new(Data.DEFAULT_PARTY, 41, {2: ["fog_pavio"]})
	var guest = WorldState.new(Data.DEFAULT_PARTY, 41, {2: ["fog_pavio"]})
	check(guest.party.map(func(u): return u.pos) == host.party.map(func(u): return u.pos), "mesma semente, mesmo início")
	check(guest.terrain_id_at(Vector2i(20, -30)) == host.terrain_id_at(Vector2i(20, -30)), "mesma semente, mesmo mapa")
	check(guest.party[2].passives == host.party[2].passives, "mesmas skills dos dois lados")
	host.steps_until_spawn = 0
	host.tick()
	check(host.units.size() > 4, "surgem inimigos")
	var foe = host.units[4]
	foe.hp -= 3
	foe.pos = host.party[0].pos + Vector2i(2, 0)
	host.tick()
	check(host.in_combat(), "dono em combate")
	guest.apply_snapshot(bytes_to_var(var_to_bytes(host.snapshot())))
	check(guest.units.size() == host.units.size(), "convidado recebe os inimigos")
	var copy = guest.unit_by_uid(foe.uid)
	check(copy != null and copy.hp == foe.hp and copy.pos == foe.pos and copy.max_hp == foe.max_hp, "inimigo igual nos dois lados")
	check(guest.in_combat() and guest.active_unit().uid == host.active_unit().uid, "mesma vez nos dois lados")
	check(guest.snapshot() == host.snapshot(), "estado idêntico")
	host.units.erase(foe)
	host.engaged.erase(foe)
	guest.apply_snapshot(host.snapshot())
	check(not guest.units.has(copy) and guest.unit_by_uid(foe.uid) == copy, "quem saiu continua conhecido para os eventos")
	for i in 3:
		var added = host.add_unit("esqueleto", Data.Team.ENEMY, host.party[0].pos + Vector2i(20 + i, 0))
		check(added.uid > foe.uid, "uid nunca se repete")


func test_combat_flow() -> void:
	var sight: int = Data.WORLD["sight_radius"]
	# Ver e ser visto.
	var state = WorldState.new("duelista", 21)
	var far = _foe_at(state, sight + 3)
	state.tick()
	check(not state.in_combat(), "inimigo longe não inicia combate")
	check(state.active_unit() == state.hero, "fora de combate só o herói age")
	check(state.turn_order() == [state.hero], "fila só com o herói")
	var near = _foe_at(state, sight)
	var buddy = state.add_unit("mumia", Data.Team.ENEMY, near.pos + Vector2i(2, 0))
	var hero_clock: int = state.hero.clock
	var events: Array = state.tick()
	check(_kinds(events).has("combat_start"), "inimigo ao alcance da visão inicia combate")
	check(state.engaged.has(near) and state.engaged.has(buddy), "companheiro próximo entra junto")
	check(not state.takes_turns(far) or Hex.distance(far.pos, near.pos) <= Data.WORLD["group_radius"], "quem não viu fica fora da fila")
	check(state.hero.clock > hero_clock, "visto, o herói espera a sua vez")
	check(near.clock > hero_clock and buddy.clock > hero_clock, "ninguém ganha ações de graça")
	check(state.turn_order().has(near) and state.turn_order().has(state.hero), "fila com os combatentes")
	check(state.steps_until_spawn == Data.WORLD["first_spawn_steps"], "contagem intacta")
	state.steps_until_spawn = 0
	var during: Array = state.tick()
	check(not _kinds(during).has("spawn"), "ninguém novo surge em combate")
	# Mais rápido age primeiro.
	var race = WorldState.new("guardiao", 22)
	var quick = _foe_at(race, sight, "diabrete")
	race.tick()
	check(race.active_unit() == quick, "inimigo mais rápido age primeiro quando vê o herói")
	# Vitória volta à exploração.
	near.hp = 0
	buddy.hp = 0
	for unit in state.engaged.keys():
		if unit.alive():
			unit.hp = 0
	far.pos = state.hero.pos + Vector2i(30, 0)
	var ended: Array = state.tick()
	check(_kinds(ended).has("combat_end") and not state.in_combat(), "sem inimigos o combate acaba")
	check(not ended.filter(func(e): return e["type"] == "combat_end")[0]["fled"], "fim por vitória")
	# Fuga.
	var chase = WorldState.new("duelista", 23)
	var hunter = _foe_at(chase, sight)
	chase.tick()
	hunter.pos = chase.hero.pos + Vector2i(Data.WORLD["flee_radius"] + 1, 0)
	var fled: Array = chase.tick()
	check(_kinds(fled).has("combat_end") and fled.filter(func(e): return e["type"] == "combat_end")[0]["fled"], "longe o bastante, o herói escapa")
	check(chase.units.has(hunter), "quem perdeu o herói continua no mundo")
	check(not chase.takes_turns(hunter), "e sai da fila")
	# Sem caminho e sem ver a party, o inimigo desiste.
	var stuck = WorldState.new("duelista", 28)
	var island = _foe_at(stuck, sight)
	stuck.tick()
	island.pos = stuck.hero.pos + Vector2i(sight + 2, 0)
	stuck.do_wait(island)
	check(not stuck.engaged.has(island), "inimigo sem caminho desiste")
	# Ataque de surpresa.
	var ambush = WorldState.new("besteiro", 24)
	var prey = _foe_at(ambush, sight - 1)
	var prey_hp: int = prey.hp
	var opening_clock: int = ambush.hero.clock
	var shot: Array = ambush.do_ability(ambush.hero, "tiro", prey.pos)
	check(_kinds(shot)[0] == "combat_start" and not shot[0]["surprised"], "atacar quem não viu inicia combate")
	check(prey.hp < prey_hp, "o golpe de surpresa acerta")
	check(ambush.engaged.has(prey), "a vítima entra na luta")
	check(prey.clock > opening_clock, "a vítima não reage de graça")
	# Magia carregada não pode sair na hora só porque ninguém estava em combate.
	var caster = WorldState.new("mago", 25)
	var victim = _foe_at(caster, 3)
	caster.do_ability(caster.hero, "flor_fogo", victim.pos) if "flor_fogo" in caster.hero.abilities else caster.engage([victim], false)
	check(caster.in_combat(), "magia em área inicia combate")
	# Quem apanha numa área entra na luta.
	var splash = WorldState.new("duelista", 26)
	var other = _foe_at(splash, sight + 2)
	var bruise: Array = []
	splash._apply_damage(other, 1, bruise, {})
	check(splash.engaged.has(other), "dano puxa o inimigo para o combate")
	# Andar.
	var walk = WorldState.new("duelista", 27)
	walk.hero.hp = 10
	var step_to = Hex.neighbors(walk.hero.pos).filter(func(c): return walk.can_enter(walk.hero.pos, c))[0]
	var moved: Array = walk.do_step(walk.hero, step_to)
	check(walk.hero.hp == 10 + Data.WORLD["rest_heal"] and _kinds(moved).has("regen"), "fora de combate, andar recupera vida")
	var idle = _foe_at(walk, sight + 4)
	var was: Vector2i = idle.pos
	var moved_once := false
	for i in 40:
		var options = Hex.neighbors(walk.hero.pos).filter(func(c): return walk.can_enter(walk.hero.pos, c))
		var wander_events: Array = walk.do_step(walk.hero, options[0])
		moved_once = moved_once or _kinds(wander_events).has("wander")
		check(_kinds(wander_events).find("wander") < _kinds(wander_events).find("move") or not _kinds(wander_events).has("wander"), "inimigos andam junto com o herói")
	check(moved_once and idle.pos != was, "quem não viu anda pelo mapa")
	walk.engage([idle], false)
	walk.hero.hp = 10
	var fight_step = Hex.neighbors(walk.hero.pos).filter(func(c): return walk.can_enter(walk.hero.pos, c))[0]
	var fight_events: Array = walk.do_step(walk.hero, fight_step)
	check(walk.hero.hp == 10 and not _kinds(fight_events).has("regen"), "em combate, andar não cura")
	check(not _kinds(fight_events).has("wander"), "em combate ninguém passeia")


## Jogadas completas com o herói guiado pela IA: acha travamentos e mede a dificuldade.
func test_full_runs() -> void:
	var rows := []
	for party in [Data.DEFAULT_PARTY, ["guardiao", "besteiro", "mago_agua", "druida"]]:
		var distances := []
		var kills := []
		for world_seed in SIM_RUNS:
			var result := _play_run(party, world_seed * 137 + 9)
			check(result["ended"], "%s, semente %d: jornada avança sem travar" % [party, world_seed])
			distances.append(result["distance"])
			kills.append(result["kills"])
		distances.sort()
		kills.sort()
		rows.append("%-42s distância mediana %3d (%d–%d) · abates %2d" % [" + ".join(party), distances[SIM_RUNS / 2], distances[0], distances[SIM_RUNS - 1], kills[SIM_RUNS / 2]])
	for type_id in Data.WORLD_HEROES:
		var distances := []
		var kills := []
		for world_seed in SIM_RUNS:
			var result := _play_run(type_id, world_seed * 131 + 5)
			check(result["ended"], "%s, semente %d: jornada avança sem travar" % [type_id, world_seed])
			distances.append(result["distance"])
			kills.append(result["kills"])
		distances.sort()
		kills.sort()
		rows.append("%-10s distância mediana %3d (%d–%d) · abates %2d" % [type_id, distances[SIM_RUNS / 2], distances[0], distances[SIM_RUNS - 1], kills[SIM_RUNS / 2]])
	print("\n".join(rows))


func _play_run(type_id: Variant, world_seed: int) -> Dictionary:
	var state = WorldState.new(type_id, world_seed)
	var actions := 0
	var combat_streak := 0
	var healed := {}
	while state.winner() < 0 and actions < 3000 and state.farthest < 120:
		actions += 1
		state.tick()
		var unit = state.active_unit()
		if not unit.pending.is_empty():
			state.resolve_pending(unit)
		elif state.is_hero(unit) and not state.in_combat():
			_walk_on(state, unit)
		else:
			var action: Dictionary = AI.decide(state, unit)
			var healing: bool = action["kind"] == "ability" and Data.ABILITIES[action["id"]]["kind"] == "heal"
			# A IA curaria para sempre contra um inimigo fraco; uma pessoa revezaria com o ataque.
			if state.is_hero(unit) and healing and healed.get(unit, false):
				action = _attack_or_walk(state, unit)
			if state.is_hero(unit):
				healed[unit] = healing and not action.is_empty()
			if action.is_empty() or (state.is_hero(unit) and action["kind"] == "wait"):
				_walk_on(state, unit)
			else:
				AI.apply(state, unit, action)
		combat_streak = combat_streak + 1 if state.in_combat() else 0
		if combat_streak > 900: # um combate não pode ficar preso para sempre
			print("parado: combate=%s, %s" % [state.in_combat(), state.units.filter(func(u): return u.alive()).map(func(u): return [u.type_id, u.hp, u.pos, state.engaged.has(u)])])
			return {"ended": false, "distance": state.farthest, "kills": state.kills}
	return {"ended": true, "distance": state.farthest, "kills": state.kills}


func _attack_or_walk(state, unit) -> Dictionary:
	for id in unit.abilities:
		if Data.ABILITIES[id]["kind"] == "attack" and not state.valid_targets(unit, id).is_empty():
			return {"kind": "ability", "id": id, "cell": state.valid_targets(unit, id)[0]}
	return {}


## Anda rumo à casa alcançável mais distante do início.
func _walk_on(state, unit) -> void:
	var found: Dictionary = state.search(unit)
	var goal: Vector2i = unit.pos
	var best := -1
	for cell in found["cost"]:
		var far: int = Hex.distance(cell, state.start_cell)
		if far > best:
			best = far
			goal = cell
	var path: Array = state.path_from_search(found, goal)
	if path.is_empty():
		state.do_wait(unit)
	else:
		state.do_step(unit, path[0])
