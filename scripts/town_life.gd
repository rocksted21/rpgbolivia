extends Node2D
## O que faz a cidade parecer viva: luz de fogo, gente andando e falas soltas.
## Só enfeite: nada aqui bloqueia caminho ou muda regra.

const Hex = preload("res://scripts/hex.gd")
const Town = preload("res://scripts/town_data.gd")
const Content = preload("res://scripts/town_content.gd")
const TownProgress = preload("res://scripts/town_progress.gd")

const DRAW_LAYER := 850 # acima de tudo no mapa e abaixo da interface
const GLOW_SIZE := 150.0
const FLAME_HEIGHT := 34.0
const SCREEN_MARGIN := 240.0
const WALK_TIME := 0.85
const REST_TIME := Vector2(1.0, 4.0)
const BOB := 7.0
const BUBBLE_TIME := 3.2
const BUBBLE_PAUSE := Vector2(2.5, 5.0)
const BUBBLE_RADIUS := 7
const BOARD_FEET := Vector2(93, 160)
const CALL_PAUSE := 4.5 # o guia chama a party de tempos em tempos enquanto tem história nova
const NO_CELL := Vector2i(-9999, -9999)

var view
var state
var camera
var lights := []
var walkers := []
var bubble_wait := 2.0
var call_wait := 1.0
var calling := false
var guide_cell := NO_CELL
var time := 0.0


func setup(p_view) -> void:
	view = p_view
	state = view.state
	camera = view.battle_camera
	z_index = DRAW_LAYER
	z_as_relative = false
	for decor in Town.decor():
		if Town.LIGHT_ART.has(decor["art"]):
			_add_light(decor["cell"], Town.LIGHT_ART[decor["art"]], true, FLAME_HEIGHT, decor.get("offset", 0))
	for building in Town.buildings():
		if building["art"] == "farol":
			_add_light(building["cell"], Town.BEACON_LIGHT, false, Town.BEACON_HEIGHT * building["scale"] * Town.BiomeArt.building_scale(building["path"]))
		elif building["art"] == "forja" and state.is_present(building):
			_add_light(building["cell"], Town.FORGE_LIGHT, true)
	var count: int = mini(Town.WALKER_BASE + TownProgress.rescued().size() + TownProgress.beacons(), Town.WALKER_MAX)
	for i in count:
		_add_walker(i)
	for person in Town.people():
		if person["id"] == Content.GUIDE:
			guide_cell = person["cell"]
	calling = TownProgress.story_pending()


# --- Luz -----------------------------------------------------------------------

func _add_light(cell: Vector2i, power: float, sparks: bool, height := FLAME_HEIGHT, offset := 0) -> void:
	var glow := Sprite2D.new()
	glow.texture = _glow_texture()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = additive
	add_child(glow)
	var embers: CPUParticles2D = null
	if sparks:
		embers = CPUParticles2D.new()
		embers.amount = 10
		embers.lifetime = 1.3
		embers.direction = Vector2.UP
		embers.spread = 22.0
		embers.gravity = Vector2(0, -14)
		embers.initial_velocity_min = 16.0
		embers.initial_velocity_max = 38.0
		embers.scale_amount_min = 1.5
		embers.scale_amount_max = 3.0
		embers.color = Color(1.0, 0.68, 0.28)
		embers.local_coords = true # as faíscas andam com a fogueira quando a câmera se move
		add_child(embers)
	lights.append({"cell": cell, "offset": offset, "power": power, "height": height, "glow": glow, "embers": embers, "phase": cell.x * 1.7 + cell.y})


