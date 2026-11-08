extends CanvasLayer
class_name BattleHud

# Resolve services after the content pack is mounted by the thin installer.
var sound_manager:
	get: return get_node("/root/SoundManager")

## Interface: fila de turnos à esquerda e um menu que abre em cima da casa tocada.

const GameSettings = preload("res://scripts/game_settings.gd")
const END_TURN_WIDTH := 150.0
const SaveGame = preload("res://scripts/save_game.gd")
const OPTIONS_WIDTH := 136
const OPTIONS_Y := 74

@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal option_pressed(index: int)
signal order_toggled(on: bool)
signal restart_pressed
signal skills_pressed
signal menu_pressed
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal party_pressed(unit)
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal level_up_pressed(unit) # selo LEVEL UP em cima da carta: abrir a árvore
signal bag_pressed(unit) # botão da bolsa na carta: abrir a bolsa do herói (hud/hero_bag_ui.gd)
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal rotate_held(direction: int) # -1 ou 1 enquanto o botão está apertado; 0 ao soltar
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal together_toggled(on: bool)
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal unit_picked(unit)
signal potion_pressed
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal end_turn_pressed
signal jump_pressed
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal save_pressed
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal load_pressed
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal quit_pressed
@warning_ignore("unused_signal") # quem emite é um componente em scripts/hud/
signal options_toggled(open: bool)
signal zoom_toggled(on: bool)
signal group_pressed
signal group_assign(unit, player_id: int)
signal open_room_pressed
signal leave_room_pressed

const Data = preload("res://scripts/game_data.gd")
const SpellPreview = preload("res://scripts/spell_preview.gd")
const Icon = preload("res://scripts/icon.gd")
const UnitView = preload("res://scripts/unit_view.gd")
# Fontes escolhidas no mockup; enquanto os arquivos não estiverem no projeto, vale a padrão.
const TITLE_FONT_PATH := "res://assets/fonts/LilitaOne-Regular.ttf"
const BODY_FONT_PATH := "res://assets/fonts/Fredoka-Medium.ttf"

const PLAYER_COLOR := Color(0.35, 0.65, 1.0)
const ENEMY_COLOR := Color(0.95, 0.35, 0.3)
const ACTIVE_COLOR := Color(1.0, 0.84, 0.35)
const TIMELINE_Y := 18.0
const MENU_FILL := Color(1.0, 0.97, 0.88)
const MENU_INK := Color(0.11, 0.12, 0.15)
const OPTION_FILL := Color(1.0, 0.84, 0.32)
const DAMAGE_INK := Color(0.66, 0.13, 0.09)
const HEAL_INK := Color(0.1, 0.45, 0.2)
const PLAYER_INK := Color(0.12, 0.37, 0.66)
const SCREEN := Vector2(1280, 720)
const MARGIN := 12.0
const MENU_WIDTH := 340.0
const SHOW_ORDER_TEXT := "Mostrar ordem"
const HIDE_ORDER_TEXT := "Esconder ordem"
const HP_ENEMY := Color(0.89, 0.29, 0.23)
const ANIM_IDLE := 0
# Painel do topo (exploração): latão e vinho, como a tela inicial (scripts/hud/brass.gd).
const Brass = preload("res://scripts/hud/brass.gd")
const PANEL_FILL := Color(0.165, 0.075, 0.098, 0.94)
const PANEL_EDGE := Color("f2ca76")
const PANEL_TEXT := Color("f4dcb8")
const PANEL_MUTED := Color("cdb596")
const RADAR_SIZE := 106.0 # bússola, pendurada à esquerda da faixa do topo
const RADAR_TOP := 6.0
const RADAR_LEFT := 14.0
const STRIP_HEIGHT := 44.0
const DOCK_BUTTON := 64.0 # botões da coluna da direita: do tamanho de um dedo
const STRIP_WIDTH := SCREEN.x - MARGIN - DOCK_BUTTON - 16 # faixa do topo: até a coluna de botões
const DOCK_GAP := 8
const PARTY_CARD := Vector2(228, 92)
const HudOptions = preload("res://scripts/hud/options_menu.gd")
const HudCard = preload("res://scripts/hud/unit_card.gd")
const HudActionMenu = preload("res://scripts/hud/action_menu.gd")
const HudPartyBar = preload("res://scripts/hud/party_bar.gd")
const HudTimeline = preload("res://scripts/hud/timeline.gd")
const HudHeroBag = preload("res://scripts/hud/hero_bag_ui.gd")

var timeline: VBoxContainer
var hint: Label
var order_button: Button
var menu: PanelContainer
var menu_buttons := []
var end_panel: PanelContainer
var end_label: Label
var end_note: Label
var skills_button: Button
var card: Control
var card_spell: Control
var title_font: Font
var card_atlas: AtlasTexture
var card_info := {}
var card_row := ANIM_IDLE
var card_time := 0.0
var meta := {}
var highlighted = null # unidade em foco, vinda do mapa ou da fila
var last_state = null
var timeline_units := []
var timeline_tween: Tween
var cast_preview := {} # {mago: tempo da magia} enquanto o menu oferece uma magia carregada


