extends RefCounted

## Desenho do tabuleiro: chão, casas, paredes, enfeites, locais e o mapa que carrega
## e descarrega conforme a câmera anda. Só apresentação: não mexe nas regras.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const TownState = preload("res://scripts/town_state.gd")
# Pisos da Cidade-Farol, na ordem em que são pintados.
const TOWN_FLOORS := [
	[TownState.FLOOR_PAVE, "res://assets/town/chao/calcada_bairro.png"],
	[TownState.FLOOR_STREET, "res://assets/town/chao/calcada_rua.png"],
	[TownState.FLOOR_PLAZA, "res://assets/town/chao/laje_praca.png"],
]
const GARDEN_EDGE := 0.45 # o canteiro chega até perto dos cantos da casa
const UnitView = preload("res://scripts/unit_view.gd")
const Hud = preload("res://scripts/hud.gd")
const BattleCamera = preload("res://scripts/battle_camera.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")

const BOSS_SCALE := 1.35
const ELITE_SCALE := 1.15 # a Sentinela da Lanterna fica entre o inimigo comum e o guardião
const TILE_FRONT := 213.0 # ponta da frente do topo do hexágono, na textura (igual ao shader)
const TILE_SLOPE := 53.0 # quanto as bordas inclinadas descem do centro até o lado
const TILE_WALL := 31.0 # altura da parede abaixo da borda da frente
# Cantos do topo do hexágono; o lado i dá para a vizinha na direção i de Hex.neighbor.
const HEX_CORNERS := [Vector2(185, 53), Vector2(185, 160), Vector2(93, 213), Vector2(0, 160), Vector2(0, 53), Vector2(93, 0)]
const WALL_SIDE_MARGIN := 0.4
const MODEL_META := "res://assets/town/modelos/meta.json"
const MODEL_SCALE := 2.0 # como os personagens: 1 pixel de arte vale 2 no tabuleiro
const MODEL_NIGHT_LIFT := Color(1.3, 1.26, 1.05) # desfaz parte do tom de noite: janelas acesas continuam vivas
# Construções grandes ficam transparentes quando escondem alguém atrás delas.
const TALL_PROP_HEIGHT := 200.0 # altura no tabuleiro a partir da qual a arte conta como "grande" (herói ~170)
const TALL_SEE_THROUGH := 0.4 # opacidade enquanto cobre alguém
const TALL_FADE_SPEED := 10.0 # quão rápido some e volta
const TALL_INSET := 0.12 # a arte tem margem transparente: ignora essa fração de cada lado
const UNIT_BOX := Vector2(70, 160) # corpo de um personagem no tabuleiro, a partir dos pés
# Chão natural das expedições: as casas continuam nas regras, mas não aparecem no desenho.
const CORNER_WOBBLE := Vector2(38, 26) # quanto cada canto sai do lugar: some o desenho da colmeia
const PROP_WOBBLE := Vector2(74, 50) # árvores e pedras fora do centro da casa
const RING_RADIUS := Vector2(78, 62)
const TOWN_WOBBLE := 0.55
const TRAIL_STRENGTH := 0.86 # abaixo de 1 estreita o traço; a estrada é mais larga
const ROAD_CORNER := 0.22
const SCENERY_BASE := {3: 1, 6: 7, 10: 9, 11: 9}
const TILE_PATH := "res://assets/tiles/%d.png"
const FOG_SIDE_SQUEEZE := 0.6 # igual ao peso lateral da névoa no shader
const VIEW_ROWS_FRONT := 7
const VIEW_ROWS_BACK := 14
const UNLOAD_MARGIN := 2
const Z_REBASE_ROWS := 12 # em meias linhas: a ordem de desenho fica longe do limite do Godot
const REACH_LINE := Color(1.0, 0.6, 0.15, 0.95)
# Borda da área onde está a próxima lanterna: um círculo de brasas no chão (só visual).
const AREA_DOT := Color(1.0, 0.78, 0.38, 0.5)
const AREA_DOT_CORE := Color(1.0, 0.93, 0.7, 0.85)
const AREA_DOT_RADIUS := Vector2(30, 22)

var battle: BattleView # a tela dona deste módulo
var area_key := "" # qual área de lanterna está desenhada no chão
var area_marks := {} # casa: marca da borda da área
var used_art := {} # caminho da imagem: retângulo sem a margem transparente


func _init(host: Node) -> void:
	battle = host


func _build_tiles() -> void:
	if battle.exploring:
		_sync_world(battle.camera_cell)
		return
	for row in battle.state.rows():
		for col in battle.state.cols():
			_build_cell(Vector2i(col, row))


