extends SceneTree
## Regras da expedição, sem tela: locais especiais, níveis, chefe e save da cidade.
## Rodar: godot --headless --path . --script tests/test_expedition.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const AI = preload("res://scripts/ai.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const SaveGame = preload("res://scripts/save_game.gd")

const SIM_RUNS := 3

var walk_maps := {}

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	TownProgress.path = "user://test_town.cfg"
	test_placement()
	test_region()
	test_layout()
	test_visits()
	test_levels()
	test_boss()
	test_town()
	test_services()
	print("regras: %d verificações, %d falhas" % [checks, failures])
	if not OS.has_environment("SKIP_SIM"):
		test_simulation()
	DirAccess.remove_absolute(TownProgress.path)
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _new(world_seed: int, town := {}):
	return ExpeditionState.new(Data.DEFAULT_PARTY, world_seed, {}, town)


## Uma expedição acontece num bioma só e tem borda: além do raio, nada se atravessa.
func test_region() -> void:
	for biome in Data.BIOMES:
		var state = _new(41, {"biome": biome})
		var radius: int = state._route_radius()
		var others := 0
		for cell in state.area_of(state.start_cell, radius + 6):
			if state.biome_at(cell) != biome:
				others += 1
		check(others == 0, "%s: o mapa inteiro é deste bioma (%d casas de outro)" % [biome, others])
		_visit(state, state.beacon_cell)
		check(state.boss != null and state.boss.type_id == Exp.BOSS_BY_BIOME.get(biome, Exp.BOSS["type"]), "%s: o guardião é o do bioma escolhido" % biome)
		check(state.town_setup.get("biome") == biome, "%s: o save guarda o bioma" % biome)
	var chosen := {}
	for world_seed in 12:
		var state = _new(world_seed * 31 + 5)
		var radius: int = state._route_radius()
		chosen[state.biome] = true
		var outside := 0
		var open_edge := 0
		for cell in state.area_of(state.start_cell, radius + 6):
			var gap: int = Hex.distance(cell, state.start_cell)
			if gap > radius + 4 and state.tile_at(cell)["walkable"]:
				outside += 1
			if gap == radius + 1 and state.tile_at(cell)["walkable"] and not state.gen.outside_bounds(cell):
				open_edge += 1 # a beira serpenteia para fora: aqui ainda pode ser chão
		check(outside == 0, "semente %d: nada andável além da borda (%d)" % [world_seed, outside])
		var reach: Dictionary = state.layout.walk_area()
		var leak: bool = reach.keys().any(func(cell): return Hex.distance(cell, state.start_cell) > radius)
		check(not leak, "semente %d: a área a pé fica dentro do raio" % world_seed)
		var steps := {state.start_cell: true}
		var frontier := [state.start_cell]
		var escaped := false
		while not frontier.is_empty() and not escaped:
			var current: Vector2i = frontier.pop_back()
			for next in Hex.neighbors(current):
				if steps.has(next) or not state.tile_at(next)["walkable"] or absi(state.elevation_at(next) - state.elevation_at(current)) > 1:
					continue
				if Hex.distance(next, state.start_cell) > radius + 4:
					escaped = true
					break
				steps[next] = true
				frontier.append(next)
		check(not escaped, "semente %d: a pé não se sai do mapa" % world_seed)
	check(chosen.size() >= 3, "sem região escolhida, as sementes variam o bioma (%d)" % chosen.size())