var overview: Control
var overview_left: PanelContainer # a faixa do topo
var overview_numbers: HBoxContainer
var overview_radar
var overview_title: Label
var overview_key := ""
var overview_cells := [] # {value, icon} na ordem dos números
var overview_text := "" # o painel em uma linha (testes)
var overview_stats := [] # os números do topo, repetidos no Diário
var party_info := {} # herói -> {level, fraction, points, mine}, para o Diário
var group_button: Button
var group_layer: CanvasLayer
var legend_layer: CanvasLayer # legenda da bússola, aberta ao clicar nela
var dock: VBoxContainer # coluna de botões à direita, espelhando a fila de turnos à esquerda
var quest_chip: PanelContainer
var zoom_button: Button
var potion_button: Button
var tracker: Label
var options_button: Button
var options_overlay: ColorRect
var options_panel: PanelContainer
var quit_panel: PanelContainer
var options_note: Label
var volume_label: Label
var save_button: Button
var load_button: Button
var save_allowed := true # falso no online e depois do fim da partida
var load_allowed := true # falso no online
var volume_slider: HSlider
var volume_mute: Button
var detail: Label
var end_menu_button: Button
var party_row: HBoxContainer
var party_cards := {} # herói -> {panel, fill, status, level, xp, points, level_up}
var together_button: Button
var end_turn_button: Button
var jump_button: Button
var banner: Label
var options_ui := HudOptions.new(self) # menu de opções: volume, salvar, carregar e sair
var card_ui := HudCard.new(self) # ficha da unidade
var menu_ui := HudActionMenu.new(self) # menu de ações em cima da casa
var party_ui := HudPartyBar.new(self) # barra da party e botões do canto
var timeline_ui := HudTimeline.new(self) # fila de turnos à esquerda
var bag_ui := HudHeroBag.new(self) # bolsa de cada herói (Orbe de Talento)


func setup(p_meta: Dictionary) -> void:
	meta = p_meta
	if ResourceLoader.exists(TITLE_FONT_PATH):
		title_font = load(TITLE_FONT_PATH)
	if ResourceLoader.exists(BODY_FONT_PATH):
		var theme := Theme.new()
		theme.default_font = load(BODY_FONT_PATH)
		get_tree().root.theme = theme
	timeline = VBoxContainer.new()
	timeline.position = Vector2(MARGIN, TIMELINE_Y)
	timeline.add_theme_constant_override("separation", 5)
	add_child(timeline)

	dock = VBoxContainer.new()
	dock.position = Vector2(SCREEN.x - MARGIN - DOCK_BUTTON, MARGIN)
	dock.add_theme_constant_override("separation", DOCK_GAP)
	add_child(dock)
	zoom_button = _icon_button("zoom_in")
	zoom_button.toggle_mode = true
	zoom_button.tooltip_text = "Aproximar (Z ou roda do mouse). Aproximado, arraste o chão para mover a câmera."
	zoom_button.toggled.connect(func(on):
		_show_zoom(on)
		zoom_toggled.emit(on))
	order_button = _icon_button("hourglass")
	order_button.toggle_mode = true
	order_button.tooltip_text = SHOW_ORDER_TEXT
	order_button.toggled.connect(_on_order_toggled)

	hint = Label.new()
	hint.position = Vector2(90, 676)
	hint.custom_minimum_size = Vector2(1110, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1.0, 0.88, 0.54))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.visible = false # sem textos de ajuda embaixo: a tela fica limpa
	add_child(hint)

	menu = PanelContainer.new()
	menu.custom_minimum_size.x = MENU_WIDTH
	menu.add_theme_stylebox_override("panel", _box(MENU_FILL, MENU_INK, 3, 16, 12))
	menu.visible = false
	add_child(menu)

	end_panel = PanelContainer.new()
	end_panel.position = Vector2(480, 290)
	end_panel.custom_minimum_size = Vector2(320, 140)
	end_panel.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE, Brass.BRASS, 2, 4, 14))
	end_panel.visible = false
	add_child(end_panel)
	var end_column := VBoxContainer.new()
	end_column.alignment = BoxContainer.ALIGNMENT_CENTER
	end_panel.add_child(end_column)
	end_label = Brass.label("", 30, Brass.GOLD, 700)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_column.add_child(end_label)
	end_note = Brass.label("", 18, Brass.TEXT)
	end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_note.visible = false
	end_column.add_child(end_note)
	var restart := Button.new()
	restart.text = "Lutar de novo"
	restart.custom_minimum_size.y = 56
	Brass.style_button(restart, true)
	restart.add_theme_font_size_override("font_size", 20)
	sound_manager.bind_button(restart, &"click3")
	restart.pressed.connect(func(): restart_pressed.emit())
	end_column.add_child(restart)
	skills_button = Button.new()
	skills_button.text = "Árvore de skills"
	skills_button.custom_minimum_size.y = 48
	Brass.style_button(skills_button)
	skills_button.add_theme_font_size_override("font_size", 18)
	sound_manager.bind_button(skills_button)
	skills_button.pressed.connect(func(): skills_pressed.emit())
	end_column.add_child(skills_button)

	options_ui._build_options()

	# Cartão de detalhes: cobre a tela toda para que o toque que fecha não caia no tabuleiro.
	card = ColorRect.new()
	card.color = Color(0, 0, 0, 0.55)
	card.size = SCREEN
	card.visible = false
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			card_ui.hide_card())
	add_child(card)


