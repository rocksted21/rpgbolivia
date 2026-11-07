extends RefCounted
## Números e textos da expedição. Balancear mexendo só aqui.

const TERRAIN_VILLAGE := 10
const TERRAIN_BEACON := 11

const BEACON_DISTANCE := 45 # o farol da região fica a essa distância do início, mais a folga
const BEACON_SPREAD := 6
const BEACON_MIN_EXITS := 4 # casas livres em volta do farol: a luta precisa de espaço
const LANDMARK_MIN := 10 # nenhum local especial nasce colado no início
const LANDMARK_SPACING := 9
const EDGE_MARGIN := 4 # os locais não nascem colados na borda do mapa
const ISLAND_MIN := 12 # ilha a partir desse tamanho ganha trilha (e ponte) até a rede
const ISLAND_BRIDGE_MAX := 6 # ponte maior que isso até a ilha não vale: ela fica como paisagem
const ROUTE_MARGIN := 10 # quanto a estrada e as trilhas podem desviar além da área dos locais
const CHEST_SPACING := 5 # baús ficam mais perto dos outros locais que o normal
const VISIT_RADIUS := 1
const BEACON_VISIT_RADIUS := 2
const COMPASS_RADIUS := 25 # além disso a bússola só mostra o farol

const LANDMARKS := {
	"forte": {"label": "Forte da Vigília", "count": 0, "color": Color("ff6858"), "brasas": 24, "xp": 80},
	"vila": {"label": "Vila", "count": 2, "color": Color("7fb6ff"), "guards": 3, "brasas": 4, "xp": 30},
	"ruina": {"label": "Ruínas", "count": 3, "color": Color("f2ca76"), "brasas": 6, "xp": 10},
	"emboscada": {"label": "Ruínas", "count": 2, "color": Color("f2ca76"), "guards": 3, "brasas": 12, "xp": 20},
	"fonte": {"label": "Fonte", "count": 2, "color": Color("7ff0c8"), "heal": 0.5},
	"memoria": {"label": "Memória", "count": 2, "color": Color("d6a6ff"), "xp": 30},
	# hidden: quantos deles não têm trilha nem aparecem na bússola, para quem sair do caminho.
	"bau": {"label": "Baú", "count": 6, "hidden": 2, "color": Color("f5b52e"), "brasas": 7, "xp": 5, "potion_chance": 0.35},
	# count 0: as lanternas têm regras próprias (LANTERNS) e nascem antes dos outros locais.
	"lanterna": {"label": "Lanterna", "count": 0, "color": Color("ffd36b")},
}

# Lanternas (ver docs/MAPA_LANTERNAS.md): uma corrente até o farol. Cada uma tem uma elite
# de guarda; acender uma revela a área da próxima, e a terceira revela o farol.
const LANTERNS := [
	{"min": 14, "max": 18, "elite": "mumia", "hp": 1.8, "atk": 1.10, "escort": 1, "brasas": 10, "xp": 40},
	{"min": 26, "max": 30, "elite": "feiticeira", "hp": 2.2, "atk": 1.15, "escort": 2, "brasas": 14, "xp": 60},
	{"min": 36, "max": 40, "elite": "cerbero", "hp": 2.8, "atk": 1.20, "escort": 3, "brasas": 18, "xp": 80},
]
const LANTERN_GAP := 18 # cada lanterna fica longe da anterior: o caminho vira zigue-zague
const LANTERN_BEACON_GAP := 12 # a última não fica colada no farol
const LANTERN_GAP_MAX := 26 # ...mas não tão longe que vire uma caminhada sem fim
const LANTERN_BEACON_MAX := 24
const LANTERN_AREA := 6 # a bússola mostra só uma área em volta da lanterna
const LANTERN_AREA_FAR := 3 # com a Cartógrafa ou o Mapa Rasgado, a área é mais precisa
const LANTERN_EXACT := 2 # chegando perto, a lanterna (ou o farol) aparece exata
const LANTERN_LIGHT := 10 # lanterna acesa ilumina em volta: os locais perto entram na bússola
const LANTERN_HEAL := 0.3
const ELITE_NAME := "Sentinela da Lanterna"
const ELITE_AURA := Color(1.0, 0.55, 0.25) # brilho de brasa em volta da Sentinela (só visual)
# Cada lanterna apagada deixa o guardião mais forte; vencê-lo assim rende brasas a mais.
const DARK_HP := 0.2
const DARK_ATK := 0.08
const DARK_BRASAS := 5

const BOSS := {
	"type": "mumia",
	"name": "Guardião do Farol",
	"hp_mult": 3.5,
	"atk_mult": 1.25,
	"speed": 9,
	"abilities": ["golpe", "chama"],
	"escort": 3,
	"brasas": 15,
	"xp": 100,
}
# Cada bioma tem o seu guardião (tipo em Data.UNIT_TYPES); o que não estiver aqui usa BOSS.
const BOSS_BY_BIOME := {
	"floresta": "boss_cervo",
	"selva": "boss_serpente",
	"neve": "boss_jarl",
	"deserto": "boss_farao",
}

const KILL_XP := 10
const LEVEL_XP := [0, 60, 160, 320, 520] # experiência total para cada nível da expedição
const LEVEL_HP := 4
const LEVEL_ATK := 1
const REST_HEAL := 1 # fora de combate, andar recupera pouco: as fontes e a cidade valem mais
const DEFEAT_BRASAS := 0.5 # o que sobra das brasas quando a party inteira cai