func _build_cell(cell: Vector2i) -> void:
	battle.building = []
	var row := battle._row(cell)
	var base := Vector2(battle._column_x(cell), cell.y * battle.ROW_STEP)
	var layers: int = battle.state.elevation_at(cell) * battle.level_layers
	# Só a parede que aparece: o que as casas da frente cobrem não precisa ser desenhado.
	var terrain_id: int = battle.state.terrain_id_at(cell)
	# Só a exploração tem biomas; o Online continua com os tiles do mapa fixo.
	var biome: String = battle.state.biome_at(cell) if battle.exploring else ""
	var wall := BiomeArt.wall(biome) if battle.exploring else TILE_PATH % 9
	var ground := BiomeArt.ground(biome, battle.state.floor_id_at(cell), battle.state.detail_at(cell)) if battle.exploring else TILE_PATH % SCENERY_BASE.get(terrain_id, terrain_id)
	battle.cell_tint = BiomeArt.NIGHT_TINT.get(biome, Color.WHITE) if battle.world_light != null else Color.WHITE
	if battle.exploring:
		_add_walls(cell, wall, ground, row, layers)
	else:
		for layer in range(_hidden_layers(cell, layers), layers):
			_add_tile(wall, base - Vector2(0, layer * battle.SIDE_HEIGHT), row, layer * battle.SIDE_HEIGHT)
	if battle.natural:
		_add_natural_ground(cell, row, layers, biome)
	else:
		_add_tile(ground, battle.cell_origin(cell), row, layers * battle.SIDE_HEIGHT)
	if battle.exploring:
		if not battle.natural:
			for overlay_path in battle.state.ground_overlays(cell):
				_add_tile(overlay_path, battle.cell_origin(cell), row, layers * battle.SIDE_HEIGHT)
		_add_biome_props(biome, terrain_id, cell)
	elif terrain_id in [2, 3, 6, 7, 10, 11, 16]:
		_add_scenery(terrain_id, cell)
	if battle.expedition:
		_add_landmark(cell, row)
		_add_area_mark(cell, row, battle.building)
	if battle.town:
		battle.town_mode._add_person_name(cell, row)
	var overlay := Polygon2D.new()
	overlay.polygon = battle.hex_poly
	battle._place_ground_marker(overlay, cell)
	overlay.z_index = battle._z(row) + 1
	overlay.visible = false
	battle.board.add_child(overlay)
	battle.building.append(overlay)
	battle.overlays[cell] = overlay
	var line := _new_hex_line(REACH_LINE, 5)
	battle._place_ground_marker(line, cell)
	line.z_index = battle._z(row) + 2
	line.visible = false
	battle.building.append(line)
	battle.reach_lines[cell] = line
	battle.cell_nodes[cell] = battle.building
	battle.cell_rows[cell] = row


## Com a câmera livre, qualquer lado pode ficar de frente: cada lado com desnível ganha a sua
## parede, degrau por degrau. Os lados de trás ficam cobertos pelo topo da própria casa.
func _add_walls(cell: Vector2i, wall: String, ground: String, row: int, layers: int) -> void:
	for dir in 6:
		var side: int = battle.state.elevation_at(Hex.neighbor(cell, dir)) * battle.level_layers
		for layer in range(side + 1, layers + 1):
			var height := layer * battle.SIDE_HEIGHT
			var path := ground if layer == layers else wall
			var strip := Polygon2D.new()
			strip.texture = load(path)
			var mesh: Dictionary = _natural_wall_mesh(cell, dir) if battle.natural else _wall_mesh(dir)
			strip.polygon = mesh["vertices"]
			strip.uv = mesh["uv"]
			strip.polygons = mesh["faces"]
			strip.material = battle.battle_camera.tile_material(height * battle.BOARD_SCALE, battle.BOARD_SCALE)
			strip.position = Vector2(battle._column_x(cell), cell.y * battle.ROW_STEP - height)
			strip.z_index = battle._z(row)
			strip.modulate = battle.cell_tint
			battle.wall_groups[dir].add_child(strip)
			battle.battle_camera.keep_drawn(strip)
			battle.building.append(strip)


## A mesma parede, com os cantos fora do lugar como no chão: o penhasco não sai em zigue-zague.
func _natural_wall_mesh(cell: Vector2i, dir: int) -> Dictionary:
	var base: Dictionary = _wall_mesh(dir)
	var origin := Vector2(battle._column_x(cell), cell.y * battle.ROW_STEP)
	var a := _natural_corner(cell, dir) - origin
	var b := _natural_corner(cell, (dir + 1) % 6) - origin
	var drop := Vector2(signf(a.x - battle.HEX_MIDDLE.x) if is_equal_approx(a.x, b.x) else 0.0, TILE_WALL)
	return {"vertices": PackedVector2Array([a, b, b + drop, a + drop]), "uv": base["uv"], "faces": base["faces"]}


## Canto de uma casa, no plano do mundo. Casas vizinhas calculam o mesmo canto, então nunca abre fresta.
func _natural_corner(cell: Vector2i, index: int) -> Vector2:
	var corner: Vector2 = HEX_CORNERS[index]
	var key := Vector2i(battle._column_x(cell) + (battle.TILE_WIDTH if corner.x > battle.HEX_MIDDLE.x else int(corner.x)) , cell.y * battle.ROW_STEP + int(corner.y))
	var mixed := (key.x * 73856093) ^ (key.y * 19349663)
	mixed = (mixed ^ (mixed >> 13)) * 1274126177
	mixed = mixed ^ (mixed >> 16)
	var wobble := Vector2(float(mixed & 0xFFF) / 4095.0 - 0.5, float((mixed >> 12) & 0xFFF) / 4095.0 - 0.5)
	# A planta da cidade alinha escadas e prédios com os degraus: lá os cantos saem menos do lugar.
	return Vector2(key) + wobble * CORNER_WOBBLE * 2.0 * (TOWN_WOBBLE if battle.town else 1.0)


