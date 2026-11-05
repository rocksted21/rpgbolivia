extends Control
## Interface da Cidade-Farol: botões no canto e as janelas de moradores e da party.

signal depart(party: Array)
signal skills_requested
signal menu_requested
signal changed

const Data = preload("res://scripts/game_data.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const Town = preload("res://scripts/town_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")

const SCREEN := Vector2(1280, 720)
const WINDOW_WIDTH := 720
const CORNER_WIDTH := 200
const INK := Color("191e2a")
const PANEL := Color("252d3e")
const GOLD := Color("f2ca76")
const TEXT := Color("f5efdf")
const MUTED := Color("aab2c2")

var sound_manager:
	get: return get_node("/root/SoundManager")

var action_button: Button
var nearby := {}
var window: Control
var party := []
var hero_buttons := {}
var start_button: Button


func setup(chosen: Array) -> void:
	party = chosen.duplicate()
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var leave := _button(self, "Partir para a\nExpedição", true)
	_place_corner(leave, 76, SCREEN.y - 126)
	leave.pressed.connect(open_party)
	action_button = _button(self, "")
	_place_corner(action_button, 56, SCREEN.y - 190)
	action_button.visible = false
	action_button.pressed.connect(func(): open_person(nearby))


func _place_corner(button: Button, height: float, y: float) -> void:
	button.custom_minimum_size = Vector2(CORNER_WIDTH, height)
	button.size = button.custom_minimum_size
	button.clip_text = true
	button.position = Vector2(SCREEN.x - CORNER_WIDTH - 16, y)


func window_open() -> bool:
	return window != null


## Quem está perto do herói selecionado. Muda o botão de conversar.
func set_nearby(person: Dictionary) -> void:
	if person == nearby:
		return
	nearby = person
	action_button.visible = not person.is_empty()
	if not person.is_empty():
		action_button.text = "Falar: %s" % person["name"]


func open_person(person: Dictionary) -> void:
	var body := _open(person["name"])
	match person["service"]:
		"resident":
			_fill_resident(body, person)
		"memories":
			_fill_memories(body)
		"skills":
			_paragraph(body, Town.SKILLS_TEXT)
			var train := _button(body, "Abrir árvores de skills", true)
			train.pressed.connect(func(): skills_requested.emit())
		"beacon":
			_paragraph(body, Town.BEACON_TEXT)
			_paragraph(body, "Faróis acesos: %d   ·   Expedições: %d" % [TownProgress.beacons(), TownProgress.expeditions()], GOLD)
			if TownProgress.beacons() > 0:
				_paragraph(body, Town.NEXT_REGION_TEXT, MUTED)
		"talk":
			var lines: Array = person["lines"]
			_paragraph(body, lines[TownProgress.expeditions() % lines.size()])
	_close_button(body)


func _fill_resident(body: Control, person: Dictionary) -> void:
	var id: String = person["id"]
	if id not in TownProgress.rescued():
		_paragraph(body, Town.MISSING_TEXT)
		return
	var data: Dictionary = Exp.RESIDENTS[id]
	var costs: Array = data["costs"]
	var level := TownProgress.service_level(id)
	_paragraph(body, "%s %d de %d" % [data["service"], level, costs.size()], GOLD)
	_paragraph(body, data["effect"] % data["per_level"])
	_paragraph(body, "Brasas: %d" % TownProgress.brasas(), MUTED)
	var cost := TownProgress.next_cost(id)
	var buy := _button(body, "Melhorar (%d brasas)" % cost if cost >= 0 else "Nível máximo", true)
	buy.disabled = cost < 0 or cost > TownProgress.brasas()
	buy.pressed.connect(func():
		if TownProgress.buy(id):
			changed.emit()
			open_person(person))


func _fill_memories(body: Control) -> void:
	var note := TownProgress.last_note()
	if note != "":
		_paragraph(body, note, GOLD)
	var found := TownProgress.memories()
	if found == 0:
		_paragraph(body, Town.NO_MEMORY_TEXT)
	for i in found:
		_paragraph(body, Exp.MEMORIES[i])


func open_party() -> void:
	var body := _open("Party da expedição")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	hero_buttons.clear()
	var units_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	for id in Data.WORLD_HEROES:
		var button := _button(grid, "")
		_fill_hero(button, id, units_meta[id])
		hero_buttons[id] = button
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	_close_button(row, "Ficar na cidade")
	var menu := _button(row, "Menu principal")
	menu.pressed.connect(func(): menu_requested.emit())
	start_button = _button(row, "", true)
	start_button.pressed.connect(_depart)
	_show_party()


func _fill_hero(button: Button, id: String, info: Dictionary) -> void:
	var data: Dictionary = Data.UNIT_TYPES[id]
	button.custom_minimum_size = Vector2(340, 92)
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
	portrait.custom_minimum_size = Vector2(84, 84)
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
	depart.emit(chosen)


# --- Peças da janela -----------------------------------------------------------

func close_window() -> void:
	if window != null:
		window.queue_free()
		window = null


## Abre uma janela centralizada, que bloqueia os cliques no mapa. Devolve onde pôr o conteúdo.
func _open(title: String) -> Control:
	close_window()
	window = ColorRect.new()
	(window as ColorRect).color = Color(0, 0, 0, 0.55)
	window.size = SCREEN
	add_child(window)
	var center := CenterContainer.new()
	center.size = SCREEN
	window.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size.x = WINDOW_WIDTH
	var style := _box(INK)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_content_margin_all(22)
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	box.add_child(body)
	body.add_child(_label(title, 30, GOLD))
	return body


func _close_button(parent: Control, text := "Voltar") -> void:
	var close := _button(parent, text)
	close.pressed.connect(close_window)


func _paragraph(parent: Control, text: String, color := TEXT) -> void:
	var label := _label(text, 19, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WINDOW_WIDTH - 44
	parent.add_child(label)


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
	button.custom_minimum_size = Vector2(200, 52)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else TEXT)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_stylebox_override("normal", _box(GOLD if primary else PANEL))
	button.add_theme_stylebox_override("hover", _box(Color("ffe0a0")))
	button.add_theme_stylebox_override("pressed", _box(Color("d5aa58")))
	button.add_theme_stylebox_override("disabled", _box(Color("1f2533")))
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
