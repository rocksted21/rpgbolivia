extends RefCounted

## Menu de ações que abre em cima da casa tocada.

const Data = preload("res://scripts/game_data.gd")

const CAST_INK := Color(0.72, 0.33, 0.0)
const DISABLED_FILL := Color(0.86, 0.85, 0.8)
const DISABLED_INK := Color(0.4, 0.4, 0.42)
const MENU_GAP := 56.0 # distância do centro da casa até o menu, para não cobrir quem foi tocado
const OPTION_HEIGHT := 72
const MENU_VISIBLE_OPTIONS := 5

var hud: BattleHud # a tela dona deste módulo


func _init(host: Node) -> void:
	hud = host


func menu_open() -> bool:
	return hud.menu.visible


## Abre o menu ao lado de `anchor` (centro da casa, em coordenadas de tela).
## Cada opção é {label, detail, tone}; tone escolhe a cor do detalhe.
func show_menu(anchor: Vector2, title: String, title_team: int, info: String, options: Array) -> void:
	hide_menu()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	hud.menu.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var name_label := hud._label(title, 26, hud.MENU_INK if title_team < 0 else (hud.PLAYER_INK if title_team == Data.Team.PLAYER else hud.DAMAGE_INK))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	if info != "":
		var info_label := hud._label(info, 18, hud.MENU_INK)
		column.add_child(info_label)

	# Muitas opções (o Mago de Fogo tem 13 magias): a lista rola e o menu cabe na tela.
	var list: VBoxContainer = column
	if options.size() > MENU_VISIBLE_OPTIONS:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = MENU_VISIBLE_OPTIONS * (OPTION_HEIGHT + 8)
		column.add_child(scroll)
		list = VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
	for i in options.size():
		hud.menu_buttons.append(_add_option(list, options[i], i))
	if list != column: # sem rolagem lateral: a lista define a largura, mais a barra
		list.get_parent().custom_minimum_size.x = list.get_combined_minimum_size().x + 16
	var footer := hud._label("Toque fora para fechar", 16, hud.MENU_INK)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	hud.menu.reset_size()
	var size := hud.menu.get_combined_minimum_size()
	var x := anchor.x + MENU_GAP
	if x + size.x > hud.SCREEN.x - hud.MARGIN:
		x = anchor.x - MENU_GAP - size.x
	# A câmera baixa deixa espaço acima do campo. Usa esse espaço quando couber,
	# para manter as casas vizinhas livres para fechar o menu ou mudar de alvo.
	var y := anchor.y - size.y - MENU_GAP
	if y < hud.MARGIN:
		y = anchor.y - size.y / 2
	hud.menu.position = Vector2(clampf(x, hud.MARGIN, hud.SCREEN.x - hud.MARGIN - size.x), clampf(y, hud.MARGIN, hud.SCREEN.y - hud.MARGIN - size.y))
	hud.menu.visible = true
	hud.sound_manager.play_ui(&"switch3")


func hide_menu() -> void:
	hud.menu.visible = false
	hud.menu_buttons.clear()
	for child in hud.menu.get_children():
		hud.menu.remove_child(child)
		child.queue_free()


func _add_option(column: VBoxContainer, option: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = OPTION_HEIGHT
	button.focus_mode = Control.FOCUS_NONE
	var fill := Color.WHITE if option.get("kind", "") == "cancel" else hud.OPTION_FILL # Cancelar não compete com a ação
	button.add_theme_stylebox_override("normal", hud._box(fill, Color(0.9, 0.85, 0.71), 2 if fill == Color.WHITE else 0, 12, 0))
	button.add_theme_stylebox_override("hover", hud._box(fill.lightened(0.25) if fill != Color.WHITE else Color(0.96, 0.94, 0.88), fill, 0, 12, 0))
	button.add_theme_stylebox_override("pressed", hud._box(fill.darkened(0.15), fill, 0, 12, 0))
	button.add_theme_stylebox_override("disabled", hud._box(DISABLED_FILL, DISABLED_FILL, 0, 12, 0))
	button.disabled = option.get("disabled", false)
	hud.sound_manager.bind_button(button, &"click2" if option.get("kind", "") == "cancel" else &"click1")
	button.pressed.connect(func(): hud.option_pressed.emit(index))
	column.add_child(button)

	# Nome à esquerda e o efeito (dano, cura) à direita, como no mockup.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	button.add_child(row)
	var ink := DISABLED_INK if button.disabled else hud.MENU_INK
	var name_label := hud._label(option["label"], 24, ink)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if option.has("note"):
		# Magia carregada: embaixo do nome, a ampulheta com quanto tempo até sair.
		var stack := VBoxContainer.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_theme_constant_override("separation", 0)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stack.add_child(name_label)
		var wait := HBoxContainer.new()
		wait.add_theme_constant_override("separation", 4)
		wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hourglass := hud._icon(option.get("note_icon", "hourglass"), CAST_INK, 18) # efeito extra usa outro ícone
		hourglass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wait.add_child(hourglass)
		wait.add_child(hud._label(option["note"], 17, CAST_INK))
		stack.add_child(wait)
		row.add_child(stack)
	else:
		row.add_child(name_label)
	var tone: String = option.get("tone", "")
	var detail := hud._label(option["detail"], 26 if tone != "" else 18, hud.DAMAGE_INK if tone == "damage" else (hud.HEAL_INK if tone == "heal" else ink))
	detail.size_flags_vertical = Control.SIZE_FILL
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(detail)
	# A linha fica sobreposta ao botão (não é contêiner): a largura mínima vem dela.
	button.custom_minimum_size.x = row.get_combined_minimum_size().x + 32 + row.get_theme_constant("separation")
	return button