## Malha da casa: centro, 6 cantos e 6 meios de lado. A cobertura de cada mancha é dada nesses pontos.
func _natural_mesh(cell: Vector2i) -> Dictionary:
	var vertices := PackedVector2Array()
	vertices.resize(13)
	var middle := Vector2.ZERO
	for i in 6:
		vertices[1 + i] = _natural_corner(cell, i)
		middle += vertices[1 + i]
	vertices[0] = middle / 6.0
	for i in 6:
		vertices[7 + i] = (vertices[1 + i] + vertices[1 + (i + 1) % 6]) / 2.0
	var faces: Array[PackedInt32Array] = []
	for i in 6:
		faces.append(PackedInt32Array([0, 1 + i, 7 + i]))
		faces.append(PackedInt32Array([0, 7 + i, 1 + (i + 1) % 6]))
	return {"vertices": vertices, "faces": faces}


## Desenha o chão em camadas. Cada camada é uma mancha: cobre as casas do seu tipo e avança até
## o meio do caminho nas vizinhas, com a borda recortada pelo ruído do shader.
func _add_natural_ground(cell: Vector2i, row: int, layers: int, biome: String) -> void:
	var mesh := _natural_mesh(cell)
	var around := []
	for dir in 6:
		var next: Vector2i = Hex.neighbor(cell, dir)
		# Um penhasco separa os terrenos: a mancha não atravessa o desnível.
		around.append(next if battle.state.elevation_at(next) == battle.state.elevation_at(cell) else cell)
	var order: Array = BiomeArt.BIOME_ORDER
	var ranks := {}
	for spot in [cell] + around:
		ranks[spot] = order.find(battle.state.biome_at(spot))
	var lowest: int = ranks.values().min()
	var highest: int = ranks.values().max()
	_natural_layer(mesh, BiomeArt.soil(order[lowest]), _full_cover(), order[lowest], row, layers)
	for level in range(lowest + 1, highest + 1):
		if ranks.values().has(level) or level <= ranks[cell]:
			var cover := _cover(around, cell, func(spot): return ranks[spot] >= level)
			_natural_layer(mesh, BiomeArt.soil(order[level]), cover, order[level], row, layers)
	var shaded := _cover(around, cell, func(spot): return battle.state.floor_id_at(spot) in BiomeArt.SHADED)
	_natural_layer(mesh, BiomeArt.solo(biome, "sombra"), shaded, biome, row, layers)
	var wet := _cover(around, cell, func(spot): return battle.state.floor_id_at(spot) in BiomeArt.WET)
	_natural_layer(mesh, BiomeArt.solo(biome, "agua"), wet, biome, row, layers)
	if battle.expedition and (battle.state.fort.cells.has(cell) or around.any(func(c): return battle.state.fort.cells.has(c))):
		var paving := _cover(around, cell, func(c): return battle.state.fort.cells.has(c))
		_natural_layer(mesh, BiomeArt.COBBLES, paving, biome, row, layers)
	if battle.town: # a cidade é calçada; as ruas e a praça vêm da planta
		# A calçada vai embaixo de tudo que é pavimento: sem fresta de grama entre ela e a rua.
		var paved_ids: Array = TOWN_FLOORS.map(func(kind): return kind[0])
		for i in TOWN_FLOORS.size(): # de baixo para cima: a rua fica por cima da calçada
			var ids: Array = paved_ids if i == 0 else [TOWN_FLOORS[i][0]]
			if not ([cell] + around).any(func(spot): return battle.state.floor_id_at(spot) in ids):
				continue
			var cover := _cover(around, cell, func(spot): return battle.state.floor_id_at(spot) in ids)
			_natural_layer(mesh, TOWN_FLOORS[i][1], cover, biome, row, layers)
		if battle.state.gardens.has(cell): # canteiro redondo no pé da árvore
			_natural_layer(mesh, BiomeArt.soil(biome), _path_cover([], 1.0, GARDEN_EDGE), biome, row, layers)
		return
	var links: Array = battle.state.gen.path_links(cell)
	if links.is_empty():
		return
	if battle.state.terrain_id_at(cell) == WorldGen.BRIDGE:
		for dir in links:
			_add_tile(BiomeArt.COMMON % ("ponte_%d" % dir), battle.cell_origin(cell), row, layers * battle.SIDE_HEIGHT)
		_add_tile(BiomeArt.COMMON % "ponte", battle.cell_origin(cell), row, layers * battle.SIDE_HEIGHT)
		return
	_natural_layer(mesh, BiomeArt.solo(biome, "trilha"), _path_cover(links, TRAIL_STRENGTH, 0.0), biome, row, layers)
	var roads: Array = battle.state.gen.road_links(cell)
	if not roads.is_empty():
		_natural_layer(mesh, BiomeArt.solo(biome, "estrada"), _path_cover(roads, 1.0, ROAD_CORNER), biome, row, layers)


func _full_cover() -> PackedFloat32Array:
	var cover := PackedFloat32Array()
	cover.resize(13)
	cover.fill(1.0)
	return cover


## Cobertura nos 13 pontos: a média das casas que se encontram em cada ponto.
func _cover(around: Array, cell: Vector2i, member: Callable) -> PackedFloat32Array:
	var cover := PackedFloat32Array()
	cover.resize(13)
	var own := 1.0 if member.call(cell) else 0.0
	var sides := []
	for dir in 6:
		sides.append(1.0 if member.call(around[dir]) else 0.0)
	cover[0] = own
	for i in 6:
		# O canto i fica entre os lados i e i - 1; o meio i fica só no lado i.
		cover[1 + i] = (own + sides[i] + sides[(i + 5) % 6]) / 3.0
		cover[7 + i] = (own + sides[i]) / 2.0
	return cover


