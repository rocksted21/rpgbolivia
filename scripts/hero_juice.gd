extends RefCounted
## Quanto peso cada golpe e magia dos 7 heróis tem na tela. Só apresentação.
##
## Campos de cada habilidade (todos opcionais):
##   stop: hitstop em segundos · shake: tremor (0 a 1) · knock: empurrão em quem apanha
##   lunge: avanço de quem bate (corpo a corpo) · recoil: coice de quem atira
##   ghosts: rastros do corpo no avanço · flash: clarão na tela (cor com alpha)
##   zoom: aproximação rápida · ult: escurece a tela e acende o mago antes de soltar
##   fx: camadas no alvo (em cada um, nas áreas) · impact: camadas no centro da magia
##   trail: cor do rastro do projétil · rain: virotes por casa caindo do céu
##   heavy: soma um baque ao som do golpe · color: cor do herói/elemento
##   peak: segundos até o auge da animação da magia (quando treme e o dano aparece)
## Camadas (as mesmas de BOSS_FX, com extras): burst, flash e ring; align gira
## na direção do golpe, add soma luz, height ergue do chão, delay atrasa.

const HEROES := ["guardiao", "duelista", "besteiro", "mago", "mago_agua", "druida", "fumaca"]
## Em que parte da animação o golpe acerta (fração dos frames da linha).
const ATTACK_HIT := 0.4
const STRONG_HIT := {"guardiao": 0.55, "duelista": 0.8, "besteiro": 0.42, "mago": 0.4, "mago_agua": 0.46, "druida": 0.68, "fumaca": 0.55}

## Cada herói tem só duas animações de golpe: a normal e a forte, usadas por
## várias habilidades. Ficam com a forte as habilidades pesadas e as magias
## carregadas (essas na hora de soltar; ao começar a carregar usam a normal).
const STRONG_ANIM := ["golpe_pesado", "estocada", "giro", "virote_pesado", "perfurante", "tiro_longo",
	"golpe_solar", "pilar_fogo", "estaca_gelo", "cristal_gelo", "carga", "investida", "rajada_calor", "sufocar", "passo_fumaca"]
## A Druida ataca sempre com a forte; a normal dela é o gesto de cura.
const ALWAYS_STRONG := ["druida"]

const STEEL := Color(1.0, 0.93, 0.75)
const GOLD := Color(1.0, 0.78, 0.3)
const DUEL := Color(0.72, 0.78, 1.0)
const ARROW := Color(1.0, 0.82, 0.5)
const FIRE := Color(1.0, 0.48, 0.12)
const SUN := Color(1.0, 0.8, 0.4)
const WATER := Color(0.35, 0.75, 1.0)
const ICE := Color(0.7, 0.95, 1.0)
const GORE := Color(0.85, 0.08, 0.12) # Mago de Sangue (ex-Água)
const GORE_PALE := Color(1.0, 0.45, 0.5)
const NATURE := Color(0.45, 1.0, 0.35)
const EARTH := Color(0.42, 0.3, 0.18)
const BLOOD := Color(1.0, 0.86, 0.8)
const SMOKE := Color(0.72, 0.68, 0.82) # cinza-violeta: o brilho da fumaça
const ASH := Color(0.2, 0.18, 0.22, 0.5) # fumaça escura (camada sem luz)

const HERO_COLOR := {"guardiao": GOLD, "duelista": DUEL, "besteiro": ARROW, "mago": FIRE, "mago_agua": GORE, "druida": NATURE, "fumaca": SMOKE}

static var _table := {}
static var _guards := {}


static func is_hero(type_id: String) -> bool:
	return HEROES.has(type_id)


## O peso de `id` usado por um herói, ou {} se quem age não é um dos heróis.
static func for_ability(type_id: String, id: String) -> Dictionary:
	if not is_hero(type_id):
		return {}
	if _table.is_empty():
		_table = _build()
	var out: Dictionary = (_table[id] if _table.has(id) else _table["_basic"]).duplicate()
	out["hero"] = type_id
	if not out.has("color"):
		out["color"] = HERO_COLOR[type_id]
	return out


