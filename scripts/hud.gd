extends CanvasLayer
class_name BattleHud

# Resolve services after the content pack is mounted by the thin installer.
var sound_manager:
	get: return get_node("/root/SoundManager")

## Interface: fila de turnos à esquerda e um menu que abre em cima da casa tocada.

const GameSettings = preload("res://scripts/game_settings.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const OPTIONS_WIDTH := 136

signal option_pressed(index: int)
signal order_toggled(on: bool)
signal restart_pressed
signal skills_pressed
signal menu_pressed
signal party_pressed(unit)
signal rotate_held(direction: int) # -1 ou 1 enquanto o botão está apertado; 0 ao soltar
signal together_toggled(on: bool)
signal unit_picked(unit)
signal potion_pressed
signal end_turn_pressed
signal save_pressed
signal load_pressed
signal quit_pressed
signal options_toggled(open: bool)

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
const ANIM_IDLE := 0
const HudOptions = preload("res://scripts/hud/options_menu.gd")
const HudCard = preload("res://scripts/hud/unit_card.gd")
const HudActionMenu = preload("res://scripts/hud/action_menu.gd")
const HudPartyBar = preload("res://scripts/hud/party_bar.gd")
const HudTimeline = preload("res://scripts/hud/timeline.gd")

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


var journey: Label
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
var objective: Label
var detail: Label
var end_menu_button: Button
var party_row: HBoxContainer
var party_cards := {} # herói -> {panel, fill, status}
var together_button: Button
var end_turn_button: Button
var banner: Label
var options_ui := HudOptions.new(self) # menu de opções: volume, salvar, carregar e sair
var card_ui := HudCard.new(self) # ficha da unidade
var menu_ui := HudActionMenu.new(self) # menu de ações em cima da casa
var party_ui := HudPartyBar.new(self) # barra da party e botões do canto
var timeline_ui := HudTimeline.new(self) # fila de turnos à esquerda


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

	order_button = Button.new()
	order_button.text = SHOW_ORDER_TEXT
	order_button.toggle_mode = true
	order_button.focus_mode = Control.FOCUS_NONE
	order_button.add_theme_font_size_override("font_size", 22)
	order_button.custom_minimum_size = Vector2(200, 56)
	order_button.position = Vector2(SCREEN.x - MARGIN - 200, MARGIN)
	sound_manager.bind_button(order_button, &"switch1")
	order_button.toggled.connect(_on_order_toggled)
	add_child(order_button)

	hint = Label.new()
	hint.position = Vector2(90, 676)
	hint.custom_minimum_size = Vector2(1110, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1.0, 0.88, 0.54))
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	add_child(hint)

	menu = PanelContainer.new()
	menu.custom_minimum_size.x = MENU_WIDTH
	menu.add_theme_stylebox_override("panel", _box(MENU_FILL, MENU_INK, 3, 16, 12))
	menu.visible = false
	add_child(menu)

	end_panel = PanelContainer.new()
	end_panel.position = Vector2(480, 290)
	end_panel.custom_minimum_size = Vector2(320, 140)
	end_panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.97), Color(1.0, 0.85, 0.4), 2, 6, 8))
	end_panel.visible = false
	add_child(end_panel)
	var end_column := VBoxContainer.new()
	end_column.alignment = BoxContainer.ALIGNMENT_CENTER
	end_panel.add_child(end_column)
	end_label = Label.new()
	end_label.add_theme_font_size_override("font_size", 32)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_column.add_child(end_label)
	end_note = Label.new()
	end_note.add_theme_font_size_override("font_size", 17)
	end_note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_note.visible = false
	end_column.add_child(end_note)
	var restart := Button.new()
	restart.text = "Lutar de novo"
	restart.custom_minimum_size.y = 56
	sound_manager.bind_button(restart, &"click3")
	restart.pressed.connect(func(): restart_pressed.emit())
	end_column.add_child(restart)
	skills_button = Button.new()
	skills_button.text = "Árvore de skills"
	skills_button.custom_minimum_size.y = 48
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


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _on_order_toggled(on: bool) -> void:
	order_button.text = HIDE_ORDER_TEXT if on else SHOW_ORDER_TEXT
	order_toggled.emit(on)