func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.72, 0.36, 0.6))
	gradient.add_point(0.4, Color(1.0, 0.56, 0.22, 0.2))
	gradient.set_color(gradient.get_point_count() - 1, Color(1.0, 0.45, 0.15, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture


func _update_lights() -> void:
	var board_transform: Transform2D = view.board.get_global_transform()
	for light in lights:
		var anchor: Vector2 = board_transform * (view.feet_of(light["cell"]) + Vector2(light["offset"], 0))
		var spot: Vector2 = camera.project(anchor, view._cell_elevation(light["cell"]))
		var depth: float = camera.depth_at(anchor, view._cell_elevation(light["cell"]))
		spot.y -= light["height"] * depth
		var seen := Rect2(-SCREEN_MARGIN, -SCREEN_MARGIN, 1280 + SCREEN_MARGIN * 2, 720 + SCREEN_MARGIN * 2).has_point(spot)
		var glow: Sprite2D = light["glow"]
		glow.visible = seen
		var embers: CPUParticles2D = light["embers"]
		if embers != null:
			embers.emitting = seen
			embers.position = spot
		if seen:
			var flicker: float = 0.92 + 0.08 * sin(time * 7.0 + light["phase"]) + 0.05 * sin(time * 13.0 + light["phase"] * 2.0)
			glow.position = spot
			glow.scale = Vector2.ONE * light["power"] * depth * flicker * GLOW_SIZE * 2.0 / 256.0


# --- Quem anda pela cidade -----------------------------------------------------

func _add_walker(index: int) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = load(Town.TOWN_ROOT % Town.WALKER_ART[index % Town.WALKER_ART.size()])
	sprite.centered = false
	var foot: Vector2 = sprite.texture.get_size() / 2.0
	var route: Array = Town.walk_route().filter(func(cell): return state.tile_at(cell)["walkable"])
	var cell: Vector2i = route[index * 3 % route.size()]
	view.board.add_child(sprite)
	camera.add_billboard(sprite, foot, view._cell_elevation(cell))
	var walker := {"sprite": sprite, "foot": foot, "cell": cell, "next": cell, "path": [], "route": route, "goal": index * 3, "step": 1.0, "rest": randf_range(REST_TIME.x, REST_TIME.y)}
	walkers.append(walker)
	_place_walker(walker)


func _place_walker(walker: Dictionary) -> void:
	var sprite: Sprite2D = walker["sprite"]
	var from: Vector2 = view.cell_origin(walker["cell"]) + BOARD_FEET
	var to: Vector2 = view.cell_origin(walker["next"]) + BOARD_FEET
	var step: float = walker["step"]
	sprite.position = from.lerp(to, step) - walker["foot"]
	sprite.position.y -= abs(sin(step * PI * 2.0)) * BOB if walker["cell"] != walker["next"] else 0.0
	sprite.z_index = view._z(view._row(walker["next"] if step > 0.5 else walker["cell"])) + 5
	camera.set_elevation(lerpf(view._cell_elevation(walker["cell"]), view._cell_elevation(walker["next"]), step), sprite)
	if to.x != from.x:
		sprite.flip_h = to.x < from.x


func _update_walker(walker: Dictionary, delta: float) -> void:
	if walker["rest"] > 0.0:
		walker["rest"] -= delta
		return
	if walker["step"] >= 1.0:
		walker["cell"] = walker["next"]
		if walker["path"].is_empty():
			walker["goal"] = (walker["goal"] + 1 + randi() % 3) % walker["route"].size()
			walker["path"] = _path(walker["cell"], walker["route"][walker["goal"]])
			walker["rest"] = randf_range(REST_TIME.x, REST_TIME.y)
			return
		walker["next"] = walker["path"].pop_front()
		walker["step"] = 0.0
	walker["step"] = minf(walker["step"] + delta / WALK_TIME, 1.0)
	_place_walker(walker)


## Caminho a pé entre duas casas, sem contar a primeira.
func _path(from: Vector2i, to: Vector2i) -> Array:
	var came := {from: from}
	var frontier := [from]
	while not frontier.is_empty() and not came.has(to):
		var current: Vector2i = frontier.pop_front()
		for next in Hex.neighbors(current):
			if came.has(next) or not state.tile_at(next)["walkable"]:
				continue
			if absi(state.elevation_at(next) - state.elevation_at(current)) > 1:
				continue
			came[next] = current
			frontier.append(next)
	if not came.has(to):
		return []
	var path := []
	var cell := to
	while cell != from:
		path.push_front(cell)
		cell = came[cell]
	return path


# --- Falas soltas --------------------------------------------------------------

## Balão em cima de uma casa. Some sozinho.
func say(cell: Vector2i, text: String, height := 150.0) -> Label:
	var bubble := Label.new()
	bubble.text = text
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.97, 0.94, 0.84, 0.95)
	box.set_corner_radius_all(14)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	bubble.add_theme_stylebox_override("normal", box)
	bubble.add_theme_font_size_override("font_size", 26)
	bubble.add_theme_color_override("font_color", Color("262016"))
	var width: float = bubble.get_minimum_size().x
	var offset := Vector2(width / 2.0, height)
	bubble.position = view.feet_of(cell) - offset
	bubble.z_index = view._z(view._row(cell)) + 8
	view.board.add_child(bubble)
	camera.add_billboard(bubble, offset, view._cell_elevation(cell))
	var tween := bubble.create_tween()
	tween.tween_interval(BUBBLE_TIME)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.4)
	tween.tween_callback(bubble.queue_free)
	return bubble


func _chat() -> void:
	if view.selected == null:
		return
	var hero: Vector2i = view.selected.pos
	var talkers := []
	for cell in state.people:
		var person: Dictionary = state.people[cell]
		if calling and cell == guide_cell:
			continue # o guia está chamando a party: sem conversa solta por cima
		if state.is_present(person) and Content.AMBIENT.has(person["id"]) and Hex.distance(cell, hero) <= BUBBLE_RADIUS:
			talkers.append({"cell": cell, "lines": Content.AMBIENT[person["id"]]})
	for walker in walkers:
		if Hex.distance(walker["next"], hero) <= BUBBLE_RADIUS:
			talkers.append({"cell": walker["next"], "lines": Content.WALKER_LINES})
	if talkers.is_empty():
		return
	var pick: Dictionary = talkers[randi() % talkers.size()]
	say(pick["cell"], pick["lines"][randi() % pick["lines"].size()])


## Enquanto houver capítulo novo, o guia chama a party com um balão. Para quando ele contar.
func _call_party() -> void:
	calling = guide_cell != NO_CELL and state.people.has(guide_cell) and TownProgress.story_pending()
	if not calling:
		return
	var lines: Array = Content.STORY[TownProgress.story_heard() + 1]["call"]
	say(guide_cell, lines[randi() % lines.size()])


func _process(delta: float) -> void:
	time += delta
	if view.board == null:
		return
	_update_lights()
	for walker in walkers:
		_update_walker(walker, delta)
	bubble_wait -= delta
	if bubble_wait <= 0.0:
		bubble_wait = randf_range(BUBBLE_PAUSE.x, BUBBLE_PAUSE.y)
		_chat()
	if calling:
		call_wait -= delta
		if call_wait <= 0.0:
			call_wait = CALL_PAUSE
			_call_party()
