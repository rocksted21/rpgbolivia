extends RefCounted
## Regras e textos da Cidade-Farol. A PLANTA fica em scenes/cidade.tscn: abra no Godot e edite
## chão, ruas, prédios, moradores, enfeites, árvores, rota de passeio e praça à vontade.
## Cada peça vale para o hexágono mais perto do seu centro; o deslocamento dentro dele é mantido.
## As posições que o resto do jogo usa são casas (coluna, linha) do mapa hexagonal.

const BiomeArt = preload("res://scripts/biome_art.gd")
const Hex = preload("res://scripts/hex.gd")
const SCENE := "res://scenes/cidade.tscn"
const VISIT_RADIUS := 2
const TOWN_ROOT := "res://assets/town/%s.png"
const RUBBLE := "res://assets/biomes/floresta/montanha_b.png"
const BASE_PEOPLE := 4
const PEOPLE_PER_RESCUE := 4
const PEOPLE_PER_BEACON := 2

# Tiles do chão, na ordem do atlas (assets/town/editor/chao_cidade.png):
# ~ água, # morro alto ao fundo, p praça de pedra, 0 a 3 o nível do chão. Sem tile = água.
const TILE_MARKS := ["~", "#", "p", "0", "1", "2", "3"]
const PLAZA_LEVEL := 1
const ROCK_LEVEL := 3

# Construções em 3D têm desenho de todos os lados: ver tools/build_town_models.py.
const MODEL_ROOT := "res://assets/town/modelos/%s.png"
# Enfeites em 3D (tools/build_harbor_models.py): giram com a câmera; o editor mostra um quadro.
const MODEL_DECOR := ["porto_barco", "porto_pier"]
const MODELS := ["casa_a", "casa_b", "casa_c", "taverna", "mansao", "capela", "forja", "tenda", "abrigo", "forno", "torre_madeira", "fonte", "farol"]

# Quem anda pelas ruas. A cidade ganha gente com os resgates e os faróis.
const WALKER_ART := ["morador_f", "morador_a", "morador_c", "morador_h"] # morador_g é o guia: não pode ter sósia
const WALKER_BASE := 2
const WALKER_MAX := 6
# Tochas e fogueiras: de noite, é a luz delas que mostra a cidade.
const LIGHT_ART := {"fogueira_a": 1.0, "fogueira_b": 1.0, "tocha": 0.6, "porto_pier": 0.7, "porto_barco": 0.45}
const BEACON_LIGHT := 2.2
const BEACON_HEIGHT := 226.0 # altura da lanterna acima do pé, em pixels do desenho do farol; cresce com a escala dele
const FORGE_LIGHT := 1.2
# O farol da cidade cresce com os faróis das regiões: chama fraca no começo, facho girando depois.
const BEACON_LEVELS := [0.55, 0.9, 1.15, 1.35, 1.5, 1.65] # força da chama por faróis acesos
const BEAM_FROM := 1 # a partir de quantos faróis acesos o facho gira no céu
const BEAM_LENGTH := [0.0, 900.0, 1250.0, 1600.0, 1950.0, 2300.0]
const BEAM_SPEED := 0.45 # voltas por segundo × TAU
# Lampiões das ruas (grupo Lampioes em cidade.tscn): acendem do mais perto da praça para fora,
# um pouco a cada morador resgatado e mais a cada farol aceso.
const LAMP_UNLIT := "res://assets/biomes/suburbios/lampiao.png"
const LAMP_LIT := "res://assets/biomes/suburbios/lampiao_aceso.png"
const LAMP_GROUND := 118 # pé do lampião no hexágono (meio da casa)
const LAMPS_BASE := 2
const LAMPS_PER_RESCUE := 1
const LAMPS_PER_BEACON := 2
const LAMP_LIGHT := 0.55
const LAMP_HEIGHT := 196.0 # altura da chama no desenho do lampião
# Moradores animados (tools/build_npc_idle.py): folha com os quadros lado a lado, cada um
# do mesmo tamanho da arte parada. Se a folha não existir, o morador fica parado como antes.
const IDLE_ROOT := "res://assets/town/anim/%s_idle.png"
const IDLE_FRAMES := 24
const IDLE_FPS := 8.0
# Moradores que carregam luz: [força, distância do pé até a chama (x, y) na arte].
const PERSON_LIGHT := {
	"morador_guarda": [0.4, Vector2(-38, 32)], # lanterna do Faroleiro
	"morador_arquivista": [0.3, Vector2(-44, 88)], # vela na mão
	"morador_e": [0.22, Vector2(-2, 86)], # vela da freira
	"morador_d": [0.22, Vector2(40, 95)], # lanterna nas costas da mascate
	"morador_ferreiro": [0.3, Vector2(64, 52)], # ferro em brasa na bigorna, onde o martelo bate
}

const BEACON_TEXT := "Enquanto esta chama arder, a cidade existe. Acendam os faróis das regiões e a escuridão vai recuar até quem a trouxe."
const NO_MEMORY_TEXT := "Ninguém aqui lembra de muita coisa. Traga memórias das expedições e eu conto o que elas significam."
const MISSING_TEXT := "Este lugar está em ruínas. Procure uma vila tomada pela escuridão: quem mora ali pode trazê-lo de volta."
const SKILLS_TEXT := "Treine aqui antes de partir. O que vocês aprenderam nas expedições vira força nas árvores de skills."

static var _plan := {}


# --- A planta, lida de scenes/cidade.tscn ---------------------------------------------
# Peças: {cell, path, art, offset, lift, scale, flip}; offset/lift = deslocamento em pixels
# dentro do hexágono, scale = tamanho além da escala padrão (BiomeArt.building_scale).