## Prepara a tela para a exploração: mostra o progresso e oferece voltar ao menu no fim.
func setup_exploration() -> void:
	order_button.visible = false
	journey = _label("", 22, Color(1.0, 0.95, 0.8))
	journey.position = Vector2(0, 16)
	journey.custom_minimum_size = Vector2(SCREEN.x - 320, 0) # à direita ficam os botões da câmera
	journey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	journey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	journey.add_theme_color_override("font_outline_color", Color.BLACK)
	journey.add_theme_constant_override("outline_size", 6)
	add_child(journey)
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
	sound_manager.bind_button(menu_button, &"click3")
	menu_button.pressed.connect(func(): menu_pressed.emit())
	end_column.add_child(menu_button)


func set_journey(alive: int, total: int, distance: int, kills: int, danger: int, biome := "") -> void:
	journey.text = "%s   ·   Heróis %d/%d   ·   Distância %d   ·   Abates %d   ·   Perigo %d" % [biome, alive, total, distance, kills, danger]


## Aviso grande no meio da tela, que some sozinho: início e fim de combate.
func show_banner(text: String, color: Color) -> void:
	if banner != null:
		banner.queue_free()
	banner = _label(text, 54, color)
	banner.position = Vector2(0, 120)
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


## Primeira linha do topo, quando o texto padrão da jornada não serve (na cidade).
func set_status(text: String) -> void:
	journey.text = text


## Linha da expedição, abaixo do progresso: nível, brasas e bússola.
func set_objective(text: String) -> void:
	if objective == null:
		objective = _label("", 20, Color(0.95, 0.85, 0.55))
		objective.position = Vector2(0, 48)
		objective.custom_minimum_size = Vector2(SCREEN.x - 320, 0)
		objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
		objective.add_theme_color_override("font_outline_color", Color.BLACK)
		objective.add_theme_constant_override("outline_size", 6)
		add_child(objective)
	objective.text = text


## Missão em andamento, abaixo da linha da expedição.
func set_tracker(text: String) -> void:
	if tracker == null:
		tracker = _label("", 17, Color(0.78, 0.86, 0.95))
		tracker.position = Vector2(0, 78)
		tracker.custom_minimum_size = Vector2(SCREEN.x - 320, 0)
		tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tracker.add_theme_color_override("font_outline_color", Color.BLACK)
		tracker.add_theme_constant_override("outline_size", 5)
		add_child(tracker)
	tracker.text = text


## Botão da Poção de Luz, no canto. Sem poção, ele some.
func set_potions(count: int) -> void:
	if potion_button == null:
		potion_button = party_ui._corner_button("", Vector2(SCREEN.x - OPTIONS_WIDTH - MARGIN, 124), OPTIONS_WIDTH)
		potion_button.pressed.connect(func(): potion_pressed.emit())
	potion_button.text = "Poção (%d)" % count
	potion_button.visible = count > 0


## Texto do que acabou de acontecer no mapa, como uma memória encontrada. Some sozinho.
func show_detail(text: String) -> void:
	if detail != null:
		detail.queue_free()
	detail = _label(text, 24, Color(1.0, 0.97, 0.88))
	detail.position = Vector2(140, 196)
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


func show_menu(anchor: Vector2, title: String, title_team: int, info: String, options: Array) -> void:
	menu_ui.show_menu(anchor, title, title_team, info, options)


func hide_menu() -> void:
	menu_ui.hide_menu()


func setup_party(heroes: Array, owners: Dictionary) -> void:
	party_ui.setup_party(heroes, owners)


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
