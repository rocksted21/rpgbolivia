extends RefCounted
## Árvores de skills dos heróis. Balancear mexendo só aqui (e nas habilidades em game_data).
##
## Cada herói tem 3 ramos com 4 níveis; um nó exige o anterior do mesmo ramo.
## Efeitos de um nó (todos opcionais):
##   unlock: habilidade liberada
##   stats: soma em atributos {"hp", "atk", "def", "speed"}
##   mods: soma em campos de uma habilidade {"tiro": {"time": -20}}
##   passive: regra especial, lida em battle_state:
##     guard_mult     multiplicador da própria Guarda
##     guard_aura     multiplicador do dano em aliados vizinhos enquanto em Guarda
##     counter        força do contragolpe corpo a corpo enquanto em Guarda
##     opportunity_mult  multiplica o ataque de oportunidade que a unidade causa
##     opportunity_immune  não sofre ataques de oportunidade
##     flank_mult     multiplicador de flanqueio
##     execute        multiplicador contra alvo com metade da vida ou menos
##     kill_heal      vida recuperada ao derrotar um inimigo
##     cast_mult      multiplica a conjuração das magias carregadas (o custo total não muda)
##     heal_self      fração da cura que também volta para quem curou
##     heal_guard     quem recebe cura entra em Guarda
## Efeitos das habilidades novas (empurrar, investida, efeitos com duração, aliados)
## ficam nos campos delas em game_data.ABILITIES.

const MAX_POINTS := 12 # menor que o custo da árvore (21): obriga a escolher
const START_POINTS := 2
const WIN_POINTS := 2
const LOSS_POINTS := 1
# Exploração: nunca é vencida, então a jornada paga por abates e distância.
const JOURNEY_KILLS_PER_POINT := 5
const JOURNEY_DISTANCE_PER_POINT := 20
const TIER_COST := [1, 1, 2, 3]
# Nós que mudaram de id: o save antigo continua valendo na mesma posição da árvore.
const RENAMED := {
	"gua_placas": "gua_interpor", "gua_forca": "gua_escudada", "gua_baluarte": "gua_carga",
	"due_afiar": "due_marcar", "due_frenesi": "due_investida", "due_casca": "due_sangria",
	"bes_mira": "bes_marcador", "bes_recuo": "bes_chute", "bes_gibao": "bes_perna",
	"fog_alma": "fog_incinerar", "fog_brasa": "fog_rajada",
	"agu_inverno": "agu_toque", "agu_fluxo": "agu_corrente",
	"dru_ira": "dru_venenoso", "dru_agil": "dru_bencao",
}

