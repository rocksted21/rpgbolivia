extends RefCounted

## Barra da party, embaixo: vida de cada herói, seleção, fila/separados e encerrar turno.
## Cada herói é um medalhão de latão com o retrato, numa placa vinho (scripts/hud/brass.gd).

const Brass = preload("res://scripts/hud/brass.gd")
const MEDAL := 66.0 # diâmetro do retrato


const XP_COLOR := Color(0.55, 0.9, 1.0)
const LEVEL_UP_FILL := Color(1.0, 0.82, 0.2)
const LEVEL_UP_SIZE := Vector2(150, 36)
const CARD_GAP := 10 # separação entre as cartas da party

var hud: BattleHud # a tela dona deste módulo


func _init(host: Node) -> void:
	hud = host


## Barra da party, embaixo: mostra a vida de todos e seleciona o herói. `owners` tem o nome
## do jogador de cada herói no online.
func setup_party(heroes: Array, owners: Dictionary) -> void:
	hud.party_row = HBoxContainer.new()
	hud.party_row.add_theme_constant_override("separation", CARD_GAP)
	var row_width := heroes.size() * hud.PARTY_CARD.x + (heroes.size() - 1) * CARD_GAP
	hud.party_row.position = Vector2((hud.SCREEN.x - row_width) / 2, hud.SCREEN.y - hud.MARGIN - hud.PARTY_CARD.y)
	hud.add_child(hud.party_row)
	for index in heroes.size():
		var unit = heroes[index]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = hud.PARTY_CARD
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				hud.party_pressed.emit(unit))
		hud.party_row.add_child(panel)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)
		var medal := PanelContainer.new()
		medal.custom_minimum_size = Vector2(MEDAL, MEDAL)
		medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		medal.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		medal.add_theme_stylebox_override("panel", Brass.medal(Brass.WINE_DEEP, Brass.BRASS_DIM, 3))
		medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(medal)
		var portrait := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/units/%s.png" % unit.type_id)
		atlas.region = _bust(atlas.atlas, Rect2(0, 0, hud.meta[unit.type_id]["cell_w"], hud.meta[unit.type_id]["cell_h"]))
		portrait.texture = atlas
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.custom_minimum_size = Vector2(MEDAL, MEDAL)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		medal.add_child(portrait)
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
		var name_label := Brass.label(title, 14, Brass.TEXT_LIT, 700)
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		var level := Brass.label("", 13, Brass.WINE_DEEP, 700)
		var level_box := PanelContainer.new()
		var level_style := Brass.panel(Brass.BRASS, Brass.BRASS, 0, 4, 0, 0)
		level_style.content_margin_left = 6
		level_style.content_margin_right = 6
		level_box.add_theme_stylebox_override("panel", level_style)
		level_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		level_box.visible = false
		level_box.add_child(level)
		top.add_child(level_box)
		var bag := _bag_button(unit) # bolsa do herói (hud/hero_bag_ui.gd)
		top.add_child(bag)
		var back := ColorRect.new()
		back.color = Brass.WINE_DEEP
		back.custom_minimum_size = Vector2(150, 10)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(back)
		var fill := ColorRect.new()
		fill.color = hud.PLAYER_COLOR
		fill.size = Vector2(150, 10)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(fill)
		var middle := HBoxContainer.new()
		middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(middle)
		var status := Brass.label("", 13, Brass.MUTED)
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		middle.add_child(status)
		# Pontos para gastar: selo dourado piscando. A árvore abre pelo LEVEL UP em cima da carta.
		var points := Brass.label("", 13, Brass.WINE_DEEP, 700)
		var points_box := PanelContainer.new()
		var points_style := Brass.panel(Brass.FLAME, Brass.TEXT_LIT, 1, 8, 0, 0)
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
		xp_back.color = Brass.WINE_DEEP
		xp_back.custom_minimum_size = Vector2(150, 6)
		xp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		xp_back.visible = false
		column.add_child(xp_back)
		var xp_fill := ColorRect.new()
		xp_fill.color = XP_COLOR
		xp_fill.size = Vector2(0, 6)
		xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		xp_back.add_child(xp_fill)
		var level_up := _level_up_badge(unit, index)
		hud.party_cards[unit] = {"panel": panel, "medal": medal, "fill": fill, "status": status, "level": level, "xp": xp_fill, "points": points, "name": name_label, "level_up": level_up,
			"bag": bag, "bag_icon": bag.get_meta("icon"), "bag_count": bag.get_meta("count")}
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