func refresh(state) -> void:
	timeline_ui._refresh_timeline(state)


## Selo arredondado com ícone e texto, usado nos atributos e nas habilidades.
func _pill(icon_kind: String, icon_color: Color, text: String, fill: Color, ink: Color, height: int, font_size: int) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.custom_minimum_size.y = height
	pill.add_theme_stylebox_override("panel", _box(fill, fill, 0, 12, 10))
	var center := CenterContainer.new()
	pill.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	center.add_child(row)
	row.add_child(_icon(icon_kind, icon_color, font_size))
	var label := _title(text, font_size, ink)
	row.add_child(label)
	return pill


func _icon(kind: String, color: Color, size: float) -> Control:
	var icon := Icon.new()
	icon.setup(kind, color, size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


## Texto de título e números: usa a Lilita One se o arquivo estiver no projeto.
func _title(text: String, size: int, color: Color) -> Label:
	var label := _label(text, size, color)
	if title_font != null:
		label.add_theme_font_override("font", title_font)
	return label


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _process(delta: float) -> void:
	if card.visible:
		card_time += delta
		card_ui._update_card_frame()


## Selo do golpe: espada e o dano em branco no vermelho; se derruba, caveira e "ABATE".
func _hit_badge(option: Dictionary) -> Control:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if option.get("flank", false):
		var flank := _title("COSTAS", 16, DAMAGE_INK)
		flank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_child(flank)
	if option.get("lethal", false):
		holder.add_child(_badge("skull", "ABATE", Color(0.12, 0.1, 0.12), Color(1.0, 0.82, 0.35)))
	else:
		holder.add_child(_badge("sword", str(option["damage"]), Color(0.78, 0.16, 0.12), Color.WHITE))
	return holder


func _badge(icon_kind: String, text: String, fill: Color, ink: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	var style := _box(fill, fill.darkened(0.35), 2, 12, 0)
	style.content_margin_left = 10
	style.content_margin_right = 12 if text != "" else 10
	badge.add_theme_stylebox_override("panel", style)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.custom_minimum_size.y = 46
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(line)
	line.add_child(_icon(icon_kind, ink, 24))
	if text != "":
		var value := _title(text, 28, ink)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
	return badge


## Quando a unidade age: ampulheta e "2º"; a próxima a agir fica vermelha; quem ainda não
## viu o grupo mostra o olho fechado.
func _turn_badge(status: Dictionary) -> Control:
	if status.get("unaware", false):
		return _badge("eye_off", "", Color(0.4, 0.42, 0.48), Color.WHITE)
	var order: int = status.get("order", 0)
	var soon := order > 0 and order <= 2
	return _badge("hourglass", "%dº" % order if order > 0 else "–", Color(0.78, 0.16, 0.12) if soon else Color(0.29, 0.31, 0.37), Color.WHITE)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _on_order_toggled(on: bool) -> void:
	order_button.tooltip_text = HIDE_ORDER_TEXT if on else SHOW_ORDER_TEXT
	order_toggled.emit(on)


## Prepara a tela para a exploração: mostra o progresso e oferece voltar ao menu no fim.
func setup_exploration() -> void:
	order_button.visible = false
	_build_overview()
	var end_column: Node = end_label.get_parent()
	end_panel.position = Vector2(320, 240)
	end_panel.custom_minimum_size = Vector2(640, 200)
	end_label.add_theme_font_size_override("font_size", 26)
	for child in end_column.get_children():
		if child is Button and child != skills_button:
			child.text = "Nova jornada"
	var menu_button := Button.new()
	end_menu_button = menu_button
	menu_button.text = "Menu principal"
	menu_button.custom_minimum_size.y = 56
	Brass.style_button(menu_button)
	menu_button.add_theme_font_size_override("font_size", 18)
	sound_manager.bind_button(menu_button, &"click3")
	menu_button.pressed.connect(func(): menu_pressed.emit())
	end_column.add_child(menu_button)


## Botão "Pular", logo acima de "Encerrar turno". `active`: o modo pulo está ligado.
func show_jump(on: bool, active := false) -> void:
	if jump_button == null:
		if not on:
			return
		jump_button = party_ui._corner_button("Pular", Vector2(SCREEN.x - END_TURN_WIDTH - MARGIN, SCREEN.y - MARGIN - PARTY_CARD.y - 8 - 56), END_TURN_WIDTH)
		jump_button.custom_minimum_size.y = 56
		jump_button.pressed.connect(func(): jump_pressed.emit())
	jump_button.text = "Cancelar pulo" if active else "Pular"
	jump_button.visible = on


## Botão quadrado só com ícone, do tamanho de um dedo.
func _icon_button(kind: String) -> Button:
	var button := party_ui._corner_button("", Vector2.ZERO, DOCK_BUTTON)
	button.custom_minimum_size.y = DOCK_BUTTON
	button.reparent(dock)
	Brass.style_button(button, false, true)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(center)
	center.add_child(_icon(kind, PANEL_TEXT, 34))
	return button


func _show_zoom(on: bool) -> void:
	_set_icon(zoom_button, "zoom_out" if on else "zoom_in")


func _set_icon(button: Button, kind: String) -> void:
	var icon = button.get_child(0).get_child(0)
	icon.kind = kind
	icon.queue_redraw()


## Sincroniza o botão quando o zoom muda por gesto ou tecla.
func set_zoomed(on: bool) -> void:
	zoom_button.set_pressed_no_signal(on)
	_show_zoom(on)


## Online: quem joga com cada herói aparece no nome da carta ("Ana · Guardião").
func set_party_owners(names: Dictionary) -> void:
	for unit in party_cards:
		var owner: String = names.get(unit, "")
		party_cards[unit].name.text = unit.display_name if owner == "" else "%s · %s" % [owner, unit.display_name]


## Botão do grupo na coluna da direita (jornada e online): abre a sala e distribui os heróis.
func show_group_button(on: bool) -> void:
	if group_button == null:
		if not on:
			return
		group_button = _icon_button("people_plus")
		group_button.tooltip_text = "Grupo: jogar com amigos"
		group_button.pressed.connect(func(): group_pressed.emit())
		dock.move_child(group_button, mini(4, dock.get_child_count() - 1))
	group_button.visible = on


func group_open() -> bool:
	return group_layer != null


func hide_group() -> void:
	if group_layer != null:
		group_layer.queue_free()
		group_layer = null


## Janela do grupo. data: {online, is_host, me, code, players {id: nome}, heroes [{unit, type_id, owner}]}.
## Fora do online: um botão grande para abrir a sala. Dono: toca no nome de um jogador na linha
## do herói para passar o herói para ele. Os outros só veem quem joga com quem.
func show_group(data: Dictionary) -> void:
	hide_group()
	group_layer = CanvasLayer.new()
	group_layer.layer = layer + 5
	add_child(group_layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = SCREEN
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			hide_group())
	group_layer.add_child(shade)
	var box := options_ui._options_box(720)
	group_layer.add_child(box)
	var column: VBoxContainer = box.get_child(0)
	column.add_theme_constant_override("separation", 12)
	column.add_child(options_ui._options_title("Grupo"))
	var players: Dictionary = data.get("players", {})
	if not data.get("online", false):
		var note := _label("Abra a sala e passe o código: seus amigos entram no meio da jornada e você escolhe com qual herói cada um joga. Níveis, talentos e itens são os do seu save.", 20, PANEL_TEXT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 680
		column.add_child(note)
		var open := options_ui._options_button(column, "Abrir sala para amigos")
		open.pressed.connect(func():
			hide_group()
			open_room_pressed.emit())
	else:
		var code := _title("Código da sala:  %s" % data.get("code", ""), 30, PANEL_EDGE)
		code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(code)
		var who := _label("Na sala: " + ", ".join(players.values()), 20, PANEL_MUTED)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		who.custom_minimum_size.x = 680
		column.add_child(who)
		if data.get("is_host", false) and players.size() > 1:
			var tip := _label("Toque no nome de quem vai jogar com cada herói.", 18, PANEL_MUTED)
			tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(tip)
		for hero in data.get("heroes", []):
			column.add_child(_group_row(hero, players, data.get("is_host", false)))
		var leave := options_ui._options_button(column, "Fechar a sala" if data.get("is_host", false) else "Sair da sala")
		leave.pressed.connect(func():
			hide_group()
			leave_room_pressed.emit())
	var back := options_ui._options_button(column, "Voltar ao jogo")
	back.pressed.connect(hide_group)
	options_ui._center(box)


## Cada símbolo da bússola: ícone, cor e o que significa. As cores seguem expedition_data.LANDMARKS.
const COMPASS_LEGEND := [
	{"icon": "lighthouse", "color": Color(1.0, 0.85, 0.35), "name": "Farol", "text": "Objetivo final."},
	{"icon": "lantern", "color": Color("ffd36b"), "name": "Lanterna", "text": "Acenda para achar o farol."},
	{"icon": "shield", "color": Color("ff6858"), "name": "Forte", "text": "Luta dura, cofre grande."},
	{"icon": "house", "color": Color("7fb6ff"), "name": "Vila", "text": "Salve e ganhe um morador."},
	{"icon": "ruin", "color": Color("f2ca76"), "name": "Ruínas", "text": "Brasas. Pode ter emboscada."},
	{"icon": "drop", "color": Color("7ff0c8"), "name": "Fonte", "text": "Cura a party."},
	{"icon": "star", "color": Color("d6a6ff"), "name": "Memória", "text": "Dá experiência."},
	{"icon": "chest", "color": Color("f5b52e"), "name": "Baú", "text": "Brasas e poção."},
	{"icon": "swords", "color": Color("ff9d5c"), "name": "Desafio", "text": "Arena. Dá Chama Viva."},
	{"icon": "tent", "color": Color(0.85, 0.7, 0.5), "name": "Acampamento", "text": "Inimigos e brasas."},
	{"icon": "eye_off", "color": Color("b9a8e6"), "name": "Névoa Densa", "text": "Alguém se esconde ali."},
]


func show_compass_legend() -> void:
	hide_compass_legend()
	legend_layer = CanvasLayer.new()
	legend_layer.layer = layer + 5
	add_child(legend_layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = SCREEN
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			hide_compass_legend())
	legend_layer.add_child(shade)
	var box := options_ui._options_box(1100)
	legend_layer.add_child(box)
	var column: VBoxContainer = box.get_child(0)
	column.add_theme_constant_override("separation", 14)
	column.add_child(options_ui._options_title("Bússola"))
	var intro := _label("Cada ícone aponta para o lugar. Anel dourado = XP.", 24, PANEL_MUTED)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(intro)
	var grid := GridContainer.new() # 2 colunas: letra grande e tudo cabe na tela
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 14)
	column.add_child(grid)
	for entry in COMPASS_LEGEND:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.custom_minimum_size.x = 500
		var icon := _icon(entry["icon"], entry["color"], 52)
		icon.custom_minimum_size = Vector2(58, 58)
		row.add_child(icon)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_child(_title(entry["name"], 30, entry["color"]))
		words.add_child(_label(entry["text"], 24, PANEL_TEXT))
		row.add_child(words)
		grid.add_child(row)
	var back := options_ui._options_button(column, "Fechar")
	back.pressed.connect(hide_compass_legend)
	options_ui._center(box)


func hide_compass_legend() -> void:
	if legend_layer != null:
		legend_layer.queue_free()
		legend_layer = null


func _group_row(hero: Dictionary, players: Dictionary, is_host: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var face := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % hero["type_id"])
	atlas.region = Rect2(0, 0, meta[hero["type_id"]]["cell_w"], meta[hero["type_id"]]["cell_h"])
	face.texture = atlas
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(56, 56)
	row.add_child(face)
	var name_label := _title(hero["unit"].display_name, 22, PANEL_TEXT)
	name_label.custom_minimum_size.x = 170
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	for id in players:
		var mine: bool = hero["owner"] == id
		if not is_host and not mine:
			continue
		var chip := Button.new()
		chip.text = players[id]
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(0, 52)
		chip.add_theme_font_size_override("font_size", 20)
		chip.add_theme_color_override("font_color", MENU_INK if mine else PANEL_TEXT)
		chip.add_theme_color_override("font_hover_color", MENU_INK if mine else PANEL_TEXT)
		chip.add_theme_stylebox_override("normal", _box(PANEL_EDGE if mine else PANEL_FILL, PANEL_EDGE, 2, 12, 10))
		chip.add_theme_stylebox_override("hover", _box(PANEL_EDGE.lightened(0.2) if mine else Color(0.2, 0.23, 0.3), PANEL_EDGE, 2, 12, 10))
		chip.add_theme_stylebox_override("pressed", _box(PANEL_EDGE, PANEL_EDGE, 2, 12, 10))
		chip.disabled = not is_host
		var unit = hero["unit"]
		chip.pressed.connect(func(): group_assign.emit(unit, id))
		sound_manager.bind_button(chip, &"switch1")
		row.add_child(chip)
	return row


## Nível, barra de experiência e pontos livres. O selo LEVEL UP (que abre a árvore) só
## aparece nos heróis deste jogador (`mine`).
func set_party_progress(unit, info: Dictionary, points: int, mine := true) -> void:
	if not party_cards.has(unit):
		return
	var card: Dictionary = party_cards[unit]
	party_info[unit] = {"level": info["level"], "fraction": info["fraction"], "points": points, "mine": mine}
	card.level.text = "Nv %d" % info["level"]
	card.level.get_parent().visible = true
	card.xp.get_parent().visible = true
	card.xp.size.x = 150.0 * clampf(info["fraction"], 0.0, 1.0)
	card.points.text = "+%d" % points
	card.points.get_parent().visible = points > 0
	card.level_up.visible = mine and points > 0


## Faixa do topo (exploração e cidade): uma tira fina de latão e vinho com o nome do lugar,
## a missão e os números em linha. A bússola é um medalhão pequeno pendurado à esquerda, com
## o farol e o local mais perto (só ícones: sem nome nem distância, nada de spoiler).
## O anel dourado da bússola é a experiência até o próximo nível.
func _build_overview() -> void:
	overview = Control.new()
	overview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overview)
	overview_left = PanelContainer.new()
	var strip := StyleBoxFlat.new()
	strip.bg_color = PANEL_FILL
	strip.border_color = Brass.BRASS
	strip.border_width_bottom = 2
	strip.shadow_color = Brass.WINE_DEEP
	strip.shadow_size = 1
	strip.shadow_offset = Vector2(0, 2)
	overview_left.add_theme_stylebox_override("panel", strip)
	overview_left.position = Vector2.ZERO
	overview_left.custom_minimum_size = Vector2(STRIP_WIDTH, STRIP_HEIGHT)
	overview_left.size = overview_left.custom_minimum_size
	overview.add_child(overview_left)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 18)
	overview_left.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)
	overview_title = Brass.label("", 16, PANEL_EDGE, 700)
	overview_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(overview_title)
	quest_chip = PanelContainer.new() # a missão, logo depois do nome do lugar
	quest_chip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	quest_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quest_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_chip.clip_contents = true
	quest_chip.visible = false
	row.add_child(quest_chip)
	var quest_row := HBoxContainer.new()
	quest_row.add_theme_constant_override("separation", 6)
	quest_chip.add_child(quest_row)
	quest_row.add_child(_icon("star", Brass.GOLD, 14))
	tracker = Brass.label("", 13, PANEL_MUTED)
	quest_row.add_child(tracker)
	var gap := Control.new() # sem missão, os números continuam encostados à direita
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.name = "Gap"
	row.add_child(gap)
	quest_chip.visibility_changed.connect(func(): gap.visible = not quest_chip.visible)
	overview_numbers = HBoxContainer.new()
	overview_numbers.add_theme_constant_override("separation", 18)
	row.add_child(overview_numbers)
	overview_radar = Radar.new()
	overview_radar.size = Vector2.ONE * RADAR_SIZE
	overview_radar.position = Vector2(RADAR_LEFT, RADAR_TOP)
	overview.add_child(overview_radar)
	_ignore_mouse(overview)
	overview_radar.mouse_filter = Control.MOUSE_FILTER_STOP # clicar na bússola abre a legenda
	overview_radar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	overview_radar.tooltip_text = "Bússola: clique para ver a legenda"
	overview_radar.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			show_compass_legend())