const TREES := {
	"guardiao": [
		{"name": "Baluarte", "nodes": [
			{"id": "gua_ferro", "name": "Pele de Ferro", "desc": "+6 de vida.", "stats": {"hp": 6}},
			{"id": "gua_interpor", "name": "Interpor", "desc": "Põe um aliado a até 2 casas em Guarda.", "unlock": "interpor"},
			{"id": "gua_protecao", "name": "Proteção", "desc": "Em Guarda, aliados vizinhos recebem 25% menos dano.", "passive": {"guard_aura": 0.75}},
			{"id": "gua_muralha", "name": "Muralha Viva", "desc": "A Guarda reduz o dano em 65%, em vez de 50%.", "passive": {"guard_mult": 0.35}},
		]},
		{"name": "Represália", "nodes": [
			{"id": "gua_escudada", "name": "Escudada", "desc": "Golpe leve com o escudo que empurra o inimigo 1 casa.", "unlock": "escudada"},
			{"id": "gua_pesado", "name": "Golpe Pesado", "desc": "Golpe lento e muito forte.", "unlock": "golpe_pesado"},
			{"id": "gua_contra", "name": "Contragolpe", "desc": "Em Guarda, revida ataques corpo a corpo com 60% de força.", "passive": {"counter": 0.6}},
			{"id": "gua_furia", "name": "Fúria do Escudo", "desc": "+3 de ataque.", "stats": {"atk": 3}},
		]},
		{"name": "Sentinela", "nodes": [
			{"id": "gua_passo", "name": "Passo Firme", "desc": "+1 de velocidade.", "stats": {"speed": 1}},
			{"id": "gua_vigia", "name": "Vigilância", "desc": "Ataques de oportunidade dobram de força.", "passive": {"opportunity_mult": 2.0}},
			{"id": "gua_provocar", "name": "Provocar", "desc": "Assume Guarda e obriga inimigos a até 2 casas a persegui-lo.", "unlock": "provocar"},
			{"id": "gua_carga", "name": "Carga do Escudo", "desc": "Salta até um inimigo a 2-3 casas, bate e empurra 1 casa.", "unlock": "carga"},
		]},
	],
	"duelista": [
		{"name": "Lâmina", "nodes": [
			{"id": "due_marcar", "name": "Golpe Marcante", "desc": "Golpe leve que marca o alvo: ele recebe 25% mais dano por 2 turnos.", "unlock": "marcar"},
			{"id": "due_estocada", "name": "Estocada", "desc": "Golpe forte, mais lento que o normal.", "unlock": "estocada"},
			{"id": "due_flanco", "name": "Pelas Costas", "desc": "Flanqueio causa o dobro, em vez de 1,5×.", "passive": {"flank_mult": 2.0}},
			{"id": "due_executor", "name": "Executor", "desc": "+40% de dano em quem tem metade da vida ou menos.", "passive": {"execute": 1.4}},
		]},
		{"name": "Vento", "nodes": [
			{"id": "due_leve", "name": "Pés Leves", "desc": "+1 de velocidade.", "stats": {"speed": 1}},
			{"id": "due_escape", "name": "Escapada", "desc": "Não sofre ataques de oportunidade.", "passive": {"opportunity_immune": true}},
			{"id": "due_relampago", "name": "Relâmpago", "desc": "Golpe rápido fica 20 mais rápido.", "mods": {"rapido": {"time": -20}}},
			{"id": "due_investida", "name": "Investida", "desc": "Salta até um inimigo a 2-4 casas e ataca, sem sofrer oportunidade.", "unlock": "investida"},
		]},
		{"name": "Sobrevivente", "nodes": [
			{"id": "due_couro", "name": "Couro Curtido", "desc": "+5 de vida.", "stats": {"hp": 5}},
			{"id": "due_aparar", "name": "Aparar", "desc": "Guarda rápida com a lâmina.", "unlock": "aparar"},
			{"id": "due_sangria", "name": "Lâmina Sedenta", "desc": "Golpe que devolve metade do dano em vida.", "unlock": "sangria"},
			{"id": "due_sede", "name": "Sede de Sangue", "desc": "Recupera 8 de vida ao derrotar um inimigo.", "passive": {"kill_heal": 8}},
		]},
	],
	"besteiro": [
		{"name": "Pontaria", "nodes": [
			{"id": "bes_marcador", "name": "Virote Marcador", "desc": "Tiro fraco até 5 casas que marca o alvo: +25% de dano nele por 2 turnos.", "unlock": "virote_marcador"},
			{"id": "bes_longo", "name": "Tiro Longo", "desc": "Alcance 3-6, com menos força.", "unlock": "tiro_longo"},
			{"id": "bes_certeiro", "name": "Olho de Falcão", "desc": "+40% de dano em quem tem metade da vida ou menos.", "passive": {"execute": 1.4}},
			{"id": "bes_perfurante", "name": "Virote Perfurante", "desc": "Tiro lento que ignora a defesa do alvo.", "unlock": "perfurante"},
		]},
		{"name": "Barragem", "nodes": [
			{"id": "bes_rapido", "name": "Tiro Rápido", "desc": "Tiro curto e fraco, mas ligeiro.", "unlock": "tiro_rapido"},
			{"id": "bes_aljava", "name": "Aljava à Mão", "desc": "Tiro fica 20 mais rápido.", "mods": {"tiro": {"time": -20}}},
			{"id": "bes_saraivada", "name": "Saraivada", "desc": "Virotes em área; atinge aliados também.", "unlock": "saraivada"},
			{"id": "bes_chuva", "name": "Chuva de Virotes", "desc": "Área maior, com preparo longo.", "unlock": "chuva_virotes"},
		]},
		{"name": "Batedor", "nodes": [
			{"id": "bes_chute", "name": "Chute", "desc": "Empurra o inimigo colado 2 casas para abrir espaço.", "unlock": "chute"},
			{"id": "bes_adaga", "name": "Adaga", "desc": "Ataque corpo a corpo; também permite ataques de oportunidade.", "unlock": "adaga"},
			{"id": "bes_perna", "name": "Tiro na Perna", "desc": "Deixa o alvo lento (anda 1 casa a menos) por 2 turnos.", "unlock": "tiro_perna"},
			{"id": "bes_sombra", "name": "Sombra", "desc": "Não sofre ataques de oportunidade.", "passive": {"opportunity_immune": true}},
		]},
	],
	"mago": [
		{"name": "Chama", "nodes": [
			{"id": "fog_labareda", "name": "Labareda", "desc": "Fogo direto a curta distância.", "unlock": "labareda"},
			{"id": "fog_pilar", "name": "Pilar de Fogo", "desc": "Coluna de fogo sobre um alvo.", "unlock": "pilar_fogo"},
			{"id": "fog_solar", "name": "Golpe Solar", "desc": "Alto dano a grande distância.", "unlock": "golpe_solar"},
			{"id": "fog_incinerar", "name": "Incinerar", "desc": "Fogo que gruda: o alvo queima 4 por turno durante 3 turnos.", "unlock": "incinerar"},
		]},
		{"name": "Incêndio", "nodes": [
			{"id": "fog_pavio", "name": "Pavio Curto", "desc": "Magias carregadas saem 15% antes.", "passive": {"cast_mult": 0.85}},
			{"id": "fog_explosao", "name": "Explosão", "desc": "Grande dano em área.", "unlock": "explosao"},
			{"id": "fog_chuva", "name": "Chuva de Lava", "desc": "Área a grande distância.", "unlock": "chuva_lava"},
			{"id": "fog_fenix", "name": "Fênix", "desc": "A maior área do fogo, com preparo longo.", "unlock": "fenix"},
		]},
		{"name": "Magma", "nodes": [
			{"id": "fog_poca", "name": "Poça de Lava", "desc": "Área perto do mago.", "unlock": "poca_lava"},
			{"id": "fog_geiser", "name": "Gêiser de Magma", "desc": "Dano enorme em uma única casa.", "unlock": "geiser_magma"},
			{"id": "fog_furacao", "name": "Furacão de Fogo", "desc": "Área forte, com preparo mais longo.", "unlock": "furacao_fogo"},
			{"id": "fog_rajada", "name": "Rajada de Calor", "desc": "Empurra o inimigo colado 2 casas. +4 de vida.", "unlock": "rajada_calor", "stats": {"hp": 4}},
		]},
	],
	"mago_agua": [
		{"name": "Gelo", "nodes": [
			{"id": "agu_estaca", "name": "Estaca de Gelo", "desc": "Golpe gelado à distância.", "unlock": "estaca_gelo"},
			{"id": "agu_estilhaco", "name": "Estilhaço de Gelo", "desc": "Grande dano em área.", "unlock": "estilhaco_gelo"},
			{"id": "agu_cristal", "name": "Cristal de Gelo", "desc": "Alto dano a grande distância.", "unlock": "cristal_gelo"},
			{"id": "agu_toque", "name": "Toque Gélido", "desc": "Atrasa o alvo e o deixa lento por 2 turnos.", "unlock": "toque_gelido"},
		]},
		{"name": "Maré", "nodes": [
			{"id": "agu_chicote", "name": "Chicote d'Água", "desc": "Água direta a curta distância.", "unlock": "chicote_agua"},
			{"id": "agu_onda", "name": "Onda", "desc": "Área perto do mago.", "unlock": "onda"},
			{"id": "agu_redemoinho", "name": "Redemoinho", "desc": "Área forte, com preparo mais longo.", "unlock": "redemoinho"},
			{"id": "agu_kraken", "name": "Kraken", "desc": "A maior área da água, com preparo longo.", "unlock": "kraken"},
		]},
		{"name": "Fonte", "nodes": [
			{"id": "agu_corrente", "name": "Corrente", "desc": "Adianta a próxima vez de um aliado em 60.", "unlock": "corrente"},
			{"id": "agu_vital", "name": "Água Vital", "desc": "Cura leve em um aliado.", "unlock": "agua_vital"},
			{"id": "agu_geiser", "name": "Gêiser", "desc": "Dano enorme em uma única casa.", "unlock": "geiser"},
			{"id": "agu_manto", "name": "Manto d'Água", "desc": "Guarda de água e +6 de vida.", "unlock": "manto_agua", "stats": {"hp": 6}},
		]},
	],
	"druida": [
		{"name": "Bosque", "nodes": [
			{"id": "dru_seiva", "name": "Seiva Forte", "desc": "Cura restaura +4.", "mods": {"cura": {"heal": 4}}},
			{"id": "dru_alcance", "name": "Vento Curador", "desc": "Cura alcança +1 casa.", "mods": {"cura": {"range": 1}}},
			{"id": "dru_clareira", "name": "Clareira", "desc": "Cura o aliado escolhido e os vizinhos dele.", "unlock": "clareira"},
			{"id": "dru_comunhao", "name": "Comunhão", "desc": "Metade do que cura também volta para ela.", "passive": {"heal_self": 0.5}},
		]},
		{"name": "Espinhos", "nodes": [
			{"id": "dru_espinho", "name": "Espinho", "desc": "Ataque à distância.", "unlock": "espinho"},
			{"id": "dru_raizes", "name": "Raízes", "desc": "Prende o alvo e atrasa a próxima ação dele em 40.", "unlock": "raizes"},
			{"id": "dru_venenoso", "name": "Espinhos Venenosos", "desc": "Envenena: 3 de dano por turno durante 3 turnos.", "unlock": "espinhos_venenosos"},
			{"id": "dru_cipos", "name": "Cipós", "desc": "Raízes atrasam mais 40.", "mods": {"raizes": {"delay": 40}}},
		]},
		{"name": "Casca", "nodes": [
			{"id": "dru_vigor", "name": "Vigor Élfico", "desc": "+6 de vida.", "stats": {"hp": 6}},
			{"id": "dru_casca", "name": "Pele de Casca", "desc": "Guarda natural.", "unlock": "casca"},
			{"id": "dru_bencao", "name": "Bênção da Mata", "desc": "Fortalece um aliado (ou ela mesma): +25% de dano por 2 turnos.", "unlock": "bencao"},
			{"id": "dru_abrigo", "name": "Abrigo", "desc": "Quem recebe a cura entra em Guarda.", "passive": {"heal_guard": true}},
		]},
	],
}


