extends RefCounted

## Barra da party, embaixo: vida de cada herói, seleção, fila/separados e encerrar turno.


const END_TURN_WIDTH := 190.0

var hud: BattleHud # a tela dona deste módulo


func _init(host: Node) -> void:
	hud = host


## Barra da party, embaixo: mostra a vida de todos e seleciona o herói. `owners` tem o nome
## do jogador de cada herói no online.
func setup_party(heroes: Array, owners: Dictionary) -> void:
	hud.party_row = HBoxContainer.new()
	hud.party_row.position = Vector2(90, 606)
	hud.party_row.add_theme_constant_override("separation", 8)
	hud.add_child(hud.party_row)
	for unit in heroes:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(200, 62)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				hud.party_pressed.emit(unit))
		hud.party_row.add_child(panel)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var portrait := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/units/%s.png" % unit.type_id)
		atlas.region = Rect2(0, 0, hud.meta[unit.type_id]["cell_w"], hud.meta[unit.type_id]["cell_h"])
		portrait.texture = atlas
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.custom_minimum_size = Vector2(46, 46)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(column)
		var title: String = unit.display_name
		if owners.get(unit, "") != "":
			title = "%s · %s" % [owners[unit], unit.display_name]
		var name_label := hud._label(title, 15, Color.WHITE)
		name_label.clip_text = true
		name_label.custom_minimum_size.x = 130
		column.add_child(name_label)
		var back := ColorRect.new()
		back.color = Color(0, 0, 0, 0.7)
		back.custom_minimum_size = Vector2(130, 10)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(back)
		var fill := ColorRect.new()
		fill.color = hud.PLAYER_COLOR
		fill.size = Vector2(130, 10)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(fill)
		var status := hud._label("", 13, Color(0.85, 0.87, 0.92))
		column.add_child(status)
		hud.party_cards[unit] = {"panel": panel, "fill": fill, "status": status}
	var rotate_left := _corner_button("⟲ Q", Vector2(hud.SCREEN.x - 300, hud.MARGIN), 90)
	rotate_left.button_down.connect(func(): hud.rotate_held.emit(-1))
	rotate_left.button_up.connect(func(): hud.rotate_held.emit(0))
	var rotate_right := _corner_button("E ⟳", Vector2(hud.SCREEN.x - 202, hud.MARGIN), 90)
	rotate_right.button_down.connect(func(): hud.rotate_held.emit(1))
	rotate_right.button_up.connect(func(): hud.rotate_held.emit(0))
	hud.together_button = _corner_button("", Vector2(hud.SCREEN.x - 104, hud.MARGIN), 92)
	hud.together_button.toggle_mode = true
	hud.together_button.button_pressed = true
	hud.together_button.toggled.connect(func(on):
		_show_together(on)
		hud.together_toggled.emit(on))
	_show_together(true)


func show_end_turn(on: bool) -> void:
	if hud.end_turn_button == null:
		if not on:
			return
		hud.end_turn_button = _corner_button("Encerrar turno", Vector2(hud.SCREEN.x - END_TURN_WIDTH - hud.MARGIN, hud.SCREEN.y - 118), END_TURN_WIDTH)
		hud.end_turn_button.pressed.connect(func(): hud.end_turn_pressed.emit())
	hud.end_turn_button.visible = on


func _corner_button(text: String, at: Vector2, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.position = at
	button.custom_minimum_size = Vector2(width, 48)
	hud.sound_manager.bind_button(button, &"switch1")
	hud.add_child(button)
	return button


func _show_together(on: bool) -> void:
	hud.together_button.text = "Em fila" if on else "Separados"


func set_together(on: bool) -> void:
	hud.together_button.button_pressed = on


func update_party(current) -> void:
	for unit in hud.party_cards:
		var card: Dictionary = hud.party_cards[unit]
		card.fill.size.x = 130.0 * clampf(float(unit.hp) / unit.max_hp, 0.0, 1.0)
		card.status.text = "%d/%d" % [unit.hp, unit.max_hp] if unit.alive() else "caído"
		card.panel.modulate.a = 1.0 if unit.alive() else 0.5
		var border := hud.ACTIVE_COLOR if unit == current else Color(0.3, 0.33, 0.4)
		card.panel.add_theme_stylebox_override("panel", hud._box(Color(0.1, 0.11, 0.14, 0.92), border, 3 if unit == current else 1, 8, 6))
