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
# O que cada letra da planta vira. Os sólidos sem peça própria ganham a arte do tipo.
const LEGEND := {
	".": FIELD_A, ",": FIELD_B, ":": FIELD_A, "=": ROAD, "-": PATH, "~": WATER, "o": STONES,
	"H": BRIDGE, "#": HOUSE, "T": TREE, "t": FOREST, "h": HOUSE, "f": HOUSE, "w": HOUSE,
	"g": ROCKS, "r": ROCKS, "^": HILLS, "M": MOUNTAIN, "c": HOUSE,
}
const AUTO_ART := {"h": ["sebe", "sebe_b"], "f": ["grade"], "w": ["muro"], "g": ["lapides", "lapides_b"], "c": ["caixas"], "o": ["pedras_vau"]}
const PAVED := [":", "="]
const ROADS := ["=", "H"]
const TRAILS := ["-"]

var cells := {} # casa: {terrain, elevation, biome, detail}
var marks := {} # casa: letra da planta
var paved := {} # casas calçadas (praças, cais, ruas)
var art := {} # casa: [peças desenhadas pela planta]; vazio = nada em pé
var labels := {}
var districts := {}


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
				art[cell] = [_piece(options[int(roll * 7.0) % options.size()], cell)]
			elif mark == "#":
				art[cell] = [] # parte de um prédio: a arte fica no centro dele
	for piece in Plan.PIECES:
		var cell: Vector2i = piece["cell"]
		if not cells.has(cell):
			continue
		# Peça em cima de uma letra com arte própria (portão no muro) toma o lugar dela.
		var list: Array = [] if AUTO_ART.has(marks[cell]) else art.get(cell, [])
		list.append(_piece(piece["art"], cell))
		art[cell] = list
	labels = Plan.LABELS
	_carve_streets()


## Peça desenhada pela planta, no formato de BiomeArt (path, ground_y, depth, layer).
func _piece(name: String, cell: Vector2i) -> Dictionary:
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


## Fora da planta: muralha de árvores mortas e entulho. No sul, a muralha da Cidade-Farol.
func _wall(cell: Vector2i) -> Dictionary:
	var roll := _roll(cell)
	var terrain := TREE if fmod(roll * 37.0, 1.0) < 0.55 and cell.y < 4 else MOUNTAIN
	return {"terrain": terrain, "elevation": 1 if cell.y < 4 else 2, "biome": BIOME, "detail": DECOR_DETAIL + fmod(roll * 97.0, 1.0) * 0.9, "wall": true}


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
	return art.get(cell)


func fountain_art(cell: Vector2i) -> Dictionary:
	return _piece("fonte_luz", cell)


func label_at(cell: Vector2i) -> String:
	return labels.get(cell, "")


func district_at(cell: Vector2i) -> String:
	return Plan.DISTRICT_NAMES.get(districts.get(cell, ""), "")


func is_paved(cell: Vector2i) -> bool:
	return paved.has(cell) and not layout_terrain.has(cell)


func mark_at(cell: Vector2i) -> String:
	return marks.get(cell, " ")
