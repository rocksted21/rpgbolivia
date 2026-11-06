extends SceneTree
## Testes das regras, sem janela.
## Rodar com: godot --headless --path combate --script tests/test_battle.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const BattleState = preload("res://scripts/battle_state.gd")
const AI = preload("res://scripts/ai.gd")

const PLAYER := Data.Team.PLAYER
const ENEMY := Data.Team.ENEMY

const FLAT := [
	[1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1],
]
const FLAT_ELEVATION := [
	[0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0],
]

var failures := 0
var checks := 0


func _initialize() -> void:
	test_hex()
	test_clock()
	test_step_rules()
	test_jump()
	test_opportunity()
	test_damage_modifiers()
	test_guard()
	test_charge()
	test_charge_timing()
	test_heal()
	test_turn_order()
	test_move_and_act()
	test_attack_reach()
	test_full_battles()
	test_skills()
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


## Árvores: dados coerentes, build válida, efeitos nas regras, IA e save.
func test_skills() -> void:
	var Skills = preload("res://scripts/skill_data.gd")
	var HeroProgress = preload("res://scripts/hero_progress.gd")
	# Toda habilidade inicial + árvore cobre as magias, sem nó ou id quebrado.
	var seen := {}
	for type_id in Skills.hero_types():
		check(Data.UNIT_TYPES.has(type_id), "árvore de herói existente: " + type_id)
		var total := 0
		for branch in Skills.tree(type_id):
			check(branch["nodes"].size() == Skills.TIER_COST.size(), "ramo com 4 níveis: " + branch["name"])
			for node in branch["nodes"]:
				check(not seen.has(node["id"]), "id único: " + node["id"])
				seen[node["id"]] = true
				total += Skills.cost_of(type_id, node["id"])
				if node.has("unlock"):
					check(Data.ABILITIES.has(node["unlock"]), "habilidade existe: " + node["unlock"])
					check(node["unlock"] not in Data.UNIT_TYPES[type_id]["abilities"], "não libera o que já tem: " + node["unlock"])
				for ability_id in node.get("mods", {}):
					check(Data.ABILITIES.has(ability_id), "mod em habilidade existente: " + ability_id)
		check(total > Skills.MAX_POINTS, "a árvore custa mais que o teto: " + type_id)
	for id in Data.ABILITIES:
		var ability: Dictionary = Data.ABILITIES[id]
		if ability["kind"] == "charge" and not id in ["chama"]:
			check(ability.has("cast_time") and ability.has("radius"), "magia carregada completa: " + id)

	# Regras de compra e limpeza do que vem de fora.
	check(not Skills.can_unlock("besteiro", [], "bes_longo", 12), "exige o nó anterior")
	check(Skills.can_unlock("besteiro", ["bes_mira"], "bes_longo", 12), "libera com o anterior")
	check(not Skills.can_unlock("besteiro", ["bes_mira"], "bes_longo", 1), "sem pontos não compra")
	check(Skills.sanitize("besteiro", ["bes_longo", "bes_mira", "bes_mira", "x", 5]) == ["bes_mira", "bes_longo"], "limpa e ordena a build")
	check(Skills.sanitize("besteiro", ["bes_longo"]).is_empty(), "remove nó sem requisito")
	check(Skills.sanitize("besteiro", "lixo").is_empty(), "ignora build inválida")
	var everything := []
	for branch in Skills.tree("mago"):
		for node in branch["nodes"]:
			everything.append(node["id"])
	check(Skills.spent("mago", Skills.sanitize("mago", everything)) <= Skills.MAX_POINTS, "a rede não passa do teto")

	# Atributos e habilidades.
	var plain = flat().add_unit("guardiao", PLAYER, Vector2i(0, 0))
	var built = flat().add_unit("guardiao", PLAYER, Vector2i(0, 0), ["gua_ferro", "gua_passo"])
	check(built.max_hp == plain.max_hp + 6 and built.hp == built.max_hp, "vida sobe")
	check(built.speed == plain.speed + 1, "velocidade sobe")
	check(built.clock < plain.clock, "relógio inicial usa a velocidade nova")
	check("guarda" in Data.UNIT_TYPES["guardiao"]["abilities"] and Data.UNIT_TYPES["guardiao"]["abilities"].size() == 2, "a build não altera os dados")
	var bow = flat().add_unit("besteiro", PLAYER, Vector2i(0, 0), ["bes_rapido", "bes_aljava"])
	check("tiro_rapido" in bow.abilities, "libera habilidade")
	check(bow.ability("tiro")["time"] == 150 and Data.ABILITIES["tiro"]["time"] == 170, "mod não altera o dado original")

	# Conjuração menor conserva o custo total.
	var state := flat()
	var mage = state.add_unit("mago", PLAYER, Vector2i(0, 0), ["fog_pavio"])
	var base_mage = state.add_unit("mago", PLAYER, Vector2i(4, 4))
	check(state.cast_time_for(mage, "explosao") < state.cast_time_for(base_mage, "explosao"), "Pavio Curto adianta o impacto")
	check(state.cast_time_for(mage, "explosao") + state.recovery_time_for(mage, "explosao") == state.time_for(220, mage), "custo total igual")

	# Proteção, Muralha e Contragolpe.
	state = flat()
	var tank = state.add_unit("guardiao", PLAYER, Vector2i(2, 2), ["gua_ferro", "gua_placas", "gua_protecao"])
	var friend = state.add_unit("duelista", PLAYER, Hex.neighbor(Vector2i(2, 2), 0))
	var foe = state.add_unit("cerbero", ENEMY, Hex.neighbor(friend.pos, 0))
	var open_hit: int = state.preview_attack(foe, "golpe", friend)["amount"]
	state.do_ability(tank, "guarda", tank.pos)
	check(state.preview_attack(foe, "golpe", friend)["amount"] < open_hit, "Proteção reduz dano no vizinho")
	state = flat()
	var wall = state.add_unit("guardiao", PLAYER, Vector2i(2, 2), ["gua_forca", "gua_pesado", "gua_contra"])
	var biter = state.add_unit("cerbero", ENEMY, Hex.neighbor(Vector2i(2, 2), 0))
	state.do_ability(wall, "guarda", wall.pos)
	var hp_before: int = biter.hp
	var events: Array = state.do_ability(biter, "golpe", wall.pos)
	check(biter.hp < hp_before and events.any(func(e): return e.get("label", "") == "contragolpe"), "Contragolpe revida")

	# Perfurante, Raízes, Executor e Sede de Sangue.
	state = flat()
	var archer = state.add_unit("besteiro", PLAYER, Vector2i(0, 2), ["bes_mira", "bes_longo", "bes_certeiro", "bes_perfurante"])
	var armored = state.add_unit("guardiao", ENEMY, Vector2i(3, 2))
	var expected := roundi(archer.atk * 1.0)
	check(state.preview_attack(archer, "perfurante", armored)["amount"] == expected, "Perfurante ignora defesa")
	var healthy: int = state.preview_attack(archer, "tiro", armored)["amount"]
	armored.hp = 5
	check(state.preview_attack(archer, "tiro", armored)["amount"] > healthy, "Olho de Falcão pune alvo ferido")
	state = flat()
	var elf = state.add_unit("druida", PLAYER, Vector2i(0, 2), ["dru_espinho", "dru_raizes", "dru_ira", "dru_cipos"])
	var rooted = state.add_unit("mumia", ENEMY, Vector2i(2, 2))
	var clock_before: int = rooted.clock
	state.do_ability(elf, "raizes", rooted.pos)
	check(rooted.clock == clock_before + 80, "Raízes e Cipós atrasam o alvo")
	state = flat()
	var killer = state.add_unit("duelista", PLAYER, Vector2i(2, 2), ["due_couro", "due_aparar", "due_casca", "due_sede"])
	var weak = state.add_unit("diabrete", ENEMY, Hex.neighbor(Vector2i(2, 2), 0))
	weak.hp = 1
	killer.hp = 10
	state.do_ability(killer, "golpe", weak.pos)
	check(not weak.alive() and killer.hp == 18, "Sede de Sangue cura ao derrotar")

	# Escapada, Clareira, Comunhão e Abrigo.
	state = flat()
	var slip = state.add_unit("duelista", PLAYER, Vector2i(2, 2), ["due_leve", "due_escape"])
	var neighbor := Hex.neighbor(Vector2i(2, 2), 0)
	state.add_unit("esqueleto", ENEMY, neighbor)
	var away := Hex.neighbor(Vector2i(2, 2), 3)
	var hp_full: int = slip.hp
	state.do_step(slip, away)
	check(slip.hp == hp_full, "Escapada evita oportunidade")
	state = flat()
	var healer = state.add_unit("druida", PLAYER, Vector2i(2, 2), ["dru_seiva", "dru_alcance", "dru_clareira", "dru_comunhao", "dru_vigor", "dru_casca", "dru_agil", "dru_abrigo"])
	var left = state.add_unit("guardiao", PLAYER, Vector2i(1, 2))
	var right = state.add_unit("besteiro", PLAYER, Hex.neighbor(Vector2i(1, 2), 3))
	left.hp = 10
	right.hp = 10
	healer.hp = 10
	state.do_ability(healer, "clareira", left.pos)
	check(left.hp == 20 and right.hp == 20, "Clareira cura o alvo e o vizinho")
	check(healer.hp > 10, "Comunhão devolve cura para ela")
	check(left.guarding, "Abrigo dá Guarda a quem foi curado")

	# Provocar obriga a IA a perseguir e não trava a unidade.
	state = flat()
	var bait = state.add_unit("guardiao", PLAYER, Vector2i(2, 2), ["gua_passo", "gua_vigia", "gua_provocar"])
	var other = state.add_unit("mago", PLAYER, Vector2i(4, 3))
	var hound = state.add_unit("cerbero", ENEMY, Vector2i(4, 2))
	state.do_ability(bait, "provocar", bait.pos)
	check(bait.guarding and hound.taunted_by == bait, "Provocar dá Guarda e marca o inimigo")
	var action: Dictionary = AI.decide(state, hound)
	check(action["kind"] == "step", "provocado ignora quem está colado e persegue")
	check(other.alive(), "alvo ignorado continua vivo")
	AI.apply(state, hound, action)
	bait.hp = 0
	check(AI.decide(state, hound)["kind"] != "wait", "provocador morto solta a unidade")

	# Save: pontos, compra, teto e arquivo estranho.
	HeroProgress.path = "user://test_progress.cfg"
	DirAccess.remove_absolute(HeroProgress.path)
	check(HeroProgress.earned("mago") == Skills.START_POINTS, "começa com os pontos iniciais")
	check(HeroProgress.unlock("mago", "fog_labareda"), "compra um nó")
	check(not HeroProgress.unlock("mago", "fog_solar"), "não pula nó")
	check(HeroProgress.available("mago") == Skills.START_POINTS - 1, "desconta o ponto")
	check(HeroProgress.award(["mago", "esqueleto"], Skills.WIN_POINTS) == 1, "só herói com árvore ganha")
	check(HeroProgress.earned("mago") == Skills.START_POINTS + Skills.WIN_POINTS, "vitória dá pontos")
	check("fog_labareda" in HeroProgress.unlocked("mago"), "nó continua salvo")
	HeroProgress.reset("mago")
	check(HeroProgress.unlocked("mago").is_empty() and HeroProgress.available("mago") == HeroProgress.earned("mago"), "redistribuir devolve tudo")
	for i in 20:
		HeroProgress.award(["mago"], Skills.LOSS_POINTS)
	check(HeroProgress.earned("mago") == Skills.MAX_POINTS, "para no teto")
	check(HeroProgress.award(["mago"], Skills.WIN_POINTS) == 0, "no teto não ganha mais")
	check(Skills.journey_points(0, 3) == Skills.LOSS_POINTS, "jornada curta vale o mínimo")
	check(Skills.journey_points(10, 40) == 4, "jornada paga por abates e distância")
	var junk := ConfigFile.new()
	junk.set_value("mago", "earned", "muito")
	junk.set_value("mago", "unlocked", ["fog_fenix", 3])
	junk.save(HeroProgress.path)
	check(HeroProgress.earned("mago") == Skills.START_POINTS and HeroProgress.unlocked("mago").is_empty(), "save estranho não quebra")
	DirAccess.remove_absolute(HeroProgress.path)
	HeroProgress.path = "user://progress.cfg"

	# Luta completa com builds e igual nos dois lados da rede.
	var builds := {0: ["gua_ferro"], 3: Skills.sanitize("mago", ["fog_pavio", "fog_explosao"])}
	var a = BattleState.from_data(builds)
	var b = BattleState.from_data(builds)
	check(a.units[0].max_hp == 52 and "explosao" in a.units[3].abilities, "from_data aplica builds por índice")
	check(a.units.map(func(u): return u.clock) == b.units.map(func(u): return u.clock), "mesma build, mesmo relógio")
	check(a.units[6].max_hp == Data.UNIT_TYPES["esqueleto"]["hp"], "inimigo sem build")
	var actions := 0
	while a.winner() < 0 and actions < 2000:
		var unit = a.active_unit()
		if not unit.pending.is_empty():
			a.resolve_pending(unit)
		else:
			AI.apply(a, unit, AI.decide(a, unit))
		actions += 1
	check(a.winner() >= 0, "luta com builds termina")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FALHOU: ", label)


