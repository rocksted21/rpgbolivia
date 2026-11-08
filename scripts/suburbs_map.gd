extends "res://scripts/world_gen.gd"
## Mapa fixo dos Subúrbios Apagados: o terreno vem da planta (scripts/suburbs_plan.gd, gerada
## por tools/build_suburbios_map.py), não do ruído. Ruas, bairros e segredos ficam sempre no
## mesmo lugar; o que muda por expedição (lanternas, vilas, baús...) é escolhido em
## expedition_state.gd a partir dos candidatos da planta.

const Plan = preload("res://scripts/suburbs_plan.gd")

const BIOME := "suburbios"
const STONES := 17 # pedras do vau: andáveis, com água em volta
const ART := "res://assets/biomes/suburbios/%s.png"
const GROUND_Y := 118 # pé das peças no hexágono (como BiomeArt.MIDDLE_Y)
# Tamanho de cada peça da planta. A arte da cidade é pequena: as casas crescem como lá (2,5).
const ART_SCALE := {
	"casa_suburbio_a": 2.5, "casa_suburbio_b": 2.5, "casa_suburbio_c": 2.5, "pensao": 2.5,
	"mansao_aurelio": 3.1, "capela_canal": 2.5, "mausoleu": 1.45, "cripta": 1.9, "barracao": 1.6,
	"alojamento": 2.0, "galpao": 2.5, "torre_vigia": 2.2, "guarita": 1.35, "estufa": 1.4,
	"barraca_a": 1.25, "barraca_b": 1.25, "barraca_c": 1.0, "carroca": 1.6, "caixas": 1.4,
	"barricada": 1.4, "coreto": 1.6, "gasometro": 2.9, "gasometro_pequeno": 2.4, "bonde": 1.7,
	"fonte_seca": 1.5, "portao_jardim": 1.4, "portao_cemiterio": 1.4, "portao_cidade": 2.6,
	"estatua": 1.0, "coluna": 1.0, "banco": 0.9, "lampiao": 1.0, "lampiao_aceso": 1.0,
	"ponte_caida": 1.0, "muro": 1.2, "grade": 1.22, "fonte_luz": 1.5, "barco": 1.3, "barris": 1.3, "sebe": 1.0, "sebe_b": 1.0, "lapides": 1.0,
	"lapides_b": 1.0, "pedras_vau": 1.0, "telescopio": 1.0,
}
const RENAME := {"telescopio": "coluna"} # peças da planta sem arte própria
# Peças que são modelos de 16 ângulos (giram com a câmera, como os prédios da cidade).
# nome na planta: [modelo, pasta]. tools/build_suburbios_models.py gera os da pasta dos Subúrbios.
const MODEL_ROOT := "res://assets/biomes/suburbios/modelos/%s.png"
const TOWN_MODEL_ROOT := "res://assets/town/modelos/%s.png"
const MODEL_GROUND := 107 # centro do hexágono, como na cidade
const OWN_MODELS := ["casa_suburbio_a", "casa_suburbio_b", "casa_suburbio_c", "pensao", "mansao_aurelio",
	"capela_canal", "mausoleu", "cripta", "barracao", "alojamento", "galpao", "torre_vigia", "guarita",
	"barraca_a", "barraca_b", "barraca_c", "coreto", "gasometro", "gasometro_pequeno", "bonde",
	"portao_cidade", "lapides", "lapides_b"]
const TOWN_MODELS := {"carroca": "camp_carroca", "caixas": "camp_caixas", "banco": "shrine_bench",
	"fonte_luz": "fonte", "fonte_seca": "garden_fountain", "portao_jardim": "garden_gate",
	"portao_cemiterio": "garden_gate", "barco": "porto_barco", "casa": "casa_a"}
# Cercas, muros e sebes: um trecho de meia casa para cada vizinho da mesma linha, virado na
# direção dele. Assim a linha fica certa de qualquer ângulo da câmera.
const BARRIERS := {"f": "grade", "w": "muro", "h": "sebe"}
const JOINS := {"f": ["f", "w"], "w": ["w", "f"], "h": ["h"]}
# O que cada letra da planta vira. Os sólidos sem peça própria ganham a arte do tipo.
const LEGEND := {
	".": FIELD_A, ",": FIELD_B, ":": FIELD_A, "=": ROAD, "-": PATH, "~": WATER, "o": STONES,
	"H": BRIDGE, "#": HOUSE, "T": TREE, "t": FOREST, "h": HOUSE, "f": HOUSE, "w": HOUSE,
	"g": ROCKS, "r": ROCKS, "^": HILLS, "M": MOUNTAIN, "c": HOUSE,
}
const AUTO_ART := {"g": ["lapides", "lapides_b"], "c": ["caixas"], "o": ["pedras_vau"]}
const PAVED := [":", "="]
const CITY_ROW := 5 # daqui para o sul, fora da planta, é a cidade
const ROADS := ["=", "H"]
const TRAILS := ["-"]

