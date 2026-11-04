extends Control

# Resolve services after the content pack is mounted by the thin installer.
var online_session:
	get: return get_node("/root/OnlineSession")

var sound_manager:
	get: return get_node("/root/SoundManager")

## Entrada do jogo; o combate continua em main.tscn.

const Data = preload("res://scripts/game_data.gd")
const WORLD_META := "world_hero"

const INK := Color("191e2a")
const GOLD := Color("f2ca76")
const TEXT := Color("f5efdf")

var single_player: Button
var options: AcceptDialog
var hero_picker: Control


func _ready() -> void:
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 360
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	_label(column, "RPG TÁTICO", 16, GOLD)
	_label(column, "COMBATE\nTÁTICO", 54, TEXT)
	_spacer(column, 20)
	single_player = _button(column, "Single Player", true)
	single_player.pressed.connect(_open_hero_picker)
	var online_button := _button(column, "Online")
	online_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/online_lobby.tscn"))
	var heroes_button := _button(column, "Heróis")
	heroes_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	var options_button := _button(column, "Options")
	options_button.pressed.connect(_open_options)
	_spacer(column, 10)
	_label(column, "Sua próxima batalha começa aqui.", 16, Color("9da5b5"))

	_build_options()
	_build_hero_picker()
	single_player.grab_focus()
	preload("res://update/pck_updater.gd").confirm_boot()


func _open_hero_picker() -> void:
	hero_picker.visible = true
	hero_picker.find_child("Hero0", true, false).grab_focus()


func _close_hero_picker() -> void:
	hero_picker.visible = false
	single_player.grab_focus()


func _build_hero_picker() -> void:
	hero_picker = ColorRect.new()
	hero_picker.color = INK
	hero_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_picker.visible = false
	add_child(hero_picker)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_picker.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)
	_label(column, "Escolha seu herói", 40, TEXT)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	column.add_child(grid)
	var units_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	for i in Data.WORLD_HEROES.size():
		var id: String = Data.WORLD_HEROES[i]
		var button := _button(grid, "")
		button.name = "Hero%d" % i
		_fill_hero_button(button, id, units_meta[id])
	var back := _button(column, "Voltar")
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_hero_picker)


func _fill_hero_button(button: Button, id: String, info: Dictionary) -> void:
	var data: Dictionary = Data.UNIT_TYPES[id]
	button.custom_minimum_size = Vector2(350, 150)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	button.add_child(row)
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % id)
	atlas.region = Rect2(0, 0, info["cell_w"], info["cell_h"])
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(130, 130)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var title := Label.new()
	title.text = data["name"]
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", TEXT)
	text.add_child(title)
	var role := Label.new()
	role.text = data["role"]
	role.autowrap_mode = TextServer.AUTOWRAP_WORD
	role.add_theme_font_size_override("font_size", 16)
	role.add_theme_color_override("font_color", Color("c3c8d3"))
	text.add_child(role)
	button.pressed.connect(func(): _start_single_player(id))


func _start_single_player(hero_type: String) -> void:
	get_tree().root.set_meta(WORLD_META, hero_type)
	online_session.leave()
	var error := get_tree().change_scene_to_file("res://main.tscn")
	if error != OK:
		push_error("Não foi possível abrir o combate: %s" % error)


func _open_options() -> void:
	options.popup_centered(Vector2i(420, 220))


func _build_options() -> void:
	options = AcceptDialog.new()
	options.title = "Options"
	options.ok_button_text = "Voltar"
	add_child(options)
	sound_manager.bind_button(options.get_ok_button())
	options.visibility_changed.connect(_restore_focus)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	options.add_child(column)
	var volume_label := Label.new()
	volume_label.text = "Volume geral: %d%%" % sound_manager.volume
	column.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.step = 1
	volume.value = sound_manager.volume
	volume.custom_minimum_size = Vector2(360, 40)
	column.add_child(volume)
	volume.value_changed.connect(func(value: float):
		sound_manager.volume = value
		volume_label.text = "Volume geral: %d%%" % value)
	var note := Label.new()
	note.text = "Ajuste válido durante esta sessão."
	column.add_child(note)


func _restore_focus() -> void:
	if not options.visible:
		single_player.grab_focus()


func _label(parent: Control, text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)


func _button(parent: Control, text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 62)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 23)
	button.add_theme_color_override("font_color", INK if primary else TEXT)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK if primary else TEXT)
	button.add_theme_stylebox_override("normal", _box(GOLD if primary else Color("252d3e")))
	button.add_theme_stylebox_override("hover", _box(Color("ffe0a0")))
	button.add_theme_stylebox_override("pressed", _box(Color("d5aa58")))
	var focus := _box(Color.TRANSPARENT)
	focus.border_color = TEXT
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	parent.add_child(button)
	sound_manager.bind_button(button)
	return button


func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	return style