func flat() -> BattleState:
	return BattleState.new(FLAT, FLAT_ELEVATION)


func test_hex() -> void:
	for cell in [Vector2i(2, 2), Vector2i(2, 3)]:
		for dir in 6:
			var next := Hex.neighbor(cell, dir)
			check(Hex.distance(cell, next) == 1, "vizinho a distância 1")
			check(Hex.neighbor(next, (dir + 3) % 6) == cell, "direção oposta volta à origem")
			check(Hex.direction_to(cell, next) == dir, "direction_to acha a direção")
	check(Hex.distance(Vector2i(0, 0), Vector2i(3, 0)) == 3, "distância em linha")
	check(Hex.distance(Vector2i(0, 0), Vector2i(1, 2)) == 2, "distância na diagonal")


func test_clock() -> void:
	var state := flat()
	var fast = state.add_unit("diabrete", ENEMY, Vector2i(0, 0))
	var slow = state.add_unit("mumia", PLAYER, Vector2i(4, 4))
	check(state.active_unit() == fast, "o mais rápido age primeiro")
	var fast_turns := 0
	var slow_turns := 0
	for i in 40:
		var unit = state.active_unit()
		if unit == fast:
			fast_turns += 1
		else:
			slow_turns += 1
		state.do_wait(unit)
	check(fast_turns > slow_turns * 1.8, "velocidade 15 age perto de 2x a velocidade 7")
	check(state.timeline(5).size() == 5, "linha do tempo com 5 entradas")