func test_placement() -> void:
	_test_chest()
	for world_seed in 12:
		var state = _new(world_seed * 17 + 3)
		var distance: int = Hex.distance(state.start_cell, state.beacon_cell)
		check(distance >= Exp.BEACON_DISTANCE - 5, "semente %d: farol longe do início (%d)" % [world_seed, distance])
		check(not state.tile_at(state.beacon_cell)["walkable"], "o farol é um obstáculo")
		check(state.landmarks.size() >= 8, "semente %d: mapa com locais especiais (%d)" % [world_seed, state.landmarks.size()])
		var cells: Array = state.landmarks.keys()
		for i in cells.size():
			for j in range(i + 1, cells.size()):
				var spacing: int = Exp.CHEST_SPACING if "bau" in [state.landmarks[cells[i]]["kind"], state.landmarks[cells[j]]["kind"]] else Exp.LANDMARK_SPACING
				check(Hex.distance(cells[i], cells[j]) >= spacing, "locais separados")
		_check_network(state, world_seed)
		_check_spread(state, world_seed)
		check(not state.camps.centers.is_empty(), "semente %d: tem acampamento" % world_seed)
		var reached: Dictionary = state.layout.walk_area()
		for center in state.camps.centers:
			check(reached.has(center), "acampamento acessível pela rede do mapa")
			check(state.tile_at(center)["walkable"], "fogueira fria permite caminhar")
		for cell in state.camps.cells:
			var prop: Dictionary = state.camps.cells[cell]
			check(state.tile_at(cell)["walkable"] != prop["solid"], "carga e carroça bloqueiam suas casas")
			check(not prop["solid"] or not state.gen.is_path(cell), "objetos não bloqueiam trilhas")
	var a = _new(77)
	var b = _new(77)
	check(a.beacon_cell == b.beacon_cell and a.landmarks.keys() == b.landmarks.keys(), "mesma semente, mesmos locais")
	check(a.camps.cells == b.camps.cells, "mesma semente, mesmo acampamento")
	var restored = SaveGame.restore(SaveGame.capture(a))
	check(a.camps.cells == restored.camps.cells, "save restaura composição e colisão do acampamento")


## Ponte curta: a rota contorna o lago e o rio tem largura de 1 a 2 casas.
func _check_bridges(state, world_seed: int) -> void:
	var bridges := {}
	for cell in state.area_of(state.start_cell, state._route_radius()):
		if state.gen.sample(cell)["terrain"] == state.gen.BRIDGE:
			bridges[cell] = true
	var longest := 0
	var seen := {}
	for cell in bridges:
		if seen.has(cell):
			continue
		var size := 0
		var frontier := [cell]
		seen[cell] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_back()
			size += 1
			for next in Hex.neighbors(current):
				if bridges.has(next) and not seen.has(next):
					seen[next] = true
					frontier.append(next)
		longest = maxi(longest, size)
	check(longest <= 6, "semente %d: nenhuma ponte longa (maior: %d casas)" % [world_seed, longest])


## Os locais se espalham pelo mapa: quase toda zona tem algum, e há prêmio no alto de platô.
func _check_spread(state, world_seed: int) -> void:
	var zones := {}
	var on_plateau := 0
	for cell in state.landmarks:
		zones[state.layout.zone_at(cell)] = true
		for zone in state.layout.zones:
			if zone["plateau"].has(cell):
				on_plateau += 1
	var total: int = state.layout.zones.size()
	check(zones.size() >= total - 2, "semente %d: locais em quase todas as zonas (%d de %d)" % [world_seed, zones.size(), total])
	check(on_plateau >= 1, "semente %d: há local no alto de um platô" % world_seed)