## Efeito de Guarda / Provocar / Aparar / Casca.
static func for_guard(type_id: String, id: String) -> Dictionary:
	if not is_hero(type_id):
		return {}
	if _guards.is_empty():
		_guards = _build_guards()
	var out: Dictionary = (_guards[id] if _guards.has(id) else _guards["guarda"]).duplicate()
	if not out.has("color"):
		out["color"] = HERO_COLOR[type_id]
	return out


## A animação de golpe (forte ou não) de uma habilidade de ataque de herói.
static func strong_anim(type_id: String, id: String) -> bool:
	return ALWAYS_STRONG.has(type_id) or STRONG_ANIM.has(id)


static func color_of(type_id: String) -> Color:
	return HERO_COLOR.get(type_id, STEEL)


## Quem cai: fumaça, poeira e (inimigo) a alma subindo.
static func death_fx(hero_died: bool) -> Array:
	var soul := Color(1.0, 0.45, 0.4) if hero_died else Color(0.8, 0.9, 1.0)
	return [_smoke(Color(0.62, 0.57, 0.5, 0.35), 7, 0.3, 20), _debris(EARTH, 8, 0.8), _ring(Color(0.85, 0.8, 0.7), 1.1, 0.45),
		_embers(soul, 18, 80), {"kind": "flash", "tex": "trace_01", "color": soul, "size": 0.5, "life": 0.5, "grow": 0.5, "stretch": Vector2(0.6, 1.4), "spin": 0.0, "align": true, "turn": PI / 2, "add": true, "height": 130}]


## Cura: anel no chão, brilho e faíscas subindo.
static func heal_fx(color: Color) -> Array:
	return [_ring(color, 1.0, 0.5), _embers(color, 16, 40), {"kind": "burst", "tex": "star_06", "color": color, "amount": 6, "speed": [40, 120], "size": 0.14, "life": 0.9, "gravity": -200, "add": true, "height": 60},
		{"kind": "flash", "tex": "circle_05", "color": color, "size": 0.6, "life": 0.45, "grow": 0.4, "add": true, "height": 90}]


## Poeira dos passos de um herói em combate (maior quando sobe ou desce degrau).
static func dust_fx(big: bool) -> Array:
	var amount := 7 if big else 3
	return [{"kind": "burst", "tex": "smoke_04", "color": Color(0.55, 0.48, 0.38, 0.32 if big else 0.22), "amount": amount, "speed": [40, 110 if big else 70], "size": 0.16 if big else 0.11, "life": 0.55, "gravity": -30, "height": 6}]


## Começar a carregar uma magia: lampejo e faíscas subindo.
static func cast_fx(color: Color) -> Array:
	return [_ring(color, 1.1, 0.45), _embers(color, 14, 50), _glow(color, 0.5, 0.3, "circle_05", 100)]


## Disparo: clarão na ponta da besta (ou da mão).
static func muzzle_fx(color: Color) -> Array:
	return [_glow(color, 0.3, 0.1, "star_08", 95), {"kind": "burst", "tex": "smoke_04", "color": Color(0.7, 0.68, 0.62, 0.25), "amount": 3, "speed": [30, 80], "size": 0.12, "life": 0.5, "gravity": -40, "height": 95}]


## Virote caindo da chuva: poeira e lasca no chão.
static func landing_fx(color: Color) -> Array:
	return [_debris(EARTH, 4, 0.7), _glow(color, 0.2, 0.08, "star_08", 20), {"kind": "burst", "tex": "smoke_04", "color": Color(0.55, 0.48, 0.38, 0.3), "amount": 2, "speed": [30, 80], "size": 0.12, "life": 0.5, "gravity": -30, "height": 8}]


# --- Camadas prontas -------------------------------------------------------------

static func _slash(color: Color, size: float, turn := 0.0, delay := 0.0, tex := "slash_03") -> Dictionary:
	return {"kind": "flash", "tex": tex, "color": color, "size": size, "life": 0.2, "align": true, "turn": turn, "delay": delay, "grow": 0.7, "add": true, "height": 85}


