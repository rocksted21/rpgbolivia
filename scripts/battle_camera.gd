extends Node
## Câmera 2,5D: projeta só a apresentação. As regras continuam na grade original.
## O chão converge ao fundo; sprites e seus marcadores permanecem em pé.

const SHADER = preload("res://scripts/battle_perspective.gdshader")
const SHADER_ADD = preload("res://scripts/battle_perspective_add.gdshader")
const SEA_NOISE = preload("res://assets/town/chao/mar_ruido.png") # ondas suaves do mar da cidade
const FOCUS := Vector2(660, 450)
const SCREEN_FOCUS := Vector2(660, 470)
const GROUND_TILT := 0.80 # mais alto = câmera mais de cima
const PERSPECTIVE := 0.001
const NO_CULL_RECT := Rect2(-100000, -100000, 200000, 200000)

var billboards: Array[Dictionary] = []
var ground_material: ShaderMaterial
var surface_materials := {}
var tile_materials := {}
var ground_materials := {}
var ground_noise: Texture2D
var soil_edge := 0.8
var fog_range := Vector2.ZERO # início e fim da névoa; zero desliga
var lights := PackedVector4Array() # luz no chão; casas novas também recebem
var view_angle := 0.0 # giro da câmera, em radianos, em volta do centro da tela
var zoom := 1.0 # menor que 1 afasta a câmera; só muda o desenho


func _init() -> void:
	ground_material = _material(false)
	# Atualiza depois das animações de posição e antes do desenho.
	process_priority = 100


func _ready() -> void:
	# Tweens avançam após _process. Atualiza novamente antes de renderizar,
	# para o ponto de apoio não ficar um frame atrás durante passos e saltos.
	RenderingServer.frame_pre_draw.connect(_sync_billboards)


## Gira um ponto do chão em volta do centro da câmera.
func turned(world: Vector2) -> Vector2:
	return FOCUS + (world - FOCUS).rotated(view_angle)


func set_view_angle(angle: float) -> void:
	view_angle = angle
	ground_material.set_shader_parameter("view_angle", angle)
	for mat in surface_materials.values():
		mat.set_shader_parameter("view_angle", angle)
	for mat in tile_materials.values():
		mat.set_shader_parameter("view_angle", angle)
	for mat in ground_materials.values():
		mat.set_shader_parameter("view_angle", angle)
	for entry in billboards:
		entry.material.set_shader_parameter("view_angle", angle)


## Aproxima ou afasta a câmera; vale também para o que já está desenhado.
func set_zoom(value: float) -> void:
	zoom = value
	ground_material.set_shader_parameter("zoom", value)
	for group in [surface_materials, tile_materials, ground_materials]:
		for mat in group.values():
			mat.set_shader_parameter("zoom", value)
	for entry in billboards:
		entry.material.set_shader_parameter("zoom", value)


## Escala de um ponto em pé sobre esse lugar do chão, já com o giro e o afastamento.
func depth_at(anchor: Vector2, elevation: float) -> float:
	return depth_scale(turned(anchor + Vector2(0, elevation)).y) * zoom


func depth_scale(world_y: float) -> float:
	return 1.0 / maxf(0.25, 1.0 - (world_y - FOCUS.y) * PERSPECTIVE)


func project(world: Vector2, elevation := 0.0) -> Vector2:
	# Recupera a profundidade no chão antes de aplicar a altura vertical.
	# Altura não é distância: subir um penhasco não pode diminuir o personagem.
	var ground := turned(world + Vector2(0, elevation))
	var depth := depth_scale(ground.y)
	return SCREEN_FOCUS + Vector2(ground.x - FOCUS.x, (ground.y - FOCUS.y) * GROUND_TILT - elevation) * depth * zoom


func surface_material(elevation: float) -> ShaderMaterial:
	if not surface_materials.has(elevation):
		var mat := _material(false)
		mat.set_shader_parameter("elevation", elevation)
		surface_materials[elevation] = mat
	return surface_materials[elevation]


## Tiles na mesma altura dividem o material, o que deixa mapas grandes bem mais leves.
func tile_material(elevation: float, tile_scale: float) -> ShaderMaterial:
	if not tile_materials.has(elevation):
		var mat := _material(false)
		mat.set_shader_parameter("elevation", elevation)
		mat.set_shader_parameter("tile_surface", true)
		mat.set_shader_parameter("tile_scale", tile_scale)
		mat.set_shader_parameter("lights", lights)
		tile_materials[elevation] = mat
	return tile_materials[elevation]