## Caminho: sai do centro para os meios dos lados por onde continua.
func _path_cover(links: Array, strength: float, corner: float) -> PackedFloat32Array:
	var cover := PackedFloat32Array()
	cover.resize(13)
	cover.fill(corner)
	cover[0] = strength
	for dir in links:
		cover[7 + dir] = strength
	return cover


func _natural_layer(mesh: Dictionary, path: String, cover: PackedFloat32Array, biome: String, row: int, layers: int) -> void:
	var seen := false
	for value in cover:
		if value > 0.2:
			seen = true
			break
	if not seen:
		return
	var tint: Color = battle.cell_tint if battle.world_light != null else Color.WHITE
	tint = BiomeArt.NIGHT_TINT.get(biome, tint) if battle.world_light != null else tint
	var colors := PackedColorArray()
	colors.resize(13)
	for i in 13:
		colors[i] = Color(tint, cover[i])
	var height := layers * battle.SIDE_HEIGHT
	var tile := Polygon2D.new()
	tile.texture = load(path)
	tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.polygon = mesh["vertices"]
	tile.uv = mesh["vertices"]
	tile.polygons = mesh["faces"]
	tile.vertex_colors = colors
	tile.material = battle.battle_camera.soil_material(height * battle.BOARD_SCALE)
	tile.position = Vector2(0, -height)
	tile.z_index = battle._z(row)
	battle.board.add_child(tile)
	battle.battle_camera.keep_drawn(tile)
	battle.building.append(tile)


## Parede de um lado do hexágono, com o mesmo truque da faixa da frente dos tiles: a base fica
## mais abaixo na malha e o shader a converte em altura, de volta à mesma borda do chão.
func _wall_mesh(dir: int) -> Dictionary:
	if battle.wall_meshes.has(dir):
		return battle.wall_meshes[dir]
	var a: Vector2 = HEX_CORNERS[dir]
	var b: Vector2 = HEX_CORNERS[(dir + 1) % 6]
	# Nos lados verticais, 1 pixel para fora: o Godot não desenha malha sem área.
	var drop := Vector2(signf(a.x - battle.HEX_MIDDLE.x) if a.x == b.x else 0.0, TILE_WALL)
	# A arte da parede é a faixa inclinada da frente do tile.
	var ua := Vector2(0, TILE_FRONT - TILE_SLOPE)
	var ub := Vector2(battle.TILE_WIDTH / 2.0, TILE_FRONT)
	battle.wall_meshes[dir] = {
		"vertices": PackedVector2Array([a, b, b + drop, a + drop]),
		"uv": PackedVector2Array([ua, ub, ub + Vector2(0, TILE_WALL), ua + Vector2(0, TILE_WALL)]),
		"faces": [PackedInt32Array([0, 1, 2, 3])] as Array[PackedInt32Array],
	}
	return battle.wall_meshes[dir]


func _hidden_layers(cell: Vector2i, layers: int) -> int:
	var hidden := layers
	for dir in [1, 2]: # as duas vizinhas de baixo, as únicas na frente da parede
		var front: Vector2i = Hex.neighbor(cell, dir)
		hidden = mini(hidden, battle.state.elevation_at(front) * battle.level_layers if battle.state.exists(front) else 0)
	return hidden


func _rebase_depth(row: int) -> void:
	if absi(row - battle.z_origin) < Z_REBASE_ROWS:
		return
	var shift := (row - battle.z_origin) * 10
	battle.z_origin = row
	for child in battle.board.get_children():
		if battle.wall_groups.has(child):
			for strip in child.get_children():
				strip.z_index = clampi(strip.z_index - shift, -RenderingServer.CANVAS_ITEM_Z_MAX, RenderingServer.CANVAS_ITEM_Z_MAX)
		elif child.z_index < 800: # marcadores e efeitos ficam sempre por cima
			child.z_index = clampi(child.z_index - shift, -RenderingServer.CANVAS_ITEM_Z_MAX, RenderingServer.CANVAS_ITEM_Z_MAX)


## Desenha as casas que cabem na tela em volta de `center` e descarrega as distantes. Durante a
## caminhada isso é dividido entre vários quadros (`all_now` falso), para o movimento não engasgar.
func _sync_world(center: Vector2i, all_now := true) -> void:
	var wanted := {}
	var reach := VIEW_ROWS_BACK + 8
	var middle := _flat_point(center)
	for row in range(center.y - reach, center.y + reach + 1):
		for col in range(center.x - reach - 6, center.x + reach + 7):
			var cell := Vector2i(col, row)
			var spot := (_flat_point(cell) - middle).rotated(battle.view_angle)
			var gap := roundi(spot.y / battle.ROW_STEP)
			if gap >= -VIEW_ROWS_BACK and gap <= VIEW_ROWS_FRONT and absf(spot.x) / battle.TILE_WIDTH <= _visible_columns(gap):
				wanted[cell] = true
	battle.cells_to_build = wanted.keys().filter(func(cell): return not battle.cell_nodes.has(cell))
	battle.cells_to_build.sort_custom(func(a, b): return Hex.distance(a, center) > Hex.distance(b, center)) # o fim sai primeiro
	battle.cells_to_unload = []
	for cell in battle.cell_nodes:
		var spot := (_flat_point(cell) - middle).rotated(battle.view_angle)
		var gap := roundi(spot.y / battle.ROW_STEP)
		if gap < -VIEW_ROWS_BACK - UNLOAD_MARGIN or gap > VIEW_ROWS_FRONT + UNLOAD_MARGIN or absf(spot.x) / battle.TILE_WIDTH > _visible_columns(gap) + UNLOAD_MARGIN:
			battle.cells_to_unload.append(cell)
	if all_now:
		_work_on_map(-1)