## Só a cabeça e o peito do primeiro quadro, para o retrato encher o medalhão.
func _bust(sheet: Texture2D, cell: Rect2) -> Rect2:
	var used := sheet.get_image().get_region(Rect2i(cell)).get_used_rect()
	if used.size.x <= 0:
		return cell
	var side := mini(used.size.x, roundi(used.size.y * 0.62))
	var center_x := used.position.x + used.size.x / 2
	return Rect2(cell.position + Vector2(center_x - side / 2, used.position.y), Vector2(side, side))


## Selo amarelo "LEVEL UP" em cima da carta do herói: aparece com pontos para gastar e
## é o único jeito de abrir a árvore pela party (tocar na carta só seleciona o herói).
func _level_up_badge(unit, index: int) -> Button:
	var badge := Button.new()
	badge.text = "LEVEL UP"
	badge.focus_mode = Control.FOCUS_NONE
	badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	badge.tooltip_text = "Abrir a árvore de talentos"
	Brass.style_button(badge, true)
	badge.add_theme_font_size_override("font_size", 15)
	badge.custom_minimum_size = LEVEL_UP_SIZE
	badge.size = LEVEL_UP_SIZE
	# As cartas têm tamanho fixo: o selo fica centrado em cima da carta `index`.
	var x: float = index * (hud.PARTY_CARD.x + CARD_GAP) + (hud.PARTY_CARD.x - LEVEL_UP_SIZE.x) / 2
	var top: Vector2 = hud.party_row.position + Vector2(x, -LEVEL_UP_SIZE.y - 6)
	badge.position = top
	badge.visible = false
	badge.pressed.connect(func(): hud.level_up_pressed.emit(unit))
	hud.add_child(badge)
	# Pula de leve para chamar atenção.
	var bounce := badge.create_tween().set_loops()
	bounce.tween_property(badge, "position:y", top.y - 5, 0.4).set_trans(Tween.TRANS_SINE)
	bounce.tween_property(badge, "position:y", top.y, 0.4).set_trans(Tween.TRANS_SINE)
	return badge


## Botãozinho da bolsa no topo da carta: ícone (roxo com Orbe) e quantos itens tem.
## Fica por cima do clique da carta: tocar nele abre a bolsa, não seleciona o herói.
func _bag_button(unit) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = Vector2(34, 22)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = "Bolsa"
	var flat := Brass.panel(Brass.WINE_DEEP, Brass.BRASS_DIM, 1, 4, 0, 0)
	var lit := Brass.panel(Brass.WINE_LIFT, Brass.BRASS, 1, 4, 0, 0)
	button.add_theme_stylebox_override("normal", flat)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("pressed", lit)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var icon: Control = hud._icon("bag", Brass.MUTED, 16)
	row.add_child(icon)
	var count := Brass.label("", 11, Brass.TEXT_LIT, 700)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	button.set_meta("icon", icon)
	button.set_meta("count", count)
	button.pressed.connect(func(): hud.bag_pressed.emit(unit))
	hud.sound_manager.bind_button(button, &"click3")
	return button


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
	button.add_theme_font_size_override("font_size", 18)
	Brass.style_button(button)
	button.add_theme_stylebox_override("normal", Brass.panel(Brass.WINE, Brass.BRASS, 2, 4, 8))
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
		var chosen: bool = unit == current
		var plate := Brass.panel(Color(Brass.WINE, 0.94), Brass.GOLD if chosen else Brass.BRASS_DIM, 2, 4, 4)
		plate.content_margin_left = 6
		card.panel.add_theme_stylebox_override("panel", plate)
		card.medal.add_theme_stylebox_override("panel", Brass.medal(Brass.WINE_DEEP, Brass.GOLD if chosen else Brass.BRASS_DIM, 3))