## A estrada liga o início ao farol, e todo local que não é escondido tem caminho até ela.
func _check_network(state, world_seed: int) -> void:
	var gen = state.gen
	var seen := {state.start_cell: true}
	var frontier: Array = [state.start_cell]
	var along_road := {state.start_cell: true}
	var road_front: Array = [state.start_cell]
	while not road_front.is_empty():
		var current: Vector2i = road_front.pop_back()
		for dir in gen.road_links(current):
			var next: Vector2i = Hex.neighbor(current, dir)
			if not along_road.has(next):
				along_road[next] = true
				road_front.append(next)
	check(along_road.has(state.beacon_cell), "semente %d: a estrada chega ao farol" % world_seed)
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for dir in gen.path_links(current):
			var next: Vector2i = Hex.neighbor(current, dir)
			if Hex.distance(next, state.start_cell) > Exp.BEACON_DISTANCE + Exp.BEACON_SPREAD + Exp.ROUTE_MARGIN:
				continue
			check(gen.path_links(next).has((dir + 3) % 6), "ligação vale dos dois lados")
			var blocked: bool = not state.tile_at(next)["walkable"]
			check(blocked or absi(state.elevation_at(next) - state.elevation_at(current)) <= 1, "o caminho não tem degrau alto")
			if not seen.has(next):
				seen[next] = true
				if not blocked:
					frontier.append(next)
	var chests := 0
	var hidden := 0
	for cell in state.landmarks:
		var entry: Dictionary = state.landmarks[cell]
		chests += 1 if entry["kind"] == "bau" else 0
		if entry.get("hidden", false):
			hidden += 1
			check(not state.open_landmarks(state.start_cell).has(cell), "baú escondido não aparece na bússola")
		else:
			check(seen.has(cell), "semente %d: há caminho até %s" % [world_seed, entry["kind"]])
	check(chests >= Exp.LANDMARKS["bau"]["hidden"] + 1, "semente %d: o mapa tem baús (%d)" % [world_seed, chests])
	check(hidden >= 1, "semente %d: há baú fora dos caminhos" % world_seed)


func _test_chest() -> void:
	var state = _new(91)
	var chest: Vector2i = _cell_of(state, "bau")
	var brasas: int = state.brasas
	var bag: int = state.potions
	var free: int = state.free_potions
	state._complete(chest, [])
	check(state.brasas == brasas + Exp.LANDMARKS["bau"]["brasas"], "baú dá brasas")
	check(state.landmarks[chest]["state"] == "done", "baú só abre uma vez")
	check(state.tally["chests"] == 1, "baú entra na contagem")
	check(state.potions - bag == state.free_potions - free, "poção do baú não gasta a mochila")


func _cell_of(state, kind: String) -> Variant:
	for cell in state.landmarks:
		if state.landmarks[cell]["kind"] == kind:
			return cell
	return null


## Põe o herói ao lado do local e deixa a regra de visita agir.
func _visit(state, cell: Vector2i) -> Array:
	for member in state.party:
		member.pos = cell + Vector2i(40, 40) * (state.party.find(member) + 1)
	for next in Hex.neighbors(cell):
		if state.tile_at(next)["walkable"]:
			state.hero.pos = next
			break
	for member in state.party:
		if member != state.hero:
			member.pos = state.hero.pos + Vector2i(1 + state.party.find(member), 0)
	return state.tick()


func _kinds(events: Array) -> Array:
	return events.map(func(e): return e["type"])