func test_jump() -> void:
	var state := flat()
	var hero = state.add_unit("druida", PLAYER, Vector2i(0, 2))
	var ally = state.add_unit("guardiao", PLAYER, Vector2i(1, 2))
	var foe = state.add_unit("esqueleto", ENEMY, Vector2i(3, 2))
	check(state.jump_cells(hero).get(Vector2i(2, 2)) == Data.JUMP_TIME, "herói pula o aliado colado, custa JUMP_TIME")
	check(state.jump_cells(hero).has(Vector2i(0, 0)), "pula mesmo sem nada no meio")
	check(state.jump_cells(hero).keys().all(func(c): return Hex.distance(hero.pos, c) == 2 and state.unit_at(c) == null), "só casas livres a 2 de distância")
	check(not state.move_cells(hero).has(Vector2i(2, 2)) or state.move_cells(hero)[Vector2i(2, 2)] > Data.JUMP_TIME, "andar nunca pula sozinho")
	check(state.jump_cells(foe).is_empty(), "inimigo não pula")
	var normal: int = state.action_time(170, hero)
	state.do_jump(hero, Vector2i(2, 2))
	check(hero.pos == Vector2i(2, 2) and hero.jumped, "pulou e caiu do outro lado")
	check(state.action_time(170, hero) == state.time_for(340, hero) and state.action_time(170, hero) > normal, "druida pulando age 2x mais devagar")
	var before: int = hero.clock
	state.do_ability(hero, "cura", ally.pos)
	check(hero.clock - before == state.time_for(340, hero) and not hero.jumped, "cura após pulo custa o dobro e zera o pulo")