## Pontos de uma jornada encerrada. Cair logo no começo ainda vale o mesmo que uma derrota.
static func journey_points(kills: int, distance: int) -> int:
	return maxi(LOSS_POINTS, kills / JOURNEY_KILLS_PER_POINT + distance / JOURNEY_DISTANCE_PER_POINT)


static func has_tree(type_id: String) -> bool:
	return TREES.has(type_id)


## Heróis na ordem da batalha.
static func hero_types() -> Array:
	return TREES.keys()


static func tree(type_id: String) -> Array:
	return TREES.get(type_id, [])


## {"node", "branch", "tier"} ou {} se o nó não pertence a este herói.
static func locate(type_id: String, node_id: String) -> Dictionary:
	var branches: Array = tree(type_id)
	for branch in branches.size():
		var nodes: Array = branches[branch]["nodes"]
		for tier in nodes.size():
			if nodes[tier]["id"] == node_id:
				return {"node": nodes[tier], "branch": branch, "tier": tier}
	return {}


static func cost_of(type_id: String, node_id: String) -> int:
	var found := locate(type_id, node_id)
	return TIER_COST[found["tier"]] if not found.is_empty() else 0


static func spent(type_id: String, unlocked: Array) -> int:
	var total := 0
	for id in unlocked:
		total += cost_of(type_id, id)
	return total


