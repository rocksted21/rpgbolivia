extends RefCounted

## Diário: o menu do jogo, aberto pelo botão do canto ou pelo ESC. Abas Party, Mochila,
## Missões e Ajustes (volume); ao lado, o resumo de onde a party está, salvar, carregar e o
## menu principal. Visual latão e vinho (scripts/hud/brass.gd), como a tela inicial.

const GameSettings = preload("res://scripts/game_settings.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Content = preload("res://scripts/town_content.gd")
const Town = preload("res://scripts/town_data.gd")
const Brass = preload("res://scripts/hud/brass.gd")

const DIARY := Rect2(44, 36, 1192, 648)
const SIDE_WIDTH := 250
const OPTIONS_CONFIRM_WIDTH := 460
const TABS := ["PARTY", "MOCHILA", "MISSÕES", "AJUSTES"]
const GOOD := Color("9fe39a")

var hud: BattleHud # a tela dona deste módulo
var tab_buttons: Array[Button] = []
var pages: Array[Control] = []
var current_tab := 0
var party_page: HBoxContainer
var bag_list: VBoxContainer
var quest_list: VBoxContainer
var summary: VBoxContainer


func _init(host: Node) -> void:
	hud = host


func _build_options() -> void:
	GameSettings.apply()
	hud.options_button = hud._icon_button("gear")
	hud.options_button.tooltip_text = "Diário e opções (Esc)"
	hud.options_button.pressed.connect(open_options)
	var layer := CanvasLayer.new()
	layer.layer = hud.layer + 10 # acima de tudo que o HUD cria depois (party, cidade, cartão)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS # o jogo fica pausado com o menu aberto
	hud.add_child(layer)
	hud.options_overlay = ColorRect.new()
	hud.options_overlay.color = Color(0.047, 0.024, 0.031, 0.8)
	hud.options_overlay.size = hud.SCREEN
	hud.options_overlay.visible = false
	layer.add_child(hud.options_overlay)
	var keys := KeyCatcher.new()
	keys.on_escape = _on_escape
	keys.on_tab = func(step: int) -> bool:
		if not options_open() or hud.quit_panel.visible:
			return false
		show_tab(posmod(current_tab + step, TABS.size()))
		return true
	layer.add_child(keys)

	hud.options_panel = PanelContainer.new()
	hud.options_panel.position = DIARY.position
	hud.options_panel.custom_minimum_size = DIARY.size
	hud.options_panel.size = DIARY.size
	hud.options_panel.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE, Brass.BRASS, 2, 6, 0, 4))
	hud.options_overlay.add_child(hud.options_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	hud.options_panel.add_child(column)
	column.add_child(_header())
	var line := ColorRect.new()
	line.color = Color(Brass.BRASS, 0.35)
	line.custom_minimum_size.y = 1
	column.add_child(line)
	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 30)
	body.add_theme_constant_override("margin_top", 22)
	body.add_theme_constant_override("margin_bottom", 24)
	column.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	body.add_child(row)
	var holder := Control.new() # as quatro páginas, uma por cima da outra
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(holder)
	party_page = HBoxContainer.new()
	party_page.add_theme_constant_override("separation", 14)
	_add_page(holder, party_page)
	bag_list = _list_page(holder)
	quest_list = _list_page(holder)
	_add_page(holder, _settings_page())
	row.add_child(_side())
	_build_quit()
	show_tab(0)


func _header() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	for index in TABS.size():
		var tab := Button.new()
		tab.text = TABS[index]
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(0, 46)
		tab.add_theme_font_override("font", Brass.font(700))
		tab.add_theme_font_size_override("font_size", 16)
		tab.pressed.connect(func(): show_tab(index))
		hud.sound_manager.bind_button(tab, &"click3")
		tab_buttons.append(tab)
		row.add_child(tab)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var help := Brass.label("Q / E troca de aba  ·  Esc volta", 13, Brass.DIM)
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(help)
	return margin


func _add_page(holder: Control, page: Control) -> void:
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(page)
	pages.append(page)


