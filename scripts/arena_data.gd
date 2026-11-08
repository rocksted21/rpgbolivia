extends RefCounted
## Desafios de Arena: lutas feitas à mão no tabuleiro da arena original (8 x 6, alturas, FFT puro).
## Cada local "desafio" da expedição recebe uma arena daqui; a luta roda em arena_state.gd e a tela
## troca de state em battle/arena_challenge.gd. Balancear mexendo só aqui.
##
## Mapa: uma linha de texto por fileira (odd-r, como Hex), uma letra por casa (TERRAIN_KEYS).
## Alturas: um dígito por casa. heroes: onde a party entra, na ordem dela.
## enemies / waves[].units / minions: {type, cell}; extra opcional: hp e atk (multiplicam), name.
## Regras (rule):
##   waves        reforços chegam nas rodadas de `waves`; acabando os inimigos, o próximo vem na hora
##   high_ground  a vantagem de altura conta em dobro, para os dois lados (até nas magias)
##   survive      vence quem resistir `rounds` rodadas (ou derrubar todo mundo, ondas incluídas)
##   leader       vence ao derrubar o líder; os lacaios voltam a cada `respawn_every` rodadas

const Exp = preload("res://scripts/expedition_data.gd")
const Hex = preload("res://scripts/hex.gd")
const Recruits = preload("res://scripts/recruits.gd")

const COLOR := Color("ff9d5c") # cor do local, do anel no chão e das janelas do desafio
const ROUND_TIME := 150 # uma rodada no relógio da fila (Data.TURN_TIME): quase todos agem uma vez
const LOSS_HP := 0.3 # perdeu: a party volta ao mapa com essa fração da vida
const WIN_REVIVE_HP := 0.25 # venceu: quem caiu na arena volta de pé com essa fração
const ARENA_HP := 1.1 # inimigos da arena são um pouco mais duros que os do mapa
const NEAR_TIER := 20 # desafio a até tantas casas do início prefere as arenas de tier 1
const TERRAIN_KEYS := {".": 9, ",": 1, "=": 12, "-": 13, "~": 5, "r": 2, "t": 3, "T": 16, "M": 6, "^": 7, "h": 10, "o": 11}