func _chip_box(edge: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := Brass.panel(PANEL_FILL, edge, 2, 4, 0)
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	return chip


## `stats`: [{icon, value, label, color?, ink?}], metade em cada asa. `level`: {} ou
## {level, fraction, name}: fraction enche o anel; sem alvos, o radar mostra o nível no meio.
## `targets`: [{icon, color, angle, label, spread?}] no radar; spread desenha a faixa de uma área. Só troca os números quando o desenho é o
## mesmo: o radar acompanha o giro da câmera a cada quadro.
func set_overview(title: String, stats: Array, level := {}, targets := []) -> void:
	if overview == null:
		_build_overview()
	var medallion := not targets.is_empty() or not level.is_empty()
	var key := str(stats.map(func(s): return s["label"])) + str(medallion)
	if key != overview_key:
		overview_key = key
		_layout_overview(stats, medallion)
	var line := [title]
	for i in stats.size():
		var stat: Dictionary = stats[i]
		overview_cells[i]["value"].text = str(stat["value"])
		overview_cells[i]["value"].add_theme_color_override("font_color", stat.get("ink", PANEL_TEXT))
		overview_cells[i]["icon"].color = stat.get("color", PANEL_TEXT)
		overview_cells[i]["icon"].queue_redraw()
		line.append("%s %s" % [stat["label"], stat["value"]])
	overview_radar.visible = medallion
	overview_radar.set_targets(targets)
	overview_radar.xp = level.get("fraction", -1.0)
	overview_radar.center_text = str(level["level"]) if targets.is_empty() and not level.is_empty() else ""
	overview_radar.center_note = level.get("name", "") if targets.is_empty() else ""
	overview_radar.queue_redraw()
	if not level.is_empty():
		line.append("%s %d" % [level.get("name", "Nível"), level["level"]])
	for target in targets:
		line.append(target["label"])
	overview_title.text = title
	overview_text = "   ·   ".join(line)
	overview_stats = stats.duplicate()


## Os números em linha: ícone, valor e o nome pequeno. Com a bússola, a faixa começa depois dela.
func _layout_overview(stats: Array, medallion: bool) -> void:
	overview_cells = []
	for child in overview_numbers.get_children():
		overview_numbers.remove_child(child)
		child.queue_free()
	for stat in stats:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		overview_numbers.add_child(cell)
		var icon := _icon(stat["icon"], PANEL_TEXT, 17)
		cell.add_child(icon)
		var value := Brass.label("", 15, PANEL_TEXT, 700)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(value)
		var caption := Brass.label(stat["label"], 11, Brass.DIM)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(caption)
		overview_cells.append({"value": value, "icon": icon})
	var margin: MarginContainer = overview_left.get_child(0)
	margin.add_theme_constant_override("margin_left", int(RADAR_LEFT + RADAR_SIZE + 14) if medallion else 18)
	_ignore_mouse(overview)
	overview_radar.mouse_filter = Control.MOUSE_FILTER_STOP # a bússola continua clicável (legenda)


## Radar redondo: o grupo no meio e os alvos em volta, na direção certa da tela.
## Barra de vida grande do menu: números dentro, e o pedaço que o golpe tiraria piscando.
class HpBar extends Control:
	const BACK := Color(0.16, 0.13, 0.12)
	var hp := 0
	var max_hp := 1
	var color := Color.RED
	var font: Font
	var preview := 0: # dano (positivo) ou cura (negativo) em foco
		set(value):
			preview = value
			queue_redraw()

	func setup(p_hp: int, p_max: int, p_color: Color, p_font: Font) -> void:
		hp = p_hp
		max_hp = maxi(1, p_max)
		color = p_color
		font = p_font
		custom_minimum_size = Vector2(0, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		if preview != 0:
			queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_style_box(_round(BACK), rect)
		var now := float(hp) / max_hp
		var after := clampf(float(hp - preview) / max_hp, 0.0, 1.0)
		var inner := rect.grow(-3)
		var kept := minf(now, after)
		if kept > 0.0:
			draw_style_box(_round(color), Rect2(inner.position, Vector2(inner.size.x * kept, inner.size.y)))
		if preview != 0: # o que muda pisca: branco no dano, verde na cura
			var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 130.0)
			var tint := Color(1.0, 0.95, 0.85, pulse) if preview > 0 else Color(0.45, 1.0, 0.55, pulse)
			var from := inner.size.x * kept
			draw_rect(Rect2(inner.position + Vector2(from, 0), Vector2(inner.size.x * absf(now - after), inner.size.y)), tint)
		if font != null:
			var text := "%d / %d" % [hp, max_hp]
			draw_string_outline(font, Vector2(0, size.y / 2 + 8), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 5, Color(0, 0, 0, 0.85))
			draw_string(font, Vector2(0, size.y / 2 + 8), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE)

	func _round(fill: Color) -> StyleBoxFlat:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.set_corner_radius_all(8)
		return box


class Radar extends Control:
	const IconScript = preload("res://scripts/icon.gd")
	const FILL := Color(0.165, 0.075, 0.098, 0.96)
	const EDGE := Color("f2ca76")
	const RIM := Color("c9a36a") # moldura de latão
	const DEEP := Color("16090c")
	const TEXT := Color("f4dcb8")
	const ORBIT := 0.52 # onde os ícones ficam, em fração do raio
	const ICON := 0.24 # tamanho do ícone, em fração do radar
	const MIN_APART := 0.8 # radianos: ícones na mesma direção se afastam um pouco (a ponta na borda continua exata)
	var xp := -1.0
	var center_text := ""
	var center_note := ""
	var title_font: Font
	var pins := [] # {icon, angle, spot, color, spread}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_font = preload("res://scripts/hud/brass.gd").font(700)

	func set_targets(targets: Array) -> void:
		var kinds := targets.map(func(t): return t["icon"])
		if kinds != pins.map(func(p): return p["icon"].kind):
			for pin in pins:
				pin["icon"].queue_free()
			pins = []
			for target in targets:
				var icon := IconScript.new()
				icon.setup(target["icon"], target["color"], size.x * ICON)
				add_child(icon)
				pins.append({"icon": icon})
		var spots := targets.map(func(t): return t["angle"])
		if spots.size() > 2:
			# Três alvos podem estar na mesma direção. Distribui os discos preservando a ordem.
			for pass_index in 8:
				for a in spots.size():
					for b in range(a + 1, spots.size()):
						var delta := angle_difference(spots[a], spots[b])
						if absf(delta) < 1.35:
							var shift := (1.35 - absf(delta)) * (0.5 if delta >= 0 else -0.5)
							spots[a] -= shift
							spots[b] += shift
		elif spots.size() == 2:
			var gap := angle_difference(spots[0], spots[1])
			if absf(gap) < MIN_APART:
				var push := (MIN_APART - absf(gap)) / 2 * (1.0 if gap >= 0.0 else -1.0)
				spots[0] -= push
				spots[1] += push
		var mid := size / 2
		for i in pins.size():
			var pin: Dictionary = pins[i]
			pin["angle"] = targets[i]["angle"]
			pin["spot"] = mid + Vector2.from_angle(spots[i]) * (size.x / 2) * ORBIT
			pin["color"] = targets[i]["color"]
			pin["spread"] = float(targets[i].get("spread", 0.0))
			var icon: Control = pin["icon"]
			icon.color = targets[i]["color"]
			icon.position = pin["spot"] - icon.custom_minimum_size / 2
			icon.queue_redraw()
		queue_redraw()

	func _draw() -> void:
		var mid := size / 2
		var radius := size.x / 2 - 3
		draw_circle(mid, radius + 1, DEEP)
		draw_circle(mid, radius - 2, FILL)
		draw_arc(mid, radius - 2, 0.0, TAU, 72, RIM, 4.0, true)
		for quarter in 4: # cruz fina de bússola
			var dir := Vector2.from_angle(quarter * PI / 2)
			draw_line(mid + dir * 10, mid + dir * (radius - 24), Color(RIM, 0.22), 1.0)
		if xp >= 0.0: # trilho e progresso da experiência, por dentro da borda
			draw_arc(mid, radius - 7, 0.0, TAU, 72, Color(EDGE, 0.15), 6.0, true)
			draw_arc(mid, radius - 7, -PI / 2, -PI / 2 + TAU * clampf(xp, 0.0, 1.0), 72, EDGE, 6.0, true)
		for pin in pins: # área de busca: uma faixa na borda, na direção do alvo
			if pin.get("spread", 0.0) > 0.0:
				var spread: float = pin["spread"]
				if spread >= PI: # dentro da área: o radar todo ganha a cor da lanterna
					draw_circle(mid, radius - 13, Color(pin["color"], 0.16))
				draw_arc(mid, radius - 18, pin["angle"] - spread, pin["angle"] + spread, 40, Color(pin["color"], 0.4), 9.0, true)
		if not pins.is_empty():
			draw_circle(mid, 6.0, TEXT)
			for pin in pins:
				# disco atrás do ícone: lê como um marcador do mapa
				var disc := size.x * ICON * 0.66
				draw_circle(pin["spot"], disc, Color(0.03, 0.04, 0.06, 0.85))
				draw_arc(pin["spot"], disc, 0.0, TAU, 32, Color(pin["color"], 0.8), 2.0, true)
		if center_text != "" and title_font != null:
			draw_string(title_font, mid + Vector2(-size.x / 2, size.x * 0.1), center_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(size.x * 0.3), TEXT)
			draw_string(title_font, mid + Vector2(-size.x / 2, size.x * 0.28), center_note, HORIZONTAL_ALIGNMENT_CENTER, size.x, int(size.x * 0.11), Color(EDGE, 0.9))


## Aviso grande no meio da tela, que some sozinho: início e fim de combate.
func show_banner(text: String, color: Color) -> void:
	if banner != null:
		banner.queue_free()
	banner = _label(text, 54, color)
	banner.position = Vector2(0, 280)
	banner.custom_minimum_size = Vector2(SCREEN.x, 0)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 12)
	add_child(banner)
	var shown := banner
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(shown, "modulate:a", 0.0, 0.5)
	tween.tween_callback(shown.queue_free)