## Onde a party começa (nó Praca).
static func plaza() -> Vector2i:
	return plan()["plaza"]


## Uma letra por casa, linha por linha (linhas ímpares meia casa para a direita).
static func map_rows() -> Array:
	return plan()["map"]


static func road_cells() -> Array:
	return plan()["roads"]


static func trees() -> Array:
	return plan()["trees"]


## Peça + {radius, needs, face}. needs: morador sem o qual o prédio está em ruínas ("" = nenhum).
static func buildings() -> Array:
	return plan()["buildings"]


## Peça + {solid}. solid false deixa passar por cima (tochas na beira da rua).
static func decor() -> Array:
	return plan()["decor"]


## Peça + {id, name, service, needs}. service: "resident" (melhorias), "memories", "skills",
## "beacon", "shop", "board", "talk" ou "guide".
## Lampiões, do mais perto da praça ao mais longe (a ordem em que acendem).
static func lamps() -> Array:
	var out: Array = plan()["lamps"].duplicate()
	out.sort_custom(func(a, b): return Hex.distance(a["cell"], plaza()) < Hex.distance(b["cell"], plaza()))
	return out


## Quantos lampiões estão acesos com esse progresso.
static func lit_lamps(rescued_count: int, beacons: int) -> int:
	return LAMPS_BASE + rescued_count * LAMPS_PER_RESCUE + beacons * LAMPS_PER_BEACON


static func beacon_power(beacons: int) -> float:
	return BEACON_LIGHT * BEACON_LEVELS[clampi(beacons, 0, BEACON_LEVELS.size() - 1)]


static func beam_length(beacons: int) -> float:
	return BEAM_LENGTH[clampi(beacons, 0, BEAM_LENGTH.size() - 1)]


static func people() -> Array:
	return plan()["people"]


## Por onde passeia quem anda pelas ruas (nós dentro de Rota, em ordem).
static func walk_route() -> Array:
	return plan()["route"]


static func plan() -> Dictionary:
	if _plan.is_empty():
		var scene: Node = load(SCENE).instantiate()
		_plan = read_scene(scene)
		scene.free()
	return _plan


static func read_scene(scene: Node) -> Dictionary:
	var ground: TileMapLayer = scene.get_node("Chao")
	var out := {"plaza": _cell_of(ground, scene.get_node("Praca")), "map": [], "roads": [], "trees": [],
		"buildings": [], "decor": [], "people": [], "route": [], "lamps": []}
	var size: Vector2i = ground.get_used_rect().end + Vector2i.ONE # uma volta de água
	for row in size.y:
		var line := ""
		for col in size.x:
			var tile: int = ground.get_cell_atlas_coords(Vector2i(col, row)).x
			line += TILE_MARKS[tile] if tile >= 0 and tile < TILE_MARKS.size() else "~"
		out["map"].append(line)
	out["roads"] = scene.get_node("Ruas").get_used_cells()
	for tree in _sprites(scene, "Arvores"):
		out["trees"].append(_piece(ground, tree))
	for node in _sprites(scene, "Predios"):
		var building := _piece(ground, node)
		building["radius"] = int(node.get("raio")) if node.get("raio") != null else 0
		building["needs"] = _needs(node)
		building["face"] = building["cell"]
		out["buildings"].append(building)
	for node in _sprites(scene, "Enfeites"):
		var item := _piece(ground, node)
		item["solid"] = true if node.get("solido") == null else bool(node.get("solido"))
		out["decor"].append(item)
	for node in _sprites(scene, "Moradores"):
		if node.get("id") == null or str(node.get("id")) == "":
			push_warning("Morador sem id em cidade.tscn: %s" % node.name)
			continue
		var person := _piece(ground, node)
		person["id"] = str(node.get("id"))
		person["name"] = str(node.get("nome")) if str(node.get("nome")) != "" else str(node.name)
		person["service"] = str(node.get("servico"))
		person["needs"] = _needs(node)
		out["people"].append(person)
	if scene.has_node("Lampioes"):
		for node in _sprites(scene, "Lampioes"):
			out["lamps"].append(_piece(ground, node))
	for point in scene.get_node("Rota").get_children():
		if point is Node2D:
			out["route"].append(_cell_of(ground, point))
	return out


static func _sprites(scene: Node, group: String) -> Array:
	return scene.get_node(group).get_children().filter(func(n): return n is Sprite2D and n.texture != null)


## Posição do nó em relação ao chão (os grupos podem ter sido movidos).
static func _spot(ground: TileMapLayer, node: Node2D) -> Vector2:
	var spot := node.position
	var parent := node.get_parent()
	while parent is Node2D and parent != ground.get_parent():
		spot += (parent as Node2D).position
		parent = parent.get_parent()
	return spot - ground.position


static func _cell_of(ground: TileMapLayer, node: Node2D) -> Vector2i:
	return ground.local_to_map(_spot(ground, node))


static func _piece(ground: TileMapLayer, sprite: Sprite2D) -> Dictionary:
	var spot := _spot(ground, sprite)
	var cell := ground.local_to_map(spot)
	var shift: Vector2 = spot - ground.map_to_local(cell)
	var path: String = sprite.texture.resource_path
	return {"cell": cell, "path": path, "art": path.get_file().get_basename(), "offset": roundi(shift.x), "lift": roundi(shift.y),
		"scale": absf(sprite.scale.x) / BiomeArt.building_scale(path), "flip": sprite.flip_h,
		"turn": deg_to_rad(float(sprite.get("giro"))) if sprite.get("giro") != null else 0.0}


static func _needs(node: Node) -> String:
	var needs = node.get("precisa_de")
	return "" if needs == null or needs == "ninguem" else str(needs)
