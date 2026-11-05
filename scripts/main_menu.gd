extends Control

# Resolve services after the content pack is mounted by the thin installer.
var online_session:
	get: return get_node("/root/OnlineSession")

var sound_manager:
	get: return get_node("/root/SoundManager")

## Entrada do jogo; o combate continua em main.tscn. A arte vem de tools/build_menu.py, que tira
## da imagem os textos e o botão aceso; o que muda durante o jogo é desenhado aqui por cima.


const GameData = preload("res://scripts/game_data.gd")
const GameSettings = preload("res://scripts/game_settings.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const FONT := preload("res://assets/fonts/LibreBaskerville.ttf")
const BACKGROUND := preload("res://assets/menu/fundo.jpg")
const LIT_BUTTON := preload("res://assets/menu/botao_aceso.png")

const TEXT := Color("f4dcb8")
const TEXT_DIM := Color("cdb596")
const TEXT_LIT := Color("fff1cf")
const INK := Color("16090c")
const GOLD := Color("f2ca76")
const PANEL := Color("2a1319")

# A imagem original tem 2556 px úteis, a partir de x = 10. Em build_menu.py estão os mesmos números.
const ART_LEFT := 10.0
const ART_SCALE := 1280.0 / 2556.0
const BUTTON_FIRST_Y := 546.0
const BUTTON_STEP := 137.0
const BUTTON_LEFT := 190.0
const BUTTON_RIGHT := 835.0
const BUTTON_HALF := 58.0
const TEXT_LEFT := 312.0
const TEXT_RIGHT := 800.0
const LIT_ORIGIN := Vector2(250.0, 430.0) # canto da imagem do botão aceso
const LIT_TEXTURE_SCALE := 1280.0 / 1920.0
const LANTERN := Vector2(1966.0, 168.0)
const CAMPFIRE := Vector2(1289.0, 1240.0)
const SHORE_TORCH := Vector2(2291.0, 950.0)
const PANEL_EDGE := 858.0

const FOG_SHADER := "
shader_type canvas_item;
uniform sampler2D noise : repeat_enable, filter_linear;
void fragment() {
	float near = texture(noise, UV * vec2(1.0, 0.5) + vec2(TIME * 0.006, 0.0)).r;
	float far = texture(noise, UV * vec2(1.6, 0.9) - vec2(TIME * 0.004, TIME * 0.002)).r;
	float band = smoothstep(0.0, 0.45, UV.y) * smoothstep(1.0, 0.55, UV.y);
	COLOR = vec4(0.62, 0.68, 0.78, smoothstep(0.42, 0.78, near * 0.6 + far * 0.5) * band * 0.24);
}
"

var single_player: Button
var options: Control
var archive: Control
var menu_buttons: Array[Button] = []
var volume_chip: Button
var volume_slider: HSlider
var counters: Label
var version_label: Label
var lit_overlays := {}
var active_button: Button
var last_focus: Button
var open_modal: Control
var hover_embers: CPUParticles2D
var flicker := FastNoiseLite.new()
var glows: Array[Dictionary] = []
var beam: Node2D
var clock := 0.0
var title_font: FontVariation
var body_font: FontVariation


func _ready() -> void:
	for key in ["skills_back", "town", "expedition"]:
		get_tree().root.remove_meta(key)
	GameSettings.apply()
	get_window().title = "Cidade-Farol"
	title_font = _font(700)
	body_font = _font(400)
	flicker.frequency = 2.4
	_build_background()
	_build_ambience()
	_build_status()
	single_player = _menu_button(0, "JORNADA SOLO", "Single Player", _enter_town)
	_menu_button(1, "EXPEDIÇÃO ONLINE", "Multiplayer", func(): get_tree().change_scene_to_file("res://scenes/online_lobby.tscn"))
	_menu_button(2, "PROGRESSÃO & HERÓIS", "Skills e builds", func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	_menu_button(3, "MEMÓRIAS & ARQUIVO", "Resumos e história", _open_archive)
	_menu_button(4, "AJUSTES", "Opções", _open_options)
	_menu_button(5, "SAIR DO JOGO", "Fechar", func(): get_tree().quit())
	hover_embers = _embers(14, Vector2(24, 10), 0.9, Vector2(40, -30), Color("ffb347"), 1.0)
	add_child(hover_embers)
	_build_options()
	_build_archive()
	single_player.grab_focus()
	preload("res://update/pck_updater.gd").confirm_boot()


func _process(delta: float) -> void:
	clock += delta
	for glow in glows:
		var wave: float = flicker.get_noise_1d(clock + glow["seed"]) * 0.5 + 0.5
		glow["node"].modulate.a = lerpf(glow["low"], glow["high"], wave)
	if beam != null:
		beam.rotation_degrees = sin(clock * 0.35) * 1.6
		beam.modulate.a = 0.75 + sin(clock * 0.9) * 0.2
	if active_button != null and lit_overlays.has(active_button):
		var lit: TextureRect = lit_overlays[active_button]
		var wave: float = flicker.get_noise_1d(clock * 2.5) * 0.5 + 0.5
		lit.modulate.a = minf(lit.get_meta("reveal", 0.0), lerpf(0.86, 1.0, wave))


func _unhandled_input(event: InputEvent) -> void:
	if open_modal != null and event.is_action_pressed("ui_cancel"):
		_close_modal()
		get_viewport().set_input_as_handled()


func _enter_town() -> void:
	var root := get_tree().root
	root.set_meta("town", true)
	root.set_meta("skills_back", "res://main.tscn")
	if not root.has_meta("world_hero"):
		root.set_meta("world_hero", GameData.DEFAULT_PARTY)
	var error := get_tree().change_scene_to_file("res://main.tscn")
	if error != OK:
		push_error("Não foi possível abrir a cidade: %s" % error)


func _open_options() -> void:
	volume_slider.set_value_no_signal(GameSettings.volume())
	_show_modal(options)


func _open_archive() -> void:
	_fill_archive()
	_show_modal(archive)


# --- Fundo e luz ---------------------------------------------------------------

## De um ponto da imagem original para a tela de 1280×720.
func _art(point: Vector2) -> Vector2:
	return Vector2((point.x - ART_LEFT) * ART_SCALE, point.y * ART_SCALE)


func _build_background() -> void:
	var image := TextureRect.new()
	image.texture = BACKGROUND
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)


func _build_ambience() -> void:
	var left := _art(Vector2(PANEL_EDGE, 0)).x
	# Tudo o que anda no céu e no mar fica à direita do painel.
	var world := Control.new()
	world.clip_contents = true
	world.position = Vector2(left, 0)
	world.size = Vector2(1280 - left, 720)
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	world.add_child(_fog(world.size))
	beam = _lantern_beam(_art(LANTERN) - world.position)
	world.add_child(beam)
	_glow(world, _art(LANTERN) - world.position, 96, Color("ffd98a"), 0.32, 0.58)
	_glow(world, _art(CAMPFIRE) - world.position, 230, Color("ff9a3c"), 0.22, 0.46)
	_glow(world, _art(SHORE_TORCH) - world.position, 70, Color("ff9a3c"), 0.25, 0.6)
	var sparks := _embers(32, Vector2(26, 6), 3.4, Vector2(8, -58), Color("ffa63d"), 1.6)
	sparks.position = _art(CAMPFIRE) - world.position
	world.add_child(sparks)
	var drift := _embers(26, Vector2(world.size.x * 0.5, 240), 9.0, Vector2(16, -12), Color("e8853a"), 1.2)
	drift.position = Vector2(world.size.x * 0.5, 380)
	drift.preprocess = 9.0
	world.add_child(drift)


func _fog(area: Vector2) -> ColorRect:
	var fog := ColorRect.new()
	fog.position = Vector2(0, 150)
	fog.size = Vector2(area.x, 430)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var shader := Shader.new()
	shader.code = FOG_SHADER
	var paint := ShaderMaterial.new()
	paint.shader = shader
	paint.set_shader_parameter("noise", texture)
	fog.material = paint
	return fog


func _additive() -> CanvasItemMaterial:
	var paint := CanvasItemMaterial.new()
	paint.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return paint


## Dois fachos de luz com as bordas transparentes, para não aparecer uma cunha no céu.
func _lantern_beam(origin: Vector2) -> Node2D:
	var holder := Node2D.new()
	holder.position = origin
	holder.material = _additive()
	var bright := Color(1.0, 0.86, 0.55, 0.17)
	var clear := Color(1.0, 0.86, 0.55, 0.0)
	for side in [-1.0, 1.0]:
		var ray := Polygon2D.new()
		ray.use_parent_material = true
		ray.polygon = PackedVector2Array([Vector2(0, -8), Vector2(0, 8), Vector2(side * 24, 0), Vector2(side * 640, -64), Vector2(side * 640, -6), Vector2(side * 640, 52)])
		ray.polygons = [PackedInt32Array([0, 2, 3]), PackedInt32Array([2, 4, 3]), PackedInt32Array([2, 5, 4]), PackedInt32Array([1, 5, 2])]
		ray.vertex_colors = PackedColorArray([clear, clear, bright, clear, Color(1.0, 0.86, 0.55, 0.03), clear])
		holder.add_child(ray)
	return holder


func _glow(parent: Control, center: Vector2, radius: float, color: Color, low: float, high: float) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var light := TextureRect.new()
	light.texture = texture
	light.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	light.size = Vector2.ONE * radius * 2.0
	light.position = center - Vector2.ONE * radius
	light.material = _additive()
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(light)
	glows.append({"node": light, "low": low, "high": high, "seed": glows.size() * 37.0})


func _embers(amount: int, area: Vector2, life: float, speed: Vector2, color: Color, size: float) -> CPUParticles2D:
	var embers := CPUParticles2D.new()
	embers.amount = amount
	embers.lifetime = life
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = area
	embers.direction = speed.normalized()
	embers.spread = 28.0
	embers.gravity = Vector2.ZERO
	embers.initial_velocity_min = speed.length() * 0.6
	embers.initial_velocity_max = speed.length()
	embers.scale_amount_min = size
	embers.scale_amount_max = size * 2.0
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color, 0.0))
	embers.color_ramp = fade
	embers.material = _additive()
	return embers


