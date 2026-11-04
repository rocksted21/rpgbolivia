extends RefCounted
## Números do jogo. Balancear mexendo só aqui.

enum Team { PLAYER, ENEMY }

const STEP_TIME := 100
const CLIMB_TIME := 40
const WAIT_TIME := 50
const FLANK_MULT := 1.5
const HEIGHT_MULT_PER_LEVEL := 0.2
const GUARD_MULT := 0.5
const OPPORTUNITY_POWER := 0.5

# A chave é o número do PNG em assets/tiles.
# cost = tempo extra para entrar; damage = multiplicador do dano recebido em cima dele.
const TERRAIN := {
	1: {"name": "Campo", "walkable": true, "cost": 0, "damage": 1.0},
	2: {"name": "Pedras", "walkable": true, "cost": 0, "damage": 1.0},
	3: {"name": "Floresta", "walkable": true, "cost": 50, "damage": 0.8},
	5: {"name": "Água", "walkable": false, "cost": 0, "damage": 1.0},
	6: {"name": "Montanha", "walkable": false, "cost": 0, "damage": 1.0},
	7: {"name": "Colinas", "walkable": true, "cost": 50, "damage": 1.0},
	9: {"name": "Campo", "walkable": true, "cost": 0, "damage": 1.0},
	10: {"name": "Casa", "walkable": false, "cost": 0, "damage": 1.0},
	11: {"name": "Torre", "walkable": false, "cost": 0, "damage": 1.0},
}

const MAP_TERRAIN := [
	[3, 3, 1, 9, 6, 6, 3, 3],
	[3, 1, 9, 2, 9, 6, 1, 3],
	[1, 9, 1, 9, 1, 9, 9, 11],
	[5, 5, 9, 1, 2, 1, 9, 1],
	[5, 5, 1, 9, 1, 3, 9, 1],
	[10, 1, 9, 1, 9, 3, 3, 1],
]
const MAP_ELEVATION := [
	[1, 1, 1, 2, 2, 3, 2, 2],
	[1, 1, 1, 1, 2, 2, 1, 1],
	[0, 0, 1, 1, 1, 1, 1, 1],
	[0, 0, 0, 0, 1, 0, 0, 1],
	[0, 0, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 0, 0, 0],
]

