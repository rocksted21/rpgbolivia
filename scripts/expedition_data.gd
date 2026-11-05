extends RefCounted
## Números e textos da expedição. Balancear mexendo só aqui.

const TERRAIN_VILLAGE := 10
const TERRAIN_BEACON := 11

const BEACON_DISTANCE := 45 # o farol da região fica a essa distância do início, mais a folga
const BEACON_SPREAD := 6
const BEACON_MIN_EXITS := 4 # casas livres em volta do farol: a luta precisa de espaço
const LANDMARK_MIN := 10 # nenhum local especial nasce colado no início
const LANDMARK_SPACING := 9
const ROUTE_WIDTH := 14 # os locais ficam a até essa distância do caminho até o farol
const ROUTE_MARGIN := 10 # quanto a estrada e as trilhas podem desviar além da área dos locais
const CHEST_SPACING := 5 # baús ficam mais perto dos outros locais que o normal
const VISIT_RADIUS := 1
const BEACON_VISIT_RADIUS := 2
const COMPASS_RADIUS := 25 # além disso a bússola só mostra o farol

const LANDMARKS := {
	"vila": {"label": "Vila", "count": 2, "color": Color("7fb6ff"), "guards": 3, "brasas": 4, "xp": 30},
	"ruina": {"label": "Ruínas", "count": 3, "color": Color("f2ca76"), "brasas": 6, "xp": 10},
	"emboscada": {"label": "Ruínas", "count": 2, "color": Color("f2ca76"), "guards": 3, "brasas": 12, "xp": 20},
	"fonte": {"label": "Fonte", "count": 2, "color": Color("7ff0c8"), "heal": 0.5},
	"memoria": {"label": "Memória", "count": 2, "color": Color("d6a6ff"), "xp": 30},
	# hidden: quantos deles não têm trilha nem aparecem na bússola, para quem sair do caminho.
	"bau": {"label": "Baú", "count": 6, "hidden": 2, "color": Color("f5b52e"), "brasas": 7, "xp": 5, "potion_chance": 0.35},
}

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

const KILL_XP := 10
const LEVEL_XP := [0, 60, 160, 320, 520] # experiência total para cada nível da expedição
const LEVEL_HP := 4
const LEVEL_ATK := 1
const REST_HEAL := 1 # fora de combate, andar recupera pouco: as fontes e a cidade valem mais
const DEFEAT_BRASAS := 0.5 # o que sobra das brasas quando a party inteira cai

# Moradores que podem ser resgatados e o serviço que abrem na cidade.
const RESIDENTS := {
	"curandeira": {
		"name": "Curandeira", "service": "Enfermaria", "effect": "+%d de vida para todos os heróis",
		"stat": "hp", "per_level": 6, "costs": [15, 30, 50],
		"line": "A enfermaria voltou a ter luz. Ninguém mais parte sem cuidado.",
	},
	"ferreiro": {
		"name": "Ferreiro", "service": "Forja", "effect": "+%d de ataque para todos os heróis",
		"stat": "atk", "per_level": 1, "costs": [15, 30, 50],
		"line": "O martelo voltou a soar na Cidade-Farol.",
	},
}
const RESIDENT_ORDER := ["curandeira", "ferreiro"]

# Rascunho da história: cada memória encontrada aparece uma vez, nesta ordem.
const MEMORIES := [
	"Uma voz antiga: \"Quando a última chama apagar, ninguém lembrará que houve um mundo.\"",
	"Um diário queimado: \"Os faroleiros não chegaram tarde. Eles estavam aqui quando começou.\"",
	"Nomes riscados em uma parede. O último ainda parece recente.",
	"Uma ordem selada: \"Apaguem os faróis. É o único jeito de escondê-lo.\"",
	"O eco de um juramento: \"Guardaremos a luz, mesmo de quem a acendeu.\"",
]
const EMPTY_MEMORY := "Só ecos desta vez. Eles ainda fortalecem quem escuta."