# --- Botões e textos ------------------------------------------------------------

func _font(weight: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = FONT
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return font


func _text(parent: Control, content: String, font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 3)
	parent.add_child(label)
	return label


func _menu_button(index: int, title: String, subtitle: String, action: Callable) -> Button:
	var center_y := BUTTON_FIRST_Y + BUTTON_STEP * index
	var button := Button.new()
	button.flat = true
	var corner := _art(Vector2(BUTTON_LEFT, center_y - BUTTON_HALF))
	button.position = corner
	button.size = _art(Vector2(BUTTON_RIGHT, center_y + BUTTON_HALF)) - corner
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var nothing := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, nothing)
	add_child(button)

	var lit := TextureRect.new()
	lit.texture = LIT_BUTTON
	lit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lit.size = LIT_BUTTON.get_size() * LIT_TEXTURE_SCALE
	lit.position = _art(LIT_ORIGIN + Vector2(0, BUTTON_STEP * index)) - corner
	lit.modulate.a = 0.0
	lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(lit)
	lit_overlays[button] = lit

	var column_left := _art(Vector2(TEXT_LEFT, 0)).x - corner.x
	var column_width := (TEXT_RIGHT - TEXT_LEFT) * ART_SCALE
	var heading := _text(button, title, title_font, 17, TEXT)
	var caption := _text(button, subtitle, body_font, 13, TEXT_DIM)
	for line in [heading, caption]:
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.position.x = column_left
		line.size.x = column_width
	heading.position.y = 5
	caption.position.y = 31
	button.set_meta("heading", heading)
	button.set_meta("caption", caption)

	button.pressed.connect(action)
	button.mouse_entered.connect(func():
		if open_modal == null:
			button.grab_focus())
	button.focus_entered.connect(_light.bind(button, true))
	button.focus_exited.connect(_light.bind(button, false))
	sound_manager.bind_button(button)
	if not menu_buttons.is_empty():
		button.focus_neighbor_top = menu_buttons[-1].get_path()
		menu_buttons[-1].focus_neighbor_bottom = button.get_path()
		button.focus_neighbor_bottom = menu_buttons[0].get_path()
		menu_buttons[0].focus_neighbor_top = button.get_path()
	menu_buttons.append(button)
	return button


