extends RefCounted
## Árvores de skills dos heróis. Balancear mexendo só aqui (e nas habilidades em game_data).
##
## Cada herói tem 3 ramos com 4 níveis; um nó exige o anterior do mesmo ramo.
## Poucas ativas por herói (o menu de ações fica curto); o resto são passivas que melhoram
## o que ele já tem, com movimento, suporte, defesa e reações (como FFT e Battle Brothers).
##
## Efeitos de um nó (todos opcionais):
##   tag: tipo, só para a tela: ativa, ataque, defesa, movimento, suporte, reacao, controle
##   unlock: habilidade liberada (ativa: entra no menu de ações)
##   stats: soma em atributos {"hp", "atk", "def", "speed"}
##   mods: soma em campos de uma habilidade {"tiro": {"time": -20}}
##   passive: regra especial, lida em battle_state:
##     guard_mult     multiplicador da própria Guarda
##     guard_aura     multiplicador do dano em aliados vizinhos enquanto em Guarda
##     ward           multiplicador do dano em aliados vizinhos, sempre
##     inspire        multiplicador do dano causado por aliados vizinhos
##     expose         multiplicador do dano recebido por inimigos vizinhos (de qualquer atacante)
##     counter        força do contragolpe corpo a corpo enquanto em Guarda
##     riposte        força do revide corpo a corpo, sempre
##     wait_guard     encerrar o turno sem agir põe em Guarda
##     regen          vida recuperada no fim de cada turno próprio
##     move_bonus     casas a mais de movimento por turno
##     kill_haste     derrubar um inimigo adianta a próxima vez nesse tanto
##     opportunity_mult  multiplica o ataque de oportunidade que a unidade causa
##     opportunity_immune  não sofre ataques de oportunidade
##     flank_mult     multiplicador de flanqueio
##     execute        multiplicador contra alvo com metade da vida ou menos
##     lifesteal      fração do dano de todo golpe que volta em vida
##     hit_status     efeito de STATUS que todo ataque e magia deixa no alvo
##     aoe_safe       magias de área não ferem aliados
##     kill_heal      vida recuperada ao derrotar um inimigo
##     cast_mult      multiplica a conjuração das magias carregadas (o custo total não muda)
##     heal_self      fração da cura que também volta para quem curou
##     heal_guard     quem recebe cura entra em Guarda
##     heal_haste     quem recebe cura age esse tanto antes
##     blind_hunter   multiplicador do dano em quem está Cego
## Os nós entram por nível: um nó mais alto pode trocar a regra de um anterior (Fogo Eterno).
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
	"gua_placas": "gua_postura", "gua_forca": "gua_escudada", "gua_baluarte": "gua_estandarte",
	"due_afiar": "due_marcar", "due_frenesi": "due_investida", "due_casca": "due_sedenta",
	"bes_mira": "bes_alcance", "bes_recuo": "bes_chute", "bes_gibao": "bes_perna",
	"fog_alma": "fog_eterno", "fog_brasa": "fog_rajada",
	"agu_inverno": "agu_frio", "agu_fluxo": "agu_corrente",
	"dru_ira": "dru_venenoso", "dru_agil": "dru_bencao",
	# Revisão das árvores (06/11/2026): cada ativa que saiu vira o nó novo da mesma casa.
	"gua_interpor": "gua_postura", "gua_pesado": "gua_couraca", "gua_carga": "gua_estandarte",
	"due_estocada": "due_flanco", "due_aparar": "due_riposta", "due_sangria": "due_sedenta", "due_executor": "due_distracao",
	"bes_marcador": "bes_alcance", "bes_longo": "bes_olho", "bes_rapido": "bes_cacador", "bes_adaga": "bes_couro",
	"fog_labareda": "fog_bola", "fog_pilar": "fog_faminto", "fog_solar": "fog_brasas", "fog_incinerar": "fog_eterno",
	"fog_chuva": "fog_controle", "fog_fenix": "fog_flor", "fog_poca": "fog_rajada", "fog_geiser": "fog_passo", "fog_furacao": "fog_escudo",
	"agu_estaca": "agu_gota", "agu_cristal": "agu_nevasca", "agu_toque": "agu_frio", "agu_vital": "agu_correnteza", "agu_geiser": "agu_nevoa",
	"agu_chicote": "agu_fonte", "agu_onda": "agu_deslizar", "agu_redemoinho": "agu_manto", "agu_kraken": "agu_nascente",
	"dru_espinho": "dru_elfico", "dru_casca": "dru_ligeira",
}