static func _sparks(color: Color, amount: int, speed := 1.0, height := 85.0) -> Dictionary:
	return {"kind": "burst", "tex": "star_04", "color": color, "amount": amount, "speed": [260 * speed, 560 * speed], "size": 0.11, "life": 0.38, "gravity": 900, "along": true, "spread": 70.0, "add": true, "height": height}


static func _glow(color: Color, size: float, life := 0.14, tex := "star_09", height := 85.0) -> Dictionary:
	return {"kind": "flash", "tex": tex, "color": color, "size": size, "life": life, "grow": 0.6, "add": true, "height": height}


static func _ring(color: Color, size: float, life := 0.42, tex := "circle_03") -> Dictionary:
	return {"kind": "ring", "tex": tex, "color": color, "size": size, "life": life, "add": true}


static func _debris(color: Color, amount: int, speed := 1.0) -> Dictionary:
	return {"kind": "burst", "tex": "dirt_02", "color": color, "amount": amount, "speed": [180 * speed, 420 * speed], "size": 0.07, "life": 0.6, "gravity": 1100, "height": 30}


static func _smoke(color: Color, amount: int, size := 0.3, height := 40.0) -> Dictionary:
	return {"kind": "burst", "tex": "smoke_04", "color": color, "amount": amount, "speed": [50, 150], "size": size, "life": 0.9, "gravity": -50, "height": height}


static func _embers(color: Color, amount: int, height := 70.0) -> Dictionary:
	return {"kind": "burst", "tex": "star_04", "color": color, "amount": amount, "speed": [90, 300], "size": 0.08, "life": 0.9, "gravity": -260, "add": true, "height": height}


static func _shards(color: Color, amount: int) -> Dictionary:
	return {"kind": "burst", "tex": "star_07", "color": color, "amount": amount, "speed": [240, 520], "size": 0.12, "life": 0.55, "gravity": 1000, "add": true, "height": 80}


static func _streak(color: Color, length: float, life := 0.2) -> Dictionary:
	return {"kind": "flash", "tex": "trace_07", "color": color, "size": 0.5, "life": life, "align": true, "turn": PI / 2, "stretch": Vector2(0.5, length), "grow": 0.4, "add": true, "height": 85}


static func _spiral(color: Color, size: float, height := 80.0) -> Dictionary:
	return {"kind": "flash", "tex": "twirl_01", "color": color, "size": size, "life": 0.45, "grow": 0.4, "spin": 3.0, "add": true, "height": height}


# --- Tabela ----------------------------------------------------------------------