func test_layout() -> void:
	var total_repairs := 0
	var sizes := {}
	var ramp_sides := {}
	for world_seed in [7, 93, 248, 279, 465, 1054]:
		var state = ExpeditionState.new(Data.DEFAULT_PARTY, world_seed)
		var layout = state.layout
		var area: Dictionary = layout.walk_area()
		total_repairs += layout.repairs
		check(layout.zones.size() >= 6, "semente %d: mapa dividido em zonas (%d)" % [world_seed, layout.zones.size()])
		for zone in layout.zones:
			check(not zone["passages"].is_empty(), "semente %d: toda zona tem passagem" % world_seed)
			check(zone["top"] >= 2, "semente %d: toda zona tem platô de nível 2 ou 3" % world_seed)
			check(area.has(zone["peak"]), "semente %d: dá para subir até o alto do platô" % world_seed)
			check(zone["plateau"].has(zone["peak"]), "semente %d: o alto fica no platô" % world_seed)
			sizes[zone["plateau"].size()] = true
			if not zone["ramp"].is_empty():
				ramp_sides[Hex.distance(zone["ramp"][0], zone["center"]) < Hex.distance(zone["peak"], zone["center"])] = true
				for step in zone["ramp"]:
					check(not zone["plateau"].has(step), "semente %d: a rampa fica fora do platô" % world_seed)
			check(area.has(zone["center"]) or Hex.neighbors(zone["center"]).any(func(cell): return area.has(cell)), "semente %d: dá para chegar à zona" % world_seed)
			for strip in zone["passages"]:
				_check_passage_width(state, strip, world_seed)
		for cell in state.landmarks:
			check(area.has(cell) or Hex.neighbors(cell).any(func(next): return area.has(next)), "semente %d: local %s alcançável" % [world_seed, cell])
		# A serra fica inteira: nenhum caminho a atravessa, só as passagens e os reparos.
		var cut := 0
		for cell in layout.ridge:
			if state.gen.is_path(cell) or state.tile_at(cell)["walkable"]:
				cut += 1
		check(cut == 0, "semente %d: nenhum caminho fura a serra (%d)" % [world_seed, cut])
		for zone in layout.zones:
			check(state.gen.is_path(zone["center"]), "semente %d: a trilha chega ao centro da zona %s" % [world_seed, zone["center"]])
		_check_bridges(state, world_seed)
	print("Forma do mapa: %d reparos em 6 mapas" % total_repairs)
	check(sizes.size() >= 8, "platôs de tamanhos variados (%d tamanhos)" % sizes.size())
	check(ramp_sides.size() == 2, "rampas não apontam todas para o mesmo lado")
	# Atrás da serra o inimigo não entra na luta.
	var walled = ExpeditionState.new(Data.DEFAULT_PARTY, 93)
	var hidden_foe = walled.add_unit("esqueleto", Data.Team.ENEMY, walled.start_cell + Vector2i(30, 30))
	for member in walled.party.slice(1):
		member.hp = 0
	var found_wall := false
	var walled_cells: Array = walled.layout.ridge.keys()
	walled_cells.sort()
	for ridge_cell in walled_cells:
		walled.party[0].pos = ridge_cell # a busca só vale em volta da party
		var around: Array = walled.area_of(ridge_cell, 2).filter(func(cell): return walled.gen.walkable(cell))
		for a in around:
			hidden_foe.pos = a
			var reach: Dictionary = walled.search(hidden_foe, Data.WORLD["sight_walk"])["cost"]
			for b in around:
				if Hex.distance(a, b) <= 3 and not Hex.neighbors(b).any(func(cell): return reach.has(cell)) and not reach.has(b):
					walled.party[0].pos = b
					found_wall = true
					break
			if found_wall:
				break
		if found_wall:
			break
	check(found_wall, "achou os dois lados de uma serra")
	check(not walled._can_reach_party(hidden_foe), "inimigo sem caminho até a party não entra na luta")
	# Guardas nascem onde a party chega.
	for world_seed in [93, 248, 279]:
		var guarded = ExpeditionState.new(Data.DEFAULT_PARTY, world_seed)
		for cell in guarded.landmarks:
			var walkers: Array = Hex.neighbors(cell).filter(func(next): return guarded.gen.walkable(next))
			if walkers.is_empty():
				continue
			guarded.hero.pos = walkers[0]
			guarded.last_walker = guarded.hero
			var reach: Dictionary = guarded.search(guarded.hero)["cost"]
			for spot in guarded._spots_around(cell, 4):
				check(reach.has(spot), "semente %d: guarda em lugar alcançável" % world_seed)
	# A mesma semente dá o mesmo mapa.
	var one = ExpeditionState.new(Data.DEFAULT_PARTY, 93)
	var two = ExpeditionState.new(Data.DEFAULT_PARTY, 93)
	check(one.layout.ridge == two.layout.ridge and one.beacon_cell == two.beacon_cell, "semente repete o mapa")
	# A Jornada online não passa por aqui.
	var journey = preload("res://scripts/world_state.gd").new(Data.DEFAULT_PARTY, 93)
	check(journey.gen.layout_terrain.is_empty(), "Jornada mantém o mapa sem zonas")