var cells := {} # casa: {terrain, elevation, biome, detail}
var marks := {} # casa: letra da planta
var paved := {} # casas calçadas (praças, cais, ruas)
var art := {} # casa: [peças desenhadas pela planta]; vazio = nada em pé
var labels := {}
var districts := {}
var lamps := {} # casas com lampião de rua: acendem com a lanterna do bairro


func _init(p_seed: int) -> void:
	super(p_seed)
	fixed_biome = BIOME
	noise_paths = false
	_read_plan()


func _read_plan() -> void:
	for row in Plan.TERRAIN.size():
		var line: String = Plan.TERRAIN[row]
		var heights: String = Plan.HEIGHT[row]
		var zones: String = Plan.DISTRICT[row]
		for col in line.length():
			var mark := line[col]
			if mark == " ":
				continue
			var cell: Vector2i = Plan.ORIGIN + Vector2i(col, row)
			var roll := _roll(cell)
			var terrain: int = LEGEND.get(mark, FIELD_A)
			if mark == "." and roll >= 0.5:
				terrain = FIELD_B
			# detail: abaixo de DECOR_DETAIL a arte põe um enfeite; só no chão comum, e pouco.
			var detail := DECOR_DETAIL + fmod(roll * 97.0, 1.0) * 0.9
			if mark == "." and fmod(roll * 31.0, 1.0) < 0.06:
				detail = fmod(roll * 13.0, 1.0) * DECOR_DETAIL * 0.99
			cells[cell] = {"terrain": terrain, "elevation": int(heights[col]), "biome": BIOME, "detail": detail}
			marks[cell] = mark
			if mark in PAVED:
				paved[cell] = true
			if zones[col] != " ":
				districts[cell] = zones[col]
			if AUTO_ART.has(mark):
				var options: Array = AUTO_ART[mark]
				var turn := floorf(fmod(roll * 53.0, 1.0) * 6.0) * PI / 3.0 if mark == "g" else 0.0
				art[cell] = [_piece(options[int(roll * 7.0) % options.size()], cell, turn)]
			elif mark == "#":
				art[cell] = [] # parte de um prédio: a arte fica no centro dele
	for piece in Plan.PIECES:
		var cell: Vector2i = piece["cell"]
		if not cells.has(cell):
			continue
		# Peça em cima de uma letra com arte própria (portão no muro) toma o lugar dela.
		var list: Array = [] if AUTO_ART.has(marks[cell]) or BARRIERS.has(marks[cell]) else art.get(cell, [])
		list.append(_piece(piece["art"], cell, piece.get("turn", 0.0)))
		art[cell] = list
		if piece["art"] == "lampiao":
			lamps[cell] = true
	_build_barriers()
	labels = Plan.LABELS
	_carve_streets()


## Trechos de cerca, muro e sebe. Casas com peça própria (portões, guaritas) ficam como estão.
func _build_barriers() -> void:
	for cell in marks:
		var mark: String = marks[cell]
		if not BARRIERS.has(mark) or (art.has(cell) and not art[cell].is_empty()):
			continue
		var list: Array = []
		for dir in 6:
			var next := Hex.neighbor(cell, dir)
			if marks.get(next, " ") in JOINS[mark]:
				list.append(_model(BARRIERS[mark], MODEL_ROOT, _angle(cell, next)))
		if list.is_empty():
			if mark == "h":
				list.append(_model("sebe_bloco", MODEL_ROOT, 0.0))
			else: # pedaço solto: um trecho inteiro, de lado a lado
				list.append(_model(BARRIERS[mark], MODEL_ROOT, 0.0))
				list.append(_model(BARRIERS[mark], MODEL_ROOT, PI))
		art[cell] = list


## Ângulo da casa até a vizinha, no plano do tabuleiro (y para baixo), como o "turn" dos modelos.
func _angle(from: Vector2i, to: Vector2i) -> float:
	var a := Vector2(from.x + (from.y & 1) * 0.5, from.y * 0.866)
	var b := Vector2(to.x + (to.y & 1) * 0.5, to.y * 0.866)
	return (b - a).angle()


func _model(key: String, root: String, turn: float) -> Dictionary:
	return {"path": root % key, "model": key, "turn": turn, "ground_y": MODEL_GROUND, "depth": 3,
		"layer": "main", "fixed": true, "bob": key == "porto_barco"}