static func _build() -> Dictionary:
	var t := {}
	# Corpo a corpo genérico (contragolpe, oportunidade).
	t["_basic"] = {"stop": 0.05, "shake": 0.22, "knock": 30, "lunge": 34, "fx": [_slash(STEEL, 0.38), _sparks(STEEL, 6), _glow(STEEL, 0.22)]}
	# Guardião: pesado, escudo e espada.
	t["golpe"] = {"stop": 0.06, "shake": 0.28, "knock": 38, "lunge": 40, "fx": [_slash(STEEL, 0.46), _sparks(STEEL, 9), _glow(STEEL, 0.28)]}
	t["golpe_pesado"] = {"stop": 0.17, "shake": 0.66, "knock": 80, "lunge": 64, "zoom": 0.045, "heavy": true, "flash": Color(1.0, 0.9, 0.7, 0.2),
		"fx": [_slash(STEEL, 0.8, 0.0, 0.0, "slash_02"), _glow(GOLD, 0.6, 0.2), _sparks(GOLD, 18, 1.3), _debris(EARTH, 16, 1.2), _ring(Color(1.0, 0.85, 0.55), 1.3), _smoke(Color(0.5, 0.42, 0.32, 0.4), 6, 0.4, 20)]}
	# Duelista: rápida, cortes cruzados e rastros.
	t["rapido"] = {"stop": 0.035, "shake": 0.18, "knock": 26, "lunge": 54, "ghosts": 2, "color": DUEL,
		"fx": [_slash(DUEL, 0.4, 0.6), _slash(Color(1, 1, 1), 0.4, -0.6, 0.06), _sparks(DUEL, 6)]}
	t["estocada"] = {"stop": 0.13, "shake": 0.48, "knock": 70, "lunge": 90, "ghosts": 4, "zoom": 0.03, "color": DUEL,
		"fx": [_streak(Color(0.85, 0.9, 1.0), 2.4), _glow(Color(0.85, 0.9, 1.0), 0.5, 0.18, "star_08"), _sparks(DUEL, 14, 1.4), _ring(DUEL, 0.7, 0.3)]}
	t["giro"] = {"stop": 0.12, "shake": 0.5, "knock": 66, "lunge": 70, "ghosts": 5, "zoom": 0.03, "color": DUEL,
		"fx": [_slash(DUEL, 0.75, 0.0, 0.0, "slash_02"), _slash(Color(1, 1, 1), 0.55, PI, 0.05), _spiral(DUEL, 0.6), _sparks(DUEL, 14, 1.3), _ring(DUEL, 1.0, 0.35)]}
	t["escudada"] = {"stop": 0.09, "shake": 0.38, "knock": 70, "lunge": 50, "heavy": true,
		"fx": [_glow(GOLD, 0.45, 0.16, "star_08"), _sparks(GOLD, 10, 1.1), _ring(GOLD, 0.8, 0.3)]}
	t["carga"] = {"stop": 0.15, "shake": 0.62, "knock": 90, "lunge": 70, "ghosts": 4, "zoom": 0.04, "heavy": true, "flash": Color(1.0, 0.9, 0.7, 0.16),
		"fx": [_slash(GOLD, 0.7, 0.0, 0.0, "slash_02"), _glow(GOLD, 0.6, 0.2), _sparks(GOLD, 16, 1.3), _debris(EARTH, 14, 1.2), _ring(GOLD, 1.2)]}
	t["marcar"] = {"stop": 0.05, "shake": 0.22, "knock": 30, "lunge": 50, "ghosts": 2, "color": DUEL,
		"fx": [_slash(DUEL, 0.42, 0.4), _glow(GOLD, 0.4, 0.3, "star_08", 120), _sparks(DUEL, 7)]}
	t["investida"] = {"stop": 0.11, "shake": 0.45, "knock": 60, "lunge": 80, "ghosts": 5, "zoom": 0.03, "color": DUEL,
		"fx": [_streak(Color(0.85, 0.9, 1.0), 2.2), _slash(DUEL, 0.6, 0.3), _sparks(DUEL, 12, 1.3), _ring(DUEL, 0.8, 0.3)]}
	t["sangria"] = {"stop": 0.08, "shake": 0.3, "knock": 40, "lunge": 56, "ghosts": 3, "color": Color(1.0, 0.4, 0.45),
		"fx": [_slash(Color(1.0, 0.35, 0.4), 0.5, -0.4), _sparks(Color(1.0, 0.4, 0.45), 10), _embers(Color(1.0, 0.45, 0.5), 8, 60)]}
	t["chute"] = {"stop": 0.08, "shake": 0.32, "knock": 70, "lunge": 40, "fx": [_glow(ARROW, 0.4, 0.15, "star_08"), _sparks(ARROW, 8), _debris(EARTH, 8)]}
	t["virote_marcador"] = {"stop": 0.04, "shake": 0.16, "knock": 24, "recoil": 12, "trail": GOLD, "fx": [_glow(GOLD, 0.4, 0.3, "star_08", 120), _sparks(GOLD, 6)]}
	t["tiro_perna"] = {"stop": 0.07, "shake": 0.26, "knock": 30, "recoil": 18, "trail": ARROW, "fx": [_glow(ARROW, 0.32, 0.12, "star_08", 40), _sparks(ARROW, 8, 1.0, 40), _debris(EARTH, 8)]}
	t["espinhos_venenosos"] = {"stop": 0.05, "shake": 0.22, "knock": 28, "trail": Color(0.6, 1.0, 0.3), "fx": [_glow(Color(0.6, 1.0, 0.3), 0.32, 0.14, "star_08"), _spiral(Color(0.55, 0.9, 0.25), 0.35), _smoke(Color(0.4, 0.75, 0.2, 0.35), 6, 0.25, 60)]}
	t["incinerar"] = {"stop": 0.06, "shake": 0.3, "knock": 32, "impact": [_embers(FIRE, 18, 40), _smoke(Color(0.25, 0.2, 0.18, 0.4), 6)]}
	t["rajada_calor"] = {"stop": 0.1, "shake": 0.45, "knock": 90, "flash": Color(1.0, 0.55, 0.2, 0.14), "impact": [_embers(FIRE, 20), _ring(FIRE, 1.2), _glow(FIRE, 0.7, 0.2, "circle_05", 60)]}
	t["toque_gelido"] = {"stop": 0.08, "shake": 0.34, "knock": 30, "color": ICE, "flash": Color(0.7, 0.9, 1.0, 0.12), "impact": [_shards(ICE, 14), _ring(ICE, 0.9), _embers(ICE, 10, 30)]}
	t["adaga"] = {"stop": 0.04, "shake": 0.18, "knock": 26, "lunge": 36, "fx": [_slash(STEEL, 0.34), _sparks(STEEL, 5)]}
	t["coronhada"] = {"stop": 0.08, "shake": 0.32, "knock": 46, "lunge": 34, "fx": [_glow(ARROW, 0.4, 0.15, "star_08"), _sparks(ARROW, 8), _debris(EARTH, 6)]}
	# Besteiro: virotes com rastro, coice e estocada no impacto.
	t["tiro"] = {"stop": 0.05, "shake": 0.2, "knock": 30, "recoil": 16, "trail": ARROW, "fx": [_glow(ARROW, 0.3, 0.12, "star_08"), _sparks(ARROW, 7), _debris(EARTH, 4)]}
	t["virote_pesado"] = {"stop": 0.12, "shake": 0.45, "knock": 60, "recoil": 28, "zoom": 0.03, "trail": Color(1.0, 0.75, 0.35), "flash": Color(1.0, 0.85, 0.55, 0.1),
		"fx": [_glow(Color(1.0, 0.75, 0.35), 0.5, 0.16, "star_08"), _sparks(ARROW, 14, 1.4), _debris(EARTH, 10, 1.1), _ring(ARROW, 0.9, 0.3)]}
	t["tiro_longo"] = {"stop": 0.06, "shake": 0.24, "knock": 34, "recoil": 18, "trail": ARROW, "fx": [_glow(ARROW, 0.34, 0.12, "star_08"), _sparks(ARROW, 8)]}
	t["tiro_rapido"] = {"stop": 0.03, "shake": 0.14, "knock": 22, "recoil": 10, "trail": ARROW, "fx": [_glow(ARROW, 0.24, 0.1, "star_08"), _sparks(ARROW, 5)]}
	t["perfurante"] = {"stop": 0.14, "shake": 0.52, "knock": 72, "recoil": 30, "zoom": 0.035, "trail": Color(1.0, 0.95, 0.7), "flash": Color(1.0, 0.9, 0.6, 0.12),
		"fx": [_streak(Color(1.0, 0.92, 0.65), 3.0, 0.25), _glow(Color(1.0, 0.9, 0.6), 0.55, 0.18, "star_08"), _sparks(ARROW, 16, 1.5), _ring(ARROW, 0.8, 0.32)]}
	t["saraivada"] = {"stop": 0.06, "shake": 0.3, "knock": 34, "rain": 2, "trail": ARROW, "fx": [_sparks(ARROW, 6)]}
	t["chuva_virotes"] = {"stop": 0.09, "shake": 0.45, "knock": 40, "rain": 3, "ult": true, "trail": ARROW, "flash": Color(1.0, 0.85, 0.55, 0.12), "fx": [_sparks(ARROW, 8)]}
	# Druida: natureza, folhas e terra.
	t["vinha"] = {"stop": 0.06, "shake": 0.26, "knock": 34, "trail": NATURE, "fx": [_glow(NATURE, 0.34, 0.14, "star_08"), _spiral(NATURE, 0.45), _sparks(NATURE, 9), _debris(EARTH, 6)]}
	t["espinho"] = {"stop": 0.05, "shake": 0.22, "knock": 32, "trail": NATURE, "fx": [_glow(NATURE, 0.32, 0.14, "star_08"), _sparks(NATURE, 8), _spiral(NATURE, 0.3)]}
	t["raizes"] = {"stop": 0.09, "shake": 0.36, "knock": 10, "trail": NATURE, "fx": [_debris(EARTH, 14, 1.1), _spiral(NATURE, 0.5, 40), _ring(NATURE, 0.9), _embers(NATURE, 10, 30)]}
	# Mago de Fogo.
	t["faisca"] = {"stop": 0.03, "shake": 0.12, "knock": 20, "impact": [_embers(FIRE, 8)]}
	t["labareda"] = {"stop": 0.05, "shake": 0.3, "knock": 36, "impact": [_embers(FIRE, 12), _glow(FIRE, 0.4, 0.2, "circle_05", 60)]}
	t["bola_fogo"] = {"peak": 0.1, "stop": 0.08, "shake": 0.42, "knock": 46, "trail": FIRE, "flash": Color(1.0, 0.55, 0.2, 0.12), "impact": [_glow(FIRE, 0.8, 0.25, "circle_05"), _embers(FIRE, 16), _ring(FIRE, 1.0), _smoke(Color(0.25, 0.2, 0.18, 0.45), 6)]}
	t["pilar_fogo"] = {"stop": 0.09, "shake": 0.5, "knock": 40, "flash": Color(1.0, 0.55, 0.2, 0.14), "impact": [_embers(FIRE, 20, 120), _ring(FIRE, 1.1)]}
	t["golpe_solar"] = {"peak": 0.15, "stop": 0.12, "shake": 0.7, "knock": 56, "zoom": 0.04, "flash": Color(1.0, 0.85, 0.5, 0.3), "impact": [_glow(SUN, 1.1, 0.3, "circle_05"), _embers(SUN, 22), _ring(SUN, 1.5, 0.5)]}
	t["flor_fogo"] = {"stop": 0.06, "shake": 0.36, "knock": 40, "flash": Color(1.0, 0.55, 0.2, 0.12), "impact": [_embers(FIRE, 18), _ring(FIRE, 1.2)]}
	t["explosao"] = {"peak": 0.12, "stop": 0.13, "shake": 0.78, "knock": 72, "zoom": 0.05, "trail": FIRE, "flash": Color(1.0, 0.6, 0.25, 0.32), "impact": [_glow(FIRE, 1.4, 0.3, "circle_05"), _embers(FIRE, 30), _ring(FIRE, 2.0, 0.5), _debris(EARTH, 18, 1.3), _smoke(Color(0.3, 0.26, 0.24, 0.3), 6, 0.35, 20)]}
	t["poca_lava"] = {"stop": 0.06, "shake": 0.34, "knock": 30, "flash": Color(1.0, 0.45, 0.15, 0.1), "impact": [_embers(FIRE, 20, 20), _smoke(Color(0.25, 0.2, 0.18, 0.4), 8)]}
	t["chuva_lava"] = {"stop": 0.09, "shake": 0.55, "knock": 46, "flash": Color(1.0, 0.5, 0.2, 0.16), "impact": [_embers(FIRE, 24), _ring(FIRE, 1.6)]}
	t["geiser_magma"] = {"peak": 0.22, "stop": 0.15, "shake": 0.82, "knock": 84, "zoom": 0.05, "flash": Color(1.0, 0.5, 0.15, 0.3), "impact": [_glow(FIRE, 1.0, 0.3, "circle_05", 40), _embers(FIRE, 30, 140), _debris(EARTH, 20, 1.5), _ring(FIRE, 1.3)]}
	t["furacao_fogo"] = {"stop": 0.1, "shake": 0.6, "knock": 50, "flash": Color(1.0, 0.5, 0.2, 0.18), "impact": [_spiral(FIRE, 1.0, 90), _embers(FIRE, 26), _ring(FIRE, 1.6)]}
	t["fenix"] = {"peak": 0.5, "stop": 0.18, "shake": 1.0, "knock": 96, "zoom": 0.075, "ult": true, "flash": Color(1.0, 0.65, 0.3, 0.5), "impact": [_glow(SUN, 1.8, 0.4, "circle_05", 120), _embers(FIRE, 40, 120), _ring(FIRE, 2.6, 0.6), _ring(SUN, 1.6, 0.4, "circle_05")]}
	# Mago de Água (agora de sangue: as cores viraram vermelho).
	t["gota"] = {"stop": 0.03, "shake": 0.12, "knock": 20, "color": GORE, "impact": [_sparks(GORE, 6, 0.8, 40)]}
	t["chicote_agua"] = {"stop": 0.06, "shake": 0.32, "knock": 46, "color": GORE, "impact": [_sparks(GORE, 12), _ring(GORE, 0.9)]}
	t["bola_agua"] = {"stop": 0.07, "shake": 0.38, "knock": 44, "trail": GORE, "color": GORE, "flash": Color(0.9, 0.12, 0.15, 0.1), "impact": [_sparks(GORE, 14, 1.1, 40), _ring(GORE, 1.1), _glow(GORE, 0.6, 0.2, "circle_05", 40)]}
	t["estaca_gelo"] = {"stop": 0.1, "shake": 0.48, "knock": 40, "color": GORE_PALE, "flash": Color(1.0, 0.45, 0.5, 0.14), "impact": [_shards(GORE_PALE, 16), _ring(GORE_PALE, 1.0)]}
	t["cristal_gelo"] = {"stop": 0.13, "shake": 0.66, "knock": 52, "zoom": 0.04, "color": GORE_PALE, "flash": Color(1.0, 0.5, 0.55, 0.28), "impact": [_shards(GORE_PALE, 24), _glow(GORE_PALE, 1.0, 0.28, "circle_05", 60), _ring(GORE_PALE, 1.4, 0.5)]}
	t["floco_neve"] = {"stop": 0.06, "shake": 0.34, "knock": 36, "color": GORE_PALE, "flash": Color(1.0, 0.45, 0.5, 0.12), "impact": [_shards(GORE_PALE, 16), _embers(GORE_PALE, 12)]}
	t["estilhaco_gelo"] = {"peak": 0.2, "stop": 0.13, "shake": 0.76, "knock": 70, "zoom": 0.05, "color": GORE_PALE, "flash": Color(1.0, 0.5, 0.55, 0.32), "impact": [_shards(GORE_PALE, 34), _glow(GORE_PALE, 1.3, 0.3, "circle_05"), _ring(GORE_PALE, 2.0, 0.5)]}
	t["onda"] = {"stop": 0.07, "shake": 0.42, "knock": 56, "color": GORE, "flash": Color(0.9, 0.12, 0.15, 0.12), "impact": [_sparks(GORE, 20, 1.2, 30), _ring(GORE, 1.8, 0.5)]}
	t["geiser"] = {"peak": 0.15, "stop": 0.15, "shake": 0.8, "knock": 84, "zoom": 0.05, "color": GORE, "flash": Color(0.95, 0.15, 0.18, 0.28), "impact": [_sparks(GORE, 28, 1.5, 60), _glow(GORE, 1.0, 0.3, "circle_05", 60), _ring(GORE, 1.3)]}
	t["redemoinho"] = {"stop": 0.1, "shake": 0.6, "knock": 50, "color": GORE, "flash": Color(0.9, 0.12, 0.15, 0.18), "impact": [_spiral(GORE, 1.0, 90), _sparks(GORE, 20, 1.2, 60), _ring(GORE, 1.6)]}
	t["kraken"] = {"peak": 0.55, "stop": 0.18, "shake": 1.0, "knock": 96, "zoom": 0.075, "ult": true, "color": GORE, "flash": Color(0.9, 0.12, 0.15, 0.45), "impact": [_glow(GORE, 1.8, 0.4, "circle_05", 120), _sparks(GORE, 40, 1.6, 60), _ring(GORE, 2.6, 0.6), _ring(GORE_PALE, 1.6, 0.4, "circle_05")]}
	# Andarilho da Fumaça: pouco clarão, muita fumaça escura; o peso vem do tremor e do escurecer.
	t["baforada"] = {"stop": 0.04, "shake": 0.16, "knock": 30, "impact": [_smoke(ASH, 6, 0.3, 60), _spiral(SMOKE, 0.35, 70)]}
	t["sufocar"] = {"stop": 0.12, "shake": 0.46, "knock": 24, "zoom": 0.03, "flash": Color(0.1, 0.08, 0.14, 0.18),
		"impact": [_smoke(ASH, 10, 0.4, 90), _spiral(SMOKE, 0.55, 90), _ring(SMOKE, 0.8, 0.35)]}
	t["nuvem_cega"] = {"stop": 0.06, "shake": 0.3, "knock": 18, "flash": Color(0.1, 0.08, 0.14, 0.16), "impact": [_smoke(ASH, 14, 0.45, 30), _ring(SMOKE, 1.4, 0.5)]}
	t["passo_fumaca"] = {"stop": 0.1, "shake": 0.42, "knock": 50, "ghosts": 5, "zoom": 0.03,
		"impact": [_smoke(ASH, 12, 0.4, 20), _slash(SMOKE, 0.55, 0.3), _ring(SMOKE, 0.9, 0.3)]}
	t["cranio_fumaca"] = {"peak": 0.6, "stop": 0.18, "shake": 1.0, "knock": 80, "zoom": 0.075, "ult": true, "flash": Color(0.08, 0.06, 0.12, 0.45),
		"impact": [_smoke(ASH, 24, 0.6, 80), _spiral(SMOKE, 1.4, 110), _ring(SMOKE, 2.6, 0.6), _embers(SMOKE, 20, 80)]}
	return t


