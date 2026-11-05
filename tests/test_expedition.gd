extends SceneTree
## Regras da expedição, sem tela: locais especiais, níveis, chefe e save da cidade.
## Rodar: godot --headless --path . --script tests/test_expedition.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const AI = preload("res://scripts/ai.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const TownProgress = preload("res://scripts/town_progress.gd")

const SIM_RUNS := 3

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
	test_visits()
	test_levels()
	test_boss()
	test_town()
	print("regras: %d verificações, %d falhas" % [checks, failures])
	if not OS.has_environment("SKIP_SIM"):
		test_simulation()
	DirAccess.remove_absolute(TownProgress.path)
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _new(world_seed: int, town := {}):
	return ExpeditionState.new(Data.DEFAULT_PARTY, world_seed, {}, town)


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
	var a = _new(77)
	var b = _new(77)
	check(a.beacon_cell == b.beacon_cell and a.landmarks.keys() == b.landmarks.keys(), "mesma semente, mesmos locais")


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
	check(state.tile_name_at(ambush) == "Ruínas", "a emboscada se disfarça de ruínas")
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
	check(state.is_boss(state.boss) and state.boss.display_name == Exp.BOSS["name"], "o guardião tem nome")
	check(state.boss.abilities == Exp.BOSS["abilities"], "o guardião tem habilidades próprias")
	check(state.winner() < 0, "a luta ainda não acabou")
	var total: int = state.brasas
	state._apply_damage(state.boss, 99999, [], {})
	check(state.winner() == Data.Team.PLAYER, "derrotar o guardião vence a expedição")
	check(state.brasas == total + Exp.BOSS["brasas"], "o guardião dá brasas")
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


## Anda rumo ao local mais perto e, sem nenhum, ao farol.
func _walk(state, unit) -> void:
	var open: Array = state.open_landmarks(unit.pos)
	var target: Vector2i = open[0] if not open.is_empty() and Hex.distance(open[0], unit.pos) <= 20 else state.beacon_cell
	var found: Dictionary = state.search(unit)
	var goal: Vector2i = unit.pos
	var best: int = Hex.distance(unit.pos, target)
	for cell in found["cost"]:
		var gap: int = Hex.distance(cell, target)
		if gap < best or (gap == best and found["cost"][cell] < found["cost"].get(goal, 999999)):
			best = gap
			goal = cell
	var path: Array = state.path_from_search(found, goal)
	if path.is_empty():
		var options: Array = Hex.neighbors(unit.pos).filter(func(cell): return state.can_enter(unit.pos, cell))
		if options.is_empty():
			state.do_wait(unit)
		else:
			state.do_step(unit, options[state.rng.randi_range(0, options.size() - 1)])
	else:
		state.do_step(unit, path[0])