## Chão contínuo (ver _add_natural_ground em scripts/battle/board_art.gd): um material por altura.
func soil_material(elevation: float) -> ShaderMaterial:
	if not ground_materials.has(elevation):
		var mat := _material(false)
		mat.set_shader_parameter("elevation", elevation)
		mat.set_shader_parameter("ground_surface", true)
		mat.set_shader_parameter("ground_noise", ground_noise)
		mat.set_shader_parameter("ground_edge", soil_edge)
		mat.set_shader_parameter("lights", lights)
		ground_materials[elevation] = mat
	return ground_materials[elevation]


## O Godot descarta o que está fora da tela antes do shader mover o desenho. Com o mapa
## grande, as fileiras do fundo sumiriam mesmo projetadas para dentro da tela.
func keep_drawn(item: CanvasItem) -> void:
	if fog_range != Vector2.ZERO:
		RenderingServer.canvas_item_set_custom_rect(item.get_canvas_item(), true, NO_CULL_RECT)


func _keep_drawn_tree(item: Node) -> void:
	if item is CanvasItem:
		keep_drawn(item)
	for child in item.get_children():
		_keep_drawn_tree(child)


## Luz no chão das casas. Cada ponto: Vector4(x, y, raio, força), com x e y já girados.
func set_lights(points: PackedVector4Array) -> void:
	lights = points
	for mat in tile_materials.values():
		mat.set_shader_parameter("lights", points)
	for mat in ground_materials.values():
		mat.set_shader_parameter("lights", points)


func set_fog(from: float, to: float) -> void:
	fog_range = Vector2(from, to)
	_apply_fog(ground_material)


func _apply_fog(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("fog_start", fog_range.x)
	mat.set_shader_parameter("fog_end", fog_range.y)


func _material(upright: bool, additive := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER_ADD if additive else SHADER
	result.set_shader_parameter("focus", FOCUS)
	result.set_shader_parameter("screen_focus", SCREEN_FOCUS)
	result.set_shader_parameter("ground_tilt", GROUND_TILT)
	result.set_shader_parameter("perspective", PERSPECTIVE)
	result.set_shader_parameter("zoom", zoom)
	result.set_shader_parameter("upright", upright)
	_apply_fog(result)
	result.set_shader_parameter("view_angle", view_angle)
	return result


## Mar (cidade): mesmo material do chão, com a água desenhada pelo shader.
func sea_material(elevation: float) -> ShaderMaterial:
	var key := "mar %s" % elevation
	if not ground_materials.has(key):
		var mat := _material(false)
		mat.set_shader_parameter("elevation", elevation)
		mat.set_shader_parameter("sea", true)
		mat.set_shader_parameter("sea_noise", SEA_NOISE)
		mat.set_shader_parameter("lights", lights)
		ground_materials[key] = mat
	return ground_materials[key]


## Offset em coordenadas do pai, para efeitos cujo centro está acima do chão.
## additive soma a luz em vez de cobrir: brilhos, faíscas e clarões.
func add_billboard(item: CanvasItem, ground_offset := Vector2.ZERO, elevation := 0.0, additive := false) -> void:
	var mat := _material(true, additive)
	_apply_material(item, mat)
	_keep_drawn_tree(item)
	var entry := {"item": weakref(item), "material": mat, "offset": ground_offset}
	billboards.append(entry)
	item.set_meta("camera_elevation", elevation)
	_update_anchor(entry)


func set_elevation(value: float, item: CanvasItem) -> void:
	item.set_meta("camera_elevation", value)


func elevation_of(item: CanvasItem) -> float:
	return float(item.get_meta("camera_elevation", 0.0))


func _apply_material(item: Node, mat: ShaderMaterial) -> void:
	if item is CanvasItem:
		item.material = mat
	# O shader move o desenho, mas não as caixas de input dos Controls.
	# Toda seleção no tabuleiro passa pelo cálculo da câmera.
	if item is Control:
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in item.get_children():
		_apply_material(child, mat)


func _update_anchor(entry: Dictionary) -> bool:
	var item = entry.item.get_ref()
	if item == null:
		return false
	var anchor: Vector2 = item.get_parent().get_global_transform() * (item.position + entry.offset)
	var height := elevation_of(item)
	# Só avisa o shader se mudou: há muitas árvores paradas no mapa.
	if anchor != entry.get("anchor") or height != entry.get("height"):
		entry.anchor = anchor
		entry.height = height
		entry.material.set_shader_parameter("ground_anchor", anchor)
		entry.material.set_shader_parameter("elevation", height)
	return true


func _process(_delta: float) -> void:
	_sync_billboards()


func _sync_billboards() -> void:
	for i in range(billboards.size() - 1, -1, -1):
		if not _update_anchor(billboards[i]):
			billboards.remove_at(i)