func set_hint(text: String) -> void:
	hint.text = text


## Em combate o topo some: a luta usa a tela toda.
func show_overview(on: bool) -> void:
	if overview != null:
		overview.visible = on


## Missão em andamento: um selo abaixo da bússola.
func set_tracker(text: String) -> void:
	if overview == null:
		_build_overview()
	tracker.text = text
	quest_chip.visible = text != ""


## Botão da Poção de Luz, no canto. Sem poção, ele some.
func set_potions(count: int) -> void:
	if potion_button == null:
		potion_button = _icon_button("drop")
		potion_button.tooltip_text = "Poção de Luz"
		potion_button.pressed.connect(func(): potion_pressed.emit())
		var count_label := Brass.label("", 18, Brass.TEXT_LIT, 700)
		count_label.add_theme_color_override("font_outline_color", Brass.WINE_DEEP)
		count_label.add_theme_constant_override("outline_size", 6)
		count_label.position = Vector2(DOCK_BUTTON - 22, DOCK_BUTTON - 30)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		potion_button.add_child(count_label)
	potion_button.get_child(1).text = str(count)
	potion_button.visible = count > 0


## Texto do que acabou de acontecer no mapa, como uma memória encontrada. Some sozinho.
func show_detail(text: String) -> void:
	if detail != null:
		detail.queue_free()
	detail = _label(text, 24, Color(1.0, 0.97, 0.88))
	detail.position = Vector2(140, 300)
	detail.custom_minimum_size = Vector2(SCREEN.x - 280, 0)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_theme_color_override("font_outline_color", Color.BLACK)
	detail.add_theme_constant_override("outline_size", 8)
	add_child(detail)
	var shown := detail
	var tween := create_tween()
	tween.tween_interval(4.5)
	tween.tween_property(shown, "modulate:a", 0.0, 0.6)
	tween.tween_callback(shown.queue_free)


