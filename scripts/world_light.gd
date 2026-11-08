extends Node2D
## A luz das expedições: lanternas da party, farol, prêmios, clarões de magia e partículas.
## O escuro vem do tom de cada bioma (BiomeArt.NIGHT_TINT); aqui só se soma luz por cima.
## Só enfeite: nada aqui muda regra, e cada jogador do Online calcula o seu.

const BiomeArt = preload("res://scripts/biome_art.gd")

const DRAW_LAYER := 850 # acima do mapa, abaixo das magias (900) e da interface
const SCREEN := Rect2(0, 0, 1280, 720)
const SCREEN_MARGIN := 260.0
const GLOW_TEXTURE_SIZE := 256.0
const MAX_LIGHTS := 8 # igual a lights[] no shader
const LANTERN_RADIUS := 375.0
const LANTERN_POWER := 0.62
const BEACON_RADIUS := 700.0
const BEACON_POWER := 1.0
const LIT_LANTERN_RADIUS := 320.0 # lanterna do mapa acesa: uma ilha de luz no escuro
const LIT_LANTERN_POWER := 0.8
const LIT_LANTERN_SLOTS := 2 # só as mais perto da câmera clareiam o chão
const FLASH_RADIUS := 375.0
const FLASH_POWER := 1.4
const PROP_UPDATE_TIME := 0.066 # objetos em pé recebem a luz a cerca de 15 vezes por segundo
const WARM := Color(1.0, 0.86, 0.68)
const FOG_FADE := Vector2(475.0, 875.0) # brilhos somem na névoa, como o resto do mapa
const BIOME_CHECK_TIME := 0.5
const AMBIENT_AMOUNT := 44
# Luz de cada coisa no mapa.
const SPOTS := {
	"farol": {"color": Color(1.0, 0.68, 0.3), "alpha": 0.5, "size": 260.0, "height": 412.0, "embers": true}, # 165 × escala das construções (biome_art.gd)
	"lanterna": {"color": Color(1.0, 0.78, 0.4), "alpha": 0.55, "size": 110.0, "height": 128.0, "embers": true, "ember_count": 5},
	"bau": {"color": Color(1.0, 0.8, 0.4), "alpha": 0.42, "size": 74.0, "height": 22.0},
	"lampiao": {"color": Color(1.0, 0.76, 0.42), "alpha": 0.5, "size": 84.0, "height": 186.0}, # lampião de rua aceso (Subúrbios)
	"cristal": {"color": Color(0.3, 0.97, 0.86), "alpha": 0.2, "size": 62.0, "height": 22.0},
}
const FLASH_FIRE := Color(1.0, 0.56, 0.2)
const FLASH_WATER := Color(0.4, 0.82, 1.0)
const FLASH_BLOOD := Color(1.0, 0.15, 0.18)
const FLASH_ALPHA := 0.8
const FLASH_SIZE := 200.0
const FLASH_TIME := 0.5
const VIGNETTE_ALPHA := 0.62
# Partículas do ar em cada bioma: cor, para onde caem e quanto se espalham.
const AIR := {
	"suburbios": {"color": Color(0.62, 0.6, 0.66, 0.5), "gravity": Vector2(5, 6)}, # cinza fina caindo
	"floresta": {"color": Color(0.78, 0.85, 0.52, 0.55), "gravity": Vector2(3, -5)},
	"selva": {"color": Color(0.3, 0.97, 0.86, 0.75), "gravity": Vector2(0, -7)},
	"neve": {"color": Color(0.8, 0.83, 0.88, 0.65), "gravity": Vector2(-4, 14)},
	"deserto": {"color": Color(0.9, 0.72, 0.42, 0.5), "gravity": Vector2(16, -1)},
}

var view
var camera
var glow_texture: GradientTexture2D
var spots := {} # casa: {kind, glow, embers, phase}
var props := {} # casa: [{sprite, tint}], objetos em pé que a luz clareia
var prop_wait := 0.0
var props_dirty := true
var last_points := PackedVector4Array()
var flashes := []
var air: CPUParticles2D
var air_biome := ""
var biome_wait := 0.0
var time := 0.0


func setup(p_view) -> void:
	view = p_view
	camera = view.battle_camera
	z_index = DRAW_LAYER
	z_as_relative = false
	glow_texture = _make_glow()
	_add_vignette()
	_add_air()


func _process(delta: float) -> void:
	time += delta
	_update_spots()
	_update_flashes(delta)
	# Só avisa o shader se a luz mudou: parada, a party não custa nada.
	var points := _light_points()
	if points != last_points:
		last_points = points
		camera.set_lights(points)
		props_dirty = true
	prop_wait -= delta
	if props_dirty and prop_wait <= 0.0:
		prop_wait = PROP_UPDATE_TIME
		props_dirty = false
		_update_props(points)
	biome_wait -= delta
	if biome_wait <= 0.0:
		biome_wait = BIOME_CHECK_TIME
		_update_air()


