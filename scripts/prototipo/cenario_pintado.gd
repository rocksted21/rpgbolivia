extends Node2D
## Protótipo: a party anda por cima de uma imagem pintada inteira (cenas/prototipo_cenario.tscn).
## Clique: o líder anda até lá; os outros seguem a trilha. Roda do mouse: zoom.
## M: mostra onde dá para pisar. Esc: volta ao menu.
## Recortes da própria imagem ("frente" no areas.json) são desenhados na frente
## dos heróis quando eles passam atrás de cerca, poste, carruagem ou muro.

const ChaoPintado = preload("res://scripts/prototipo/chao_pintado.gd")
const UNIT_META := "res://assets/units/meta.json"
const PARTY := ["guardiao", "mago", "duelista", "druida"]
const HERO_SCALE := 0.42 # folha de ~170 px de altura → ~70 px, a altura de uma porta na imagem
const SPEED := 150.0 # pixels da imagem por segundo
const FOLLOW_GAP := 42.0 # distância entre um herói e o próximo na fila
const FPS := 12.0
const ZOOM_MIN := 0.64 # a imagem inteira cabe em 1280x720
const ZOOM_MAX := 1.8
# Linhas da folha (as mesmas do unit_view.gd)
const ROW_IDLE := 0
const ROW_WALK_SIDE := 1
const ROW_WALK_SOUTH := 4
const ROW_WALK_NORTH := 5

var floor_map: ChaoPintado
var world: Node2D # heróis e recortes, ordenados pela altura dos pés
var heroes: Array[Dictionary] = []
var route := PackedVector2Array()
var trail := PackedVector2Array() # por onde o líder passou, do mais novo ao mais velho
var camera: Camera2D
var mask_layer: Node2D
var marker: Node2D
var marker_time := 0.0


func _ready() -> void:
	floor_map = ChaoPintado.new()
	var background := Sprite2D.new()
	background.texture = load(floor_map.data["imagem"])
	background.centered = false
	add_child(background)

	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	_build_front_pieces(background.texture)
	_build_heroes()

	mask_layer = Node2D.new()
	mask_layer.visible = false
	add_child(mask_layer)
	_build_mask()

	marker = Node2D.new()
	marker.visible = false
	marker.z_index = 50
	add_child(marker)
	var ring := Line2D.new()
	ring.width = 3
	ring.default_color = Color(1.0, 0.85, 0.45, 0.9)
	for i in 25:
		var angle := TAU * i / 24.0
		ring.add_point(Vector2(cos(angle) * 18, sin(angle) * 9))
	marker.add_child(ring)

	_build_fog()

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = floor_map.image_size.x
	camera.limit_bottom = floor_map.image_size.y
	camera.position_smoothing_enabled = true
	camera.zoom = Vector2.ONE
	camera.position = heroes[0]["node"].position
	add_child(camera)

	var help := Label.new()
	help.text = "Clique para andar  ·  Roda: zoom  ·  M: mostrar o chão  ·  Esc: sair"
	help.add_theme_font_size_override("font_size", 18)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 6)
	help.position = Vector2(16, 12)
	var hud := CanvasLayer.new()
	hud.add_child(help)
	add_child(hud)


func _build_heroes() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UNIT_META))
	var start := floor_map.start_spot()
	for i in PARTY.size():
		var info: Dictionary = meta[PARTY[i]]
		var node := Node2D.new()
		node.position = start + Vector2(-FOLLOW_GAP * 0.8, FOLLOW_GAP * 0.4) * i
		var shadow := Polygon2D.new()
		var points := PackedVector2Array()
		for k in 24:
			var angle := TAU * k / 24.0
			points.append(Vector2(cos(angle) * 22, sin(angle) * 6))
		shadow.polygon = points
		shadow.color = Color(0, 0, 0, 0.35)
		node.add_child(shadow)
		var sprite := Sprite2D.new()
		sprite.texture = load("res://assets/units/%s.png" % PARTY[i])
		var rows: Array = info.get("row_frames", [])
		sprite.hframes = int(info["frames"])
		sprite.vframes = rows.size()
		sprite.offset = Vector2(0, float(info["cell_h"]) / 2.0 - float(info["feet_y"]))
		sprite.scale = Vector2.ONE * HERO_SCALE
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		node.add_child(sprite)
		world.add_child(node)
		heroes.append({"node": node, "sprite": sprite, "rows": rows, "frames": int(info["frames"]),
			"row": ROW_IDLE, "frame_pos": randf() * 8.0})
	for hero in heroes: # a fila começa como os heróis nasceram: o líder na frente
		trail.append(hero["node"].position)


