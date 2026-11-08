extends RefCounted
## Números do jogo. Balancear mexendo só aqui.

enum Team { PLAYER, ENEMY }

const STEP_TIME := 100
const CLIMB_TIME := 40
const WAIT_TIME := 50
# Turno em combate: anda até gastar os pontos de movimento e usa uma ação, em qualquer ordem.
# Um passo em chão plano gasta STEP_TIME pontos: todos andam 3 casas (terreno/subida gastam mais).
const MOVE_BASE := 300
const MOVE_PER_SPEED := 0
const MOVE_ONLY_TIME := 100 # andar e não agir atrasa menos que atacar
const TURN_TIME := 150 # quanto a fila supõe que um turno dura, para prever a ordem
# Pulo: herói salta por cima de 1 unidade (aliada ou inimiga) em linha reta, gastando 2 passos.
# Quem pulou age mais devagar no resto do turno: o tempo da ação é multiplicado pela classe.
const JUMP_TIME := 200
const JUMP_PENALTY := {"duelista": 1.25, "besteiro": 1.5, "mago": 1.75, "mago_agua": 1.75, "druida": 2.0, "guardiao": 2.0, "fumaca": 1.25}
const JUMP_PENALTY_DEFAULT := 2.0
const FLANK_MULT := 1.5
const HEIGHT_MULT_PER_LEVEL := 0.2
const GUARD_MULT := 0.5
const OPPORTUNITY_POWER := 0.5
const PUSH_IMPACT := 3 # dano (sem defesa) de quem é empurrado contra algo; quem está no caminho leva o mesmo
const SLOW_MOVE := 100 # pontos de movimento a menos por turno com Lentidão (uma casa plana)
const MARK_MULT := 1.25 # dano recebido por quem está Marcado
const MIGHT_MULT := 1.25 # dano causado por quem está Fortalecido
const BLIND_MULT := 0.6 # dano causado por quem está Cego (fumaça nos olhos)
const VEIL_MULT := 0.7 # dano recebido por quem está Velado (escondido na fumaça)