## Na expedição, o fim leva sempre de volta à cidade: um botão só.
func use_town_exit() -> void:
	var end_column: Node = end_label.get_parent()
	for child in end_column.get_children():
		if child is Button and child != skills_button:
			child.text = "Voltar à Cidade-Farol"
	if end_menu_button != null:
		end_menu_button.visible = false


func show_end(text: String, note := "") -> void:
	end_label.text = text
	end_note.text = note
	end_note.visible = note != ""
	end_panel.visible = true


func _box(fill: Color, border: Color, border_width: int, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box


# --- Repasses ---------------------------------------------------------------
# A tela e os testes chamam estas funções no HUD; o código mora nos componentes em scripts/hud/.

func open_options() -> void:
	options_ui.open_options()


func close_options() -> void:
	options_ui.close_options()


func options_open() -> bool:
	return options_ui.options_open()


func show_options_note(text: String) -> void:
	options_ui.show_options_note(text)


func card_open() -> bool:
	return card_ui.card_open()


func show_card(info: Dictionary) -> void:
	card_ui.show_card(info)


func hide_card() -> void:
	card_ui.hide_card()


func menu_open() -> bool:
	return menu_ui.menu_open()


func show_menu(anchor: Vector2, title: String, title_team: int, info: String, options: Array, status := {}) -> void:
	menu_ui.show_menu(anchor, title, title_team, info, options, status)


func hide_menu() -> void:
	menu_ui.hide_menu()


func setup_party(heroes: Array, owners: Dictionary) -> void:
	party_ui.setup_party(heroes, owners)
	bag_ui.refresh_buttons()


## Bolsa do herói. `free`: fora de combate (só assim dá para passar itens).
func show_hero_bag(unit, party: Array, free: bool) -> void:
	bag_ui.show_bag(unit, party, free)


func hide_hero_bag() -> void:
	bag_ui.hide_bag()


## Atualiza os selos das bolsas nas cartas (um Orbe foi achado, usado ou passado).
func refresh_bags() -> void:
	bag_ui.refresh_buttons()


func show_end_turn(on: bool) -> void:
	party_ui.show_end_turn(on)


func set_together(on: bool) -> void:
	party_ui.set_together(on)


func update_party(current) -> void:
	party_ui.update_party(current)


func highlight(unit) -> void:
	timeline_ui.highlight(unit)


func preview_cast(state, unit, time: int) -> void:
	timeline_ui.preview_cast(state, unit, time)