func _list_page(holder: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_add_page(holder, scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	return list


func _settings_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	var box := PanelContainer.new()
	box.custom_minimum_size.x = 520
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE_DEEP, Color(Brass.BRASS, 0.35), 1, 6, 20, 0))
	page.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)
	column.add_child(Brass.label("SOM", 14, Brass.GOLD, 700))
	hud.volume_label = Brass.label("", 18, Brass.TEXT)
	column.add_child(hud.volume_label)
	hud.volume_slider = HSlider.new()
	hud.volume_slider.min_value = 0
	hud.volume_slider.max_value = 100
	hud.volume_slider.step = 5
	hud.volume_slider.value = GameSettings.volume()
	hud.volume_slider.focus_mode = Control.FOCUS_NONE
	hud.volume_slider.custom_minimum_size.y = 36
	var track := Brass.panel(Brass.WINE, Brass.BRASS_DIM, 1, 4, 0, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	hud.volume_slider.add_theme_stylebox_override("slider", track)
	var filled := Brass.panel(Brass.FLAME, Brass.BRASS, 1, 4, 0, 0)
	hud.volume_slider.add_theme_stylebox_override("grabber_area", filled)
	hud.volume_slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	column.add_child(hud.volume_slider)
	hud.volume_mute = _side_button(column, "Silenciar")
	hud.volume_mute.toggle_mode = true
	hud.volume_mute.button_pressed = GameSettings.muted()
	hud.volume_slider.value_changed.connect(func(value: float):
		GameSettings.set_volume(int(value))
		if hud.volume_mute.button_pressed and value > 0.0: # mexer no volume tira do mudo
			hud.volume_mute.set_pressed_no_signal(false)
			GameSettings.set_muted(false)
		_show_volume())
	hud.volume_mute.toggled.connect(func(on: bool):
		GameSettings.set_muted(on)
		_show_volume())
	_show_volume()
	return page


## Coluna da direita: o resumo de onde a party está e os botões de sempre.
func _side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = SIDE_WIDTH
	side.add_theme_constant_override("separation", 10)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE_DEEP, Color(Brass.BRASS, 0.35), 1, 6, 16, 0))
	side.add_child(box)
	summary = VBoxContainer.new()
	summary.add_theme_constant_override("separation", 6)
	box.add_child(summary)
	hud.save_button = _side_button(side, "Salvar jogo")
	hud.save_button.pressed.connect(func(): hud.save_pressed.emit())
	hud.load_button = _side_button(side, "Carregar jogo")
	hud.load_button.clip_text = true
	hud.load_button.custom_minimum_size.y = 58
	hud.load_button.add_theme_font_size_override("font_size", 14)
	hud.load_button.pressed.connect(func(): hud.load_pressed.emit())
	hud.options_note = Brass.label("", 14, Brass.GOLD)
	hud.options_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.options_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.options_note.custom_minimum_size.x = SIDE_WIDTH
	side.add_child(hud.options_note)
	var quit := _side_button(side, "Menu principal")
	quit.pressed.connect(func():
		hud.options_panel.visible = false
		hud.quit_panel.visible = true
		_center(hud.quit_panel))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(gap)
	var back := _side_button(side, "Voltar ao jogo", true)
	back.custom_minimum_size.y = 52
	back.pressed.connect(close_options)
	return side


func _side_button(parent: Control, text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 44
	Brass.style_button(button, primary)
	button.add_theme_font_size_override("font_size", 16)
	hud.sound_manager.bind_button(button, &"click3")
	parent.add_child(button)
	return button


## Peças da janela do Grupo (hud.gd), no mesmo estilo do Diário.
func _options_box(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE, Brass.BRASS, 2, 6, 20, 4))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return panel


func _options_title(text: String) -> Label:
	var title := Brass.label(text, 24, Brass.GOLD, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _options_button(parent: Control, text: String) -> Button:
	var button := _side_button(parent, text)
	button.custom_minimum_size.y = 50
	button.add_theme_font_size_override("font_size", 18)
	return button


func _build_quit() -> void:
	hud.quit_panel = PanelContainer.new()
	hud.quit_panel.custom_minimum_size.x = OPTIONS_CONFIRM_WIDTH
	hud.quit_panel.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE, Brass.BRASS, 2, 6, 22, 4))
	hud.quit_panel.visible = false
	hud.options_overlay.add_child(hud.quit_panel)
	var confirm := VBoxContainer.new()
	confirm.add_theme_constant_override("separation", 14)
	hud.quit_panel.add_child(confirm)
	var title := Brass.label("Voltar ao menu principal?", 22, Brass.GOLD, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm.add_child(title)
	var warning := Brass.label("Você volta para a tela inicial. O que não foi salvo será perdido.", 16, Brass.TEXT)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size.x = OPTIONS_CONFIRM_WIDTH - 44
	confirm.add_child(warning)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	confirm.add_child(row)
	var ok := _side_button(row, "Sair", true)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func(): hud.quit_pressed.emit())
	var cancel := _side_button(row, "Cancelar")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func():
		hud.quit_panel.visible = false
		hud.options_panel.visible = true)