const ARENAS := {
	"ponte": {
		"name": "Ponte Estreita", "tier": 1,
		"text": "Um canal corta a arena ao meio. Só uma ponte de pedra, de uma casa de largura, chega ao outro lado.",
		"rule": "waves", "rule_text": "Gargalo: reforços chegam pela margem leste nas rodadas 3 e 5.",
		"map": [
			"..r~~.t.",
			".t.~~^..",
			"..-==-..",
			"...~~.r.",
			".t.~~.t.",
			"..r~~...",
		],
		"height": [
			"00000011",
			"00000011",
			"00000001",
			"00000011",
			"00000011",
			"00000001",
		],
		"heroes": [Vector2i(1, 2), Vector2i(0, 1), Vector2i(0, 3), Vector2i(2, 3)],
		"enemies": [
			{"type": "mumia", "cell": Vector2i(5, 2)},
			{"type": "esqueleto", "cell": Vector2i(6, 1)},
			{"type": "esqueleto_arqueiro", "cell": Vector2i(6, 0)},
			{"type": "esqueleto_arqueiro", "cell": Vector2i(7, 3)},
			{"type": "diabrete_brasa", "cell": Vector2i(6, 4)},
		],
		"waves": [
			{"round": 3, "units": [{"type": "diabrete", "cell": Vector2i(7, 1)}, {"type": "diabrete", "cell": Vector2i(7, 2)}]},
			{"round": 5, "units": [{"type": "cerbero", "cell": Vector2i(7, 4)}, {"type": "esqueleto", "cell": Vector2i(7, 5)}]},
		],
		"reward": {"brasas": 16, "xp": 50, "hero_xp": 25},
	},
	"planalto": {
		"name": "Planalto", "tier": 2,
		"text": "Os atiradores esperam no alto do planalto. A party começa embaixo e precisa subir as rampas.",
		"rule": "high_ground", "rule_text": "Terreno alto: a vantagem de altura vale o dobro, para os dois lados (até nas magias).",
		"map": [
			".t..r.To",
			"..t.^...",
			",...r.M.",
			"..t.....",
			".r..t.r.",
			"..t..^..",
		],
		"height": [
			"00112333",
			"00122333",
			"00012333",
			"00012233",
			"00112333",
			"00011223",
		],
		"heroes": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 3), Vector2i(0, 4)],
		"enemies": [
			{"type": "esqueleto_arqueiro", "cell": Vector2i(7, 1)},
			{"type": "esqueleto_arqueiro", "cell": Vector2i(7, 4)},
			{"type": "feiticeira", "cell": Vector2i(7, 2)},
			{"type": "mumia", "cell": Vector2i(5, 2)},
			{"type": "esqueleto", "cell": Vector2i(4, 3)},
		],
		"reward": {"brasas": 20, "xp": 60, "hero_xp": 30},
	},
	"cerco": {
		"name": "Cerco", "tier": 1,
		"text": "A party está no meio de uma praça em ruínas, cercada pelos dois lados.",
		"rule": "survive", "rounds": 6, "rule_text": "Resista 6 rodadas. Chegam reforços a cada rodada, de um lado e do outro.",
		"map": [
			".t..h..t",
			"..=..=..",
			"t.=..=.r",
			"..=..=..",
			".r.==..t",
			".t..h...",
		],
		"height": [
			"00000000",
			"00000000",
			"10000001",
			"00000000",
			"00000000",
			"00000000",
		],
		"heroes": [Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 3), Vector2i(4, 3)],
		"enemies": [
			{"type": "esqueleto", "cell": Vector2i(0, 1)},
			{"type": "diabrete", "cell": Vector2i(0, 4)},
			{"type": "esqueleto_arqueiro", "cell": Vector2i(7, 1)},
			{"type": "esqueleto", "cell": Vector2i(7, 3)},
			{"type": "diabrete_brasa", "cell": Vector2i(7, 5)},
		],
		"waves": [
			{"round": 2, "units": [{"type": "mumia", "cell": Vector2i(0, 2)}, {"type": "diabrete", "cell": Vector2i(0, 3)}]},
			{"round": 3, "units": [{"type": "esqueleto_arqueiro", "cell": Vector2i(7, 0)}, {"type": "esqueleto", "cell": Vector2i(7, 4)}]},
			{"round": 4, "units": [{"type": "cerbero", "cell": Vector2i(0, 0)}, {"type": "diabrete_brasa", "cell": Vector2i(0, 5)}]},
			{"round": 5, "units": [{"type": "feiticeira", "cell": Vector2i(7, 2)}]},
		],
		"reward": {"brasas": 22, "xp": 60, "hero_xp": 30},
	},
	"campeao": {
		"name": "Campeão", "tier": 2,
		"text": "No palanque do fundo, o Campeão da Arena assiste aos lacaios lutarem por ele.",
		"rule": "leader", "respawn_every": 2, "minions_max": 3,
		"rule_text": "Derrube o Campeão para vencer. Enquanto ele estiver de pé, um lacaio volta a cada 2 rodadas.",
		"map": [
			"..o..o..",
			"........",
			".r....=.",
			"......=.",
			"........",
			"..o..o..",
		],
		"height": [
			"00000011",
			"00000011",
			"00000111",
			"00000111",
			"00000011",
			"00000011",
		],
		"heroes": [Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 1), Vector2i(1, 4)],
		"enemies": [
			{"type": "boss_farao", "cell": Vector2i(7, 2), "leader": true, "name": "Campeão da Arena", "hp": 2.2, "atk": 1.1},
			{"type": "esqueleto", "cell": Vector2i(5, 1)},
			{"type": "esqueleto", "cell": Vector2i(5, 4)},
			{"type": "diabrete_brasa", "cell": Vector2i(6, 3)},
		],
		"minions": [
			{"type": "esqueleto", "cell": Vector2i(7, 0)},
			{"type": "diabrete", "cell": Vector2i(7, 5)},
			{"type": "esqueleto_arqueiro", "cell": Vector2i(6, 0)},
			{"type": "diabrete_brasa", "cell": Vector2i(6, 5)},
		],
		"reward": {"brasas": 24, "xp": 70, "hero_xp": 35},
	},
	# Herói por recrutar (recruits.gd): fica no desafio mais longe do início até ele entrar no roster.
	# Ele não cai: com `yield_at` da vida ou menos, se rende, e a vitória conta.
	"duelo_sangue": {
		"name": "Duelo do Mago de Sangue", "tier": 2, "recruit": "mago_agua",
		"text": "Num pátio de pedra, o Mago de Sangue espera sozinho. Cada golpe dele custa a própria vida, e o sangue que cai no chão vira poça.",
		"rule": "blood", "yield_at": 0.25, "blood_cost": 0.06, "blood_floor": 0.3,
		"pool_damage": 4, "pool_heal": 7, "pool_rounds": 4, "pools_max": 6,
		"rule_text": "Poças de sangue: quem termina a vez numa poça sangra; ele, numa poça, se cura. Ele rouba vida a cada golpe. Com 25% da vida, ele se rende.",
		"map": [
			".t....t.",
			"..====..",
			".=.r..=.",
			".=....=.",
			"..====..",
			".t....t.",
		],
		"height": [
			"00000000",
			"00000000",
			"00000110",
			"00000110",
			"00000000",
			"00000000",
		],
		"heroes": [Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 1), Vector2i(1, 4)],
		"enemies": [
			{"type": "mago_agua", "cell": Vector2i(5, 2), "leader": true, "name": "Mago de Sangue", "hp": 3.4, "atk": 1.3,
				"abilities": ["gota", "chicote_agua", "bola_agua", "floco_neve"], "lifesteal": 0.35},
			{"type": "diabrete", "cell": Vector2i(6, 1)},
			{"type": "diabrete", "cell": Vector2i(6, 4)},
		],
		"pools": [Vector2i(4, 2), Vector2i(4, 3)],
		"reward": {"brasas": 20, "xp": 60, "hero_xp": 30},
	},
}
const ARENA_ORDER := ["ponte", "cerco", "planalto", "campeao"] # a ordem não pode vir do dicionário
const DUEL := "duelo_sangue" # fora do sorteio: só o desafio escolhido por duel_cell recebe