# Efeitos que duram alguns turnos de quem os recebe. Contam no fim de cada turno dele.
# dot: tira `amount` de vida (sem defesa nem Guarda) no fim do turno.
const STATUS := {
	"burn": {"name": "queimando", "dot": true},
	"poison": {"name": "envenenado", "dot": true},
	"slow": {"name": "lento"},
	"mark": {"name": "marcado"},
	"might": {"name": "fortalecido"},
	"blind": {"name": "cego"},
	"veil": {"name": "velado"},
}

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
	12: {"name": "Calçada", "walkable": true, "cost": 0, "damage": 1.0},
	13: {"name": "Trilha", "walkable": true, "cost": 0, "damage": 1.0},
	14: {"name": "Ponte", "walkable": true, "cost": 0, "damage": 1.0},
	15: {"name": "Estrada", "walkable": true, "cost": 0, "damage": 1.0},
	16: {"name": "Árvore", "walkable": false, "cost": 0, "damage": 1.0},
	17: {"name": "Pedras do vau", "walkable": true, "cost": 0, "damage": 1.0}, # só nos Subúrbios
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
	# Mecânicas próprias (regras em battle_state.gd):
	#   push: empurra o alvo colado N casas · dash: salta até colar no alvo antes do golpe
	#   status: {"id", "turns", "amount"} aplica um efeito de STATUS · lifesteal: fração do dano que volta em vida
	#   kind "buff": mira um aliado; guard_ally põe em Guarda, haste adianta o relógio dele, status dá um efeito
	"escudada": {"name": "Escudada", "kind": "attack", "min_range": 1, "range": 1, "power": 0.6, "time": 120, "push": 1},
	"interpor": {"name": "Interpor", "kind": "buff", "min_range": 1, "range": 2, "time": 110, "guard_ally": true},
	"carga": {"name": "Carga do Escudo", "kind": "attack", "min_range": 2, "range": 3, "power": 1.0, "time": 210, "dash": true, "push": 1},
	"marcar": {"name": "Golpe Marcante", "kind": "attack", "min_range": 1, "range": 1, "power": 0.6, "time": 110, "status": {"id": "mark", "turns": 2}},
	"investida": {"name": "Investida", "kind": "attack", "min_range": 2, "range": 4, "power": 0.9, "time": 160, "dash": true},
	"sangria": {"name": "Lâmina Sedenta", "kind": "attack", "min_range": 1, "range": 1, "power": 0.9, "time": 160, "lifesteal": 0.5},
	"chute": {"name": "Chute", "kind": "attack", "min_range": 1, "range": 1, "power": 0.5, "time": 100, "push": 2},
	"virote_marcador": {"name": "Virote Marcador", "kind": "attack", "min_range": 2, "range": 5, "power": 0.5, "time": 130, "shot": "kit/arrow", "status": {"id": "mark", "turns": 2}},
	"tiro_perna": {"name": "Tiro na Perna", "kind": "attack", "min_range": 2, "range": 4, "power": 0.7, "time": 160, "shot": "kit/arrow", "status": {"id": "slow", "turns": 2}},
	"incinerar": {"name": "Incinerar", "kind": "attack", "min_range": 1, "range": 3, "power": 0.6, "time": 160, "status": {"id": "burn", "turns": 3, "amount": 4}},
	"rajada_calor": {"name": "Rajada de Calor", "kind": "attack", "min_range": 1, "range": 1, "power": 0.7, "time": 120, "push": 2},
	"toque_gelido": {"name": "Toque Gélido", "kind": "attack", "min_range": 2, "range": 4, "power": 0.6, "time": 170, "delay": 30, "status": {"id": "slow", "turns": 2}},
	"corrente": {"name": "Corrente", "kind": "buff", "min_range": 1, "range": 3, "time": 140, "haste": 60},
	"espinhos_venenosos": {"name": "Espinhos Venenosos", "kind": "attack", "min_range": 2, "range": 3, "power": 0.4, "time": 150, "shot": "kit/magic", "status": {"id": "poison", "turns": 3, "amount": 3}},
	"bencao": {"name": "Bênção da Mata", "kind": "buff", "min_range": 0, "range": 3, "time": 140, "status": {"id": "might", "turns": 2}},
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
	# Fumaça: controle. Cega (o alvo bate menos) e vela aliados (apanham menos). FX do pack de fumaça.
	"baforada": {"name": "Baforada", "kind": "attack", "min_range": 1, "range": 2, "power": 0.8, "time": 130},
	"sufocar": {"name": "Sufocar", "kind": "attack", "min_range": 1, "range": 1, "power": 1.25, "time": 200},
	"nuvem_cega": {"name": "Nuvem Cegante", "kind": "charge", "min_range": 2, "range": 4, "radius": 1, "power": 0.4, "time": 180, "cast_time": 80, "status": {"id": "blind", "turns": 2}},
	"veu_fumaca": {"name": "Véu de Fumaça", "kind": "buff", "min_range": 0, "range": 3, "time": 130, "status": {"id": "veil", "turns": 2}},
	"passo_fumaca": {"name": "Passo de Fumaça", "kind": "attack", "min_range": 2, "range": 4, "power": 0.8, "time": 170, "dash": true, "status": {"id": "blind", "turns": 1}},
	"cranio_fumaca": {"name": "Crânio de Fumaça", "kind": "charge", "min_range": 2, "range": 5, "radius": 2, "power": 1.4, "time": 300, "cast_time": 180, "status": {"id": "blind", "turns": 2}},
	"cura": {"name": "Cura", "kind": "heal", "min_range": 0, "range": 3, "heal": 14, "time": 170},
	"guarda": {"name": "Guarda", "kind": "guard", "min_range": 0, "range": 0, "time": 80},
	# Ataques iniciais com a animação forte (cada herói tem um normal e um forte).
	"vinha": {"name": "Chicote de Vinhas", "kind": "attack", "min_range": 1, "range": 2, "power": 0.9, "time": 150, "shot": "kit/magic"},
	"virote_pesado": {"name": "Virote Pesado", "kind": "attack", "min_range": 2, "range": 4, "power": 1.25, "time": 230, "shot": "kit/arrow"},
	"giro": {"name": "Corte Giratório", "kind": "attack", "min_range": 1, "range": 1, "power": 1.3, "time": 210},
	"coronhada": {"name": "Coronhada", "kind": "attack", "min_range": 1, "range": 1, "power": 0.6, "time": 120},
	# Golpes especiais dos chefes dos faróis (efeitos em BOSS_FX, battle_view.gd).
	"esmagar": {"name": "Esmagar", "kind": "attack", "min_range": 1, "range": 1, "power": 1.6, "time": 230},
	"bote": {"name": "Bote da Serpente", "kind": "attack", "min_range": 1, "range": 2, "power": 1.5, "time": 210},
	"giro_machado": {"name": "Giro do Machado", "kind": "attack", "min_range": 1, "range": 1, "power": 1.7, "time": 240},
	"decreto": {"name": "Decreto do Faraó", "kind": "attack", "min_range": 1, "range": 3, "power": 1.4, "time": 230},
	# Inimigos que atacam de longe: põem pressão na retaguarda da party.
	"flecha_ossea": {"name": "Flecha Óssea", "kind": "attack", "min_range": 2, "range": 4, "power": 0.85, "time": 170, "shot": "kit/arrow"},
	"brasa_cuspida": {"name": "Cuspe de Brasa", "kind": "attack", "min_range": 1, "range": 3, "power": 0.6, "time": 130, "shot": "kit/magic", "status": {"id": "burn", "turns": 2, "amount": 2}},
}