# abilities em UNIT_TYPES são as iniciais; os heróis liberam o resto em skill_data.gd.
# time = custo total até poder agir de novo. Em charge, cast_time é a parte
# anterior ao impacto; o restante vira recuperação depois de soltar a magia.
const ABILITIES := {
	"golpe": {"name": "Golpe", "kind": "attack", "min_range": 1, "range": 1, "power": 1.0, "time": 150},
	"rapido": {"name": "Golpe rápido", "kind": "attack", "min_range": 1, "range": 1, "power": 0.7, "time": 90},
	"tiro": {"name": "Tiro", "kind": "attack", "min_range": 2, "range": 4, "power": 0.9, "time": 170, "shot": "kit/arrow"},
	# Liberadas nas árvores de skills (scripts/skill_data.gd).
	# shot: projétil do kit; taunt: raio da provocação; pierce: ignora defesa; delay: atrasa o alvo.
	"golpe_pesado": {"name": "Golpe Pesado", "kind": "attack", "min_range": 1, "range": 1, "power": 1.5, "time": 220},
	"provocar": {"name": "Provocar", "kind": "guard", "min_range": 0, "range": 0, "time": 130, "taunt": 2},
	"estocada": {"name": "Estocada", "kind": "attack", "min_range": 1, "range": 1, "power": 1.4, "time": 190},
	"aparar": {"name": "Aparar", "kind": "guard", "min_range": 0, "range": 0, "time": 60},
	"tiro_longo": {"name": "Tiro Longo", "kind": "attack", "min_range": 3, "range": 6, "power": 0.8, "time": 190, "shot": "kit/arrow"},
	"perfurante": {"name": "Virote Perfurante", "kind": "attack", "min_range": 2, "range": 4, "power": 1.0, "time": 230, "shot": "kit/arrow", "pierce": true},
	"tiro_rapido": {"name": "Tiro Rápido", "kind": "attack", "min_range": 2, "range": 3, "power": 0.55, "time": 100, "shot": "kit/arrow"},
	"saraivada": {"name": "Saraivada", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 1.0, "time": 210, "cast_time": 100, "shot": "kit/arrow"},
	"chuva_virotes": {"name": "Chuva de Virotes", "kind": "charge", "min_range": 2, "range": 5, "radius": 2, "power": 1.0, "time": 300, "cast_time": 180, "shot": "kit/arrow"},
	"adaga": {"name": "Adaga", "kind": "attack", "min_range": 1, "range": 1, "power": 0.7, "time": 100},
	"clareira": {"name": "Clareira", "kind": "heal", "min_range": 0, "range": 3, "radius": 1, "heal": 10, "time": 220},
	"espinho": {"name": "Espinho", "kind": "attack", "min_range": 2, "range": 3, "power": 0.8, "time": 140, "shot": "kit/magic"},
	"raizes": {"name": "Raízes", "kind": "attack", "min_range": 1, "range": 3, "power": 0.5, "time": 150, "delay": 40, "shot": "kit/magic"},
	"casca": {"name": "Casca", "kind": "guard", "min_range": 0, "range": 0, "time": 80},
	"agua_vital": {"name": "Água Vital", "kind": "heal", "min_range": 0, "range": 3, "heal": 9, "time": 170},
	"manto_agua": {"name": "Manto d'Água", "kind": "guard", "min_range": 0, "range": 0, "time": 80},
	# Mago de Fogo: uma magia por animação do pack de fogo (ver SPELL_FX na battle_view).
	"faisca": {"name": "Faísca", "kind": "attack", "min_range": 1, "range": 3, "power": 0.5, "time": 100},
	"labareda": {"name": "Labareda", "kind": "attack", "min_range": 1, "range": 2, "power": 1.0, "time": 150},
	"bola_fogo": {"name": "Bola de Fogo", "kind": "attack", "min_range": 2, "range": 4, "power": 0.8, "time": 160},
	"pilar_fogo": {"name": "Pilar de Fogo", "kind": "attack", "min_range": 2, "range": 4, "power": 1.1, "time": 200},
	"golpe_solar": {"name": "Golpe Solar", "kind": "attack", "min_range": 3, "range": 5, "power": 1.3, "time": 240},
	"flor_fogo": {"name": "Flor de Fogo", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 0.9, "time": 170, "cast_time": 80},
	"explosao": {"name": "Explosão", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 1.5, "time": 220, "cast_time": 120},
	"poca_lava": {"name": "Poça de Lava", "kind": "charge", "min_range": 1, "range": 3, "radius": 1, "power": 1.0, "time": 200, "cast_time": 110},
	"chuva_lava": {"name": "Chuva de Lava", "kind": "charge", "min_range": 2, "range": 5, "radius": 1, "power": 1.1, "time": 220, "cast_time": 130},
	"geiser_magma": {"name": "Gêiser de Magma", "kind": "charge", "min_range": 2, "range": 4, "radius": 0, "power": 2.0, "time": 220, "cast_time": 120},
	"furacao_fogo": {"name": "Furacão de Fogo", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 1.3, "time": 260, "cast_time": 150},
	"fenix": {"name": "Fênix", "kind": "charge", "min_range": 2, "range": 5, "radius": 2, "power": 1.6, "time": 320, "cast_time": 200},
	"escudo_fogo": {"name": "Escudo de Fogo", "kind": "guard", "min_range": 0, "range": 0, "time": 80},
	# Mago de Água: uma magia por animação do pack de água e gelo.
	"gota": {"name": "Gota d'Água", "kind": "attack", "min_range": 1, "range": 3, "power": 0.5, "time": 100},
	"chicote_agua": {"name": "Chicote d'Água", "kind": "attack", "min_range": 1, "range": 2, "power": 1.0, "time": 150},
	"bola_agua": {"name": "Bola d'Água", "kind": "attack", "min_range": 2, "range": 4, "power": 0.8, "time": 160},
	"estaca_gelo": {"name": "Estaca de Gelo", "kind": "attack", "min_range": 2, "range": 4, "power": 1.1, "time": 200},
	"cristal_gelo": {"name": "Cristal de Gelo", "kind": "attack", "min_range": 3, "range": 5, "power": 1.3, "time": 240},
	"floco_neve": {"name": "Floco de Neve", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 0.9, "time": 170, "cast_time": 80},
	"estilhaco_gelo": {"name": "Estilhaço de Gelo", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 1.5, "time": 220, "cast_time": 120},
	"onda": {"name": "Onda", "kind": "charge", "min_range": 1, "range": 3, "radius": 1, "power": 1.0, "time": 200, "cast_time": 110},
	"geiser": {"name": "Gêiser", "kind": "charge", "min_range": 2, "range": 4, "radius": 0, "power": 2.0, "time": 220, "cast_time": 120},
	"redemoinho": {"name": "Redemoinho", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 1.3, "time": 260, "cast_time": 150},
	"kraken": {"name": "Kraken", "kind": "charge", "min_range": 2, "range": 5, "radius": 2, "power": 1.6, "time": 320, "cast_time": 200},
	"chama": {"name": "Chama", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 1.2, "time": 240, "cast_time": 140},
	"cura": {"name": "Cura", "kind": "heal", "min_range": 0, "range": 3, "heal": 14, "time": 170},
	"guarda": {"name": "Guarda", "kind": "guard", "min_range": 0, "range": 0, "time": 80},
	"coronhada": {"name": "Coronhada", "kind": "attack", "min_range": 1, "range": 1, "power": 0.6, "time": 120},
}

