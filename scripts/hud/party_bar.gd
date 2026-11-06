extends RefCounted

## Barra da party, embaixo: vida de cada herói, seleção, fila/separados e encerrar turno.


const XP_COLOR := Color(0.55, 0.9, 1.0)

var hud: BattleHud # a tela dona deste módulo


func _init(host: Node) -> void:
	hud = host


## Barra da party, embaixo: mostra a vida de todos e seleciona o herói. `owners` tem o nome
## do jogador de cada herói no online.
func setup_party(heroes: Array, owners: Dictionary) -> void:
	hud.party_row = HBoxContainer.new()
	hud.party_row.add_theme_constant_override("separation", 10)
	var row_width := heroes.size() * hud.PARTY_CARD.x + (heroes.size() - 1) * 10
	hud.party_row.position = Vector2((hud.SCREEN.x - row_width) / 2, hud.SCREEN.y - hud.MARGIN - hud.PARTY_CARD.y)
	hud.add_child(hud.party_row)
	for unit in heroes:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = hud.PARTY_CARD
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
		portrait.custom_minimum_size = Vector2(60, 60)
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
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(top)
		var name_label := hud._title(title, 20, Color.WHITE)
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		var level := hud._title("", 17, hud.MENU_INK)
		var level_box := PanelContainer.new()
		var level_style := hud._box(hud.PANEL_EDGE, hud.PANEL_EDGE, 0, 8, 0)
		level_style.content_margin_left = 6
		level_style.content_margin_right = 6
		level_box.add_theme_stylebox_override("panel", level_style)
		level_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		level_box.visible = false
		level_box.add_child(level)
		top.add_child(level_box)
		var back := ColorRect.new()
		back.color = Color(0, 0, 0, 0.7)
		back.custom_minimum_size = Vector2(150, 12)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(back)
		var fill := ColorRect.new()
		fill.color = hud.PLAYER_COLOR
		fill.size = Vector2(150, 12)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(fill)
		var middle := HBoxContainer.new()
		middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(middle)
		var status := hud._title("", 17, Color(0.85, 0.87, 0.92))
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		middle.add_child(status)
		# Pontos para gastar: selo dourado piscando. Tocar na carta abre a árvore.
		var points := hud._title("", 17, hud.MENU_INK)
		var points_box := PanelContainer.new()
		var points_style := hud._box(Color(1.0, 0.8, 0.25), Color.WHITE, 2, 8, 0)
		points_style.content_margin_left = 6
		points_style.content_margin_right = 6
		points_box.add_theme_stylebox_override("panel", points_style)
		points_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		points_box.visible = false
		points_box.add_child(points)
		middle.add_child(points_box)
		var pulse := points_box.create_tween().set_loops()
		pulse.tween_property(points_box, "modulate", Color(1.4, 1.3, 1.0), 0.45)
		pulse.tween_property(points_box, "modulate", Color.WHITE, 0.45)
		var xp_back := ColorRect.new()
		xp_back.color = Color(0, 0, 0, 0.7)
		xp_back.custom_minimum_size = Vector2(150, 6)
		xp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		xp_back.visible = false
		column.add_child(xp_back)
		var xp_fill := ColorRect.new()
		xp_fill.color = XP_COLOR
		xp_fill.size = Vector2(0, 6)
		xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		xp_back.add_child(xp_fill)
		hud.party_cards[unit] = {"panel": panel, "fill": fill, "status": status, "level": level, "xp": xp_fill, "points": points, "name": name_label}
	# Coluna da direita: girar, aproximar, girar, fila. No celular, dois dedos também giram
	# (torcendo) e aproximam (abrindo); no teclado, Q/E, Z e G.
	var rotate_left := hud._icon_button("turn_left")
	rotate_left.tooltip_text = "Girar (Q). No celular: torça com dois dedos."
	rotate_left.button_down.connect(func(): hud.rotate_held.emit(-1))
	rotate_left.button_up.connect(func(): hud.rotate_held.emit(0))
	var rotate_right := hud._icon_button("turn_right")
	rotate_right.tooltip_text = "Girar (E). No celular: torça com dois dedos."
	rotate_right.button_down.connect(func(): hud.rotate_held.emit(1))
	rotate_right.button_up.connect(func(): hud.rotate_held.emit(0))
	hud.together_button = hud._icon_button("file")
	hud.together_button.toggle_mode = true
	hud.together_button.button_pressed = true
	hud.together_button.toggled.connect(func(on):
		_show_together(on)
		hud.together_toggled.emit(on))
	_show_together(true)
	hud.dock.move_child(rotate_left, 0)
	hud.dock.move_child(rotate_right, 2)
	hud.dock.move_child(hud.together_button, 3)


func show_end_turn(on: bool) -> void:
	if hud.end_turn_button == null:
		if not on:
			return
		hud.end_turn_button = _corner_button("Encerrar\nturno", Vector2(hud.SCREEN.x - hud.END_TURN_WIDTH - hud.MARGIN, hud.SCREEN.y - hud.MARGIN - hud.PARTY_CARD.y), hud.END_TURN_WIDTH)
		hud.end_turn_button.custom_minimum_size.y = hud.PARTY_CARD.y
		hud.end_turn_button.pressed.connect(func(): hud.end_turn_pressed.emit())
	hud.end_turn_button.visible = on


func _corner_button(text: String, at: Vector2, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.position = at
	button.custom_minimum_size = Vector2(width, 56)
	hud.sound_manager.bind_button(button, &"switch1")
	hud.add_child(button)
	return button


func _show_together(on: bool) -> void:
	hud._set_icon(hud.together_button, "file" if on else "spread")
	hud.together_button.tooltip_text = "Em fila (G)" if on else "Separados (G)"


func set_together(on: bool) -> void:
	hud.together_button.button_pressed = on


func update_party(current) -> void:
	for unit in hud.party_cards:
		var card: Dictionary = hud.party_cards[unit]
		card.fill.size.x = 150.0 * clampf(float(unit.hp) / unit.max_hp, 0.0, 1.0)
		card.status.text = "%d/%d" % [unit.hp, unit.max_hp] if unit.alive() else "caído"
		card.panel.modulate.a = 1.0 if unit.alive() else 0.5
		var border := hud.ACTIVE_COLOR if unit == current else Color(0.3, 0.33, 0.4)
		card.panel.add_theme_stylebox_override("panel", hud._box(Color(0.1, 0.11, 0.14, 0.92), border, 3 if unit == current else 1, 8, 6))
