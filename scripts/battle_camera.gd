extends Node
## Câmera 2,5D: projeta só a apresentação. As regras continuam na grade original.
## O chão converge ao fundo; sprites e seus marcadores permanecem em pé.

const SHADER = preload("res://scripts/battle_perspective.gdshader")
const FOCUS := Vector2(660, 450)
const SCREEN_FOCUS := Vector2(660, 470)
const GROUND_TILT := 0.60
const PERSPECTIVE := 0.001

var billboards: Array[Dictionary] = []
var ground_material: ShaderMaterial
var surface_materials := {}


func _init() -> void:
	ground_material = _material(false)
	# Atualiza depois das animações de posição e antes do desenho.
	process_priority = 100


func _ready() -> void:
	# Tweens avançam após _process. Atualiza novamente antes de renderizar,
	# para o ponto de apoio não ficar um frame atrás durante passos e saltos.
	RenderingServer.frame_pre_draw.connect(_sync_billboards)


func depth_scale(world_y: float) -> float:
	return 1.0 / maxf(0.25, 1.0 - (world_y - FOCUS.y) * PERSPECTIVE)


func project(world: Vector2, elevation := 0.0) -> Vector2:
	# Recupera a profundidade no chão antes de aplicar a altura vertical.
	# Altura não é distância: subir um penhasco não pode diminuir o personagem.
	var ground := world + Vector2(0, elevation)
	var depth := depth_scale(ground.y)
	return SCREEN_FOCUS + Vector2(ground.x - FOCUS.x, (ground.y - FOCUS.y) * GROUND_TILT - elevation) * depth


func surface_material(elevation: float) -> ShaderMaterial:
	if not surface_materials.has(elevation):
		var mat := _material(false)
		mat.set_shader_parameter("elevation", elevation)
		surface_materials[elevation] = mat
	return surface_materials[elevation]


func _material(upright: bool) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.set_shader_parameter("focus", FOCUS)
	result.set_shader_parameter("screen_focus", SCREEN_FOCUS)
	result.set_shader_parameter("ground_tilt", GROUND_TILT)
	result.set_shader_parameter("perspective", PERSPECTIVE)
	result.set_shader_parameter("upright", upright)
	return result


## Offset em coordenadas do pai, para efeitos cujo centro está acima do chão.
func add_billboard(item: CanvasItem, ground_offset := Vector2.ZERO, elevation := 0.0) -> void:
	var mat := _material(true)
	_apply_material(item, mat)
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
	entry.material.set_shader_parameter("ground_anchor", anchor)
	entry.material.set_shader_parameter("elevation", elevation_of(item))
	return true


func _process(_delta: float) -> void:
	_sync_billboards()


func _sync_billboards() -> void:
	for i in range(billboards.size() - 1, -1, -1):
		if not _update_anchor(billboards[i]):
			billboards.remove_at(i)