func test_step_rules() -> void:
	var terrain := FLAT.duplicate(true)
	terrain[2][3] = 5 # água
	terrain[3][2] = 3 # floresta
	var height := FLAT_ELEVATION.duplicate(true)
	height[1][2] = 1
	height[0][2] = 2
	var state = BattleState.new(terrain, height)
	var unit = state.add_unit("guardiao", PLAYER, Vector2i(2, 2))
	state.add_unit("esqueleto", ENEMY, Vector2i(1, 2))
	check(not state.can_step(unit, Vector2i(3, 2)), "água bloqueia")
	check(not state.can_step(unit, Vector2i(1, 2)), "casa ocupada bloqueia")
	check(not state.can_step(unit, Vector2i(0, 0)), "só anda para casa vizinha")
	check(state.step_cost(unit.pos, Vector2i(2, 3)) == 150, "floresta custa mais")
	check(state.step_cost(unit.pos, Vector2i(2, 1)) == 140, "subir custa mais")
	check(state.can_enter(Vector2i(2, 1), Vector2i(2, 0)) , "sobe um nível")
	check(not state.can_enter(Vector2i(2, 2), Vector2i(2, 0)), "não sobe dois níveis")
	var before: int = unit.clock
	state.do_step(unit, Vector2i(2, 3))
	check(unit.clock == before and unit.moved == 150, "em combate, o passo gasta movimento pelo custo, não relógio")