## Tirar qualquer casa da passagem ainda deixa atravessar: um herói parado não tranca os outros.
func _check_passage_width(state, strip: Array, world_seed: int) -> void:
	var open: Array = strip.filter(func(cell): return state.gen.walkable(cell))
	check(open.size() >= strip.size() - 2, "semente %d: passagem livre" % world_seed)
	# As pontas do corredor são as duas casas mais distantes; o miolo é o que não pode afunilar.
	var first: Vector2i = open[0]
	var last: Vector2i = open[0]
	for a in open:
		for b in open:
			if Hex.distance(a, b) > Hex.distance(first, last):
				first = a
				last = b
	var length: int = Hex.distance(first, last)
	var edge: int = length / 3 # as bocas abrem; quem importa é o miolo, onde fica a serra
	var starts: Array = open.filter(func(cell): return Hex.distance(cell, first) <= edge)
	var goals: Array = open.filter(func(cell): return Hex.distance(cell, last) <= edge)
	for blocked in open:
		if starts.has(blocked) or goals.has(blocked):
			continue
		var seen := {}
		var frontier := starts.duplicate()
		for cell in frontier:
			seen[cell] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_back()
			for next in Hex.neighbors(current):
				if next != blocked and not seen.has(next) and open.has(next):
					seen[next] = true
					frontier.append(next)
		check(length >= 3 and goals.any(func(cell): return seen.has(cell)), "semente %d: passagem tem 2 casas de largura" % world_seed)


func test_visits() -> void:
	var state = _new(5)
	var ruin: Variant = _cell_of(state, "ruina")
	var events := _visit(state, ruin)
	check(_kinds(events).has("landmark"), "visitar ruínas gera evento")
	check(state.brasas == Exp.LANDMARKS["ruina"]["brasas"], "ruínas dão brasas")
	check(state.landmarks[ruin]["state"] == "done", "ruínas só valem uma vez")
	var before: int = state.brasas
	state.tick()
	check(state.brasas == before, "não paga duas vezes")

	state = _new(6)
	var spring: Variant = _cell_of(state, "fonte")
	state.hero.hp = 1
	_visit(state, spring)
	check(state.hero.hp > 1, "a fonte cura")

	state = _new(7)
	var memory: Variant = _cell_of(state, "memoria")
	_visit(state, memory)
	check(state.memories == [0], "guarda a primeira memória")
	state = _new(7, {"memories": Exp.MEMORIES.size()})
	memory = _cell_of(state, "memoria")
	_visit(state, memory)
	check(state.memories.is_empty(), "sem memórias novas, não conta nenhuma")

	state = _new(8)
	var village: Variant = _cell_of(state, "vila")
	var resident: String = state.landmarks[village]["resident"]
	check(resident in Exp.RESIDENT_ORDER, "a vila guarda um morador")
	check(not state.tile_at(village)["walkable"], "a vila é um obstáculo")
	events = _visit(state, village)
	check(state.in_combat(), "visitar a vila acorda os guardas")
	check(state.landmarks[village]["state"] == "fighting", "a vila entra em luta")
	check(state.rescued.is_empty(), "só resgata depois da luta")
	for guard in state.landmarks[village]["guards"].duplicate():
		state._apply_damage(guard, 9999, [], {})
	state.tick()
	check(state.rescued == [resident], "derrotar os guardas resgata o morador")

	state = _new(8, {"rescued": Exp.RESIDENT_ORDER})
	village = _cell_of(state, "vila")
	check(state.landmarks[village]["resident"] == "", "quem já foi salvo não aparece de novo")

	state = _new(9)
	var ambush: Variant = _cell_of(state, "emboscada")
	check(state.tile_name_at(ambush) in ["Ruínas", "Acampamento abandonado"], "emboscada parece um local abandonado")
	_visit(state, ambush)
	var guards: Array = state.landmarks[ambush]["guards"]
	check(state.in_combat() and not guards.is_empty(), "a emboscada começa um combate")
	for guard in guards:
		state.units.erase(guard) # como se tivessem se perdido na névoa
	state.engaged.clear()
	state._check_fights([])
	check(state.landmarks[ambush]["state"] == "idle", "fugir deixa o local esperando")