## Casa ganhou algo que brilha.
func add_spot(cell: Vector2i, kind: String) -> void:
	_remove_spot(cell)
	var entry := {"kind": kind, "glow": _new_glow(SPOTS[kind]["color"], SPOTS[kind]["alpha"]), "embers": null, "phase": float(cell.x * 3 + cell.y * 7)}
	if SPOTS[kind].get("embers", false):
		entry["embers"] = _new_embers(SPOTS[kind]["color"], SPOTS[kind].get("ember_count", 14))
	spots[cell] = entry


## Objeto em pé que escurece com o bioma e clareia perto da luz.
func add_prop(cell: Vector2i, sprite: Sprite2D, tint: Color) -> void:
	sprite.modulate = Color(tint, sprite.modulate.a)
	if tint != Color.WHITE:
		props.get_or_add(cell, []).append({"sprite": sprite, "tint": tint})
		props_dirty = true


## A casa foi descarregada ou será refeita.
func forget_cell(cell: Vector2i) -> void:
	props.erase(cell)
	_remove_spot(cell)


func _remove_spot(cell: Vector2i) -> void:
	if not spots.has(cell):
		return
	spots[cell]["glow"].queue_free()
	if spots[cell]["embers"] != null:
		spots[cell]["embers"].queue_free()
	spots.erase(cell)


## Clarão de uma magia, em coordenadas do tabuleiro.
## element: a pasta do efeito ("agua/...", "sangue/..."); o resto acende como fogo.
func flash(point: Vector2, element: String, power := 1.0) -> void:
	var color := FLASH_FIRE
	if element.begins_with("agua/"):
		color = FLASH_WATER
	elif element.begins_with("sangue/"):
		color = FLASH_BLOOD
	flashes.append({"point": point, "glow": _new_glow(color, 1.0), "life": FLASH_TIME, "power": power})


## Pontos de luz no chão, já girados: a party, o farol aceso, as lanternas acesas mais perto
## e o último clarão.
func _light_points() -> PackedVector4Array:
	var board: Transform2D = view.board.get_global_transform()
	var points := PackedVector4Array()
	points.resize(MAX_LIGHTS)
	var used := 0
	for unit in view.state.party:
		var unit_view = view.views.get(unit)
		if unit_view != null and unit.alive() and used < MAX_LIGHTS - 2:
			points[used] = _point(board * unit_view.position, camera.elevation_of(unit_view), LANTERN_RADIUS, LANTERN_POWER)
			used += 1
	for cell in spots:
		if spots[cell]["kind"] == "farol":
			points[used] = _point(board * view.feet_of(cell), view._cell_elevation(cell), BEACON_RADIUS, BEACON_POWER)
			used += 1
			break
	var lanterns: Array = spots.keys().filter(func(cell): return spots[cell]["kind"] == "lanterna")
	if not lanterns.is_empty():
		var focus: Vector2i = view.camera_cell
		lanterns.sort_custom(func(a, b): return a.distance_squared_to(focus) < b.distance_squared_to(focus))
		for cell in lanterns.slice(0, LIT_LANTERN_SLOTS):
			if used < MAX_LIGHTS - 1:
				points[used] = _point(board * view.feet_of(cell), view._cell_elevation(cell), LIT_LANTERN_RADIUS, LIT_LANTERN_POWER)
				used += 1
	if not flashes.is_empty():
		var entry: Dictionary = flashes.back()
		var power: float = FLASH_POWER * entry["life"] / FLASH_TIME
		points[used] = _point(board * entry["point"], view._height_at_point(entry["point"]), FLASH_RADIUS * entry["power"], power)
	return points


func _point(anchor: Vector2, height: float, radius: float, power: float) -> Vector4:
	var ground: Vector2 = camera.turned(anchor + Vector2(0, height))
	return Vector4(ground.x, ground.y, radius, power)


func _update_props(points: PackedVector4Array) -> void:
	var board: Transform2D = view.board.get_global_transform()
	for cell in props:
		var anchor: Vector2 = board * view.feet_of(cell)
		var ground: Vector2 = camera.turned(anchor + Vector2(0, view._cell_elevation(cell)))
		var light := 0.0
		for point in points:
			if point.w > 0.0:
				light += point.w * (1.0 - smoothstep(0.0, point.z, ground.distance_to(Vector2(point.x, point.y))))
		var warm: Color = WARM * minf(light, 1.0)
		for entry in props[cell]:
			var tint: Color = entry["tint"]
			var lit := Color(tint.r + (1.0 - tint.r) * warm.r, tint.g + (1.0 - tint.g) * warm.g, tint.b + (1.0 - tint.b) * warm.b)
			entry["sprite"].modulate = Color(lit, entry["sprite"].modulate.a)