## Troca a aba à mostra: a ativa fica dourada e sublinhada pela chama.
func show_tab(index: int) -> void:
	current_tab = index
	for i in pages.size():
		var on := i == index
		pages[i].visible = on
		var tab := tab_buttons[i]
		var line := StyleBoxFlat.new()
		line.bg_color = Color(0, 0, 0, 0)
		line.border_color = Brass.FLAME
		line.border_width_bottom = 3 if on else 0
		line.content_margin_left = 20
		line.content_margin_right = 20
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			tab.add_theme_stylebox_override(state, line)
		var ink := Brass.GOLD if on else Brass.MUTED
		for key in ["font_color", "font_pressed_color", "font_focus_color"]:
			tab.add_theme_color_override(key, ink)
		tab.add_theme_color_override("font_hover_color", Brass.GOLD if on else Brass.TEXT_LIT)


# --- Conteúdo das abas, refeito a cada abertura ----------------------------------

func _refresh() -> void:
	_fill_party()
	_fill_bag()
	_fill_quests()
	_fill_summary()
	var count := TownProgress.quests_with("ready").size() + TownProgress.quests_with("active").size()
	tab_buttons[2].text = "MISSÕES (%d)" % count if count > 0 else "MISSÕES"


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _fill_party() -> void:
	_clear(party_page)
	for unit in hud.party_cards:
		party_page.add_child(_hero_card(unit))


## Ficha do herói: ele em pé, vida, experiência e o atalho para a árvore de skills.
func _hero_card(unit) -> Control:
	var info: Dictionary = hud.party_info.get(unit, {})
	var points: int = info.get("points", 0)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE_DEEP, Brass.BRASS if points > 0 else Color(Brass.BRASS, 0.3), 1, 6, 0, 0))
	card.modulate.a = 1.0 if unit.alive() else 0.55
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var stage := PanelContainer.new() # o herói em pé, grande
	stage.custom_minimum_size.y = 210
	stage.add_theme_stylebox_override("panel", Brass.panel(Color("1f0e12"), Color(0, 0, 0, 0), 0, 6, 0, 0))
	column.add_child(stage)
	var figure := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % unit.type_id)
	atlas.region = Rect2(0, 0, hud.meta[unit.type_id]["cell_w"], hud.meta[unit.type_id]["cell_h"])
	figure.texture = atlas
	figure.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	figure.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	figure.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.add_child(figure)
	if points > 0:
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", Brass.panel(Brass.FLAME, Brass.FLAME, 0, 10, 0, 0))
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		badge.add_child(Brass.label(" +%d ponto%s " % [points, "" if points == 1 else "s"], 12, Brass.WINE_DEEP, 700))
		stage.add_child(badge)
	var text := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		text.add_theme_constant_override("margin_" + side, 14)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(text)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 7)
	text.add_child(lines)
	var name_label := Brass.label(unit.display_name, 16, Brass.TEXT_LIT, 700)
	name_label.clip_text = true
	lines.add_child(name_label)
	lines.add_child(Brass.label("Nível %d" % info["level"] if info.has("level") else "", 12, Brass.DIM))
	lines.add_child(_stat_line("Vida", "%d/%d" % [unit.hp, unit.max_hp] if unit.alive() else "caído"))
	lines.add_child(_bar(float(unit.hp) / maxi(1, unit.max_hp), Brass.HP, 6))
	if info.has("fraction"):
		lines.add_child(_stat_line("XP", "%d%%" % roundi(clampf(info["fraction"], 0.0, 1.0) * 100)))
		lines.add_child(_bar(info["fraction"], Brass.GOLD, 4))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lines.add_child(gap)
	if info.get("mine", false):
		var tree := _side_button(lines, "Árvore de skills")
		tree.custom_minimum_size.y = 38
		tree.add_theme_font_size_override("font_size", 14)
		tree.add_theme_color_override("font_color", Brass.GOLD)
		tree.pressed.connect(func():
			close_options()
			hud.level_up_pressed.emit(unit))
	return card


