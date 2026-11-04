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
	test_opportunity()
	test_damage_modifiers()
	test_guard()
	test_charge()
	test_charge_timing()
	test_heal()
	test_turn_order()
	test_attack_reach()
	test_full_battles()
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


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
	check(unit.clock - before == state.time_for(150, unit), "passo adianta o relógio pelo custo")


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
		check(wait < old_wait, "%s sai antes da janela antiga" % id)
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
	# Chega à primeira vez do mago usando a mesma hipótese da fila: um passo por ação.
	while battle.active_unit() != mage:
		var unit = battle.active_unit()
		unit.clock += battle.time_for(Data.STEP_TIME, unit)
	var old_wait: int = battle.actions_until(mage, {mage: battle.time_for(Data.ABILITIES["explosao"]["time"], mage)})
	print("Explosão na primeira vez do mago (10 unidades, hipótese de um passo): %d -> %d ações até o impacto" % [old_wait, battle.cast_wait(mage, "explosao")])


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