func test_opportunity() -> void:
	var state := flat()
	var hero = state.add_unit("guardiao", PLAYER, Vector2i(2, 2))
	var enemy = state.add_unit("esqueleto", ENEMY, Vector2i(3, 2))
	var hp: int = hero.hp
	var stay := Vector2i(2, 1) if Hex.distance(enemy.pos, Vector2i(2, 1)) == 1 else Vector2i(2, 3)
	check(Hex.distance(enemy.pos, stay) == 1, "casa escolhida continua colada")
	state.do_step(hero, stay)
	check(hero.hp == hp, "andar sem sair do alcance não provoca")
	var away := Vector2i(1, hero.pos.y)
	check(Hex.distance(enemy.pos, away) > 1, "casa escolhida sai do alcance")
	var events: Array = state.do_step(hero, away)
	check(hero.hp < hp, "sair do alcance provoca ataque")
	check(events[0]["type"] == "attack" and events[0]["unit"] == enemy, "o evento de ataque vem antes do movimento")


func test_damage_modifiers() -> void:
	var state := flat()
	var hero = state.add_unit("guardiao", PLAYER, Vector2i(2, 2))
	var enemy = state.add_unit("esqueleto", ENEMY, Vector2i(3, 2))
	var base: int = state.preview_attack(hero, "golpe", enemy)["amount"]
	check(base == hero.atk - enemy.def, "dano base é atk - def")
	var ally = state.add_unit("duelista", PLAYER, Vector2i(0, 0))
	check(not state.is_flanked(hero, enemy), "aliado longe não flanqueia")
	ally.pos = Vector2i(4, 2)
	var flanked: Dictionary = state.preview_attack(hero, "golpe", enemy)
	check(flanked["flank"], "aliado no lado oposto flanqueia")
	check(flanked["amount"] == roundi(hero.atk * Data.FLANK_MULT) - enemy.def, "flanqueio dá +50%")
	ally.pos = Vector2i(2, 3)
	check(not state.is_flanked(hero, enemy), "aliado vizinho mas não oposto não flanqueia")

	var terrain := FLAT.duplicate(true)
	terrain[2][3] = 3
	var height := FLAT_ELEVATION.duplicate(true)
	height[2][2] = 1
	var other = BattleState.new(terrain, height)
	var high = other.add_unit("guardiao", PLAYER, Vector2i(2, 2))
	var low = other.add_unit("esqueleto", ENEMY, Vector2i(3, 2))
	var result: Dictionary = other.preview_attack(high, "golpe", low)
	check(result["height"] == 1 and result["cover"], "motivos de altura e cobertura aparecem")
	check(result["amount"] == roundi(high.atk * 1.2 * 0.8) - low.def, "altura e floresta entram no dano")
	check(other.preview_attack(low, "golpe", high)["amount"] < base, "atacar de baixo enfraquece")