func _stat_line(left: String, right: String) -> Control:
	var row := HBoxContainer.new()
	var name_label := Brass.label(left, 12, Brass.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(Brass.label(right, 12, Brass.TEXT))
	return row


func _bar(fraction: float, color: Color, height: int) -> Control:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = clampf(fraction, 0.0, 1.0)
	bar.custom_minimum_size.y = height
	bar.add_theme_stylebox_override("background", Brass.panel(Color("3a2a2a"), Color(0, 0, 0, 0), 0, 3, 0, 0))
	bar.add_theme_stylebox_override("fill", Brass.panel(color, color, 0, 3, 0, 0))
	return bar


func _fill_bag() -> void:
	_clear(bag_list)
	bag_list.add_child(Brass.label("MOCHILA", 14, Brass.GOLD, 700))
	var carrying := false
	for id in Content.ITEM_ORDER:
		var count := TownProgress.item_count(id)
		if count <= 0:
			continue
		carrying = true
		bag_list.add_child(_entry("%d× %s" % [count, Content.ITEMS[id]["name"]], Content.ITEMS[id]["text"]))
	if not carrying:
		bag_list.add_child(Brass.label("Vazia. A Mercadora fica na praça da Cidade-Farol.", 15, Brass.DIM))


func _fill_quests() -> void:
	_clear(quest_list)
	var names := {}
	for person in Town.people():
		names[person["id"]] = person["name"]
	var sections := [["ready", "PRONTAS PARA ENTREGAR", GOOD], ["active", "EM ANDAMENTO", Brass.GOLD], ["available", "PEDIDOS NOVOS", Brass.TEXT]]
	var any := false
	for section in sections:
		var quests: Array = TownProgress.quests_with(section[0])
		if quests.is_empty():
			continue
		any = true
		quest_list.add_child(Brass.label(section[1], 14, section[2], 700))
		for id in quests:
			var quest: Dictionary = Content.QUESTS[id]
			var progress := " (%d/%d)" % [TownProgress.quest_progress(id), quest["target"]] if section[0] != "available" else ""
			quest_list.add_child(_entry(quest["title"] + progress, "%s Fale com: %s." % [quest["goal"], names.get(quest["giver"], "?")]))
	if not any:
		quest_list.add_child(Brass.label(Content.NOTHING_TEXT, 15, Brass.DIM))


## Uma linha das listas: nome em destaque e a explicação embaixo, numa ficha escura.
func _entry(title: String, text: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE_DEEP, Color(Brass.BRASS, 0.25), 1, 6, 14, 0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)
	column.add_child(Brass.label(title, 16, Brass.TEXT_LIT, 700))
	var detail := Brass.label(text, 14, Brass.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)
	return box


## Os mesmos números do topo da tela, para conferir com o jogo pausado.
func _fill_summary() -> void:
	_clear(summary)
	var place: String = hud.overview_title.text if hud.overview_title != null else ""
	summary.add_child(Brass.label("CIDADE" if place == "Cidade-Farol" else "EXPEDIÇÃO", 12, Brass.GOLD, 700))
	if place != "":
		var title := Brass.label(place, 16, Brass.TEXT_LIT, 700)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_child(title)
	for stat in hud.overview_stats:
		summary.add_child(_stat_line(str(stat["label"]), str(stat["value"])))


# --- Abrir e fechar ---------------------------------------------------------------

## Salvar só com `save_allowed` (fora do online, partida em andamento); carregar, com `load_allowed`.
func open_options() -> void:
	var can_load := SaveGame.exists()
	hud.card_ui.hide_card()
	hud.save_button.disabled = not hud.save_allowed
	hud.load_button.disabled = not can_load or not hud.load_allowed
	hud.load_button.text = "Carregar jogo" if not can_load else "Carregar jogo\n%s" % SaveGame.summary()
	hud.options_note.text = ""
	_refresh()
	hud.options_panel.visible = true
	hud.quit_panel.visible = false
	hud.options_overlay.visible = true
	_center(hud.quit_panel)
	hud.options_toggled.emit(true)


func close_options() -> void:
	hud.options_overlay.visible = false
	hud.options_toggled.emit(false)


func options_open() -> bool:
	return hud.options_overlay.visible


## ESC: na confirmação de sair, volta para o Diário; no Diário, fecha o menu.
## Devolve se usou a tecla (com o menu fechado, ela segue para o jogo).
func _on_escape() -> bool:
	if not options_open():
		return false
	if hud.quit_panel.visible:
		hud.quit_panel.visible = false
		hud.options_panel.visible = true
	else:
		close_options()
	return true


## Pega ESC (e Q/E com o Diário aberto) antes do jogo. Fica na camada do menu, que roda
## mesmo com o jogo pausado.
class KeyCatcher extends Node:
	var on_escape: Callable
	var on_tab: Callable

	func _input(event: InputEvent) -> void:
		if not (event is InputEventKey and event.pressed and not event.echo):
			return
		var used := false
		if event.keycode == KEY_ESCAPE:
			used = on_escape.call()
		elif event.keycode == KEY_Q or event.keycode == KEY_E:
			used = on_tab.call(-1 if event.keycode == KEY_Q else 1)
		if used:
			get_viewport().set_input_as_handled()


func show_options_note(text: String) -> void:
	hud.options_note.text = text


func _center(panel: Control) -> void:
	panel.reset_size()
	panel.position = (hud.SCREEN - panel.get_combined_minimum_size()) / 2


func _show_volume() -> void:
	hud.volume_label.text = "Volume: sem som" if GameSettings.muted() or GameSettings.volume() == 0 else "Volume: %d%%" % GameSettings.volume()