func _flat_point(cell: Vector2i) -> Vector2:
	return Vector2(battle._column_x(cell), cell.y * battle.ROW_STEP)


## Constrói e descarrega casas até o tempo acabar; `budget` negativo termina tudo.
func _work_on_map(budget: int) -> void:
	var begin := Time.get_ticks_usec()
	while not battle.cells_to_build.is_empty() or not battle.cells_to_unload.is_empty():
		if not battle.cells_to_build.is_empty():
			var cell: Vector2i = battle.cells_to_build.pop_back() # as mais próximas primeiro
			if not battle.cell_nodes.has(cell):
				_build_cell(cell)
		elif battle.cell_nodes.has(battle.cells_to_unload[-1]):
			_unload_cell(battle.cells_to_unload.pop_back())
		else:
			battle.cells_to_unload.pop_back()
		if budget >= 0 and Time.get_ticks_usec() - begin > budget:
			return


## Quantas colunas para cada lado cabem na tela nessa linha: mais ao fundo, mais colunas.
func _visible_columns(row_gap: int) -> int:
	var depth := 1.0 / maxf(0.25, 1.0 - row_gap * battle.ROW_STEP * battle.BOARD_SCALE * BattleCamera.PERSPECTIVE)
	var on_screen: float = 760.0 / (depth * minf(battle.battle_camera.zoom, battle._base_zoom())) / (battle.TILE_WIDTH * battle.BOARD_SCALE)
	var row_distance := row_gap * battle.ROW_STEP * battle.BOARD_SCALE
	var in_fog := sqrt(maxf(0.0, battle.FOG_END * battle.FOG_END - row_distance * row_distance)) / FOG_SIDE_SQUEEZE / (battle.TILE_WIDTH * battle.BOARD_SCALE)
	return ceili(minf(on_screen, in_fog)) + 1


func _unload_cell(cell: Vector2i) -> void:
	if not battle.cell_nodes.has(cell):
		return
	for node in battle.cell_nodes[cell]:
		node.queue_free()
	battle.cell_nodes.erase(cell)
	battle.cell_rows.erase(cell)
	if battle.world_light != null:
		battle.world_light.forget_cell(cell)
	battle.overlays.erase(cell)
	battle.reach_lines.erase(cell)
	battle.move_tiles.erase(cell)
	battle.move_shown.erase(cell)
	battle.forests.erase(cell)
	battle.trees.erase(cell)
	area_marks.erase(cell)


## A área da próxima lanterna, enquanto ela não foi achada: {cell, radius} ou {}.
func _lantern_area() -> Dictionary:
	if not battle.expedition or battle.state.winner() >= 0:
		return {}
	var lantern: Variant = battle.state.next_lantern()
	if lantern == null:
		return {}
	var target: Dictionary = battle.state.lantern_target(lantern)
	return target if target["radius"] > 0 else {}


## Uma brasa no chão se a casa fica na borda da área. `nodes`: a lista de nós da casa.
func _add_area_mark(cell: Vector2i, row: int, nodes: Array) -> void:
	var area := _lantern_area()
	if area.is_empty() or Hex.distance(cell, area["cell"]) != area["radius"] or battle.state.terrain_id_at(cell) in [5, 14]:
		return
	var dot := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 12:
		points.append(battle.HEX_MIDDLE + Vector2.from_angle(TAU * i / 12.0) * AREA_DOT_RADIUS)
	dot.polygon = points
	dot.color = AREA_DOT
	var core := Polygon2D.new() # miolo claro: lê como brasa, não como mancha
	var inner := PackedVector2Array()
	for point in points:
		inner.append(battle.HEX_MIDDLE + (point - battle.HEX_MIDDLE) * 0.45)
	core.polygon = inner
	core.color = AREA_DOT_CORE
	core.use_parent_material = true
	dot.add_child(core)
	battle.board.add_child(dot)
	battle._place_ground_marker(dot, cell)
	dot.z_index = battle._z(row) + 2
	nodes.append(dot)
	area_marks[cell] = dot


## Redesenha a borda quando a área muda: lanterna achada ou acesa, ou bússola melhor.
func refresh_lantern_area() -> void:
	var area := _lantern_area()
	var key := str(area)
	if key == area_key:
		return
	area_key = key
	for cell in area_marks:
		var dot: Node = area_marks[cell]
		if battle.cell_nodes.has(cell):
			battle.cell_nodes[cell].erase(dot)
		if is_instance_valid(dot):
			dot.queue_free()
	area_marks.clear()
	if area.is_empty():
		return
	for cell in battle.cell_nodes:
		if Hex.distance(cell, area["cell"]) == area["radius"]:
			_add_area_mark(cell, battle.cell_rows[cell], battle.cell_nodes[cell])


## Marca de um local no chão natural: um círculo, porque não há casas à vista.
func _new_place_ring(color: Color) -> Line2D:
	var ring := _new_hex_line(color, 6)
	var points := PackedVector2Array()
	for i in 24:
		points.append(battle.HEX_MIDDLE + Vector2.from_angle(TAU * i / 24.0) * RING_RADIUS)
	ring.points = points
	return ring