func test_guard() -> void:
	var state := flat()
	var hero = state.add_unit("guardiao", PLAYER, Vector2i(2, 2))
	var enemy = state.add_unit("cerbero", ENEMY, Vector2i(3, 2))
	var normal: int = state.preview_attack(enemy, "golpe", hero)["amount"]
	state.do_ability(hero, "guarda", hero.pos)
	check(state.preview_attack(enemy, "golpe", hero)["amount"] < normal, "guarda reduz o dano")
	state.do_wait(hero)
	check(not hero.guarding, "guarda acaba na próxima ação")


func test_charge() -> void:
	var state := flat()
	var mage = state.add_unit("mago", PLAYER, Vector2i(0, 2))
	var ally = state.add_unit("guardiao", PLAYER, Vector2i(2, 1))
	var near = state.add_unit("esqueleto", ENEMY, Vector2i(3, 2))
	var dodger = state.add_unit("diabrete", ENEMY, Vector2i(2, 2))
	var tile := Vector2i(2, 2)
	check(state.valid_targets(mage, "explosao").has(tile), "casa dentro do alcance")
	var clock_before: int = mage.clock
	var wait: int = state.cast_wait(mage, "explosao")
	check(wait >= 3, "a Explosão espera os outros agirem antes de sair (%d turnos)" % wait)
	state.do_ability(mage, "explosao", tile)
	check(state.timeline(wait + 1)[wait] == mage, "a prévia bate com a fila depois de carregar")
	check(not mage.pending.is_empty(), "magia fica carregando")
	check(mage.clock > clock_before, "carregar adianta o relógio")
	check(near.hp == near.max_hp, "carregar ainda não causa dano")
	dodger.pos = Vector2i(0, 4) # saiu da área antes de explodir
	var ally_hp: int = ally.hp
	state.resolve_pending(mage)
	check(mage.pending.is_empty(), "magia foi solta")
	check(near.hp < near.max_hp, "quem ficou na área leva dano")
	check(dodger.hp == dodger.max_hp, "quem saiu da área escapa")
	check(ally.hp < ally_hp, "a área também acerta aliados")


func test_heal() -> void:
	var state := flat()
	var mage = state.add_unit("druida", PLAYER, Vector2i(0, 0))
	var ally = state.add_unit("guardiao", PLAYER, Vector2i(1, 0))
	check(state.valid_targets(mage, "cura").is_empty(), "sem ferido não há alvo de cura")
	ally.hp -= 5
	check(state.valid_targets(mage, "cura").has(ally.pos), "ferido vira alvo de cura")
	state.do_ability(mage, "cura", ally.pos)
	check(ally.hp == ally.max_hp, "cura não passa do máximo")


func test_charge_timing() -> void:
	for entry in [["mago", "explosao"], ["feiticeira", "chama"]]:
		var state := flat()
		var caster = state.add_unit(entry[0], PLAYER, Vector2i(0, 2))
		var enemy = state.add_unit("cerbero", ENEMY, Vector2i(3, 2))
		enemy.clock = caster.clock + 1
		var id: String = entry[1]
		var before: int = caster.clock
		var total := state.time_for(Data.ABILITIES[id]["time"], caster)
		var cast := state.cast_time_for(caster, id)
		var recovery := state.recovery_time_for(caster, id)
		check(cast < total and recovery > 0, "%s divide conjuração e recuperação" % id)
		var wait := state.cast_wait(caster, id)
		var old_wait := state.actions_until(caster, {caster: total})
		check(wait <= old_wait, "%s não sai depois da janela antiga" % id)
		state.do_ability(caster, id, enemy.pos)
		check(caster.clock == before + cast, "%s cobra só a conjuração antes do impacto" % id)
		check(enemy.hp == enemy.max_hp, "%s continua dando chance de reação" % id)
		check(state.actions_until(caster) == wait, "%s prévia usa o tempo de impacto" % id)
		enemy.clock = caster.clock + 1
		state.resolve_pending(caster)
		check(enemy.hp < enemy.max_hp, "%s causa dano no impacto" % id)
		check(caster.clock == before + total, "%s preserva exatamente o custo total" % id)
		check(state.active_unit() == enemy, "%s recuperação impede agir de novo logo após o impacto" % id)
		print("%s: impacto %d -> %d, recuperação %d, custo total %d" % [id, total, cast, recovery, total])

	var battle: BattleState = BattleState.from_data()
	var mage = battle.units.filter(func(u): return u.type_id == "mago")[0]
	# Chega à primeira vez do mago usando a mesma hipótese da fila.
	while battle.active_unit() != mage:
		var unit = battle.active_unit()
		unit.clock += battle.time_for(Data.TURN_TIME, unit)
	var old_wait: int = battle.actions_until(mage, {mage: battle.time_for(Data.ABILITIES["explosao"]["time"], mage)})
	print("Explosão na primeira vez do mago (10 unidades, hipótese de um turno): %d -> %d ações até o impacto" % [old_wait, battle.cast_wait(mage, "explosao")])


