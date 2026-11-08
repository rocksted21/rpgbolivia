extends SceneTree
## Regras das lanternas (docs/MAPA_LANTERNAS.md), sem tela: posição, elites, revelação em
## cadeia, farol escondido, força do guardião e save no meio da corrente.
## Rodar: godot --headless --path . --script tests/test_lanterns.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	var progress = load("res://scripts/hero_progress.gd")
	progress.path = "user://test_progress_orbes.cfg" # Orbes achados não vão para o save de verdade
	test_placement()
	test_chain()
	test_elite()
	test_guardian()
	test_compass_light()
	test_save()
	test_visual()
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


## As regras de posição deste arquivo são as do mapa sorteado; os Subúrbios têm as suas
## (rotas fixas da planta) em test_suburbs.gd.
func _new(world_seed: int, town := {}):
	if not town.has("biome"):
		town = town.duplicate()
		town["biome"] = legacy_biome(world_seed)
	return ExpeditionState.new(Data.DEFAULT_PARTY, world_seed, {}, town)


## Bioma que a semente sorteava antes do mapa fixo dos Subúrbios: assim os testes do mapa
## sorteado continuam olhando os mesmos mapas de antes.
static func legacy_biome(world_seed: int) -> String:
	var dice := RandomNumberGenerator.new()
	dice.seed = world_seed + 17
	var keys := ["deserto", "floresta", "neve", "selva"]
	return keys[dice.randi_range(0, keys.size() - 1)]


## Põe a party ao lado do local e deixa a regra de visita agir.
func _visit(state, cell: Vector2i) -> Array:
	for next in Hex.neighbors(cell):
		if state.tile_at(next)["walkable"]:
			state.hero.pos = next
			break
	for member in state.party:
		if member != state.hero:
			member.pos = state.hero.pos + Vector2i(1 + state.party.find(member), 0)
	return state.tick()


## Derruba os guardas do local e deixa a luta acabar.
func _win_fight(state, cell: Vector2i) -> Array:
	for unit in state.landmarks[cell]["guards"]:
		state._apply_damage(unit, 99999, [], {})
	return state.tick()


func _light(state, cell: Vector2i) -> void:
	_visit(state, cell)
	_win_fight(state, cell)


func test_placement() -> void:
	for i in 20:
		var world_seed := i * 37 + 11
		var state = _new(world_seed)
		var lanterns: Array = state.lantern_cells()
		check(lanterns.size() == 3, "semente %d: três lanternas (%d)" % [world_seed, lanterns.size()])
		var reach: Dictionary = state.layout.walk_area()
		var previous: Vector2i = state.start_cell
		for cell in lanterns:
			var order: int = state.landmarks[cell]["order"]
			var info: Dictionary = Exp.LANTERNS[order]
			var distance := Hex.distance(cell, state.start_cell)
			check(distance >= info["min"] - 6 and distance <= info["max"] + 6, "semente %d: lanterna %d na faixa (%d)" % [world_seed, order + 1, distance])
			check(reach.has(cell) or Hex.neighbors(cell).any(func(next): return reach.has(next)), "semente %d: lanterna %d alcançável" % [world_seed, order + 1])
			check(Hex.distance(cell, previous) >= Exp.LANDMARK_SPACING, "semente %d: lanterna %d longe da anterior" % [world_seed, order + 1])
			check(Hex.distance(cell, state.beacon_cell) >= Exp.LANDMARK_SPACING, "semente %d: lanterna %d longe do farol" % [world_seed, order + 1])
			check(Hex.distance(state.landmarks[cell]["hint"], cell) <= Exp.LANTERN_AREA, "semente %d: a área contém a lanterna" % world_seed)
			previous = cell
		# Quase sempre a regra cheia (18 casas) vale; o afrouxo é só para mapas apertados.
		var gaps := 0
		for j in range(1, lanterns.size()):
			if Hex.distance(lanterns[j], lanterns[j - 1]) >= Exp.LANTERN_GAP:
				gaps += 1
		check(gaps >= 1, "semente %d: zigue-zague entre as lanternas" % world_seed)
	var a = _new(500)
	var b = _new(500)
	check(a.lantern_cells() == b.lantern_cells(), "mesma semente, mesmas lanternas")
	var far = _new(500, {"far_compass": 1})
	check(far.lantern_cells() == a.lantern_cells(), "a Cartógrafa não muda onde as lanternas nascem")
	for cell in far.lantern_cells():
		check(Hex.distance(far.landmarks[cell]["hint"], cell) <= Exp.LANTERN_AREA_FAR, "com a Cartógrafa a área é menor")