## Peça desenhada pela planta, no formato de BiomeArt (path, ground_y, depth, layer).
func _piece(name: String, cell: Vector2i, turn := 0.0) -> Dictionary:
	if name in OWN_MODELS:
		return _model(name, MODEL_ROOT, turn)
	if TOWN_MODELS.has(name):
		return _model(TOWN_MODELS[name], TOWN_MODEL_ROOT, turn)
	var file: String = RENAME.get(name, name)
	var roll := _roll(cell)
	var prop := {"path": ART % file, "ground_y": GROUND_Y, "depth": 3, "layer": "main", "fixed": true,
		"scale": ART_SCALE.get(name, 1.0), "flip": fmod(roll * 13.0, 1.0) < 0.5 and name in ["casa_suburbio_a", "casa_suburbio_b", "casa_suburbio_c", "lapides", "lapides_b", "sebe", "sebe_b", "caixas", "carroca", "barraca_a", "barraca_b"]}
	if name in ["pedras_vau", "ponte_caida"]:
		prop["ground_y"] = GROUND_Y + 10
		prop["depth"] = 2
	return prop


## Ruas e trilhas da planta viram caminhos do gerador: assim o chão desenha a rua (estrada_solo)
## e as pontes (ponte_*), e as regras de caminho continuam as mesmas do mapa sorteado.
func _carve_streets() -> void:
	for cell in marks:
		var mark: String = marks[cell]
		if not (mark in ROADS or mark in TRAILS):
			continue
		for dir in 6:
			var next := Hex.neighbor(cell, dir)
			var other: String = marks.get(next, " ")
			if mark in ROADS and other in ROADS:
				_carve_edge(cell, dir, true)
			elif (mark in TRAILS and (other in TRAILS or other in ROADS)) or (mark in ROADS and other in TRAILS):
				_carve_edge(cell, dir, false)
		if not carved.has(cell):
			carved[cell] = {} # rua sem vizinha de rua (ponta solta) continua sendo rua


# --- O que o resto do jogo pergunta ao gerador -------------------------------------

func _generate(cell: Vector2i) -> Dictionary:
	if not cells.has(cell):
		return _wall(cell)
	var spot: Dictionary = cells[cell].duplicate()
	if layout_terrain.has(cell) and not is_path(cell):
		spot["terrain"] = layout_terrain[cell]
	if layout_levels.has(cell):
		spot["elevation"] = layout_levels[cell]
	return spot


## Fora da planta: um bosque morto fechado. Atrás da muralha do sul fica a Cidade-Farol, com as
## janelas acesas: o lugar de onde a party saiu.
func _wall(cell: Vector2i) -> Dictionary:
	var roll := _roll(cell)
	var terrain := HOUSE if cell.y >= CITY_ROW else TREE
	return {"terrain": terrain, "elevation": 1, "biome": BIOME, "detail": DECOR_DETAIL + fmod(roll * 97.0, 1.0) * 0.9, "wall": true}


func _city_art(cell: Vector2i) -> Array:
	if cell.y % 2 == 0 and posmod(cell.x + cell.y, 3) == 0 and cell.y <= CITY_ROW + 6:
		var house: String = ["casa_a", "casa_b", "casa_c", "taverna"][posmod(cell.x * 7 + cell.y, 4)]
		return [_model(house, TOWN_MODEL_ROOT, PI if posmod(cell.x, 2) == 0 else PI * 0.9)]
	return []


func outside_bounds(cell: Vector2i) -> bool:
	return not cells.has(cell)


func set_bounds(_center: Vector2i, _radius: int) -> void:
	pass # a planta já tem borda


func biome_of(_cell: Vector2i) -> String:
	return BIOME


func is_road(cell: Vector2i) -> bool:
	return carved.has(cell) and (carved[cell].values().has(true) or marks.get(cell, "") in ROADS)


func find_start() -> Vector2i:
	return Plan.START


## Peças da planta nesta casa: null se a planta não diz nada (vale a arte do terreno).
func art_at(cell: Vector2i) -> Variant:
	if not cells.has(cell) and cell.y >= CITY_ROW:
		return _city_art(cell)
	return art.get(cell)


func fountain_art(cell: Vector2i) -> Dictionary:
	return _piece("fonte_luz", cell)


## Lampião desta casa, aceso: a peça da planta trocada pela versão com luz.
func lit_lamp_art(cell: Vector2i) -> Array:
	var out: Array = []
	for prop in art.get(cell, []):
		var lit: Dictionary = prop.duplicate()
		lit["path"] = String(prop["path"]).replace("/lampiao.png", "/lampiao_aceso.png")
		out.append(lit)
	return out


## A casa de quem resiste: o modelo da cidade, com as janelas acesas.
func village_art(cell: Vector2i) -> Dictionary:
	return _piece("casa", cell, PI if fmod(_roll(cell) * 17.0, 1.0) < 0.5 else 0.0)


func label_at(cell: Vector2i) -> String:
	return labels.get(cell, "")


func district_at(cell: Vector2i) -> String:
	return Plan.DISTRICT_NAMES.get(districts.get(cell, ""), "")


func is_paved(cell: Vector2i) -> bool:
	return paved.has(cell) and not layout_terrain.has(cell)


func mark_at(cell: Vector2i) -> String:
	return marks.get(cell, " ")