## Cada recorte é um pedaço da imagem, desenhado de novo por cima dos heróis
## que estão atrás dele (pés acima da "base").
func _build_front_pieces(texture: Texture2D) -> void:
	var pieces: Dictionary = floor_map.data.get("frente", {})
	var names := pieces.keys()
	names.sort()
	for piece_name in names:
		var piece: Dictionary = pieces[piece_name]
		var base := float(piece["base"])
		var holder := Node2D.new()
		holder.name = piece_name
		holder.position = Vector2(0, base)
		var polygon := Polygon2D.new()
		var points := PackedVector2Array()
		for xy in piece["pontos"]:
			points.append(Vector2(xy[0], xy[1]))
		polygon.polygon = points
		polygon.uv = points
		polygon.texture = texture
		polygon.position = Vector2(0, -base)
		holder.add_child(polygon)
		world.add_child(holder)


func _build_mask() -> void:
	var colors := {"chao": Color(0.2, 1, 0.3, 0.28), "ligacoes": Color(1, 0.6, 0.1, 0.35), "bloqueios": Color(1, 0.1, 0.1, 0.45)}
	for group in colors:
		for polygon in floor_map._polygons(group):
			var shape := Polygon2D.new()
			shape.polygon = polygon
			shape.color = colors[group]
			mask_layer.add_child(shape)


func _build_fog() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.75, 0.78, 0.85, 0.22))
	gradient.set_color(1, Color(0.75, 0.78, 0.85, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	var fog := Node2D.new()
	fog.name = "neblina"
	fog.z_index = 40
	add_child(fog)
	var random := RandomNumberGenerator.new()
	random.seed = 11
	for i in 9:
		var puff := Sprite2D.new()
		puff.texture = texture
		puff.scale = Vector2(random.randf_range(3.0, 5.0), random.randf_range(1.0, 1.6))
		puff.position = Vector2(random.randf_range(0, 2000), random.randf_range(650, 1116))
		puff.set_meta("speed", random.randf_range(6.0, 16.0))
		fog.add_child(puff)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				walk_to(get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(camera.zoom.x * 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(camera.zoom.x / 1.1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			mask_layer.visible = not mask_layer.visible
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _set_zoom(value: float) -> void:
	camera.zoom = Vector2.ONE * clampf(value, ZOOM_MIN, ZOOM_MAX)


## Manda o líder andar até `spot` (pixels da imagem). Devolve false se não há caminho.
func walk_to(spot: Vector2) -> bool:
	var target := spot if floor_map.walkable(spot) else floor_map.nearest_walkable(spot)
	if target.x < 0:
		return false
	var found := floor_map.path(heroes[0]["node"].position, target)
	if found.is_empty():
		return false
	route = found
	marker.position = target
	marker.visible = true
	marker_time = 0.0
	return true


func _process(delta: float) -> void:
	var leader: Node2D = heroes[0]["node"]
	var moved := Vector2.ZERO
	var budget := SPEED * delta
	while budget > 0.0 and not route.is_empty():
		var next := route[0]
		var step := leader.position.distance_to(next)
		if step <= budget:
			moved += next - leader.position
			leader.position = next
			route.remove_at(0)
			budget -= step
		else:
			var move := (next - leader.position).normalized() * budget
			moved += move
			leader.position += move
			budget = 0.0
	if moved.length() > 0.01:
		trail.insert(0, leader.position)
		if trail.size() > 400:
			trail.resize(400)
	_animate(0, moved, delta)
	for i in range(1, heroes.size()):
		var node: Node2D = heroes[i]["node"]
		var target := _trail_point(FOLLOW_GAP * i)
		var shift := target - node.position
		node.position = target
		_animate(i, shift, delta)
	camera.position = leader.position
	if marker.visible:
		marker_time += delta
		marker.modulate.a = 1.0 - marker_time / 0.8
		marker.visible = marker_time < 0.8
	for puff in get_node("neblina").get_children():
		puff.position.x = fposmod(puff.position.x + float(puff.get_meta("speed")) * delta + 600.0, 3200.0) - 600.0


## Ponto da trilha a `distance` pixels atrás do líder.
func _trail_point(distance: float) -> Vector2:
	var walked := 0.0
	for k in range(1, trail.size()):
		var piece := trail[k - 1].distance_to(trail[k])
		if walked + piece >= distance:
			return trail[k - 1].lerp(trail[k], (distance - walked) / piece)
		walked += piece
	return trail[trail.size() - 1]


func _animate(index: int, moved: Vector2, delta: float) -> void:
	var hero: Dictionary = heroes[index]
	var sprite: Sprite2D = hero["sprite"]
	var row := ROW_IDLE
	if moved.length() > 0.01:
		if absf(moved.y) > absf(moved.x):
			row = ROW_WALK_SOUTH if moved.y > 0 else ROW_WALK_NORTH
		else:
			row = ROW_WALK_SIDE
			sprite.flip_h = moved.x > 0 # as folhas olham para a esquerda
	if row != hero["row"]:
		hero["row"] = row
		hero["frame_pos"] = 0.0
	hero["frame_pos"] += delta * FPS
	var count: int = hero["rows"][row] if row < hero["rows"].size() else hero["frames"]
	sprite.frame = row * int(hero["frames"]) + int(hero["frame_pos"]) % maxi(count, 1)