func _new_hex_line(color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.closed = true
	line.points = battle.hex_poly
	line.material = battle.battle_camera.ground_material
	battle.board.add_child(line)
	return line


func _add_tile(path: String, pos: Vector2, row: int, height := 0.0) -> void:
	# Malha subdividida: a perspectiva acompanha a textura até nas bordas dos hexes.
	# Um Sprite2D teria só quatro vértices e abriria frestas entre casas vizinhas.
	var tile := Polygon2D.new()
	var texture: Texture2D = load(path)
	tile.texture = texture
	var mesh: Dictionary = _tile_mesh(texture)
	tile.polygon = mesh["vertices"]
	tile.uv = mesh["vertices"]
	tile.polygons = mesh["faces"]
	tile.material = battle.battle_camera.tile_material(height * battle.BOARD_SCALE, battle.BOARD_SCALE)
	tile.position = pos
	tile.z_index = battle._z(row)
	tile.modulate = battle.cell_tint
	battle.board.add_child(tile)
	battle.battle_camera.keep_drawn(tile)
	battle.building.append(tile)


func _tile_mesh(texture: Texture2D) -> Dictionary:
	var key := [texture.get_size(), battle.exploring]
	if battle.tile_meshes.has(key):
		return battle.tile_meshes[key]
	# As fileiras seguem as bordas do hexágono. Com a dobra entre o topo e a parede bem
	# em cima de um vértice, o shader não entorta a borda nem abre frestas nas junções.
	var vertices := PackedVector2Array()
	var faces: Array[PackedInt32Array] = []
	const COLUMNS := 6
	const TOP_ROWS := 8
	var rows := TOP_ROWS if battle.exploring else TOP_ROWS + 1 # a jornada desenha as paredes à parte
	var width: float = texture.get_width()
	var slope := TILE_SLOPE / (battle.TILE_WIDTH / 2.0)
	for x in COLUMNS + 1:
		var px := x * width / float(COLUMNS)
		var off_center := absf(px - battle.TILE_WIDTH / 2.0)
		var back := off_center * slope
		var front := TILE_FRONT - off_center * slope
		for y in TOP_ROWS + 1:
			vertices.append(Vector2(px, lerpf(back, front, y / float(TOP_ROWS))))
		if not battle.exploring:
			vertices.append(Vector2(px, minf(front + TILE_WALL, texture.get_height())))
	for x in COLUMNS:
		for y in rows:
			var i := x * (rows + 1) + y
			faces.append(PackedInt32Array([i, i + rows + 1, i + rows + 2, i + 1]))
	battle.tile_meshes[key] = {"vertices": vertices, "faces": faces}
	return battle.tile_meshes[key]


func _add_biome_props(biome: String, terrain_id: int, cell: Vector2i) -> void:
	var detail: float = battle.state.detail_at(cell)
	var made := {}
	var art: Array
	if battle.town:
		art = battle.state.art_at(cell)
	elif battle.expedition and battle.state.fort.cells.has(cell):
		art = battle.state.fort.art_at(cell, battle.state.landmarks[battle.state.fort.center]["state"] == "done")
	elif battle.expedition and battle.state.camps.cells.has(cell):
		art = battle.state.camps.art_at(cell)
	elif battle.expedition and cell == battle.state.beacon_cell:
		art = [BiomeArt.beacon(biome, battle.state.defeated_boss)]
	else:
		art = BiomeArt.props(biome, terrain_id, detail)
		if battle.expedition and battle.state.landmarks.has(cell):
			var entry: Dictionary = battle.state.landmarks[cell]
			var special: Array = BiomeArt.landmark(biome, entry["kind"], entry["state"] == "done", detail)
			art = art if special.is_empty() else special
	for prop in art:
		made[prop["layer"]] = _biome_prop(prop, cell, detail)
		if prop["layer"] == "tree":
			battle.trees[cell] = made["tree"]
		if battle.world_light != null:
			battle.world_light.add_prop(cell, made[prop["layer"]], BiomeArt.prop_tint(biome, prop["path"]))
			var light := BiomeArt.light_of(biome, prop["path"])
			if light != "":
				battle.world_light.add_spot(cell, light)
	if made.has("back") and made.has("front"):
		battle.forests[cell] = made


## Construção de todos os lados: uma folha com um quadro por ângulo, trocado conforme o giro.
func _model_prop(prop: Dictionary, cell: Vector2i) -> Sprite2D:
	if battle.model_meta.is_empty():
		battle.model_meta = JSON.parse_string(FileAccess.get_file_as_string(MODEL_META))
	var info: Dictionary = battle.model_meta[prop["model"]]
	var sprite := Sprite2D.new()
	sprite.texture = load(prop["path"])
	sprite.centered = false
	sprite.hframes = int(info["columns"])
	sprite.vframes = int(info["views"]) / int(info["columns"])
	sprite.scale = Vector2.ONE * MODEL_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var foot := Vector2(info["foot_x"], info["foot_y"]) * MODEL_SCALE
	sprite.position = battle.cell_origin(cell) + Vector2(93, prop["ground_y"]) - foot
	sprite.z_index = battle._z(battle._row(cell)) + prop["depth"]
	battle.board.add_child(sprite)
	battle.building.append(sprite)
	battle.battle_camera.add_billboard(sprite, foot, battle._cell_elevation(cell))
	sprite.self_modulate = MODEL_NIGHT_LIFT
	battle.models[sprite] = {"views": int(info["views"]), "turn": float(prop.get("turn", 0.0))}
	_set_model_frame(sprite)
	_mark_if_tall(sprite, foot)
	return sprite


func _set_model_frame(sprite: Sprite2D) -> void:
	var views_count: int = battle.models[sprite]["views"]
	sprite.frame = posmod(roundi((battle.view_angle + battle.models[sprite]["turn"]) / TAU * views_count), views_count)


func _update_model_frames() -> void:
	for sprite in battle.models.keys():
		if is_instance_valid(sprite):
			_set_model_frame(sprite)
		else:
			battle.models.erase(sprite)


func _biome_prop(prop: Dictionary, cell: Vector2i, detail: float) -> Sprite2D:
	if prop.has("model"):
		return _model_prop(prop, cell)
	var sprite := Sprite2D.new()
	sprite.texture = load(prop["path"])
	sprite.centered = false
	# O ponto de apoio de cada arte é o centro da imagem.
	sprite.scale = Vector2.ONE * float(prop.get("scale", 1.0)) * BiomeArt.building_scale(prop["path"])
	var foot: Vector2 = sprite.texture.get_size() * sprite.scale / 2.0
	sprite.position = battle.cell_origin(cell) + Vector2(93 + prop.get("offset_x", 0), prop["ground_y"]) - foot
	if battle.natural and not battle.town and not _is_marked_place(cell) and not prop.get("fixed", false):
		sprite.position += Vector2(fmod(detail * 53.0, 1.0) - 0.5, fmod(detail * 71.0, 1.0) - 0.5) * PROP_WOBBLE * (1.0 if prop["layer"] != "front" else 0.6)
	sprite.flip_h = prop.get("flip", false) or (not prop.get("fixed", false) and fmod(detail * 13.0, 1.0) < 0.5)
	sprite.z_index = battle._z(battle._row(cell)) + prop["depth"]
	battle.board.add_child(sprite)
	battle.building.append(sprite)
	battle.battle_camera.add_billboard(sprite, foot, battle._cell_elevation(cell))
	_mark_if_tall(sprite, foot)
	return sprite


func _mark_if_tall(sprite: Sprite2D, foot: Vector2) -> void:
	if _art_rect(sprite).size.y * sprite.scale.y >= TALL_PROP_HEIGHT:
		battle.tall_props[sprite] = foot


## Parte desenhada da arte, sem a margem transparente (as imagens soltas têm muita sobra
## em volta, porque o pé fica no centro). Folhas de vários quadros usam o quadro inteiro.
func _art_rect(sprite: Sprite2D) -> Rect2:
	var frame := sprite.get_rect()
	if sprite.hframes > 1 or sprite.vframes > 1:
		return frame
	var path := sprite.texture.resource_path
	if not used_art.has(path):
		var image := sprite.texture.get_image()
		if image == null:
			used_art[path] = Rect2(Vector2.ZERO, frame.size)
		else:
			if image.is_compressed():
				image.decompress()
			used_art[path] = Rect2(image.get_used_rect())
	var used: Rect2 = used_art[path]
	if sprite.flip_h:
		used.position.x = frame.size.x - used.end.x
	return Rect2(frame.position + used.position, used.size)


## Cada quadro: construção grande que cobre um personagem atrás dela fica meio transparente.
## A conta é feita na tela, já com giro, perspectiva e zoom, então vale para qualquer ângulo.
func _fade_tall_props(delta: float) -> void:
	if battle.tall_props.is_empty():
		return
	var cam = battle.battle_camera
	var to_global: Transform2D = battle.board.global_transform
	var bodies := []
	for unit in battle.views:
		var view = battle.views[unit]
		if not is_instance_valid(view) or not view.visible or not unit.alive():
			continue
		var feet: Vector2 = to_global * view.position
		var height: float = cam.elevation_of(view)
		var size: Vector2 = UNIT_BOX * to_global.get_scale() * cam.depth_at(feet, height)
		var spot: Vector2 = cam.project(feet, height)
		bodies.append({"z": view.z_index, "rect": Rect2(spot - Vector2(size.x / 2.0, size.y), size)})
	var blend := 1.0 - exp(-delta * TALL_FADE_SPEED)
	for sprite in battle.tall_props.keys():
		if not is_instance_valid(sprite):
			battle.tall_props.erase(sprite)
			continue
		var goal := 1.0
		if not bodies.is_empty():
			var area := _screen_rect(sprite, battle.tall_props[sprite], to_global)
			for body in bodies:
				if body["z"] < sprite.z_index and area.intersects(body["rect"]):
					goal = TALL_SEE_THROUGH
					break
		sprite.modulate.a = lerpf(sprite.modulate.a, goal, blend)


## Retângulo da arte na tela: o pé vai para onde a câmera projeta e o resto escala com a profundidade.
func _screen_rect(sprite: Sprite2D, foot: Vector2, to_global: Transform2D) -> Rect2:
	var cam = battle.battle_camera
	var anchor: Vector2 = to_global * (sprite.position + foot)
	var height: float = cam.elevation_of(sprite)
	var depth: float = cam.depth_at(anchor, height)
	var drawn: Rect2 = sprite.get_global_transform() * _art_rect(sprite)
	var area := Rect2(cam.project(anchor, height) + (drawn.position - anchor) * depth, drawn.size * depth)
	return area.grow_individual(-area.size.x * TALL_INSET, -area.size.y * TALL_INSET, -area.size.x * TALL_INSET, 0.0)


## Farol e locais especiais ficam no centro da casa: é onde o jogador espera clicar.
func _is_marked_place(cell: Vector2i) -> bool:
	return battle.expedition and (cell == battle.state.beacon_cell or battle.state.landmarks.has(cell))


func _add_scenery(id: int, cell: Vector2i) -> void:
	# Batalha fixa e expedição usam os mesmos sprites, separados do piso hexagonal.
	var made := {}
	for prop in BiomeArt.props("floresta", id, 0.5):
		made[prop["layer"]] = _biome_prop(prop, cell, 0.5)
	if made.has("back") and made.has("front"):
		battle.forests[cell] = made


func _scenery_layer(id: int, cell: Vector2i, depth: int, height := 1.0, slice := 0) -> Sprite2D:
	var prop := Sprite2D.new()
	prop.texture = load("res://assets/tiles/%d.png" % id)
	prop.centered = false
	prop.scale.y = height
	prop.position = battle.cell_origin(cell) + Vector2(0, 160 * (1.0 - height))
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.z_index = battle._z(battle._row(cell)) + depth
	battle.board.add_child(prop)
	battle.building.append(prop)
	battle.battle_camera.add_billboard(prop, Vector2(93, 160 * height), battle._cell_elevation(cell))
	prop.material.set_shader_parameter("scenery", true)
	prop.material.set_shader_parameter("scenery_base", load("res://assets/tiles/%d.png" % SCENERY_BASE[id]))
	prop.material.set_shader_parameter("scenery_slice", slice)
	return prop


func _add_unit_view(unit) -> void:
	var view := UnitView.new()
	battle.board.add_child(view)
	view.setup(unit, Hud.PLAYER_COLOR if unit.team == Data.Team.PLAYER else Hud.ENEMY_COLOR, battle.meta[unit.type_id])
	view.position = battle.feet_of(unit.pos)
	view.z_index = battle._z(battle._row(unit.pos)) + 5
	battle.views[unit] = view
	if battle.expedition and battle.state.is_boss(unit):
		view.scale *= BOSS_SCALE
		view.self_modulate = Color(0.75, 0.6, 1.0)
	if battle.expedition and Exp.is_elite(unit):
		view.scale *= ELITE_SCALE
		view.set_elite(Exp.ELITE_AURA)
	battle.battle_camera.add_billboard(view, Vector2.ZERO, battle._cell_elevation(unit.pos))


func _show_facing_walls() -> void:
	for dir in battle.wall_groups.size():
		var outward: Vector2 = HEX_CORNERS[dir] + HEX_CORNERS[(dir + 1) % 6] - battle.HEX_MIDDLE * 2.0
		# Folga: com a perspectiva, paredes quase de lado ainda aparecem nas pontas da tela.
		battle.wall_groups[dir].visible = outward.rotated(battle.view_angle).y > -outward.length() * WALL_SIDE_MARGIN


## Com o giro, a ordem de desenho muda: quem está mais perto da tela vai por cima.
func _refresh_depths() -> void:
	for cell in battle.cell_nodes:
		var row := battle._row(cell)
		var shift: int = (row - battle.cell_rows[cell]) * 10
		if shift != 0:
			battle.cell_rows[cell] = row
			for node in battle.cell_nodes[cell]:
				node.z_index += shift
	for unit in battle.views:
		if not battle.walks.has(unit):
			battle.views[unit].z_index = battle._z(battle._row(unit.pos)) + 5
	if battle.state.winner() < 0 and battle.active_outline != null:
		battle.active_outline.z_index = battle._z(battle._row(battle.state.active_unit().pos)) + 3
	_rebase_depth(battle._row(battle.camera_cell))


func _rebuild_cell(cell: Vector2i) -> void:
	battle.landmark_nodes.erase(cell)
	if battle.cell_nodes.has(cell):
		_unload_cell(cell)
		_build_cell(cell)


## Marca de um local especial no chão, com o nome em cima. Some quando o local é usado.
func _add_landmark(cell: Vector2i, row: int) -> void:
	if not battle.state.landmarks.has(cell) or battle.state.landmarks[cell]["state"] == "done":
		return
	var is_beacon: bool = cell == battle.state.beacon_cell
	var color: Color = battle.BEACON_COLOR if is_beacon else Exp.LANDMARKS[battle.state.landmarks[cell]["kind"]]["color"]
	var ring := _new_place_ring(color) if battle.natural else _new_hex_line(color, 9)
	battle._place_ground_marker(ring, cell)
	ring.z_index = battle._z(row) + 2
	battle.building.append(ring)
	var name_label := Label.new()
	name_label.text = battle.state.landmark_label(cell)
	var lift := 130 if battle.state.landmarks[cell]["kind"] == "bau" else 210 # o baú é baixo: o nome fica perto dele
	name_label.position = battle.feet_of(cell) + Vector2(-110, -lift)
	name_label.custom_minimum_size = Vector2(220, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.z_index = battle._z(row) + 7
	name_label.add_theme_font_size_override("font_size", 34)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 8)
	battle.board.add_child(name_label)
	battle.building.append(name_label)
	battle.battle_camera.add_billboard(name_label, Vector2(110, lift), battle._cell_elevation(cell))
	battle.landmark_nodes[cell] = [ring, name_label]