func test_chain() -> void:
	var state = _new(41)
	var lanterns: Array = state.lantern_cells()
	check(state.next_lantern() == lanterns[0], "começa pela lanterna 1")
	check(not state.beacon_known(), "o farol começa escondido")
	check(state.lantern_target(lanterns[0])["radius"] == Exp.LANTERN_AREA, "a bússola mostra só a área da 1ª")
	check(not state.open_landmarks(state.start_cell).has(lanterns[0]), "lanterna não entra na lista dos outros locais")
	_light(state, lanterns[0])
	check(state.landmarks[lanterns[0]]["state"] == "done", "vencer a elite acende a lanterna")
	check(state.landmarks[lanterns[0]]["found"], "chegar perto revela a lanterna exata")
	check(state.lantern_target(lanterns[0])["radius"] == 0, "lanterna achada aparece exata")
	check(state.next_lantern() == lanterns[1], "acender a 1ª revela a 2ª")
	check(not state.beacon_known(), "o farol continua escondido")
	_light(state, lanterns[1])
	check(state.next_lantern() == lanterns[2], "acender a 2ª revela a 3ª")
	_light(state, lanterns[2])
	check(state.next_lantern() == null and state.lanterns_lit() == 3, "três lanternas acesas")
	check(state.beacon_known(), "a 3ª lanterna revela o farol")
	check(state.tally["lanterns"] == 3, "lanternas entram na contagem")
	# Opção B: dá para achar o farol explorando, sem as lanternas.
	var bold = _new(41)
	bold.hero.pos = bold.beacon_cell + Vector2i(40, 40)
	for member in bold.party:
		member.pos = bold.beacon_cell
	bold._check_found()
	check(bold.beacon_known(), "chegar perto do farol revela o farol sem as lanternas")


func test_elite() -> void:
	var state = _new(41)
	var cell: Vector2i = state.lantern_cells()[2]
	var info: Dictionary = Exp.LANTERNS[2]
	_visit(state, cell)
	var guards: Array = state.landmarks[cell]["guards"]
	check(state.in_combat() and state.landmarks[cell]["state"] == "fighting", "chegar na lanterna acorda a elite")
	check(guards.size() == info["escort"] + 1, "a lanterna 3 tem elite e escolta de %d (%d)" % [info["escort"], guards.size()])
	var elite = guards[0]
	check(elite.display_name == Exp.ELITE_NAME and elite.type_id == info["elite"], "a elite tem nome e tipo")
	var plain = state._spawn_enemy(info["elite"], state.start_cell + Vector2i(60, 0))
	check(elite.max_hp == roundi(plain.max_hp * info["hp"]), "a elite tem vida a mais")
	check(elite.atk == roundi(plain.atk * info["atk"]), "a elite tem ataque a mais")
	state.units.erase(plain)
	for member in state.party:
		member.hp = 1
	var brasas: int = state.brasas
	var xp: int = state.xp
	_win_fight(state, cell)
	check(state.brasas == brasas + info["brasas"], "a lanterna dá brasas")
	check(state.xp >= xp + info["xp"] or state.level > 1, "a lanterna dá experiência")
	check(state.alive_party().all(func(m): return m.hp > 1), "acender a lanterna cura a party")
	# Perder para a elite é derrota normal.
	var lost = _new(41)
	_visit(lost, lost.lantern_cells()[0])
	lost.brasas = 10
	for member in lost.party:
		member.hp = 0
	check(lost.winner() == Data.Team.ENEMY, "cair para a elite perde a expedição")
	check(lost.result()["brasas"] == 5, "a derrota custa metade das brasas")