func test_levels() -> void:
	var state = _new(11)
	var hp: int = state.hero.max_hp
	var atk: int = state.hero.atk
	var events := []
	state._gain_xp(Exp.LEVEL_XP[1], events)
	check(state.level == 2, "sobe de nível")
	check(state.hero.max_hp == hp + Exp.LEVEL_HP and state.hero.atk == atk + Exp.LEVEL_ATK, "o nível fortalece a party")
	check(_kinds(events).has("level_up"), "avisa a subida")
	state._gain_xp(99999, events)
	check(state.level == Exp.LEVEL_XP.size(), "para no nível máximo")
	check(state.xp_to_next() == -1, "sem próximo nível no máximo")
	var town = _new(11, {"hp": 12, "atk": 2})
	check(town.hero.max_hp == Data.UNIT_TYPES[town.hero.type_id]["hp"] + 12, "a cidade dá vida")
	check(town.hero.hp == town.hero.max_hp, "sai de vida cheia")


func test_boss() -> void:
	var state = _new(13)
	_visit(state, state.beacon_cell)
	check(state.boss != null, "chegar ao farol acorda o guardião")
	check(state.in_combat(), "o guardião começa o combate")
	check(state.is_boss(state.boss) and state.boss.display_name != "", "o guardião tem nome")
	check(state.boss.type_id == Exp.BOSS_BY_BIOME.get(state.biome_at(state.beacon_cell), Exp.BOSS["type"]), "o guardião é o do bioma do farol")
	var own: bool = Exp.BOSS_BY_BIOME.has(state.biome_at(state.beacon_cell))
	check(state.boss.abilities == (Data.UNIT_TYPES[state.boss.type_id]["abilities"] if own else Exp.BOSS["abilities"]), "o guardião tem habilidades próprias")
	check(state.winner() < 0, "a luta ainda não acabou")
	var total: int = state.brasas
	state._apply_damage(state.boss, 99999, [], {})
	check(state.winner() == Data.Team.PLAYER, "derrotar o guardião vence a expedição")
	check(state.brasas == total + Exp.BOSS["brasas"] + Exp.DARK_BRASAS * state.dark_lanterns(), "o guardião dá brasas")
	check(state.result()["won"], "o resultado registra a vitória")
	var lost = _new(14)
	lost.brasas = 11
	lost.rescued = ["ferreiro"]
	for member in lost.party:
		member.hp = 0
	check(lost.winner() == Data.Team.ENEMY, "a party inteira caída perde")
	check(lost.result()["brasas"] == 5, "a derrota custa metade das brasas")
	check(lost.result()["rescued"] == ["ferreiro"], "quem foi salvo continua salvo")