const UNIT_TYPES := {
	"guardiao": {"name": "Guardião", "role": "Tanque · segura a linha", "hp": 46, "atk": 11, "def": 5, "speed": 9, "abilities": ["golpe", "guarda"]},
	"duelista": {"name": "Duelista", "role": "Ágil · age mais vezes", "hp": 28, "atk": 12, "def": 2, "speed": 14, "abilities": ["golpe", "rapido"]},
	"besteiro": {"name": "Besteiro", "role": "Atirador · ataca de longe", "hp": 26, "atk": 13, "def": 1, "speed": 10, "abilities": ["tiro"]},
	"mago": {"name": "Mago de Fogo", "role": "Magia · fogo em área", "hp": 24, "atk": 15, "def": 1, "speed": 9, "abilities": ["faisca", "bola_fogo", "flor_fogo", "escudo_fogo"]},
	"druida": {"name": "Druida Élfica", "role": "Suporte · cura aliados", "hp": 26, "atk": 10, "def": 1, "speed": 11, "abilities": ["golpe", "cura"]},
	"mago_agua": {"name": "Mago de Água", "role": "Magia · água e gelo", "hp": 24, "atk": 14, "def": 1, "speed": 10, "abilities": ["gota", "bola_agua", "floco_neve"]},
	"esqueleto": {"name": "Esqueleto", "role": "Soldado · morto-vivo comum", "hp": 22, "atk": 10, "def": 1, "speed": 10, "abilities": ["golpe"]},
	"mumia": {"name": "Múmia", "role": "Tanque · lenta e resistente", "hp": 40, "atk": 11, "def": 3, "speed": 7, "abilities": ["golpe"]},
	"diabrete": {"name": "Diabrete", "role": "Ágil · fraco, mas age muito", "hp": 16, "atk": 8, "def": 0, "speed": 15, "abilities": ["golpe"]},
	"feiticeira": {"name": "Feiticeira", "role": "Magia · chamas em área", "hp": 20, "atk": 13, "def": 0, "speed": 9, "abilities": ["chama"]},
	"cerbero": {"name": "Cérbero", "role": "Fera · forte e veloz", "hp": 34, "atk": 14, "def": 2, "speed": 12, "abilities": ["golpe"]},
}

static func range_text(ability: Dictionary) -> String:
	if ability["kind"] == "guard":
		return "em si"
	var text := "alcance %d" % ability["range"]
	if ability["min_range"] > 1:
		text = "alcance %d-%d" % [ability["min_range"], ability["range"]]
	if ability.has("radius"):
		text += ", área %d" % ability["radius"]
	return text