func test_turn_order() -> void:
	var state := flat()
	var slow = state.add_unit("mumia", ENEMY, Vector2i(0, 0))
	var fast = state.add_unit("diabrete", ENEMY, Vector2i(4, 4))
	var mid = state.add_unit("guardiao", PLAYER, Vector2i(2, 2))
	check(state.turn_order() == [fast, mid, slow], "ordem segue o relógio")
	check(state.turn_order()[0] == state.active_unit(), "o primeiro da ordem é quem joga")
	mid.clock = fast.clock
	check(state.turn_order().find(fast) < state.turn_order().find(mid), "empate igual ao de active_unit")
	check(state.active_unit() == state.turn_order()[0], "empate não diverge de active_unit")
	mid.hp = 0
	check(not state.turn_order().has(mid), "morto sai da ordem")


func test_move_and_act() -> void:
	# Anda várias casas e ataca na mesma vez; o relógio só corre com a ação.
	var state := flat()
	var hero = state.add_unit("duelista", Data.Team.PLAYER, Vector2i(0, 0))
	var foe = state.add_unit("esqueleto", Data.Team.ENEMY, Vector2i(3, 0))
	foe.clock = 1000
	check(state.move_points(hero) / Data.STEP_TIME == 3, "todos andam 3 casas")
	check(state.move_cells(hero).has(Vector2i(2, 0)) and not state.move_cells(hero).has(foe.pos), "alcance de movimento sem casa ocupada")
	check(state.approach_cell(hero, foe) == Vector2i(2, 0), "acha a casa de onde alcança o alvo")
	var clock: int = hero.clock
	var walked: Array = state.do_move(hero, Vector2i(2, 0))
	check(walked.size() == 2 and walked[0]["type"] == "move", "anda o caminho inteiro em um comando")
	check(hero.pos == Vector2i(2, 0) and hero.clock == clock and state.active_unit() == hero, "andar não passa a vez")
	check(state.steps_left(hero) == 3, "sobram 3 casas")
	state.do_ability(hero, "golpe", foe.pos)
	check(hero.clock == clock + state.time_for(150, hero), "o ataque cobra o relógio")
	check(hero.moved == 0, "o ataque encerra o turno: o próximo começa com todos os passos")
	check(state.active_unit() != hero or hero.clock < foe.clock, "a vez passa depois do ataque")
	# Sem pontos, não anda; o custo do terreno e da subida conta.
	var tired := flat()
	var mummy = tired.add_unit("mumia", Data.Team.PLAYER, Vector2i(0, 0))
	tired.add_unit("esqueleto", Data.Team.ENEMY, Vector2i(6, 3)).clock = 1000
	mummy.moved = tired.move_points(mummy)
	check(tired.move_cells(mummy).is_empty() and not tired.can_step(mummy, Vector2i(1, 0)), "sem pontos não há passo")
	# Só andar atrasa mais que esperar parado e menos que atacar.
	var lazy = flat()
	var idle = lazy.add_unit("esqueleto", Data.Team.PLAYER, Vector2i(0, 0))
	lazy.add_unit("esqueleto", Data.Team.ENEMY, Vector2i(6, 3)).clock = 1000
	var start: int = idle.clock
	lazy.do_wait(idle)
	check(idle.clock == start + lazy.time_for(Data.WAIT_TIME, idle), "parado custa a espera")
	lazy.do_step(idle, Vector2i(1, 0))
	var mid: int = idle.clock
	lazy.do_wait(idle)
	check(idle.clock == mid + lazy.time_for(Data.MOVE_ONLY_TIME, idle), "quem só andou paga a caminhada")
	# Guarda e magia carregada encerram o turno.
	var stance := flat()
	var guard = stance.add_unit("guardiao", Data.Team.PLAYER, Vector2i(0, 0))
	stance.add_unit("esqueleto", Data.Team.ENEMY, Vector2i(6, 3)).clock = 1000
	stance.do_ability(guard, "guarda", guard.pos)
	check(guard.moved == 0 and guard.guarding, "guarda encerra o turno")
	# A IA anda e bate na mesma vez.
	var chase := flat()
	var hunter = chase.add_unit("esqueleto", Data.Team.ENEMY, Vector2i(0, 0))
	var prey = chase.add_unit("mago", Data.Team.PLAYER, Vector2i(3, 0))
	prey.clock = 1000
	for i in 8:
		if chase.active_unit() != hunter or prey.hp < prey.max_hp:
			break
		AI.apply(chase, hunter, AI.decide(chase, hunter))
	check(prey.hp < prey.max_hp, "a IA chega e ataca no mesmo turno")
	check(hunter.moved == 0, "o ataque encerra o turno da IA")
	# Golpe de oportunidade no meio do caminho.
	var slip := flat()
	var runner = slip.add_unit("mago", Data.Team.PLAYER, Vector2i(1, 0))
	var blocker = slip.add_unit("esqueleto", Data.Team.ENEMY, Vector2i(0, 0))
	blocker.clock = 1000
	var run: Array = slip.do_move(runner, Vector2i(3, 0))
	check(run.any(func(e): return e["type"] == "attack" and e.get("label") == "oportunidade"), "sair de perto no caminho ainda provoca o golpe")


