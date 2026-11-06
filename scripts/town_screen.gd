extends Control
## A Cidade-Farol: de onde a party parte em cada expedição e para onde volta.
## Mostra quem foi resgatado, vende melhorias e monta a party.

const Data = preload("res://scripts/game_data.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")

const WORLD_META := "world_hero"
const EXPEDITION_META := "expedition"
const SKILLS_BACK_META := "skills_back"
const SCENE := "res://scenes/town.tscn"

const INK := Color("191e2a")
const PANEL := Color("252d3e")
const GOLD := Color("f2ca76")
const TEXT := Color("f5efdf")
const MUTED := Color("aab2c2")

var sound_manager:
	get: return get_node("/root/SoundManager")
var online_session:
	get: return get_node("/root/OnlineSession")

var party := []
var hero_buttons := {}
var start_button: Button
var status: Label
var services: VBoxContainer
var story: Label


func _ready() -> void:
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	page.add_child(_label("CIDADE-FAROL", 40, GOLD))
	status = _label("", 19, TEXT)
	page.add_child(status)
	story = _label("", 18, MUTED)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(story)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 28)
	page.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	left.add_child(_label("Moradores", 24, TEXT))
	services = VBoxContainer.new()
	services.add_theme_constant_override("separation", 10)
	left.add_child(services)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	right.add_child(_label("Party da expedição", 24, TEXT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	var units_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	for id in Data.WORLD_HEROES:
		var button := _button(grid, "")
		_fill_hero(button, id, units_meta[id])
		hero_buttons[id] = button

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 14)
	page.add_child(actions)
	var back := _button(actions, "Menu principal")
	back.pressed.connect(_back)
	var skills := _button(actions, "Skills dos heróis")
	skills.pressed.connect(_open_skills)
	start_button = _button(actions, "", true)
	start_button.pressed.connect(_depart)

	var remembered: Variant = get_tree().root.get_meta(WORLD_META, [])
	party = remembered.duplicate() if remembered is Array and not remembered.is_empty() else Data.DEFAULT_PARTY.duplicate()
	_show_party()
	_refresh()
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()


func _back() -> void:
	get_tree().root.remove_meta(SKILLS_BACK_META)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _open_skills() -> void:
	get_tree().root.set_meta(SKILLS_BACK_META, SCENE)
	get_tree().change_scene_to_file("res://scenes/skill_tree.tscn")


func _refresh() -> void:
	status.text = "Brasas: %d   ·   Faróis acesos: %d   ·   Expedições: %d" % [TownProgress.brasas(), TownProgress.beacons(), TownProgress.expeditions()]
	story.text = _story_text()
	for child in services.get_children():
		services.remove_child(child)
		child.queue_free()
	var saved := TownProgress.rescued()
	for id in Exp.RESIDENT_ORDER:
		services.add_child(_resident_row(id, id in saved))


func _story_text() -> String:
	var lines := []
	var note := TownProgress.last_note()
	if note != "":
		lines.append(note)
	var found := TownProgress.memories()
	if found > 0:
		lines.append(Exp.MEMORIES[found - 1])
	lines.append("Objetivo: %s" % TownProgress.objective())
	return "\n".join(lines)


func _resident_row(id: String, present: bool) -> Control:
	var data: Dictionary = Exp.RESIDENTS[id]
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(PANEL))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	if not present:
		row.add_child(_label("Morador desaparecido", 20, MUTED))
		row.add_child(_label("Procure vilas tomadas pela escuridão.", 16, MUTED))
		return box
	var level := TownProgress.service_level(id)
	var costs: Array = data["costs"]
	row.add_child(_label("%s · %s %d/%d" % [data["name"], data["service"], level, costs.size()], 20, TEXT))
	row.add_child(_label(data["effect"] % data["per_level"], 16, MUTED))
	var cost := TownProgress.next_cost(id)
	var buy := _button(row, "Melhorar (%d brasas)" % cost if cost >= 0 else "Nível máximo")
	buy.custom_minimum_size.y = 44
	buy.disabled = cost < 0 or cost > TownProgress.brasas()
	buy.pressed.connect(func():
		if TownProgress.buy(id):
			_refresh())
	return box


func _fill_hero(button: Button, id: String, info: Dictionary) -> void:
	var data: Dictionary = Data.UNIT_TYPES[id]
	button.custom_minimum_size = Vector2(320, 104)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % id)
	atlas.region = Rect2(0, 0, info["cell_w"], info["cell_h"])
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(90, 90)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(_label(data["name"], 20, TEXT))
	var role := _label(data["role"], 14, MUTED)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.add_child(role)
	button.pressed.connect(func(): _toggle(id))


func _toggle(id: String) -> void:
	if id in party:
		party.erase(id)
	elif party.size() < Data.PARTY_SIZE:
		party.append(id)
	_show_party()


func _show_party() -> void:
	for id in hero_buttons:
		var chosen: bool = id in party
		var style := _box(Color("3b3a2c") if chosen else PANEL)
		if chosen:
			style.border_color = GOLD
			style.set_border_width_all(4)
		hero_buttons[id].add_theme_stylebox_override("normal", style)
	start_button.disabled = party.is_empty()
	start_button.text = "Partir com %d de %d" % [party.size(), Data.PARTY_SIZE]


func _depart() -> void:
	var chosen := []
	for id in Data.WORLD_HEROES: # ordem fixa: a mesma party sempre sai igual
		if id in party:
			chosen.append(id)
	get_tree().root.set_meta(WORLD_META, chosen)
	get_tree().root.set_meta(EXPEDITION_META, true)
	get_tree().root.set_meta(SKILLS_BACK_META, SCENE)
	online_session.leave()
	var error := get_tree().change_scene_to_file("res://main.tscn")
	if error != OK:
		push_error("Não foi possível abrir a expedição: %s" % error)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(parent: Control, text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 56)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", INK if primary else TEXT)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK if primary else TEXT)
	button.add_theme_stylebox_override("normal", _box(GOLD if primary else PANEL))
	button.add_theme_stylebox_override("hover", _box(Color("ffe0a0")))
	button.add_theme_stylebox_override("pressed", _box(Color("d5aa58")))
	button.add_theme_stylebox_override("disabled", _box(Color("1f2533")))
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
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