const UNIT_TYPES := {
	"guardiao": {"name": "Guardião", "role": "Tanque · segura a linha", "hp": 46, "atk": 11, "def": 5, "speed": 9, "abilities": ["golpe", "guarda"]},
	"duelista": {"name": "Duelista", "role": "Ágil · age mais vezes", "hp": 28, "atk": 12, "def": 2, "speed": 14, "abilities": ["golpe", "rapido", "giro"]},
	"besteiro": {"name": "Besteiro", "role": "Atirador · ataca de longe", "hp": 26, "atk": 13, "def": 1, "speed": 10, "abilities": ["tiro", "virote_pesado"]},
	"mago": {"name": "Mago de Fogo", "role": "Magia · fogo em área", "hp": 24, "atk": 15, "def": 1, "speed": 9, "move": 2, "abilities": ["faisca", "bola_fogo", "flor_fogo", "escudo_fogo"]},
	"druida": {"name": "Druida Élfica", "role": "Suporte · cura aliados", "hp": 26, "atk": 10, "def": 1, "speed": 11, "abilities": ["vinha", "cura"]},
	"mago_agua": {"name": "Mago de Sangue", "role": "Magia · sangue", "hp": 24, "atk": 14, "def": 1, "speed": 10, "move": 2, "abilities": ["gota", "bola_agua", "floco_neve"]},
	# Sprite: Heroi Smoke 3 do PixelLab (pixellab/fumaca, ver tools/build_pixellab.gd).
	"fumaca": {"name": "Andarilho da Fumaça", "role": "Controle · cega e esconde", "hp": 26, "atk": 12, "def": 1, "speed": 12, "abilities": ["baforada", "sufocar", "nuvem_cega"]},
	"esqueleto": {"name": "Esqueleto", "role": "Soldado · morto-vivo comum", "hp": 22, "atk": 10, "def": 1, "speed": 10, "abilities": ["golpe"]},
	"mumia": {"name": "Múmia", "role": "Tanque · lenta e resistente", "hp": 40, "atk": 11, "def": 3, "speed": 7, "abilities": ["golpe"]},
	"diabrete": {"name": "Diabrete", "role": "Ágil · fraco, mas age muito", "hp": 16, "atk": 8, "def": 0, "speed": 15, "abilities": ["golpe"]},
	"feiticeira": {"name": "Feiticeira", "role": "Magia · chamas em área", "hp": 20, "atk": 13, "def": 0, "speed": 9, "move": 2, "abilities": ["chama"]},
	"cerbero": {"name": "Cérbero", "role": "Fera · forte e veloz", "hp": 34, "atk": 14, "def": 2, "speed": 12, "abilities": ["golpe"]},
	# Variações de longe: usam a folha de outro tipo (`art`) com outra cor (`tint`).
	"esqueleto_arqueiro": {"name": "Esqueleto Arqueiro", "role": "Atirador · flechas de longe", "hp": 16, "atk": 10, "def": 0, "speed": 10, "abilities": ["flecha_ossea"], "art": "esqueleto", "tint": Color(0.72, 0.85, 1.0)},
	"diabrete_brasa": {"name": "Diabrete de Brasa", "role": "Ágil · cospe brasas", "hp": 14, "atk": 8, "def": 0, "speed": 13, "abilities": ["brasa_cuspida"], "art": "diabrete", "tint": Color(1.0, 0.68, 0.45)},
	# Chefes dos faróis, um por bioma (ver BOSS_BY_BIOME em expedition_data.gd).
	"boss_cervo": {"name": "Rei Cervo Sombrio", "role": "Chefe · floresta", "hp": 42, "atk": 12, "def": 3, "speed": 8, "abilities": ["golpe", "esmagar"]},
	"boss_serpente": {"name": "Rainha Serpente", "role": "Chefe · selva", "hp": 38, "atk": 12, "def": 2, "speed": 10, "abilities": ["golpe", "bote"]},
	"boss_jarl": {"name": "Jarl de Gelo Negro", "role": "Chefe · neve", "hp": 46, "atk": 13, "def": 3, "speed": 7, "abilities": ["golpe", "giro_machado"]},
	"boss_farao": {"name": "Faraó Eclipse", "role": "Chefe · deserto", "hp": 38, "atk": 12, "def": 2, "speed": 9, "abilities": ["golpe", "decreto"]},
	# O faroleiro dos subúrbios: a folha do Rei Cervo, em cinza de cinzas (falta arte própria).
	"boss_acendedor": {"name": "O Acendedor Apagado", "role": "Chefe · subúrbios", "hp": 42, "atk": 12, "def": 3, "speed": 8, "abilities": ["golpe", "esmagar"], "art": "boss_cervo", "tint": Color(0.72, 0.78, 1.0)},
}