# Moradores que podem ser resgatados e o serviço que abrem na cidade.
# stat: o que cada nível soma em TownProgress.expedition_setup(). rescued: o aviso na vila.
# Os stats novos: rest_heal (vida por passo fora de combate), maps (1: bússola sem limite;
# 2: mostra os baús escondidos), xp_pct (% a mais de experiência) e potion_pct (% a mais
# de cura das poções). Ver expedition_state.gd.
const RESIDENTS := {
	"curandeira": {
		"name": "Curandeira", "service": "Enfermaria", "effect": "+%d de vida para todos os heróis",
		"stat": "hp", "per_level": 6, "costs": [15, 30, 50],
		"line": "A enfermaria voltou a ter luz. Ninguém mais parte sem cuidado.",
		"rescued": "Curandeira resgatada!",
	},
	"ferreiro": {
		"name": "Ferreiro", "service": "Forja", "effect": "+%d de ataque para todos os heróis",
		"stat": "atk", "per_level": 1, "costs": [15, 30, 50],
		"line": "O martelo voltou a soar na Cidade-Farol.",
		"rescued": "Ferreiro resgatado!",
	},
	"padeira": {
		"name": "Padeira", "service": "Padaria", "effect": "+%d de vida recuperada a cada passo fora de combate",
		"stat": "rest_heal", "per_level": 1, "costs": [15, 30, 50],
		"line": "O forno acendeu de novo. A cidade inteira acordou com cheiro de pão.",
		"rescued": "Padeira resgatada!",
	},
	"cartografa": {
		"name": "Cartógrafa", "service": "Torre de Mapas", "effect": "Mapa nível +%d: no 1º a bússola alcança tudo, no 2º mostra os baús escondidos",
		"stat": "maps", "per_level": 1, "costs": [20, 40],
		"line": "Da torre, a Cartógrafa já risca caminhos que ninguém lembrava.",
		"rescued": "Cartógrafa resgatada!",
	},
	"arquivista": {
		"name": "Arquivista", "service": "Arquivo", "effect": "+%d%% de experiência nas expedições",
		"stat": "xp_pct", "per_level": 15, "costs": [20, 40, 60],
		"line": "A mansão virou arquivo. Cada luta contada ali ensina quem vem depois.",
		"rescued": "Arquivista resgatado!",
	},
	"alquimista": {
		"name": "Alquimista", "service": "Laboratório", "effect": "Poções de Luz curam +%d%% de vida",
		"stat": "potion_pct", "per_level": 10, "costs": [20, 40],
		"line": "O abrigo das docas borbulha dia e noite. As poções nunca foram tão fortes.",
		"rescued": "Alquimista resgatado!",
	},
}
# Ordem em que aparecem nas vilas: duas vilas por expedição, então três expedições salvam todos.
const RESIDENT_ORDER := ["curandeira", "ferreiro", "padeira", "cartografa", "arquivista", "alquimista"]

# História (ver docs/SPOILER_historia.md): cada memória encontrada aparece uma vez, nesta ordem.
const MEMORIES := [
	"Uma voz antiga: \"Quando a última chama apagar, ninguém lembrará que houve um mundo.\"",
	"Um mapa do céu desenhado à mão. Metade das estrelas foi riscada, uma por uma.",
	"Um diário queimado: \"Os faroleiros não chegaram tarde. Eles estavam aqui quando começou.\"",
	"O sino de um barco antigo. Alguém raspou o nome gravado nele, com muito cuidado.",
	"Nomes riscados em uma parede. O último ainda parece recente.",
	"Uma carta: \"Mestre, o senhor não está salvando o mundo. Está trancando o mundo numa caixa.\" Assinada só com um B.",
	"Uma ordem selada: \"Apaguem os faróis. Sem chama acesa, ele não tem o que beber.\"",
	"O eco de um juramento: \"Guardaremos a luz, mesmo de quem a acendeu.\"",
	"Uma voz cansada, que um dia foi gentil: \"Eu só não queria perder mais ninguém.\"",
	"Um nome escrito no casco de um barco. Ninguém aqui o conhece, mas um de vocês sente vontade de chorar ao lê-lo.",
]
const EMPTY_MEMORY := "Só ecos desta vez. Eles ainda fortalecem quem escuta."

# O que cada guardião diz quando a luta começa e quando cai (aparece na tela de vitória).
const BOSS_LINES := {
	"boss_cervo": "\"Mais uma chama tentando passar? Nesta floresta, ninguém acende nada.\"",
	"boss_serpente": "\"Vocês cheiram a fogo novo... Ele também cheirava assim, no começo.\"",
	"boss_jarl": "\"Juramos guardar a luz. Até de quem a acendeu. Até de vocês.\"",
	"boss_farao": "\"Ele levou o céu inteiro. Não vai levar a minha última estrela.\"",
}
const BOSS_FAREWELL := {
	"boss_cervo": "\"Tomé... eu me chamava Tomé.\nNão deixem que ele beba esta chama.\"",
	"boss_serpente": "\"Killa... agora eu lembro.\nDigam ao Bento que eu cumpri o juramento.\"",
	"boss_jarl": "\"Gunnar. Guardei a luz até de quem a acendeu.\nAgora ela é de vocês.\"",
	"boss_farao": "\"Inti... E as estrelas? Ele ainda tem todas.\nO Primeiro Faroleiro nunca solta nada.\"",
}
# A batalha final ainda não existe: estes textos esperam por ela.
const VILLAIN := {
	"name": "Vésper, o Primeiro Faroleiro",
	"place": "Farol Negro",
	"intro": "\"Eu guardei vocês. Guardei tudo. Num mundo que esquece, quem vai lembrar de vocês se eu soltar?\"",
	"farewell": "\"Então... lembrem por mim.\"",
}


## A elite que guarda uma lanterna. O nome vai no save; assim a aura volta ao carregar.
static func is_elite(unit) -> bool:
	return unit != null and unit.display_name == ELITE_NAME