# Experiência dos heróis (salva): cada nível novo dá 1 ponto. Do 1 ao 11 são os 10 pontos
# que faltam entre START_POINTS e MAX_POINTS.
const HERO_LEVEL_XP := [0, 30, 70, 120, 180, 250, 330, 420, 520, 630, 750]
const HERO_KILL_XP := 10 # para cada herói vivo do jogador, por inimigo derrotado
const HERO_BOSS_XP := 60
const END_XP_PER_POINT := 15 # o prêmio do fim (vitória, jornada) vira experiência

const TREES := {
	"guardiao": [
		{"name": "Baluarte", "nodes": [
			{"id": "gua_ferro", "tag": "defesa", "name": "Pele de Ferro", "desc": "+6 de vida.", "stats": {"hp": 6}},
			{"id": "gua_postura", "tag": "defesa", "name": "Postura Firme", "desc": "Encerrar o turno sem agir também põe em Guarda.", "passive": {"wait_guard": true}},
			{"id": "gua_protecao", "tag": "suporte", "name": "Proteção", "desc": "Em Guarda, aliados vizinhos recebem 25% menos dano.", "passive": {"guard_aura": 0.75}},
			{"id": "gua_muralha", "tag": "defesa", "name": "Muralha Viva", "desc": "A Guarda reduz o dano em 65%, em vez de 50%.", "passive": {"guard_mult": 0.35}},
		]},
		{"name": "Represália", "nodes": [
			{"id": "gua_escudada", "tag": "ativa", "name": "Escudada", "desc": "Golpe leve com o escudo que empurra o inimigo 1 casa.", "unlock": "escudada"},
			{"id": "gua_couraca", "tag": "defesa", "name": "Couraça", "desc": "+1 de defesa.", "stats": {"def": 1}},
			{"id": "gua_contra", "tag": "reacao", "name": "Contragolpe", "desc": "Em Guarda, revida ataques corpo a corpo com 60% de força.", "passive": {"counter": 0.6}},
			{"id": "gua_furia", "tag": "ataque", "name": "Fúria do Escudo", "desc": "+3 de ataque.", "stats": {"atk": 3}},
		]},
		{"name": "Sentinela", "nodes": [
			{"id": "gua_passo", "tag": "movimento", "name": "Passo Firme", "desc": "Anda 1 casa a mais por turno.", "passive": {"move_bonus": 1}},
			{"id": "gua_provocar", "tag": "ativa", "name": "Provocar", "desc": "Assume Guarda e obriga inimigos a até 2 casas a persegui-lo.", "unlock": "provocar"},
			{"id": "gua_vigia", "tag": "reacao", "name": "Vigilância", "desc": "Ataques de oportunidade dobram de força.", "passive": {"opportunity_mult": 2.0}},
			{"id": "gua_estandarte", "tag": "suporte", "name": "Estandarte", "desc": "Aliados vizinhos causam 20% mais dano.", "passive": {"inspire": 1.2}},
		]},
	],
	"duelista": [
		{"name": "Lâmina", "nodes": [
			{"id": "due_marcar", "tag": "ativa", "name": "Golpe Marcante", "desc": "Golpe leve que marca o alvo: ele recebe 25% mais dano por 2 turnos.", "unlock": "marcar"},
			{"id": "due_flanco", "tag": "ataque", "name": "Pelas Costas", "desc": "Flanqueio causa o dobro, em vez de 1,5×.", "passive": {"flank_mult": 2.0}},
			{"id": "due_distracao", "tag": "suporte", "name": "Distração", "desc": "Inimigos colados nele recebem 15% mais dano de todos.", "passive": {"expose": 1.15}},
			{"id": "due_embalo", "tag": "movimento", "name": "Frenesi", "desc": "Derrubar um inimigo adianta a sua próxima vez em 60.", "passive": {"kill_haste": 60}},
		]},
		{"name": "Vento", "nodes": [
			{"id": "due_leve", "tag": "movimento", "name": "Pés Leves", "desc": "Anda 1 casa a mais por turno.", "passive": {"move_bonus": 1}},
			{"id": "due_escape", "tag": "movimento", "name": "Escapada", "desc": "Não sofre ataques de oportunidade.", "passive": {"opportunity_immune": true}},
			{"id": "due_relampago", "tag": "ataque", "name": "Relâmpago", "desc": "Golpe rápido fica 20 mais rápido.", "mods": {"rapido": {"time": -20}}},
			{"id": "due_investida", "tag": "ativa", "name": "Investida", "desc": "Salta até um inimigo a 2-4 casas e ataca, sem sofrer oportunidade.", "unlock": "investida"},
		]},
		{"name": "Sobrevivente", "nodes": [
			{"id": "due_couro", "tag": "defesa", "name": "Couro Curtido", "desc": "+5 de vida.", "stats": {"hp": 5}},
			{"id": "due_riposta", "tag": "reacao", "name": "Riposta", "desc": "Revida todo ataque corpo a corpo com 40% de força.", "passive": {"riposte": 0.4}},
			{"id": "due_sedenta", "tag": "defesa", "name": "Lâmina Sedenta", "desc": "Todo golpe devolve 25% do dano em vida.", "passive": {"lifesteal": 0.25}},
			{"id": "due_sede", "tag": "defesa", "name": "Sede de Sangue", "desc": "Recupera 8 de vida ao derrotar um inimigo.", "passive": {"kill_heal": 8}},
		]},
	],
	"besteiro": [
		{"name": "Pontaria", "nodes": [
			{"id": "bes_alcance", "tag": "ataque", "name": "Mira Longa", "desc": "Tiro e Virote Pesado alcançam 1 casa a mais.", "mods": {"tiro": {"range": 1}, "virote_pesado": {"range": 1}}},
			{"id": "bes_certeiro", "tag": "ataque", "name": "Olho de Falcão", "desc": "+40% de dano em quem tem metade da vida ou menos.", "passive": {"execute": 1.4}},
			{"id": "bes_perfurante", "tag": "ataque", "name": "Ponta de Aço", "desc": "Virote Pesado ignora a defesa do alvo.", "mods": {"virote_pesado": {"pierce": 1}}},
			{"id": "bes_olho", "tag": "suporte", "name": "Olho Marcador", "desc": "Todo ataque dele marca o alvo por 1 turno: +25% de dano nele para todos.", "passive": {"hit_status": {"id": "mark", "turns": 1}}},
		]},
		{"name": "Barragem", "nodes": [
			{"id": "bes_aljava", "tag": "ataque", "name": "Aljava à Mão", "desc": "Tiro fica 20 mais rápido.", "mods": {"tiro": {"time": -20}}},
			{"id": "bes_saraivada", "tag": "ativa", "name": "Saraivada", "desc": "Virotes em área; atinge aliados também.", "unlock": "saraivada"},
			{"id": "bes_cacador", "tag": "movimento", "name": "Caçador", "desc": "Derrubar um inimigo adianta a sua próxima vez em 40.", "passive": {"kill_haste": 40}},
			{"id": "bes_chuva", "tag": "ataque", "name": "Chuva de Virotes", "desc": "Saraivada cobre 1 casa a mais de raio, com preparo um pouco maior.", "mods": {"saraivada": {"radius": 1, "cast_time": 30, "time": 30}}},
		]},
		{"name": "Batedor", "nodes": [
			{"id": "bes_chute", "tag": "ativa", "name": "Chute", "desc": "Empurra o inimigo colado 2 casas para abrir espaço.", "unlock": "chute"},
			{"id": "bes_sombra", "tag": "movimento", "name": "Sombra", "desc": "Não sofre ataques de oportunidade.", "passive": {"opportunity_immune": true}},
			{"id": "bes_couro", "tag": "defesa", "name": "Gibão Acolchoado", "desc": "+1 de defesa e +4 de vida.", "stats": {"def": 1, "hp": 4}},
			{"id": "bes_perna", "tag": "ativa", "name": "Tiro na Perna", "desc": "Deixa o alvo lento (anda 1 casa a menos) por 2 turnos.", "unlock": "tiro_perna"},
		]},
	],
	"mago": [
		{"name": "Chama", "nodes": [
			{"id": "fog_bola", "tag": "ataque", "name": "Bola Ardente", "desc": "Bola de Fogo alcança 1 casa a mais e causa 25% mais dano.", "mods": {"bola_fogo": {"range": 1, "power": 0.2}}},
			{"id": "fog_faminto", "tag": "ataque", "name": "Fogo Faminto", "desc": "+40% de dano em quem tem metade da vida ou menos.", "passive": {"execute": 1.4}},
			{"id": "fog_brasas", "tag": "ataque", "name": "Brasas", "desc": "Todo ataque e magia dele deixa o alvo queimando: 2 por turno durante 2 turnos.", "passive": {"hit_status": {"id": "burn", "turns": 2, "amount": 2}}},
			{"id": "fog_eterno", "tag": "ataque", "name": "Fogo Eterno", "desc": "As Brasas queimam 4 por turno durante 3 turnos.", "passive": {"hit_status": {"id": "burn", "turns": 3, "amount": 4}}},
		]},
		{"name": "Incêndio", "nodes": [
			{"id": "fog_pavio", "tag": "ataque", "name": "Pavio Curto", "desc": "Magias carregadas saem 15% antes.", "passive": {"cast_mult": 0.85}},
			{"id": "fog_controle", "tag": "suporte", "name": "Chama Controlada", "desc": "Suas magias de área não ferem aliados.", "passive": {"aoe_safe": true}},
			{"id": "fog_flor", "tag": "ataque", "name": "Flor Intensa", "desc": "Flor de Fogo causa um terço a mais de dano.", "mods": {"flor_fogo": {"power": 0.3}}},
			{"id": "fog_explosao", "tag": "ativa", "name": "Explosão", "desc": "Grande dano em área.", "unlock": "explosao"},
		]},
		{"name": "Magma", "nodes": [
			{"id": "fog_rajada", "tag": "ativa", "name": "Rajada de Calor", "desc": "Empurra o inimigo colado 2 casas.", "unlock": "rajada_calor"},
			{"id": "fog_passo", "tag": "movimento", "name": "Passo Ígneo", "desc": "Anda 1 casa a mais por turno.", "passive": {"move_bonus": 1}},
			{"id": "fog_escudo", "tag": "reacao", "name": "Escudo Ardente", "desc": "Com o Escudo de Fogo, revida ataques corpo a corpo com 60% de força.", "passive": {"counter": 0.6}},
			{"id": "fog_magma", "tag": "defesa", "name": "Coração de Magma", "desc": "+6 de vida e recupera 2 no fim de cada turno dele.", "stats": {"hp": 6}, "passive": {"regen": 2}},
		]},
	],
	"mago_agua": [
		{"name": "Gelo", "nodes": [
			{"id": "agu_gota", "tag": "controle", "name": "Gota Gelada", "desc": "Gota d'Água atrasa o alvo em 25.", "mods": {"gota": {"delay": 25}}},
			{"id": "agu_frio", "tag": "controle", "name": "Frio Cortante", "desc": "Todo ataque e magia dele deixa o alvo lento (anda 1 casa a menos) por 1 turno.", "passive": {"hit_status": {"id": "slow", "turns": 1}}},
			{"id": "agu_nevasca", "tag": "ataque", "name": "Nevasca", "desc": "Floco de Neve cobre 1 casa a mais de raio.", "mods": {"floco_neve": {"radius": 1}}},
			{"id": "agu_estilhaco", "tag": "ativa", "name": "Estilhaço de Gelo", "desc": "Grande dano em área.", "unlock": "estilhaco_gelo"},
		]},
		{"name": "Maré", "nodes": [
			{"id": "agu_corrente", "tag": "ativa", "name": "Corrente", "desc": "Adianta a próxima vez de um aliado em 60.", "unlock": "corrente"},
			{"id": "agu_correnteza", "tag": "suporte", "name": "Correnteza", "desc": "Corrente alcança 1 casa a mais e adianta mais 30.", "mods": {"corrente": {"range": 1, "haste": 30}}},
			{"id": "agu_nevoa", "tag": "suporte", "name": "Névoa Protetora", "desc": "Aliados vizinhos recebem 15% menos dano.", "passive": {"ward": 0.85}},
			{"id": "agu_mare", "tag": "suporte", "name": "Maré Viva", "desc": "Corrente também cura 8 de vida do aliado.", "mods": {"corrente": {"heal": 8}}},
		]},
		{"name": "Fonte", "nodes": [
			{"id": "agu_fonte", "tag": "defesa", "name": "Fonte Interior", "desc": "+6 de vida.", "stats": {"hp": 6}},
			{"id": "agu_deslizar", "tag": "movimento", "name": "Deslizar", "desc": "Anda 1 casa a mais por turno.", "passive": {"move_bonus": 1}},
			{"id": "agu_manto", "tag": "defesa", "name": "Manto d'Água", "desc": "Encerrar o turno sem agir põe em Guarda.", "passive": {"wait_guard": true}},
			{"id": "agu_nascente", "tag": "defesa", "name": "Nascente", "desc": "Recupera 3 de vida no fim de cada turno dele.", "passive": {"regen": 3}},
		]},
	],
	"druida": [
		{"name": "Bosque", "nodes": [
			{"id": "dru_seiva", "tag": "suporte", "name": "Seiva Forte", "desc": "Cura restaura +4.", "mods": {"cura": {"heal": 4}}},
			{"id": "dru_alcance", "tag": "suporte", "name": "Vento Curador", "desc": "Cura alcança +1 casa.", "mods": {"cura": {"range": 1}}},
			{"id": "dru_clareira", "tag": "suporte", "name": "Clareira", "desc": "A Cura também atinge os vizinhos do aliado, mas demora um pouco mais.", "mods": {"cura": {"radius": 1, "time": 30}}},
			{"id": "dru_comunhao", "tag": "defesa", "name": "Comunhão", "desc": "Metade do que cura também volta para ela.", "passive": {"heal_self": 0.5}},
		]},
		{"name": "Espinhos", "nodes": [
			{"id": "dru_elfico", "tag": "movimento", "name": "Passos Élficos", "desc": "Anda 1 casa a mais por turno.", "passive": {"move_bonus": 1}},
			{"id": "dru_raizes", "tag": "ativa", "name": "Raízes", "desc": "Prende o alvo e atrasa a próxima ação dele em 40.", "unlock": "raizes"},
			{"id": "dru_venenoso", "tag": "controle", "name": "Vinhas Venenosas", "desc": "Todo ataque dela envenena: 3 por turno durante 2 turnos.", "passive": {"hit_status": {"id": "poison", "turns": 2, "amount": 3}}},
			{"id": "dru_cipos", "tag": "controle", "name": "Cipós", "desc": "Raízes atrasam mais 40.", "mods": {"raizes": {"delay": 40}}},
		]},
		{"name": "Casca", "nodes": [
			{"id": "dru_vigor", "tag": "defesa", "name": "Vigor Élfico", "desc": "+6 de vida.", "stats": {"hp": 6}},
			{"id": "dru_bencao", "tag": "ativa", "name": "Bênção da Mata", "desc": "Fortalece um aliado (ou ela mesma): +25% de dano por 2 turnos.", "unlock": "bencao"},
			{"id": "dru_ligeira", "tag": "suporte", "name": "Seiva Ligeira", "desc": "Quem recebe a cura dela age 30 antes.", "passive": {"heal_haste": 30}},
			{"id": "dru_abrigo", "tag": "defesa", "name": "Abrigo", "desc": "Quem recebe a cura entra em Guarda.", "passive": {"heal_guard": true}},
		]},
	],
	"fumaca": [
		{"name": "Névoa", "nodes": [
			{"id": "fum_espessa", "tag": "controle", "name": "Fumaça Espessa", "desc": "Nuvem Cegante alcança 1 casa a mais e sai 20 antes.", "mods": {"nuvem_cega": {"range": 1, "cast_time": -20, "time": -20}}},
			{"id": "fum_ar_pesado", "tag": "controle", "name": "Ar Pesado", "desc": "Todo ataque e magia dele deixa o alvo cego (causa 40% menos dano) por 1 turno.", "passive": {"hit_status": {"id": "blind", "turns": 1}}},
			{"id": "fum_nevoeiro", "tag": "controle", "name": "Nevoeiro", "desc": "Nuvem Cegante cobre 1 casa a mais de raio, com preparo um pouco maior.", "mods": {"nuvem_cega": {"radius": 1, "cast_time": 30, "time": 30}}},
			{"id": "fum_cranio", "tag": "ativa", "name": "Crânio de Fumaça", "desc": "Grande dano em área que cega todos por 2 turnos.", "unlock": "cranio_fumaca"},
		]},
		{"name": "Sombra", "nodes": [
			{"id": "fum_pes", "tag": "movimento", "name": "Pés de Névoa", "desc": "Anda 1 casa a mais por turno.", "passive": {"move_bonus": 1}},
			{"id": "fum_passo", "tag": "ativa", "name": "Passo de Fumaça", "desc": "Some e reaparece colado num inimigo a 2-4 casas, golpeia e o cega por 1 turno, sem sofrer oportunidade.", "unlock": "passo_fumaca"},
			{"id": "fum_intangivel", "tag": "defesa", "name": "Intangível", "desc": "Não sofre ataques de oportunidade.", "passive": {"opportunity_immune": true}},
			{"id": "fum_escuro", "tag": "ataque", "name": "Golpe no Escuro", "desc": "+50% de dano em inimigos cegos.", "passive": {"blind_hunter": 1.5}},
		]},
		{"name": "Véu", "nodes": [
			{"id": "fum_veu", "tag": "ativa", "name": "Véu de Fumaça", "desc": "Esconde um aliado (ou ele mesmo) na fumaça: recebe 30% menos dano por 2 turnos.", "unlock": "veu_fumaca"},
			{"id": "fum_cortina", "tag": "suporte", "name": "Cortina Longa", "desc": "Véu de Fumaça alcança 1 casa a mais e sai 30 mais rápido.", "mods": {"veu_fumaca": {"range": 1, "time": -30}}},
			{"id": "fum_bruma", "tag": "suporte", "name": "Bruma", "desc": "Aliados vizinhos recebem 15% menos dano.", "passive": {"ward": 0.85}},
			{"id": "fum_ligeiro", "tag": "suporte", "name": "Véu Ligeiro", "desc": "Quem recebe o Véu de outro age 40 antes.", "mods": {"veu_fumaca": {"haste": 40}}},
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