static func _build_guards() -> Dictionary:
	var g := {}
	g["guarda"] = {"shake": 0.12, "fx": [_ring(GOLD, 1.0, 0.45), {"kind": "flash", "tex": "magic_04", "color": GOLD, "size": 0.55, "life": 0.4, "grow": 0.4, "add": true, "height": 100}, _embers(GOLD, 10, 40)]}
	g["provocar"] = {"shake": 0.32, "color": Color(1.0, 0.35, 0.25), "fx": [_ring(Color(1.0, 0.35, 0.25), 2.2, 0.55), _ring(Color(1.0, 0.6, 0.3), 1.2, 0.4, "circle_05"), _glow(Color(1.0, 0.4, 0.3), 0.7, 0.3, "circle_05", 110)]}
	g["aparar"] = {"shake": 0.1, "color": DUEL, "fx": [_glow(Color(0.9, 0.95, 1.0), 0.45, 0.2, "star_08", 100), _sparks(DUEL, 10), _ring(DUEL, 0.8, 0.3)]}
	g["casca"] = {"shake": 0.12, "color": NATURE, "fx": [_ring(Color(0.6, 0.45, 0.25), 1.0, 0.45), _spiral(NATURE, 0.6, 90), _embers(NATURE, 12, 40)]}
	g["escudo_fogo"] = {"shake": 0.16, "color": FIRE, "fx": [_ring(FIRE, 1.2, 0.45), _embers(FIRE, 16, 60)]}
	g["interpor"] = {"shake": 0.14, "color": GOLD, "fx": [_ring(GOLD, 1.2, 0.45), {"kind": "flash", "tex": "magic_04", "color": GOLD, "size": 0.55, "life": 0.4, "grow": 0.4, "add": true, "height": 100}]}
	g["corrente"] = {"shake": 0.1, "color": GORE, "fx": [_spiral(GORE, 0.6, 90), _sparks(GORE, 10, 0.8, 60), _ring(GORE, 1.0, 0.4)]}
	g["bencao"] = {"shake": 0.1, "color": NATURE, "fx": [_ring(NATURE, 1.1, 0.45), _embers(Color(1.0, 0.8, 0.4), 16, 40), _glow(NATURE, 0.6, 0.35, "circle_05", 90)]}
	g["manto_agua"] = {"shake": 0.14, "color": WATER, "fx": [_ring(WATER, 1.2, 0.45), _sparks(WATER, 12, 0.8, 60)]}
	g["veu_fumaca"] = {"shake": 0.1, "color": SMOKE, "fx": [_smoke(ASH, 10, 0.4, 60), _ring(SMOKE, 1.1, 0.45), _spiral(SMOKE, 0.5, 80)]}
	g["resgate"] = g["interpor"]
	g["casca_viva"] = g["casca"]
	g["troca_fumaca"] = g["veu_fumaca"]
	return g