## Terreno da arena como a BattleState quer: [linha][coluna] de ids de Data.TERRAIN.
static func terrain_rows(info: Dictionary) -> Array:
	var rows := []
	for line in info["map"]:
		var row := []
		for mark in line:
			row.append(TERRAIN_KEYS.get(mark, 9))
		rows.append(row)
	return rows


static func height_rows(info: Dictionary) -> Array:
	var rows := []
	for line in info["height"]:
		var row := []
		for digit in line:
			row.append(int(digit))
		rows.append(row)
	return rows


## Chamado por expedition_state._check_visits para cada desafio ainda aberto.
## A party chegou perto: pergunta uma vez (evento "challenge", tocado por battle/arena_challenge.gd).
## Quem recusa só é perguntado de novo depois de se afastar e voltar.
static func check_visit(state, cell: Vector2i, entry: Dictionary, events: Array) -> void:
	var away: int = state.party_distance(cell)
	if away > Exp.VISIT_RADIUS:
		if away > Exp.VISIT_RADIUS + 1:
			entry.erase("asked")
		return
	if entry.get("asked", false):
		return
	entry["asked"] = true
	if not entry.has("arena"):
		entry["arena"] = pick_arena(state, cell)
	var recruit: String = ARENAS[entry["arena"]].get("recruit", "")
	if recruit != "":
		entry["recruit"] = recruit # recruits.recruited() conta o local "done" com essa marca
	events.append({"type": "challenge", "cell": cell, "arena": entry["arena"]})


## Arena de um desafio, sempre a mesma para a mesma semente e casa. Dois desafios do mesmo mapa
## nunca repetem arena; o mais perto do início prefere as de tier 1.
static func pick_arena(state, cell: Vector2i) -> String:
	var duel_hero: String = ARENAS[DUEL]["recruit"]
	if cell == duel_cell(state) and duel_hero not in Recruits.known(state):
		return DUEL
	var used := []
	for other in state.landmarks:
		var entry: Dictionary = state.landmarks[other]
		if entry["kind"] == "desafio" and entry.has("arena"):
			used.append(entry["arena"])
	var tier := 1 if Hex.distance(cell, state.start_cell) <= NEAR_TIER else 2
	var start := posmod(hash([state.gen.world_seed, cell.x, cell.y]), ARENA_ORDER.size())
	for pass_tier in [tier, 0]:
		for i in ARENA_ORDER.size():
			var id: String = ARENA_ORDER[(start + i) % ARENA_ORDER.size()]
			if id in used or (pass_tier != 0 and ARENAS[id]["tier"] != pass_tier):
				continue
			return id
	return ARENA_ORDER[start]


## O desafio do duelo: o mais longe do início (empate: a menor casa). Sem semente: o resto do
## mapa sai igual com ou sem o herói por recrutar.
static func duel_cell(state) -> Variant:
	var best = null
	var best_gap := -1
	var cells: Array = state.landmarks.keys().filter(func(other): return state.landmarks[other]["kind"] == "desafio")
	cells.sort()
	for other in cells:
		var gap := Hex.distance(other, state.start_cell)
		if gap > best_gap:
			best = other
			best_gap = gap
	return best


## O que a janela de entrada promete (a recompensa só sai na vitória). `prize`: nome do item
## garantido (a Chama Viva de hero_bag.gd).
static func reward_text(info: Dictionary, prize: String) -> String:
	var reward: Dictionary = info["reward"]
	return "%s · +%d brasas · +%d XP da expedição · +%d XP para cada herói de pé" % [prize, reward["brasas"], reward["xp"], reward["hero_xp"]]