const BATTLE_UNITS := [
	["guardiao", Team.PLAYER, Vector2i(2, 2)],
	["duelista", Team.PLAYER, Vector2i(3, 1)],
	["besteiro", Team.PLAYER, Vector2i(1, 1)],
	["mago", Team.PLAYER, Vector2i(1, 2)],
	["druida", Team.PLAYER, Vector2i(2, 1)],
	["mago_agua", Team.PLAYER, Vector2i(2, 3)],
	["esqueleto", Team.ENEMY, Vector2i(5, 2)],
	["diabrete", Team.ENEMY, Vector2i(6, 1)],
	["mumia", Team.ENEMY, Vector2i(6, 3)],
	["feiticeira", Team.ENEMY, Vector2i(7, 3)],
	["cerbero", Team.ENEMY, Vector2i(6, 4)],
]


# --- Exploração (modo solo) ---------------------------------------------------

const WORLD_HEROES := ["guardiao", "duelista", "besteiro", "mago", "mago_agua", "druida"]
const WORLD := {
	"active_radius": 14, # até onde a IA procura caminho a partir do herói
	"despawn_radius": 13, # inimigo mais longe que isso se perde na névoa
	"spawn_min": 7,
	"spawn_max": 9,
	"first_spawn_steps": 6,
	"spawn_steps": [5, 10], # passos entre um grupo e outro
	"sight_radius": 5, # o inimigo inicia o combate ao ver o herói a essa distância
	"group_radius": 3, # quem está perto de quem viu entra na luta junto
	"flee_radius": 10, # inimigo em combate mais longe que isso perde o herói de vista
	"wander_chance": 0.3, # chance de um inimigo parado dar um passo a cada passo do herói
	"rest_heal": 2, # fora de combate, andar recupera vida
	"kill_heal": 5,
	"danger_distance": 20, # a cada tantas casas longe do início, o perigo sobe um nível
	"danger_max": 12,
	"danger_hp": 0.08, # vida extra do inimigo por nível de perigo
	"danger_atk": 0.05, # ataque extra do inimigo por nível de perigo
}
# Sozinho, o herói não tem quem o proteja: quem só ataca de longe ganha uma arma de perto.
const WORLD_EXTRA_ABILITIES := {"besteiro": ["coronhada"]}
# Inimigos liberados conforme o nível de perigo. O peso decide quem aparece mais.
const WORLD_SPAWNS := [
	{"danger": 1, "type": "esqueleto", "weight": 5},
	{"danger": 1, "type": "diabrete", "weight": 4},
	{"danger": 2, "type": "mumia", "weight": 3},
	{"danger": 3, "type": "feiticeira", "weight": 2},
	{"danger": 4, "type": "cerbero", "weight": 2},
]


# Biomas da exploração. forest, water, hills e rocks são os limites do ruído em
# world_gen.gd: quanto mais fácil o limite, mais daquele terreno aparece.
# names troca o nome das casas (a chave é o terreno); o que falta usa TERRAIN.
# A arte fica em assets/biomes/<chave>; ver tools/build_biomes.py.
const BIOMES := {
	"floresta": {
		"name": "Floresta", "forest": 0.22, "water": 0.3, "hills": -0.42, "rocks": -0.4,
		"names": {},
	},
	"selva": {
		"name": "Selva", "forest": 0.04, "water": 0.22, "hills": -0.46, "rocks": -0.42,
		"names": {1: "Clareira", 9: "Clareira", 3: "Selva", 5: "Rio", 6: "Rochedo", 11: "Ruínas"},
	},
	"neve": {
		"name": "Neve", "forest": 0.28, "water": 0.34, "hills": -0.36, "rocks": -0.4,
		"names": {1: "Neve", 9: "Neve", 2: "Pedras geladas", 3: "Pinheiral", 5: "Lago gelado", 6: "Rochedo", 7: "Montes de neve"},
	},
	"deserto": {
		"name": "Deserto", "forest": 0.34, "water": 0.5, "hills": -0.3, "rocks": -0.3,
		"names": {1: "Areia", 9: "Areia", 2: "Rochas", 3: "Cactos", 5: "Oásis", 6: "Rochedo", 7: "Dunas"},
	},
}