func test_town() -> void:
	DirAccess.remove_absolute(TownProgress.path)
	check(TownProgress.brasas() == 0 and TownProgress.rescued().is_empty(), "a cidade começa vazia")
	check(TownProgress.next_cost("ferreiro") == -1, "serviço fechado sem o morador")
	check(not TownProgress.buy("ferreiro"), "não compra sem o morador")
	TownProgress.record({"won": false, "brasas": 15, "rescued": ["ferreiro"], "memories": 1})
	check(TownProgress.brasas() == 15 and TownProgress.rescued() == ["ferreiro"], "guarda brasas e morador")
	check(TownProgress.memories() == 1 and TownProgress.expeditions() == 1, "guarda história e contagem")
	check(TownProgress.beacons() == 0, "derrota não acende farol")
	check(TownProgress.buy("ferreiro"), "compra com brasas suficientes")
	check(TownProgress.brasas() == 0 and TownProgress.service_level("ferreiro") == 1, "cobra e sobe o nível")
	check(not TownProgress.buy("ferreiro"), "não compra sem brasas")
	check(TownProgress.expedition_setup()["atk"] == 1, "o serviço fortalece a expedição")
	TownProgress.record({"won": true, "brasas": 100, "rescued": ["ferreiro", "curandeira"], "memories": 0})
	check(TownProgress.beacons() == 1, "vitória acende farol")
	check(TownProgress.rescued().size() == 2, "morador repetido não duplica")
	check(TownProgress.last_note() != "", "guarda o resumo da volta")
	while TownProgress.next_cost("ferreiro") >= 0:
		check(TownProgress.buy("ferreiro"), "compra até o máximo")
	check(not TownProgress.buy("ferreiro"), "para no nível máximo")
	var config := ConfigFile.new()
	config.load(TownProgress.path)
	config.set_value("town", "rescued", ["inventado", 3])
	config.save(TownProgress.path)
	check(TownProgress.rescued().is_empty(), "ignora moradores estranhos no save")


## Partidas guiadas pela IA, indo de local em local até o farol. Mede a dificuldade.
## Serviços dos moradores resgatados: padaria, torre de mapas, arquivo e laboratório.
func test_services() -> void:
	var plain = _new(21)
	var fed = _new(21, {"rest_heal": 2})
	var hurt = plain.party[0]
	var hurt_fed = fed.party[0]
	hurt.hp = 5
	hurt_fed.hp = 5
	plain._rest(hurt, [])
	fed._rest(hurt_fed, [])
	check(hurt_fed.hp - 5 == (hurt.hp - 5) + 2, "a padaria cura mais a cada passo")

	var scholar = _new(22, {"xp_pct": 50})
	scholar._gain_xp(10, [])
	check(scholar.xp == 15, "o arquivo dá experiência a mais (%d)" % scholar.xp)

	var brewed = _new(23, {"potion_pct": 20, "potions": 1})
	for member in brewed.party:
		member.hp = 1
	brewed.use_potion()
	var member = brewed.party[0]
	check(member.hp == 1 + roundi(member.max_hp * 0.6), "o laboratório fortalece a poção (40% + 20%)")

	var mapped = _new(24, {"maps": 1})
	check(mapped.far_compass and not mapped.reveal_hidden, "mapa 1: bússola alcança tudo")
	var charted = _new(24, {"maps": 2})
	var hidden: Array = charted.landmarks.keys().filter(func(cell): return charted.landmarks[cell].get("hidden", false))
	check(not hidden.is_empty(), "o mapa tem baús escondidos")
	check(hidden.all(func(cell): return cell in charted.open_landmarks(charted.start_cell)), "mapa 2: a bússola mostra os baús escondidos")
	check(hidden.all(func(cell): return cell not in mapped.open_landmarks(mapped.start_cell)), "sem o mapa 2 eles continuam escondidos")

	var rich = _new(25, {"brasa_pct": 50})
	rich.brasas = 10
	rich.defeated_boss = true
	check(rich.result()["brasas"] == 15, "a destilaria rende brasas a mais")

	for id in Exp.RESIDENT_ORDER:
		check(Exp.RESIDENTS[id].has("rescued"), "%s tem aviso de resgate" % id)


func test_simulation() -> void:
	var rows := []
	for town in [{}, {"hp": 6, "atk": 1}, {"hp": 18, "atk": 3}]:
		var wins := 0
		var totals := {"actions": 0, "kills": 0, "brasas": 0, "level": 0, "rescued": 0}
		var reached := 0
		for run in SIM_RUNS:
			var outcome := _play(run * 211 + 19, town)
			check(outcome["ended"], "expedição %d termina sem travar" % run)
			wins += 1 if outcome["won"] else 0
			reached += 1 if outcome["reached"] else 0
			for key in totals:
				totals[key] += outcome[key]
		rows.append("cidade %s: %d/%d vitórias · %d chegaram ao farol · ações %d · abates %d · brasas %d · nível %.1f · resgates %.1f" % [
			town, wins, SIM_RUNS, reached, totals["actions"] / SIM_RUNS, totals["kills"] / SIM_RUNS,
			totals["brasas"] / SIM_RUNS, float(totals["level"]) / SIM_RUNS, float(totals["rescued"]) / SIM_RUNS])
	print("\n".join(rows))