## O nó anterior do ramo já foi comprado (o primeiro nível não exige nada).
static func requirement_met(type_id: String, unlocked: Array, node_id: String) -> bool:
	var found := locate(type_id, node_id)
	if found.is_empty():
		return false
	if found["tier"] == 0:
		return true
	return tree(type_id)[found["branch"]]["nodes"][found["tier"] - 1]["id"] in unlocked


static func can_unlock(type_id: String, unlocked: Array, node_id: String, points: int) -> bool:
	return node_id not in unlocked \
		and requirement_met(type_id, unlocked, node_id) \
		and spent(type_id, unlocked) + cost_of(type_id, node_id) <= points


## Limpa uma build vinda do disco ou da rede: ignora nós estranhos, repetidos, sem
## o requisito ou além do limite de pontos. Devolve só o que seria possível comprar.
static func sanitize(type_id: String, build: Variant, points := MAX_POINTS) -> Array:
	var clean := []
	if not build is Array or not has_tree(type_id):
		return clean
	var limit := mini(points, MAX_POINTS)
	# Por nível, para o requisito já estar na lista seja qual for a ordem recebida.
	for tier in TIER_COST.size():
		for id in build:
			if id is String or id is StringName:
				var node_id: String = RENAMED.get(str(id), str(id))
				var found := locate(type_id, node_id)
				if not found.is_empty() and found["tier"] == tier and can_unlock(type_id, clean, node_id, limit):
					clean.append(node_id)
	return clean
