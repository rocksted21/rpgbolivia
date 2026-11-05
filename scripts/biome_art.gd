extends RefCounted
## Qual arte de assets/biomes cada terreno usa. As regras ficam em game_data.gd e os
## arquivos são gerados por tools/build_biomes.py.

const ROOT := "res://assets/biomes/%s/%s.png"
const GROUND := {1: "campo_a", 9: "campo_b", 2: "campo_a", 3: "sombra", 16: "sombra", 5: "agua_a", 6: "sombra", 7: "campo_a", 10: "sombra", 11: "sombra", 13: "campo_a", 14: "agua_a", 15: "campo_a"}
const COMMON := "res://assets/biomes/comum/%s.png"
# A borda que invade a vizinha: quem vem depois na lista pinta por cima de quem vem antes.
const BIOME_ORDER := ["deserto", "selva", "floresta", "neve"]
const SHADED := [3, 6, 10, 11, 16] # terrenos com piso de sombra: o campo em volta avança sobre eles
const WET := [5, 14]
# Tom do chão e do cenário nas expedições: a escuridão cobre o mapa, e a luz vem de world_light.gd.
const EDGE_NOISE := "res://assets/biomes/comum/ruido_chao.png"
# Texturas contínuas do chão das expedições (tools/build_ground.py), de baixo para cima.
const SOLO := "res://assets/biomes/%s/%s_solo.png"
const SOIL := "res://assets/biomes/%s/solo.png"
const COBBLES := "res://assets/town/calcada_solo.png"
const NIGHT_TINT := {
	"floresta": Color(0.74, 0.78, 0.92),
	"selva": Color(0.92, 0.97, 1.0),
	"neve": Color(0.5, 0.56, 0.72),
	"deserto": Color(0.5, 0.48, 0.64),
}
const LANDMARK_LIFT := 0.45 # locais especiais ficam um pouco mais claros, para serem achados
const DECOR_CHANCE := 0.1 # abaixo disso a casa de campo ganha um enfeite; world_gen.gd escolhe quais
const MOUNTAIN_LANDMARK := 0.08
# Altura da base de cada objeto dentro do hexágono: fundo atrás do personagem, frente diante dele.
const BACK_Y := 92
const MIDDLE_Y := 118
const FRONT_Y := 172
const BEHIND_UNIT := 3
const BEFORE_UNIT := 6


static func soil(biome: String) -> String:
	return SOIL % biome


## Piso especial de um bioma: "sombra", "agua", "trilha" ou "estrada".
static func solo(biome: String, kind: String) -> String:
	return SOLO % [biome, kind]


## Tom de um objeto em pé. O que dá luz ou é prêmio não escurece.
static func prop_tint(biome: String, path: String) -> Color:
	var night: Color = NIGHT_TINT.get(biome, Color.WHITE)
	if light_of(biome, path) != "":
		return Color.WHITE
	if "/ruina_" in path:
		return night.lerp(Color.WHITE, LANDMARK_LIFT)
	return night


## Que luz o objeto solta, para world_light.gd; vazio se não brilhar.
static func light_of(biome: String, path: String) -> String:
	if "farol_aceso" in path:
		return "farol"
	if "bau_fechado" in path:
		return "bau"
	if biome == "selva" and "/enfeite_" in path:
		return "cristal"
	return ""


static func wall(biome: String) -> String:
	return ROOT % [biome, "parede"]


static func ground(biome: String, terrain_id: int, detail := 0.0) -> String:
	if terrain_id == 12: # calçada: só a Cidade-Farol tem
		return "res://assets/town/calcada.png"
	if terrain_id == 5 and detail >= 0.5: # a água tem duas versões: repetida, ela vira padrão
		return ROOT % [biome, "agua_b"]
	return ROOT % [biome, GROUND[terrain_id]]


## Peças de piso que completam a casa, desenhadas em ordem por cima dela. Cada lado é uma
## peça: juntas, elas ligam a casa às vizinhas. look(dir) -> {biome, terrain, elevation}.
static func overlays(biome: String, terrain_id: int, elevation: int, links: Array, look: Callable, road_links: Array = []) -> Array:
	var out := []
	for dir in 6:
		var next: Dictionary = look.call(dir)
		if terrain_id in WET:
			if not next["terrain"] in WET:
				out.append(ROOT % [biome, "margem_%d" % dir])
		elif not next["terrain"] in WET and next["elevation"] == elevation:
			if BIOME_ORDER.find(next["biome"]) > BIOME_ORDER.find(biome):
				out.append(ROOT % [next["biome"], "borda_%d" % dir])
			elif next["biome"] == biome and terrain_id in SHADED and not next["terrain"] in SHADED:
				out.append(ROOT % [biome, "borda_%d" % dir])
	out.append_array(_path_pieces(biome, terrain_id, links, road_links))
	return out