## Folha de sprite do tipo (variações reaproveitam a de outro tipo).
static func art(type_id: String) -> String:
	return UNIT_TYPES.get(type_id, {}).get("art", type_id)


static func range_text(ability: Dictionary) -> String:
	if ability["kind"] == "guard":
		return "em si"
	var text := "alcance %d" % ability["range"]
	if ability.get("dash", false):
		text = "salta %d-%d" % [ability["min_range"], ability["range"]]
		return text
	if ability["min_range"] > 1:
		text = "alcance %d-%d" % [ability["min_range"], ability["range"]]
	if ability.has("radius"):
		text += ", área %d" % ability["radius"]
	return text


## Efeitos extras de uma habilidade, em palavras curtas ("empurra 2 · lento 2 turnos").
static func effect_text(ability: Dictionary) -> String:
	var parts := []
	if ability.get("dash", false):
		parts.append("salta até o alvo")
	if ability.has("push"):
		parts.append("empurra %d" % ability["push"])
	if ability.has("lifesteal"):
		parts.append("recupera %d%% do dano" % roundi(ability["lifesteal"] * 100))
	if ability.get("delay", 0) > 0:
		parts.append("atrasa %d" % ability["delay"])
	if ability.get("guard_ally", false):
		parts.append("aliado em Guarda")
	if ability.has("haste"):
		parts.append("aliado age %d antes" % ability["haste"])
	if ability["kind"] == "buff" and ability.get("heal", 0) > 0:
		parts.append("cura %d" % ability["heal"])
	if ability.get("pierce", false):
		parts.append("ignora defesa")
	if ability.has("status"):
		var status: Dictionary = ability["status"]
		var turns: int = status["turns"]
		var info: Dictionary = STATUS[status["id"]]
		var text: String = info["name"]
		if info.get("dot", false):
			text += " (%d por turno)" % status.get("amount", 0)
		parts.append("%s %d turno%s" % [text, turns, "" if turns == 1 else "s"])
	return " · ".join(parts)


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

# No fim da lista: a sala online guarda o herói pelo índice aqui.
const WORLD_HEROES := ["guardiao", "duelista", "besteiro", "mago", "mago_agua", "druida", "fumaca"]
const PARTY_SIZE := 4
const DEFAULT_PARTY := ["guardiao", "duelista", "mago", "druida"]
const WORLD := {
	"active_radius": 17, # até onde a IA procura caminho a partir do herói
	"despawn_radius": 16, # inimigo mais longe que isso se perde na névoa
	"spawn_min": 10,
	"spawn_max": 12,
	"first_spawn_steps": 6,
	"spawn_steps": [5, 10], # passos entre um grupo e outro
	"sight_radius": 3, # o inimigo inicia o combate ao ver o herói a essa distância
	"ambush_range": 2, # fora de combate, ataques de longe alcançam essas casas a mais (emboscada)
	"sight_walk": 900, # pontos de movimento: mais longe que isso a pé, o inimigo não entra na luta
	"give_up_radius": 5, # inimigo em combate, sem caminho e mais longe que isso, desiste
	"group_radius": 3, # quem está perto de quem viu entra na luta junto
	"flee_radius": 10, # inimigo em combate mais longe que isso perde o herói de vista
	"fight_radius": 7, # herói a até essa distância dos inimigos entra na luta; o resto segue explorando
	"wander_chance": 0.3, # chance de um inimigo parado dar um passo a cada passo do herói
	"rest_heal": 2, # fora de combate, andar recupera vida
	"deploy_steps": 2, # quantas casas cada herói anda para se espalhar quando o combate começa
	"party_leash": 14, # distância máxima entre dois heróis fora de combate
	"revive_hp": 0.25, # quem caiu volta com essa fração da vida quando o combate acaba
	"party_enemies": 2, # vagas extras de inimigos por herói além do primeiro
	"party_group": 1, # inimigos a mais em cada grupo por herói além do primeiro
	"kill_heal": 5,
	"danger_distance": 20, # a cada tantas casas longe do início, o perigo sobe um nível
	"danger_max": 12,
	"danger_hp": 0.08, # vida extra do inimigo por nível de perigo
	"danger_atk": 0.05, # ataque extra do inimigo por nível de perigo
	"group_min": 3, # inimigos andam em bando: nunca menos que isso por grupo
	"group_ranged": 0.75, # chance de um bando sem atirador ganhar um
	"reinforce_below": 3, # luta que começa com menos inimigos que isso chama reforços
	"reinforce_delay": [300, 500], # tempo da fila até os reforços chegarem (uns 2 turnos)
	"reinforce_dist": [3, 5], # distância da party onde eles surgem (pelos flancos ou por trás)
}
# Sozinho, o herói não tem quem o proteja: quem só ataca de longe ganha uma arma de perto.
const WORLD_EXTRA_ABILITIES := {"besteiro": ["coronhada"]}
# Inimigos liberados conforme o nível de perigo. O peso decide quem aparece mais.
const WORLD_SPAWNS := [
	{"danger": 1, "type": "esqueleto", "weight": 5},
	{"danger": 1, "type": "diabrete", "weight": 4},
	{"danger": 1, "type": "esqueleto_arqueiro", "weight": 3, "ranged": true},
	{"danger": 1, "type": "diabrete_brasa", "weight": 2, "ranged": true},
	{"danger": 2, "type": "mumia", "weight": 3},
	{"danger": 3, "type": "feiticeira", "weight": 2, "ranged": true},
	{"danger": 4, "type": "cerbero", "weight": 2},
]