## Acende o botão escolhido: moldura dourada, chamas, faíscas e a letra mais clara.
func _light(button: Button, on: bool) -> void:
	var lit: TextureRect = lit_overlays[button]
	var tween := create_tween()
	tween.tween_method(func(value: float):
		lit.set_meta("reveal", value)
		lit.modulate.a = value, lit.modulate.a, 1.0 if on else 0.0, 0.14)
	button.get_meta("heading").add_theme_color_override("font_color", TEXT_LIT if on else TEXT)
	button.get_meta("caption").add_theme_color_override("font_color", TEXT_LIT if on else TEXT_DIM)
	if on:
		active_button = button
		last_focus = button
		hover_embers.position = button.position + Vector2(button.size.x - 12, 6)
		hover_embers.restart()
	elif active_button == button:
		active_button = null


func _build_status() -> void:
	counters = _text(self, "", body_font, 13, TEXT)
	counters.position = _art(Vector2(138, 30))
	counters.add_theme_constant_override("line_spacing", 2)
	var beacons := mini(TownProgress.beacons(), GameData.BIOMES.size())
	counters.text = "Brasas: %d\nFaróis: %d/%d" % [TownProgress.brasas(), beacons, GameData.BIOMES.size()]

	version_label = _text(self, "versão %s" % ProjectSettings.get_setting("application/config/version", ""), body_font, 11, TEXT_DIM)
	version_label.position = _art(Vector2(30, 1396))

	volume_chip = Button.new()
	volume_chip.flat = true
	var corner := _art(Vector2(2340, 14))
	volume_chip.position = corner
	volume_chip.size = _art(Vector2(2556, 84)) - corner
	volume_chip.focus_mode = Control.FOCUS_NONE
	volume_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	volume_chip.add_theme_font_override("font", body_font)
	volume_chip.add_theme_font_size_override("font_size", 13)
	volume_chip.add_theme_color_override("font_color", TEXT)
	volume_chip.add_theme_color_override("font_hover_color", TEXT_LIT)
	volume_chip.add_theme_color_override("font_pressed_color", GOLD)
	volume_chip.pressed.connect(_open_options)
	add_child(volume_chip)
	sound_manager.bind_button(volume_chip)
	_update_volume_chip()