## Trilha embaixo, estrada em cima. Os meios-fios vêm antes de todos os pisos: onde os braços
## se juntam, a borda fica só por fora. Em linha reta os braços se encontram sem o miolo.
static func _path_pieces(biome: String, terrain_id: int, links: Array, road_links: Array) -> Array:
	var out := []
	if links.is_empty():
		return out
	var straight: bool = links.size() == 2 and absi(links[0] - links[1]) == 3
	if terrain_id == 14:
		for dir in links:
			out.append(COMMON % ("ponte_%d" % dir))
		if not straight:
			out.append(COMMON % "ponte")
		return out
	for dir in links:
		if not dir in road_links:
			out.append(ROOT % [biome, "trilha_%d" % dir])
	if road_links.is_empty():
		if not straight:
			out.append(ROOT % [biome, "trilha"])
		return out
	var hub: bool = not straight or road_links.size() < links.size()
	for dir in road_links:
		out.append(ROOT % [biome, "estrada_borda_%d" % dir])
	if hub:
		out.append(ROOT % [biome, "estrada_borda"])
	for dir in road_links:
		out.append(ROOT % [biome, "estrada_%d" % dir])
	if hub:
		out.append(ROOT % [biome, "estrada"])
	return out


## Objetos em pé de uma casa: [{path, ground_y, depth, layer}]. detail varia o desenho.
static func props(biome: String, terrain_id: int, detail: float) -> Array:
	var variant := "a" if detail < 0.5 else "b"
	match terrain_id:
		3:
			return [
				_prop(biome, "floresta_fundo_" + variant, BACK_Y, BEHIND_UNIT, "back"),
				_prop(biome, "floresta_frente_" + variant, FRONT_Y, BEFORE_UNIT, "front"),
			]
		16:
			return [_prop(biome, "floresta_fundo_" + variant, MIDDLE_Y, BEHIND_UNIT, "tree")]
		2:
			return [_prop(biome, "pedras_" + variant, MIDDLE_Y, BEHIND_UNIT)]
		6:
			# As serras são de pedra; um monumento aparece de vez em quando.
			return [_prop(biome, "montanha_b" if detail < MOUNTAIN_LANDMARK else "montanha_a", MIDDLE_Y + 20, BEHIND_UNIT)]
		7:
			return [_prop(biome, "colinas_" + variant, MIDDLE_Y, BEHIND_UNIT)]
		10:
			return [_prop(biome, "casa", MIDDLE_Y + 20, BEHIND_UNIT)]
		11:
			return [_prop(biome, "torre", MIDDLE_Y + 20, BEHIND_UNIT)]
		1, 9:
			if detail < DECOR_CHANCE:
				var decor := "abc"[int(detail / DECOR_CHANCE * 3.0)]
				return [_prop(biome, "enfeite_" + decor, BACK_Y, BEHIND_UNIT)]
	return []


## Arte de um local especial, em vez do terreno; vazio se ele não tiver desenho próprio.
static func landmark(biome: String, kind: String, done: bool, detail: float) -> Array:
	match kind:
		"bau":
			return [{"path": COMMON % ("bau_aberto" if done else "bau_fechado"), "ground_y": MIDDLE_Y + 8, "depth": BEHIND_UNIT, "layer": "main", "fixed": true}]
		"ruina", "emboscada":
			return [_prop(biome, "ruina_a" if detail < 0.5 else "ruina_b", BACK_Y + 10, BEHIND_UNIT)]
	return []


## O farol da região: aceso depois de derrotar o guardião.
static func beacon(biome: String, lit: bool) -> Dictionary:
	return _prop(biome, "farol_aceso" if lit else "farol_apagado", MIDDLE_Y + 20, BEHIND_UNIT)


static func _prop(biome: String, file: String, ground_y: int, depth: int, layer := "main") -> Dictionary:
	return {"path": ROOT % [biome, file], "ground_y": ground_y, "depth": depth, "layer": layer}
