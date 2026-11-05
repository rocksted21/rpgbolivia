extends Control

# Resolve services after the content pack is mounted by the thin installer.
var online_session:
	get: return get_node("/root/OnlineSession")

var sound_manager:
	get: return get_node("/root/SoundManager")

## Entrada do jogo; o combate continua em main.tscn.


const GameSettings = preload("res://scripts/game_settings.gd")

const INK := Color("191e2a")
const GOLD := Color("f2ca76")
const TEXT := Color("f5efdf")

var single_player: Button
var options: AcceptDialog


func _ready() -> void:
	get_tree().root.remove_meta("skills_back")
	GameSettings.apply()
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
	single_player.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	var online_button := _button(column, "Online")
	online_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/online_lobby.tscn"))
	var heroes_button := _button(column, "Heróis")
	heroes_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	var options_button := _button(column, "Options")
	options_button.pressed.connect(_open_options)
	_spacer(column, 10)
	_label(column, "Sua próxima batalha começa aqui.", 16, Color("9da5b5"))

	_build_options()
	single_player.grab_focus()
	preload("res://update/pck_updater.gd").confirm_boot()


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
	volume_label.text = "Volume geral: %d%%" % GameSettings.volume()
	column.add_child(volume_label)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.step = 1
	volume.value = GameSettings.volume()
	volume.custom_minimum_size = Vector2(360, 40)
	column.add_child(volume)
	volume.value_changed.connect(func(value: float):
		GameSettings.set_volume(int(value))
		volume_label.text = "Volume geral: %d%%" % value)


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