func _update_volume_chip() -> void:
	volume_chip.text = "Sem som" if GameSettings.muted() else "Volume %d%%" % GameSettings.volume()


# --- Janelas --------------------------------------------------------------------

func _modal(title: String, width: float) -> Dictionary:
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.02, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size.x = width
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = GOLD.darkened(0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(26)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 14
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	box.add_child(column)
	var heading := _text(column, title, title_font, 24, GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	var back := Button.new()
	back.text = "Voltar"
	back.custom_minimum_size.y = 44
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.add_theme_font_override("font", title_font)
	back.add_theme_font_size_override("font_size", 16)
	back.add_theme_color_override("font_color", INK)
	back.add_theme_color_override("font_hover_color", INK)
	back.add_theme_color_override("font_pressed_color", INK)
	back.add_theme_color_override("font_focus_color", INK)
	back.add_theme_stylebox_override("normal", _button_box(GOLD))
	back.add_theme_stylebox_override("hover", _button_box(GOLD.lightened(0.25)))
	back.add_theme_stylebox_override("pressed", _button_box(GOLD.darkened(0.15)))
	var focused := _button_box(GOLD.lightened(0.25))
	focused.border_color = TEXT_LIT
	focused.set_border_width_all(2)
	back.add_theme_stylebox_override("focus", focused)
	back.pressed.connect(_close_modal)
	column.add_child(back)
	sound_manager.bind_button(back)
	dim.set_meta("back", back)
	return {"root": dim, "body": body}


func _button_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(4)
	return box


func _show_modal(modal: Control) -> void:
	open_modal = modal
	modal.visible = true
	modal.get_meta("back").grab_focus()


func _close_modal() -> void:
	if open_modal == null:
		return
	open_modal.visible = false
	open_modal = null
	(last_focus if last_focus != null else single_player).grab_focus()


func _build_options() -> void:
	var parts := _modal("Ajustes", 440.0)
	options = parts["root"]
	var load_button := Button.new()
	load_button.text = "Carregar jogo"
	load_button.disabled = not SaveGame.exists()
	load_button.tooltip_text = SaveGame.summary()
	load_button.custom_minimum_size.y = 44
	load_button.add_theme_font_override("font", title_font)
	load_button.add_theme_font_size_override("font_size", 16)
	load_button.add_theme_color_override("font_color", INK)
	load_button.add_theme_stylebox_override("normal", _button_box(GOLD))
	load_button.add_theme_stylebox_override("hover", _button_box(GOLD.lightened(0.25)))
	load_button.add_theme_stylebox_override("pressed", _button_box(GOLD.darkened(0.15)))
	load_button.pressed.connect(_load_game)
	parts["body"].add_child(load_button)
	sound_manager.bind_button(load_button)
	var volume_label := _text(parts["body"], "Volume geral: %d%%" % GameSettings.volume(), body_font, 15, TEXT)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value = GameSettings.volume()
	volume_slider.custom_minimum_size.y = 32
	var track := StyleBoxFlat.new()
	track.bg_color = INK
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var filled := track.duplicate()
	filled.bg_color = GOLD
	volume_slider.add_theme_stylebox_override("slider", track)
	volume_slider.add_theme_stylebox_override("grabber_area", filled)
	volume_slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	parts["body"].add_child(volume_slider)
	volume_slider.value_changed.connect(func(value: float):
		GameSettings.set_volume(int(value))
		volume_label.text = "Volume geral: %d%%" % value
		_update_volume_chip())
	var mute := CheckButton.new()
	mute.text = "Sem som"
	mute.button_pressed = GameSettings.muted()
	mute.add_theme_font_override("font", body_font)
	mute.add_theme_font_size_override("font_size", 15)
	mute.add_theme_color_override("font_color", TEXT)
	mute.add_theme_color_override("font_hover_color", TEXT_LIT)
	mute.add_theme_color_override("font_pressed_color", TEXT)
	mute.add_theme_color_override("font_hover_pressed_color", TEXT_LIT)
	mute.add_theme_color_override("font_focus_color", TEXT)
	mute.toggled.connect(func(on: bool):
		GameSettings.set_muted(on)
		_update_volume_chip())
	parts["body"].add_child(mute)
	sound_manager.bind_button(mute)


func _build_archive() -> void:
	var parts := _modal("Memórias & Arquivo", 520.0)
	archive = parts["root"]
	archive.set_meta("body", parts["body"])


func _fill_archive() -> void:
	var body: VBoxContainer = archive.get_meta("body")
	for child in body.get_children():
		child.queue_free()
	var rows := [
		["Expedições feitas", TownProgress.expeditions()],
		["Faróis acesos", TownProgress.beacons()],
		["Memórias encontradas", TownProgress.memories()],
		["Moradores resgatados", TownProgress.rescued().size()],
	]
	for row in rows:
		var line := HBoxContainer.new()
		body.add_child(line)
		var name_label := _text(line, row[0], body_font, 15, TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_text(line, str(row[1]), title_font, 15, GOLD)
	var note: String = TownProgress.last_note()
	var story := _text(body, note if note != "" else "Nenhuma expedição voltou ainda. O arquivo espera por suas histórias.", body_font, 14, TEXT_DIM)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size.x = 460


func _load_game() -> void:
	var data := SaveGame.read()
	if data.is_empty():
		return
	get_tree().root.set_meta("load_save", data)
	var error := get_tree().change_scene_to_file("res://main.tscn")
	if error != OK:
		push_error("Não foi possível carregar o jogo: %s" % error)