func test_attack_reach() -> void:
	var state := flat()
	var melee = state.add_unit("guardiao", PLAYER, Vector2i(2, 2))
	var reach: Array = state.attack_reach(melee)
	check(reach.size() == 6, "corpo a corpo alcança as 6 vizinhas")
	check(not reach.has(melee.pos), "a própria casa não conta")

	var archer = state.add_unit("besteiro", PLAYER, Vector2i(2, 2))
	var shots: Array = state.attack_reach(archer)
	check(not shots.has(Vector2i(3, 2)), "besteiro não alcança a casa colada")
	check(shots.has(Vector2i(4, 2)), "besteiro alcança a 2 casas")

	var witch = state.add_unit("feiticeira", ENEMY, Vector2i(2, 2))
	check(state.attack_reach(witch).has(Vector2i(3, 2)), "a área da magia conta: acerta a casa colada")
	check(state.cells_in_range(witch, "chama").has(Vector2i(4, 2)), "mira a 2 casas")
	check(not state.cells_in_range(witch, "chama").has(Vector2i(3, 2)), "não mira a casa colada")


# Luta inteira com IA dos dois lados. Serve de teste e mostra quantas decisões a
# luta pede do jogador, que é o número que diz se o passo a passo vai cansar.
func test_full_battles() -> void:
	var state = BattleState.from_data()
	var decisions := 0
	var switches := 0
	var actions := 0
	var last = null
	while state.winner() < 0 and actions < 2000:
		actions += 1
		var unit = state.active_unit()
		if not unit.pending.is_empty():
			state.resolve_pending(unit)
			continue
		if unit.team == PLAYER:
			decisions += 1
			if last != null and last != unit:
				switches += 1
			last = unit
		AI.apply(state, unit, AI.decide(state, unit))
	check(state.winner() >= 0, "a luta termina")
	var survivors: int = state.units.filter(func(u): return u.alive()).size()
	print("luta IA x IA: vencedor=%s, sobreviventes=%d, ações=%d, decisões do jogador=%d, trocas de herói=%d" % [
		"jogador" if state.winner() == PLAYER else "inimigo", survivors, actions, decisions, switches])
