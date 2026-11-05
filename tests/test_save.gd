extends SceneTree
## Save no meio do jogo, sem tela: gravar e carregar devolve o mesmo estado, e a partida
## segue igual depois de carregar.
## Rodar: godot --headless --path . --script tests/test_save.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const AI = preload("res://scripts/ai.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const WorldState = preload("res://scripts/world_state.gd")
const TownState = preload("res://scripts/town_state.gd")
const BattleState = preload("res://scripts/battle_state.gd")
const SaveGame = preload("res://scripts/save_game.gd")

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	SaveGame.path = "user://test_save.dat"
	DirAccess.remove_absolute(SaveGame.path)
	check(not SaveGame.exists() and SaveGame.read().is_empty(), "sem save, nada a carregar")
	test_expedition_mid_fight()
	test_expedition_supplies()
	test_movement_budget()
	test_world()
	test_town()
	test_battle()
	DirAccess.remove_absolute(SaveGame.path)
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _same(a, b, text: String) -> void:
	var left := SaveGame.capture(a)
	var right := SaveGame.capture(b)
	left.erase("when")
	right.erase("when")
	check(var_to_str(left) == var_to_str(right), text)


func _round_trip(state):
	check(SaveGame.save(state), "grava o save")
	var data := SaveGame.read()
	check(not data.is_empty(), "lê o save")
	return SaveGame.restore(data)


func test_expedition_mid_fight() -> void:
	var state = ExpeditionState.new(["guardiao", "duelista", "mago"], 4242, {}, {"hp": 6, "atk": 1})
	var actions := 0
	# Joga até um local entrar em luta, com algum dano já feito.
	while actions < 6000 and state.winner() < 0:
		actions += 1
		_act(state)
		var fighting: bool = state.landmarks.values().any(func(e): return e.state == "fighting")
		if fighting and state.in_combat() and state.kills > 0:
			break
	check(state.in_combat(), "a simulação chegou a um combate")
	check(SaveGame.mode_of(state) == "expedition", "reconhece a expedição")
	var loaded = _round_trip(state)
	check(loaded != null and loaded.get_script() == ExpeditionState, "volta como expedição")
	_same(state, loaded, "expedição carregada igual à salva")
	check(loaded.active_unit().uid == state.active_unit().uid, "a vez continua de quem era")
	check(loaded.is_boss(loaded.unit_by_uid(state.boss.uid)) if state.boss != null else loaded.boss == null, "o chefe continua o mesmo")
	for i in 300:
		if state.winner() >= 0:
			break
		_act(state)
		_act(loaded)
	_same(state, loaded, "a partida segue igual depois de carregar")


func test_expedition_supplies() -> void:
	var state = ExpeditionState.new(["guardiao"], 4242, {}, {"potions": 3, "free_potions": 1})
	state.party[0].hp = 1
	state.use_potion()
	state.items = ["lembranca"]
	state.tally.chests = 2
	state.far_compass = true
	state.brasa_bonus = true
	var loaded = _round_trip(state)
	check(loaded.potions == state.potions and loaded.free_potions == state.free_potions and loaded.potions_used == state.potions_used, "carregar preserva pocoes consumidas")
	check(loaded.items == state.items and loaded.tally == state.tally and loaded.far_compass and loaded.brasa_bonus, "carregar preserva itens e recompensas da expedicao")
	_same(state, loaded, "suprimentos carregados iguais aos salvos")


func test_movement_budget() -> void:
	var state = BattleState.from_data({})
	var unit = state.active_unit()
	var cells: Dictionary = state.move_cells(unit)
	check(not cells.is_empty(), "ha uma casa para mover antes de salvar")
	if cells.is_empty():
		return
	state.do_move(unit, cells.keys()[0])
	var remaining: int = state.move_left(unit)
	check(unit.moved > 0, "o turno tem movimento gasto antes de salvar")
	var loaded = _round_trip(state)
	check(loaded.move_left(loaded.active_unit()) == remaining, "carregar nao devolve movimento gasto no turno")
	_same(state, loaded, "turno carregado igual ao salvo")
	var legacy := SaveGame.capture(state)
	for row in legacy.units:
		row.erase("moved")
	check(SaveGame.restore(legacy).active_unit().moved == 0, "save anterior aos pontos de movimento continua carregando")


func test_world() -> void:
	var state = WorldState.new(["mago", "druida"], 77, {})
	for i in 400:
		if state.winner() >= 0:
			break
		_act(state)
	var loaded = _round_trip(state)
	check(SaveGame.read().mode == "world", "salva a jornada")
	_same(state, loaded, "jornada carregada igual à salva")


func test_town() -> void:
	var state = TownState.new(["guardiao"], 5, {}, {})
	state.party[0].pos = state.party[0].pos + Vector2i(1, 0)
	var loaded = _round_trip(state)
	check(SaveGame.read().mode == "town", "salva a cidade")
	check(loaded.party[0].pos == state.party[0].pos, "o herói volta onde estava na cidade")


func test_battle() -> void:
	var state = BattleState.from_data({})
	for i in 20:
		if state.winner() >= 0:
			break
		_act(state)
	var loaded = _round_trip(state)
	check(SaveGame.read().mode == "battle", "salva a batalha")
	_same(state, loaded, "batalha carregada igual à salva")


## Uma ação de quem tem a vez: a IA joga pelos dois lados; fora de combate o herói anda.
func _act(state) -> void:
	if "party" in state:
		state.tick()
		if state.winner() >= 0:
			return
	var unit = state.active_unit()
	if not unit.pending.is_empty():
		state.resolve_pending(unit)
		return
	if "party" in state and state.is_hero(unit) and not state.in_combat():
		_walk(state, unit)
		return
	var action: Dictionary = AI.decide(state, unit)
	if action.is_empty() or action["kind"] == "wait":
		if "party" in state and state.is_hero(unit):
			_walk(state, unit)
		else:
			state.do_wait(unit)
	else:
		AI.apply(state, unit, action)


func _walk(state, unit) -> void:
	var target: Vector2i = state.beacon_cell if "beacon_cell" in state else unit.pos + Vector2i(30, 0)
	if "beacon_cell" in state:
		var open: Array = state.open_landmarks(unit.pos)
		if not open.is_empty() and Hex.distance(open[0], unit.pos) <= 20:
			target = open[0]
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
		state.do_wait(unit)
	else:
		state.do_step(unit, path[0])