func _update_spots() -> void:
	var board: Transform2D = view.board.get_global_transform()
	for cell in spots:
		var entry: Dictionary = spots[cell]
		var kind: Dictionary = SPOTS[entry["kind"]]
		var anchor: Vector2 = board * view.feet_of(cell)
		var height: float = view._cell_elevation(cell)
		var depth: float = camera.depth_at(anchor, height)
		var spot: Vector2 = camera.project(anchor, height) - Vector2(0, kind["height"] * depth)
		var seen := SCREEN.grow(SCREEN_MARGIN).has_point(spot)
		var ground: Vector2 = camera.turned(anchor + Vector2(0, height))
		var clear := 1.0 - smoothstep(FOG_FADE.x, FOG_FADE.y, ((ground - camera.FOCUS) * Vector2(0.6, 1.0)).length())
		entry["glow"].visible = seen and clear > 0.0
		entry["glow"].modulate.a = kind["alpha"] * clear
		if entry["embers"] != null:
			entry["embers"].emitting = seen
			entry["embers"].position = spot
		if seen:
			var flicker := 0.93 + 0.07 * sin(time * 3.0 + entry["phase"])
			_place(entry["glow"], spot, kind["size"] * depth * flicker)


func _update_flashes(delta: float) -> void:
	var board: Transform2D = view.board.get_global_transform()
	for i in range(flashes.size() - 1, -1, -1):
		var entry: Dictionary = flashes[i]
		entry["life"] -= delta
		if entry["life"] <= 0.0:
			entry["glow"].queue_free()
			flashes.remove_at(i)
			continue
		var anchor: Vector2 = board * entry["point"]
		var height: float = view._height_at_point(entry["point"])
		var left: float = entry["life"] / FLASH_TIME
		entry["glow"].modulate.a = FLASH_ALPHA * left
		_place(entry["glow"], camera.project(anchor, height), FLASH_SIZE * entry["power"] * camera.depth_at(anchor, height) * (1.2 - left * 0.2))


func _place(glow: Sprite2D, spot: Vector2, radius: float) -> void:
	glow.position = spot
	glow.scale = Vector2.ONE * radius * 2.0 / GLOW_TEXTURE_SIZE


func _new_glow(color: Color, alpha: float) -> Sprite2D:
	var glow := Sprite2D.new()
	glow.texture = glow_texture
	glow.modulate = Color(color, alpha)
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = additive
	add_child(glow)
	return glow


func _make_glow() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.add_point(0.35, Color(1, 1, 1, 0.42))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(GLOW_TEXTURE_SIZE)
	texture.height = int(GLOW_TEXTURE_SIZE)
	return texture


## Escurece as bordas da tela: a luz fica em volta da party e a névoa fecha o resto.
func _add_vignette() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.04, 0.07, 0.0))
	gradient.add_point(0.5, Color(0.03, 0.04, 0.07, 0.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.03, 0.04, 0.07, VIGNETTE_ALPHA))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	var shade := Sprite2D.new()
	shade.texture = texture
	shade.position = camera.SCREEN_FOCUS
	shade.scale = Vector2(1500, 1000) / 256.0
	shade.show_behind_parent = true
	add_child(shade)


func _add_air() -> void:
	air = CPUParticles2D.new()
	air.amount = AMBIENT_AMOUNT
	air.lifetime = 7.0
	air.preprocess = 7.0
	air.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	air.position = SCREEN.get_center()
	air.emission_rect_extents = SCREEN.size / 2.0
	air.direction = Vector2.UP
	air.spread = 180.0
	air.initial_velocity_min = 2.0
	air.initial_velocity_max = 9.0
	air.scale_amount_min = 1.5
	air.scale_amount_max = 3.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	air.color_ramp = fade
	add_child(air)
	_update_air()


func _update_air() -> void:
	var leader = view.selected if view.selected != null else view.state.party[0]
	var biome: String = view.state.biome_at(leader.pos)
	if biome == air_biome or not AIR.has(biome):
		return
	air_biome = biome
	air.color = AIR[biome]["color"]
	air.gravity = AIR[biome]["gravity"]


func _new_embers(color: Color, amount := 14) -> CPUParticles2D:
	var embers := CPUParticles2D.new()
	embers.amount = amount
	embers.lifetime = 1.6
	embers.direction = Vector2.UP
	embers.spread = 26.0
	embers.gravity = Vector2(0, -14)
	embers.initial_velocity_min = 16.0
	embers.initial_velocity_max = 42.0
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 3.0
	embers.color = color
	embers.local_coords = true # as faíscas andam com o farol quando a câmera se move
	add_child(embers)
	return embers