# Biomas da exploração. forest, water, hills e rocks são os limites do ruído em
# world_gen.gd: quanto mais fácil o limite, mais daquele terreno aparece. Rios e serras
# formam a paisagem e valem para todos os biomas; os números deles ficam no gerador.
# names troca o nome das casas (a chave é o terreno); o que falta usa TERRAIN.
# A arte fica em assets/biomes/<chave>; ver tools/build_biomes.py.
const BIOMES := {
	# Mapa 1, desenhado à mão (scripts/suburbs_map.gd): os números de ruído só valem se um dia
	# o bioma for sorteado; os nomes trocam o que aparece ao passar o mouse.
	"suburbios": {
		"name": "Subúrbios Apagados", "forest": 0.2, "water": 0.22, "hills": -0.42, "rocks": -0.3,
		"names": {1: "Chão batido", 9: "Mato ralo", 2: "Entulho", 3: "Arvoredo seco", 16: "Plátano morto", 5: "Água do canal", 6: "Barranco", 7: "Monte de entulho", 10: "Casa", 11: "Farol", 13: "Trilha", 14: "Ponte", 15: "Rua de pedra", 17: "Pedras do vau"},
	},
	"floresta": {
		"name": "Floresta das Ruínas", "forest": 0.2, "water": 0.22, "hills": -0.42, "rocks": -0.3,
		"names": {1: "Musgo", 9: "Musgo", 2: "Pedras", 3: "Árvores mortas", 16: "Árvores mortas", 5: "Água escura", 6: "Ruínas", 7: "Colinas", 10: "Casa", 11: "Arco", 13: "Trilha", 14: "Ponte", 15: "Estrada"},
	},
	"selva": {
		"name": "Pântano de Tinta", "forest": 0.08, "water": 0.12, "hills": -0.46, "rocks": -0.38,
		"names": {1: "Lama", 9: "Lama", 2: "Cristais", 3: "Mangue", 16: "Mangue", 5: "Água de tinta", 6: "Destroços", 7: "Montes", 10: "Casa", 11: "Estufa", 13: "Trilha de lama", 14: "Ponte", 15: "Passarela"},
	},
	"neve": {
		"name": "Neve de Cinzas", "forest": 0.24, "water": 0.28, "hills": -0.38, "rocks": -0.26,
		"names": {1: "Neve", 9: "Neve", 2: "Cristais", 3: "Pinheiral", 16: "Pinheiral", 5: "Lago gelado", 6: "Destroços", 7: "Montes de neve", 10: "Casa", 11: "Arco", 13: "Trilha batida", 14: "Ponte", 15: "Estrada"},
	},
	"deserto": {
		"name": "Deserto de Ouro", "forest": 0.38, "water": 0.42, "hills": -0.24, "rocks": -0.2,
		"names": {1: "Areia", 9: "Areia", 2: "Rochas", 3: "Cactos", 16: "Cactos", 5: "Oásis", 6: "Ossadas", 7: "Dunas", 10: "Casa", 11: "Arco", 13: "Caminho", 14: "Ponte", 15: "Estrada"},
	},
}