func test_guardian() -> void:
	var strength := []
	for lit in 4:
		var state = _new(41)
		var lanterns: Array = state.lantern_cells()
		for i in lit:
			state.landmarks[lanterns[i]]["state"] = "done"
		_visit(state, state.beacon_cell)
		check(state.boss != null, "o guardião acorda com %d lanternas acesas" % lit)
		strength.append([state.boss.max_hp, state.boss.atk])
		var brasas: int = state.brasas
		state._apply_damage(state.boss, 99999, [], {})
		check(state.brasas == brasas + Exp.BOSS["brasas"] + Exp.DARK_BRASAS * (3 - lit), "prêmio do guardião com %d acesas" % lit)
	check(strength[0][0] > strength[1][0] and strength[1][0] > strength[2][0] and strength[2][0] > strength[3][0], "cada lanterna apagada dá vida ao guardião %s" % [strength])
	check(strength[0][1] >= strength[3][1], "lanternas apagadas dão ataque ao guardião")
	var base_hp: float = strength[3][0] / Exp.BOSS["hp_mult"]
	check(absf(strength[0][0] - roundi(base_hp * Exp.BOSS["hp_mult"] * (1.0 + Exp.DARK_HP * 3))) <= 2, "0 acesas: vida +60%")


func test_compass_light() -> void:
	var state = _new(41)
	var first: Vector2i = state.lantern_cells()[0]
	var near: Array = state.landmarks.keys().filter(func(cell):
		return state.landmarks[cell].get("hidden", false) and Hex.distance(cell, first) <= Exp.LANTERN_LIGHT)
	check(not state.lit_near(first), "lanterna apagada não ilumina")
	_light(state, first)
	check(state.lit_near(first + Vector2i(1, 0)), "lanterna acesa ilumina em volta")
	for cell in near:
		check(state.open_landmarks(state.start_cell).has(cell), "baú escondido perto da lanterna acesa entra na bússola")


func test_save() -> void:
	var state = _new(41)
	var lanterns: Array = state.lantern_cells()
	_light(state, lanterns[0])
	_visit(state, lanterns[1])
	check(state.landmarks[lanterns[1]]["state"] == "fighting", "salva no meio da luta da lanterna 2")
	var restored = SaveGame.restore(SaveGame.capture(state))
	check(restored.lantern_cells() == lanterns, "save mantém as lanternas")
	check(restored.lanterns_lit() == 1 and restored.next_lantern() == lanterns[1], "save mantém quais estão acesas")
	check(restored.landmarks[lanterns[0]]["found"] and not restored.beacon_known(), "save mantém o que foi revelado")
	check(restored.landmarks[lanterns[1]]["hint"] == state.landmarks[lanterns[1]]["hint"], "save mantém a área da bússola")
	check(restored.landmarks[lanterns[1]]["guards"].size() == state.landmarks[lanterns[1]]["guards"].size(), "save mantém a elite e a escolta")
	_win_fight(restored, lanterns[1])
	check(restored.next_lantern() == lanterns[2], "depois de carregar, a corrente continua")


## Tarefa 10b: a arte existe, a acesa brilha, a apagada não, e a elite é reconhecida
## (também depois de salvar, pelo nome).
func test_visual() -> void:
	for lit in [false, true]:
		var art: Array = BiomeArt.landmark("floresta", "lanterna", lit, 0.5)
		check(art.size() == 1 and ResourceLoader.exists(art[0]["path"]), "arte da lanterna %s" % ("acesa" if lit else "apagada"))
		if art.size() == 1:
			check((BiomeArt.light_of("floresta", art[0]["path"]) == "lanterna") == lit, "só a lanterna acesa brilha")
	var state = _new(11)
	var lantern: Vector2i = state.lantern_cells()[0]
	_visit(state, lantern)
	var guards: Array = state.landmarks[lantern]["guards"]
	check(not guards.is_empty() and Exp.is_elite(guards[0]), "a primeira guarda é a elite")
	check(guards.slice(1).all(func(unit): return not Exp.is_elite(unit)), "a escolta não tem aura de elite")
	var loaded = SaveGame.restore(SaveGame.capture(state))
	check(loaded != null and loaded.units.any(func(unit): return Exp.is_elite(unit) and unit.alive()), "a elite continua elite depois de carregar")