func _play(world_seed: int, town: Dictionary) -> Dictionary:
	var state = _new(world_seed, town)
	var actions := 0
	var healed := {}
	while state.winner() < 0 and actions < 12000:
		actions += 1
		state.tick()
		if state.winner() >= 0:
			break
		var unit = state.active_unit()
		if not unit.pending.is_empty():
			state.resolve_pending(unit)
		elif state.is_hero(unit) and not state.in_combat():
			_walk(state, unit)
		else:
			var action: Dictionary = AI.decide(state, unit)
			var healing: bool = action["kind"] == "ability" and Data.ABILITIES[action["id"]]["kind"] == "heal"
			if state.is_hero(unit) and healing and healed.get(unit, false):
				action = _attack(state, unit)
			if state.is_hero(unit):
				healed[unit] = healing and not action.is_empty()
			if action.is_empty() or (state.is_hero(unit) and action["kind"] == "wait"):
				_walk(state, unit)
			else:
				AI.apply(state, unit, action)
	return {
		"ended": state.winner() >= 0, "won": state.winner() == Data.Team.PLAYER, "reached": state.boss != null,
		"actions": actions, "kills": state.kills, "brasas": state.brasas, "level": state.level, "rescued": state.rescued.size(),
	}


func _attack(state, unit) -> Dictionary:
	for id in unit.abilities:
		if Data.ABILITIES[id]["kind"] == "attack" and not state.valid_targets(unit, id).is_empty():
			return {"kind": "ability", "id": id, "cell": state.valid_targets(unit, id)[0]}
	return {}


## Anda rumo ao local mais perto e, sem nenhum, ao farol, contornando serras como uma pessoa
## que segue a estrada: o mapa de distâncias diz qual passo aproxima de verdade.
func _walk(state, unit) -> void:
	var open: Array = state.open_landmarks(unit.pos)
	var target: Vector2i = open[0] if not open.is_empty() and Hex.distance(open[0], unit.pos) <= 20 else state.beacon_cell
	var distances: Dictionary = _distances_to(state, target)
	var best: int = distances.get(unit.pos, 999999)
	var step = null
	for next in Hex.neighbors(unit.pos):
		if state.can_step(unit, next) and distances.get(next, 999999) < best:
			best = distances[next]
			step = next
	if step != null:
		state.do_step(unit, step)
		return
	var options: Array = Hex.neighbors(unit.pos).filter(func(cell): return state.can_step(unit, cell))
	if state.in_combat() or options.is_empty():
		state.do_wait(unit)
	else:
		state.do_step(unit, options[state.rng.randi_range(0, options.size() - 1)]) # alguém na frente


## Distância a pé de cada casa do mapa até `target`, guardada por alvo.
func _distances_to(state, target: Vector2i) -> Dictionary:
	if walk_maps.get("state") != state:
		walk_maps = {"state": state}
	if walk_maps.has(target):
		return walk_maps[target]
	var distances := {target: 0}
	var frontier := [target]
	var head := 0
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		for next in Hex.neighbors(current):
			if distances.has(next) or Hex.distance(next, state.start_cell) > state.layout.radius or not state.gen.walkable(next):
				continue
			if current != target and absi(state.gen.sample(next)["elevation"] - state.gen.sample(current)["elevation"]) > 1:
				continue
			distances[next] = distances[current] + 1
			frontier.append(next)
	walk_maps[target] = distances
	return distances
