extends CanvasLayer

# Resolve services after the content pack is mounted by the thin installer.
var sound_manager:
	get: return get_node("/root/SoundManager")

## Interface: fila de turnos à esquerda e um menu que abre em cima da casa tocada.

const GameSettings = preload("res://scripts/game_settings.gd")
const END_TURN_WIDTH := 150.0
const SaveGame = preload("res://scripts/save_game.gd")
const OPTIONS_WIDTH := 136
const OPTIONS_PANEL_WIDTH := 400
const OPTIONS_CONFIRM_WIDTH := 460
const OPTIONS_Y := 74

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
signal jump_pressed
signal save_pressed
signal load_pressed
signal quit_pressed
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
const CAST_COLOR := Color(1.0, 0.55, 0.1)
const CAST_INK := Color(0.72, 0.33, 0.0)
const TIMELINE_Y := 18.0
const TIMELINE_SLIDE_TIME := 0.4
const FOCUS_COLOR := Color(1.0, 1.0, 1.0)
const MENU_FILL := Color(1.0, 0.97, 0.88)
const MENU_INK := Color(0.11, 0.12, 0.15)
const OPTION_FILL := Color(1.0, 0.84, 0.32)
const DAMAGE_INK := Color(0.66, 0.13, 0.09)
const HEAL_INK := Color(0.1, 0.45, 0.2)
const PLAYER_INK := Color(0.12, 0.37, 0.66)
const DISABLED_FILL := Color(0.86, 0.85, 0.8)
const DISABLED_INK := Color(0.4, 0.4, 0.42)
const SCREEN := Vector2(1280, 720)
const MARGIN := 12.0
const MENU_WIDTH := 340.0
const MENU_GAP := 56.0 # distância do centro da casa até o menu, para não cobrir quem foi tocado
const OPTION_HEIGHT := 72
const MENU_VISIBLE_OPTIONS := 5
const TIMELINE_SIZE := 10
const PORTRAIT_SIZE := 60
const SHOW_ORDER_TEXT := "Mostrar ordem"
const HIDE_ORDER_TEXT := "Esconder ordem"
const CARD_WIDTH := 620.0
const CARD_WIDTH_WIDE := 1000.0
const CARD_PORTRAIT_SIZE := Vector2(130, 150)
const STAT_FILL := Color(0.95, 0.9, 0.77)
const HP_ENEMY := Color(0.89, 0.29, 0.23)
const SPELL_INK := Color(0.35, 0.14, 0.66)
const CARD_FPS := 14.0
const SPELL_COLOR := Color(0.72, 0.3, 1.0)
const ANIM_IDLE := 0
const ANIM_ATTACK := 2 # linhas da folha de sprites: parado, andando, atacando, apanhando
# Painel do topo (exploração): mesmas cores das janelas da Cidade-Farol.
const PANEL_FILL := Color(0.098, 0.118, 0.165, 0.93)
const PANEL_EDGE := Color("f2ca76")
const PANEL_TEXT := Color("f5efdf")
const PANEL_MUTED := Color("aab2c2")
const RADAR_SIZE := 164.0
const RADAR_TOP := 10.0
const WING_HEIGHT := 100.0
const WING_MARGIN := 16.0
const STAT_WIDTH := 112.0
const DOCK_BUTTON := 64.0 # botões da coluna da direita: do tamanho de um dedo
const DOCK_GAP := 8
const PARTY_CARD := Vector2(228, 92)
const XP_COLOR := Color(0.55, 0.9, 1.0)

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
var overview_left: PanelContainer
var overview_right: PanelContainer
var overview_radar
var overview_title: Label
var overview_key := ""
var overview_cells := [] # {value, icon} na ordem dos números
var overview_text := "" # o painel em uma linha (testes)
var group_button: Button
var group_layer: CanvasLayer
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
var party_cards := {} # herói -> {panel, fill, status, level, xp, points}
var together_button: Button
var end_turn_button: Button
var jump_button: Button
var banner: Label


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
	end_note.add_theme_font_size_override("font_size", 20)
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

	_build_options()

	# Cartão de detalhes: cobre a tela toda para que o toque que fecha não caia no tabuleiro.
	card = ColorRect.new()
	card.color = Color(0, 0, 0, 0.55)
	card.size = SCREEN
	card.visible = false
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			hide_card())
	add_child(card)


## Botão "Opções", no canto: abre por cima de tudo o volume, salvar, carregar e sair.
func _build_options() -> void:
	GameSettings.apply()
	options_button = _icon_button("gear")
	options_button.tooltip_text = "Opções"
	options_button.pressed.connect(open_options)
	var layer := CanvasLayer.new()
	layer.layer = self.layer + 10 # acima de tudo que o HUD cria depois (party, cidade, cartão)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS # o jogo fica pausado com o menu aberto
	add_child(layer)
	options_overlay = ColorRect.new()
	options_overlay.color = Color(0, 0, 0, 0.6)
	options_overlay.size = SCREEN
	options_overlay.visible = false
	layer.add_child(options_overlay)
	options_panel = _options_box(OPTIONS_PANEL_WIDTH)
	options_overlay.add_child(options_panel)
	var column: VBoxContainer = options_panel.get_child(0)
	column.add_child(_options_title("Opções"))
	volume_label = _label("", 20, Color(1.0, 0.95, 0.8))
	column.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.value = GameSettings.volume()
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.custom_minimum_size.y = 36
	column.add_child(volume_slider)
	volume_mute = _options_button(column, "Silenciar")
	volume_mute.toggle_mode = true
	volume_mute.button_pressed = GameSettings.muted()
	volume_slider.value_changed.connect(func(value: float):
		GameSettings.set_volume(int(value))
		if volume_mute.button_pressed and value > 0.0: # mexer no volume tira do mudo
			volume_mute.set_pressed_no_signal(false)
			GameSettings.set_muted(false)
		_show_volume())
	volume_mute.toggled.connect(func(on: bool):
		GameSettings.set_muted(on)
		_show_volume())
	_show_volume()
	column.add_child(HSeparator.new())
	save_button = _options_button(column, "Salvar jogo")
	save_button.pressed.connect(func(): save_pressed.emit())
	load_button = _options_button(column, "Carregar jogo")
	load_button.pressed.connect(func(): load_pressed.emit())
	options_note = _label("", 16, Color(1.0, 0.85, 0.4))
	options_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	options_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options_note.custom_minimum_size.x = OPTIONS_PANEL_WIDTH - 36
	column.add_child(options_note)
	column.add_child(HSeparator.new())
	var quit := _options_button(column, "Sair do jogo")
	quit.pressed.connect(func():
		options_panel.visible = false
		quit_panel.visible = true
		_center(quit_panel))
	var back := _options_button(column, "Voltar ao jogo")
	back.pressed.connect(close_options)

	quit_panel = _options_box(OPTIONS_CONFIRM_WIDTH)
	quit_panel.visible = false
	options_overlay.add_child(quit_panel)
	var confirm: VBoxContainer = quit_panel.get_child(0)
	confirm.add_child(_options_title("Sair do jogo?"))
	var warning := _label("Você volta para a tela inicial. O que não foi salvo será perdido.", 18, Color(0.9, 0.9, 0.92))
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size.x = OPTIONS_CONFIRM_WIDTH - 36
	confirm.add_child(warning)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	confirm.add_child(row)
	var ok := _options_button(row, "OK")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func(): quit_pressed.emit())
	var cancel := _options_button(row, "Cancelar")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func():
		quit_panel.visible = false
		options_panel.visible = true
		_center(options_panel))


func _options_box(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.97), Color(1.0, 0.85, 0.4), 2, 10, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return panel


func _options_title(text: String) -> Label:
	var title := _label(text, 30, Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _options_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size.y = 50
	sound_manager.bind_button(button, &"click3")
	parent.add_child(button)
	return button


## Salvar só com `save_allowed` (fora do online, partida em andamento); carregar, com `load_allowed`.
func open_options() -> void:
	var can_load := SaveGame.exists()
	hide_card()
	save_button.disabled = not save_allowed
	load_button.disabled = not can_load or not load_allowed
	load_button.text = "Carregar jogo" if not can_load else "Carregar jogo (%s)" % SaveGame.summary()
	options_note.text = ""
	options_panel.visible = true
	quit_panel.visible = false
	options_overlay.visible = true
	_center(options_panel)
	_center(quit_panel)
	options_toggled.emit(true)


func close_options() -> void:
	options_overlay.visible = false
	options_toggled.emit(false)


func options_open() -> bool:
	return options_overlay.visible


func show_options_note(text: String) -> void:
	options_note.text = text


func _center(panel: Control) -> void:
	panel.reset_size()
	panel.position = (SCREEN - panel.get_combined_minimum_size()) / 2


func _show_volume() -> void:
	volume_label.text = "Volume: sem som" if GameSettings.muted() or GameSettings.volume() == 0 else "Volume: %d%%" % GameSettings.volume()


func refresh(state) -> void:
	_refresh_timeline(state)


func card_open() -> bool:
	return card.visible


## Ficha da unidade no estilo do mockup D1/D2: números com ícone em vez de frases.
## `info`: title, team, type_id, hp, max_hp, order, atk, def, speed, abilities e,
## se ela prepara magia, spell. Cada habilidade: name, icon, range, amount, amount_icon,
## time e, quando ameaça o herói da vez, hero_type e hero_amount.
func show_card(info: Dictionary) -> void:
	hide_card()
	card_info = info
	var casting: bool = info.has("spell")
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = CARD_WIDTH
	panel.add_theme_stylebox_override("panel", _box(MENU_FILL, MENU_INK, 3, 20, 16))
	card.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	column.add_child(top)
	top.add_child(_card_portrait(info, casting))
	var heading := VBoxContainer.new()
	heading.alignment = BoxContainer.ALIGNMENT_CENTER
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 10)
	top.add_child(heading)
	heading.add_child(_title(info["title"], 36, PLAYER_INK if info["team"] == Data.Team.PLAYER else DAMAGE_INK))
	heading.add_child(_hp_bar(info["hp"], info["max_hp"], info["team"]))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	heading.add_child(stats)
	for stat in [["sword", Color(0.7, 0.15, 0.12), info["atk"]], ["shield", Color(0.16, 0.44, 0.71), info["def"]], ["bolt", Color(0.76, 0.49, 0.0), info["speed"]]]:
		var chip := _pill(stat[0], stat[1], str(stat[2]), STAT_FILL, MENU_INK, 50, 26)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(chip)

	# Muitas habilidades: três colunas de linhas compactas numa ficha larga, para caber na tela.
	var compact: bool = info["abilities"].size() > 4
	var abilities: Container = column
	if compact:
		var grid := GridContainer.new()
		grid.columns = 3
		panel.custom_minimum_size.x = CARD_WIDTH_WIDE
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 6)
		column.add_child(grid)
		abilities = grid
	for ability in info["abilities"]:
		var row := _ability_row(ability, compact)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		abilities.add_child(row)
	if casting:
		column.add_child(_spell_block(info["spell"]))
	var footer := _label("Toque para fechar", 16, MENU_INK)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	card_row = ANIM_ATTACK if casting else ANIM_IDLE
	card_time = 0.0
	_update_card_frame()
	_ignore_mouse(panel) # qualquer toque no cartão chega ao fundo e fecha
	panel.reset_size()
	panel.position = (SCREEN - panel.get_combined_minimum_size()) / 2
	card.visible = true
	sound_manager.play_ui(&"switch3")


# Retrato animado numa moldura da cor do time (roxa se prepara magia) com a vez no canto.
func _card_portrait(info: Dictionary, casting: bool) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size = CARD_PORTRAIT_SIZE
	var border := SPELL_COLOR if casting else (PLAYER_COLOR if info["team"] == Data.Team.PLAYER else ENEMY_COLOR)
	var box := Panel.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_stylebox_override("panel", _box(Color(0.29, 0.31, 0.37), border, 4, 16, 0))
	frame.add_child(box)
	var portrait := TextureRect.new()
	card_atlas = AtlasTexture.new()
	card_atlas.atlas = load("res://assets/units/%s.png" % info["type_id"])
	portrait.texture = card_atlas
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(portrait)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _box(OPTION_FILL, MENU_INK, 3, 22, 0))
	badge.custom_minimum_size = Vector2(46, 46)
	badge.position = Vector2(-12, -12)
	var order := _title("%dº" % info["order"] if info["order"] > 0 else "–", 20, MENU_INK)
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(order)
	frame.add_child(badge)
	return frame


func _hp_bar(hp: int, max_hp: int, team: int) -> Control:
	var bar := Panel.new()
	bar.custom_minimum_size.y = 30
	bar.add_theme_stylebox_override("panel", _box(Color(0.23, 0.1, 0.09), MENU_INK, 2, 15, 0))
	var fill := Panel.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.anchor_right = float(hp) / max_hp
	fill.add_theme_stylebox_override("panel", _box(PLAYER_COLOR if team == Data.Team.PLAYER else HP_ENEMY, MENU_INK, 2, 15, 0))
	bar.add_child(fill)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	center.add_child(row)
	row.add_child(_icon("heart", Color.WHITE, 16))
	row.add_child(_title("%d/%d" % [hp, max_hp], 20, Color.WHITE))
	return bar


# Um botão por habilidade: ícone grande, nome e selos de alcance, efeito e tempo.
# compact encolhe tudo para caber em três colunas.
func _ability_row(ability: Dictionary, compact := false) -> Control:
	var k := 0.7 if compact else 1.0
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _box(Color.WHITE, Color(0.9, 0.85, 0.71), 2, 16, 6 if compact else 10))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", roundi(12 * k))
	row.add_child(line)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(60, 60) * k
	tile.add_theme_stylebox_override("panel", _box(OPTION_FILL, OPTION_FILL, 0, 14, 0))
	var tile_center := CenterContainer.new()
	tile_center.add_child(_icon(ability["icon"], MENU_INK, 34 * k))
	tile.add_child(tile_center)
	line.add_child(tile)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", roundi(6 * k))
	line.add_child(text)
	text.add_child(_title(ability["name"], roundi(26 * k), MENU_INK))
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 6)
	text.add_child(badges)
	if ability["range"] != "":
		badges.add_child(_pill("hexagon", Color(0.82, 0.42, 0.0), ability["range"], Color(1.0, 0.89, 0.76), MENU_INK, roundi(30 * k), roundi(18 * k)))
	badges.add_child(_pill(ability["amount_icon"], DAMAGE_INK if ability["amount_icon"] == "star" else HEAL_INK, ability["amount"], Color(0.98, 0.83, 0.81), MENU_INK, roundi(30 * k), roundi(18 * k)))
	var time_badge := _pill("hourglass", Color(0.29, 0.31, 0.37), str(ability["time"]), Color(0.89, 0.9, 0.93), MENU_INK, roundi(30 * k), roundi(18 * k))
	time_badge.tooltip_text = ability.get("time_hint", "Tempo até poder agir novamente")
	badges.add_child(time_badge)
	if ability.has("hero_type"):
		var threat := PanelContainer.new()
		threat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		threat.add_theme_stylebox_override("panel", _box(Color(0.98, 0.83, 0.81), Color(0.98, 0.83, 0.81), 0, 30, 6))
		var threat_row := HBoxContainer.new()
		threat_row.add_theme_constant_override("separation", 8)
		threat.add_child(threat_row)
		threat_row.add_child(_face(ability["hero_type"]))
		threat_row.add_child(_title("−%d" % ability["hero_amount"], 32, DAMAGE_INK))
		line.add_child(threat)
	return row


# Rosto do herói ameaçado: o primeiro quadro da folha, cortado na cabeça.
func _face(type_id: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _box(Color(0.29, 0.31, 0.37), PLAYER_COLOR, 3, 12, 2))
	var face := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % type_id)
	var sheet: Dictionary = meta[type_id]
	atlas.region = Rect2(0, 0, sheet["cell_w"], sheet["cell_h"] * 0.6)
	face.texture = atlas
	face.custom_minimum_size = Vector2(44, 44)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(face)
	return box


func _spell_block(spell: Dictionary) -> Control:
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel", _box(Color(0.94, 0.89, 1.0), SPELL_COLOR, 3, 16, 12))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	block.add_child(line)
	card_spell = SpellPreview.new()
	card_spell.setup(spell["radius"], SPELL_COLOR)
	line.add_child(card_spell)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 8)
	line.add_child(text)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	text.add_child(header)
	var tag := _label("PREPARANDO", 17, SPELL_INK)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(tag)
	header.add_child(_title(spell["name"], 30, SPELL_INK))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	text.add_child(grid)
	grid.add_child(_pill("hexagon", SPELL_COLOR, "%d casas" % spell["cells"], Color.WHITE, MENU_INK, 40, 19))
	grid.add_child(_pill("star", DAMAGE_INK, "até %d" % spell["power"], Color.WHITE, MENU_INK, 40, 19))
	grid.add_child(_pill("hourglass", Color(0.29, 0.31, 0.37), "solta em %d ações" % spell["actions"], Color.WHITE, MENU_INK, 40, 19))
	if spell["secret"]:
		grid.add_child(_pill("eye_off", Color.WHITE, "local secreto", Color(0.16, 0.14, 0.25), Color.WHITE, 40, 19))
	else:
		grid.add_child(_pill("warning", Color(0.76, 0.49, 0.0), "pega aliados", Color.WHITE, MENU_INK, 40, 19))
	for pill in grid.get_children():
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return block


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


func hide_card() -> void:
	if card.visible:
		sound_manager.play_ui(&"switch4")
	card.visible = false
	card_spell = null
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()


func _process(delta: float) -> void:
	if card.visible:
		card_time += delta
		_update_card_frame()


# Quem prepara magia aparece fazendo o gesto de ataque em loop; os outros, parados.
func _update_card_frame() -> void:
	var sheet: Dictionary = meta[card_info["type_id"]]
	var frame := int(card_time * CARD_FPS) % UnitView.row_frame_count(sheet, card_row)
	card_atlas.region = Rect2(frame * sheet["cell_w"], card_row * sheet["cell_h"], sheet["cell_w"], sheet["cell_h"])


func menu_open() -> bool:
	return menu.visible


## Abre o menu ao lado de `anchor` (centro da casa, em coordenadas de tela).
## Cada opção é {label, detail, tone}; tone escolhe a cor do detalhe.
## status (quando há alguém na casa): {hp, max_hp, order, unaware}. A vida vira barra e a vez
## vira um selo; o dano do golpe em foco aparece piscando na barra antes de confirmar.
func show_menu(anchor: Vector2, title: String, title_team: int, info: String, options: Array, status := {}) -> void:
	hide_menu()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	menu.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var name_label := _title(title, 28, MENU_INK if title_team < 0 else (PLAYER_INK if title_team == Data.Team.PLAYER else DAMAGE_INK))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var bar: HpBar = null
	if not status.is_empty():
		header.add_child(_turn_badge(status))
		bar = HpBar.new()
		bar.setup(status["hp"], status["max_hp"], HP_ENEMY if title_team == Data.Team.ENEMY else PLAYER_COLOR, title_font)
		column.add_child(bar)
	if info != "":
		var info_label := _label(info, 18, MENU_INK)
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
		var button := _add_option(list, options[i], i)
		menu_buttons.append(button)
		if bar != null and (options[i].has("damage") or options[i].has("heal")):
			var change: int = options[i].get("damage", -options[i].get("heal", 0))
			button.mouse_entered.connect(func(): bar.preview = change)
			if bar.preview == 0: # no celular não há "passar o mouse": vale o primeiro golpe
				bar.preview = change
	if list != column: # sem rolagem lateral: a lista define a largura, mais a barra
		list.get_parent().custom_minimum_size.x = list.get_combined_minimum_size().x + 16
	var footer := _label("Toque fora para fechar", 16, MENU_INK)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	menu.reset_size()
	var size := menu.get_combined_minimum_size()
	var x := anchor.x + MENU_GAP
	if x + size.x > SCREEN.x - MARGIN:
		x = anchor.x - MENU_GAP - size.x
	# A câmera baixa deixa espaço acima do campo. Usa esse espaço quando couber,
	# para manter as casas vizinhas livres para fechar o menu ou mudar de alvo.
	var y := anchor.y - size.y - MENU_GAP
	if y < MARGIN:
		y = anchor.y - size.y / 2
	menu.position = Vector2(clampf(x, MARGIN, SCREEN.x - MARGIN - size.x), clampf(y, MARGIN, SCREEN.y - MARGIN - size.y))
	menu.visible = true
	sound_manager.play_ui(&"switch3")


func hide_menu() -> void:
	menu.visible = false
	menu_buttons.clear()
	for child in menu.get_children():
		menu.remove_child(child)
		child.queue_free()


func _add_option(column: VBoxContainer, option: Dictionary, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = OPTION_HEIGHT
	button.focus_mode = Control.FOCUS_NONE
	var fill := Color.WHITE if option.get("kind", "") == "cancel" else OPTION_FILL # Cancelar não compete com a ação
	button.add_theme_stylebox_override("normal", _box(fill, Color(0.9, 0.85, 0.71), 2 if fill == Color.WHITE else 0, 12, 0))
	button.add_theme_stylebox_override("hover", _box(fill.lightened(0.25) if fill != Color.WHITE else Color(0.96, 0.94, 0.88), fill, 0, 12, 0))
	button.add_theme_stylebox_override("pressed", _box(fill.darkened(0.15), fill, 0, 12, 0))
	button.add_theme_stylebox_override("disabled", _box(DISABLED_FILL, DISABLED_FILL, 0, 12, 0))
	button.disabled = option.get("disabled", false)
	sound_manager.bind_button(button, &"click2" if option.get("kind", "") == "cancel" else &"click1")
	button.pressed.connect(func(): option_pressed.emit(index))
	column.add_child(button)

	# Nome à esquerda e o efeito (dano, cura) à direita, como no mockup.
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -16
	button.add_child(row)
	var ink := DISABLED_INK if button.disabled else MENU_INK
	var name_label := _label(option["label"], 24, ink)
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
		var hourglass := _icon("hourglass", CAST_INK, 18)
		hourglass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wait.add_child(hourglass)
		wait.add_child(_label(option["note"], 17, CAST_INK))
		stack.add_child(wait)
		row.add_child(stack)
	else:
		row.add_child(name_label)
	var tone: String = option.get("tone", "")
	if option.has("damage") and not button.disabled:
		row.add_child(_hit_badge(option))
	elif option.has("heal") and not button.disabled:
		row.add_child(_badge("heart", "+%d" % option["heal"], Color(0.18, 0.55, 0.28), Color.WHITE))
	else:
		var detail := _label(option["detail"], 26 if tone != "" else 18, DAMAGE_INK if tone == "damage" else (HEAL_INK if tone == "heal" else ink))
		detail.size_flags_vertical = Control.SIZE_FILL
		detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(detail)
	# A linha fica sobreposta ao botão (não é contêiner): a largura mínima vem dela.
	button.custom_minimum_size.x = row.get_combined_minimum_size().x + 32 + row.get_theme_constant("separation")
	return button


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
	sound_manager.bind_button(menu_button, &"click3")
	menu_button.pressed.connect(func(): menu_pressed.emit())
	end_column.add_child(menu_button)


## Barra da party, embaixo: mostra a vida de todos e seleciona o herói. `owners` tem o nome
## do jogador de cada herói no online.
func setup_party(heroes: Array, owners: Dictionary) -> void:
	party_row = HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 10)
	var row_width := heroes.size() * PARTY_CARD.x + (heroes.size() - 1) * 10
	party_row.position = Vector2((SCREEN.x - row_width) / 2, SCREEN.y - MARGIN - PARTY_CARD.y)
	add_child(party_row)
	for unit in heroes:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = PARTY_CARD
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				party_pressed.emit(unit))
		party_row.add_child(panel)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var portrait := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/units/%s.png" % unit.type_id)
		atlas.region = Rect2(0, 0, meta[unit.type_id]["cell_w"], meta[unit.type_id]["cell_h"])
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
		var name_label := _title(title, 20, Color.WHITE)
		name_label.clip_text = true
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		var level := _title("", 17, MENU_INK)
		var level_box := PanelContainer.new()
		var level_style := _box(PANEL_EDGE, PANEL_EDGE, 0, 8, 0)
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
		fill.color = PLAYER_COLOR
		fill.size = Vector2(150, 12)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(fill)
		var middle := HBoxContainer.new()
		middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(middle)
		var status := _title("", 17, Color(0.85, 0.87, 0.92))
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		middle.add_child(status)
		# Pontos para gastar: selo dourado piscando. Tocar na carta abre a árvore.
		var points := _title("", 17, MENU_INK)
		var points_box := PanelContainer.new()
		var points_style := _box(Color(1.0, 0.8, 0.25), Color.WHITE, 2, 8, 0)
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
		party_cards[unit] = {"panel": panel, "fill": fill, "status": status, "level": level, "xp": xp_fill, "points": points, "name": name_label}
	# Coluna da direita: girar, aproximar, girar, fila. No celular, dois dedos também giram
	# (torcendo) e aproximam (abrindo); no teclado, Q/E, Z e G.
	var rotate_left := _icon_button("turn_left")
	rotate_left.tooltip_text = "Girar (Q). No celular: torça com dois dedos."
	rotate_left.button_down.connect(func(): rotate_held.emit(-1))
	rotate_left.button_up.connect(func(): rotate_held.emit(0))
	var rotate_right := _icon_button("turn_right")
	rotate_right.tooltip_text = "Girar (E). No celular: torça com dois dedos."
	rotate_right.button_down.connect(func(): rotate_held.emit(1))
	rotate_right.button_up.connect(func(): rotate_held.emit(0))
	together_button = _icon_button("file")
	together_button.toggle_mode = true
	together_button.button_pressed = true
	together_button.toggled.connect(func(on):
		_show_together(on)
		together_toggled.emit(on))
	_show_together(true)
	dock.move_child(rotate_left, 0)
	dock.move_child(rotate_right, 2)
	dock.move_child(together_button, 3)


func show_end_turn(on: bool) -> void:
	if end_turn_button == null:
		if not on:
			return
		end_turn_button = _corner_button("Encerrar\nturno", Vector2(SCREEN.x - END_TURN_WIDTH - MARGIN, SCREEN.y - MARGIN - PARTY_CARD.y), END_TURN_WIDTH)
		end_turn_button.custom_minimum_size.y = PARTY_CARD.y
		end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	end_turn_button.visible = on


## Botão "Pular", logo acima de "Encerrar turno". `active`: o modo pulo está ligado.
func show_jump(on: bool, active := false) -> void:
	if jump_button == null:
		if not on:
			return
		jump_button = _corner_button("Pular", Vector2(SCREEN.x - END_TURN_WIDTH - MARGIN, SCREEN.y - MARGIN - PARTY_CARD.y - 8 - 56), END_TURN_WIDTH)
		jump_button.custom_minimum_size.y = 56
		jump_button.pressed.connect(func(): jump_pressed.emit())
	jump_button.text = "Cancelar pulo" if active else "Pular"
	jump_button.visible = on


func _corner_button(text: String, at: Vector2, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 22)
	button.position = at
	button.custom_minimum_size = Vector2(width, 56)
	sound_manager.bind_button(button, &"switch1")
	add_child(button)
	return button


## Botão quadrado só com ícone, do tamanho de um dedo.
func _icon_button(kind: String) -> Button:
	var button := _corner_button("", Vector2.ZERO, DOCK_BUTTON)
	button.custom_minimum_size.y = DOCK_BUTTON
	button.reparent(dock)
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


func _show_together(on: bool) -> void:
	_set_icon(together_button, "file" if on else "spread")
	together_button.tooltip_text = "Em fila (G)" if on else "Separados (G)"


func set_together(on: bool) -> void:
	together_button.button_pressed = on


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
	var box := _options_box(720)
	group_layer.add_child(box)
	var column: VBoxContainer = box.get_child(0)
	column.add_theme_constant_override("separation", 12)
	column.add_child(_options_title("Grupo"))
	var players: Dictionary = data.get("players", {})
	if not data.get("online", false):
		var note := _label("Abra a sala e passe o código: seus amigos entram no meio da jornada e você escolhe com qual herói cada um joga. Níveis, talentos e itens são os do seu save.", 20, PANEL_TEXT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 680
		column.add_child(note)
		var open := _options_button(column, "Abrir sala para amigos")
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
		var leave := _options_button(column, "Fechar a sala" if data.get("is_host", false) else "Sair da sala")
		leave.pressed.connect(func():
			hide_group()
			leave_room_pressed.emit())
	var back := _options_button(column, "Voltar ao jogo")
	back.pressed.connect(hide_group)
	_center(box)


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


## Nível, barra de experiência e pontos livres (só nas cartas dos heróis deste jogador).
func set_party_progress(unit, info: Dictionary, points: int) -> void:
	if not party_cards.has(unit):
		return
	var card: Dictionary = party_cards[unit]
	card.level.text = "Nv %d" % info["level"]
	card.level.get_parent().visible = true
	card.xp.get_parent().visible = true
	card.xp.size.x = 150.0 * clampf(info["fraction"], 0.0, 1.0)
	card.points.text = "+%d" % points
	card.points.get_parent().visible = points > 0


func update_party(current) -> void:
	for unit in party_cards:
		var card: Dictionary = party_cards[unit]
		card.fill.size.x = 150.0 * clampf(float(unit.hp) / unit.max_hp, 0.0, 1.0)
		card.status.text = "%d/%d" % [unit.hp, unit.max_hp] if unit.alive() else "caído"
		card.panel.modulate.a = 1.0 if unit.alive() else 0.5
		var border := ACTIVE_COLOR if unit == current else Color(0.3, 0.33, 0.4)
		card.panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.92), border, 3 if unit == current else 1, 8, 6))


## Painel do topo, simétrico no meio da tela: duas asas de números e, entre elas, o radar
## com o farol e o local mais perto (só ícones: sem nome nem distância, nada de spoiler).
## O anel dourado do radar é a experiência até o próximo nível.
func _build_overview() -> void:
	overview = Control.new()
	overview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overview)
	overview_left = _wing()
	overview_right = _wing()
	overview_radar = Radar.new()
	overview_radar.size = Vector2.ONE * RADAR_SIZE
	overview_radar.position = Vector2(SCREEN.x / 2 - RADAR_SIZE / 2, RADAR_TOP)
	overview.add_child(overview_radar)
	overview_title = _title("", 26, PANEL_EDGE)
	overview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overview_title.add_theme_color_override("font_outline_color", Color.BLACK)
	overview_title.add_theme_constant_override("outline_size", 8)
	overview_title.size = Vector2(SCREEN.x, 0)
	overview.add_child(overview_title)
	quest_chip = _chip_box(Color(0.55, 0.72, 0.95, 0.7))
	quest_chip.visible = false
	overview.add_child(quest_chip)
	var quest_row := HBoxContainer.new()
	quest_row.add_theme_constant_override("separation", 8)
	quest_chip.add_child(quest_row)
	quest_row.add_child(_icon("star", Color(0.78, 0.86, 0.95), 20))
	tracker = _label("", 20, Color(0.88, 0.92, 0.98))
	quest_row.add_child(tracker)
	quest_chip.resized.connect(func(): quest_chip.position.x = (SCREEN.x - quest_chip.size.x) / 2)
	_ignore_mouse(overview)


func _wing() -> PanelContainer:
	var wing := PanelContainer.new()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	wing.add_child(row)
	overview.add_child(wing)
	return wing


func _chip_box(edge: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := _box(PANEL_FILL, edge, 2, 18, 0)
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	return chip


## `stats`: [{icon, value, label, color?, ink?}], metade em cada asa. `level`: {} ou
## {level, fraction, name}: fraction enche o anel; sem alvos, o radar mostra o nível no meio.
## `targets`: [{icon, color, angle, label}] no radar. Só troca os números quando o desenho é o
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


## Asas do mesmo tamanho, coladas no radar; sem radar, encostam no meio.
func _layout_overview(stats: Array, medallion: bool) -> void:
	overview_cells = []
	var half := ceili(stats.size() / 2.0)
	var inner := RADAR_SIZE / 2 + 14 if medallion else 22.0
	var width := half * STAT_WIDTH + WING_MARGIN + inner
	for side in 2:
		var wing: PanelContainer = overview_left if side == 0 else overview_right
		var row: HBoxContainer = wing.get_child(0)
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		var style := _box(PANEL_FILL, Color(PANEL_EDGE, 0.75), 2, 18, 0)
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.content_margin_left = WING_MARGIN if side == 0 else inner
		style.content_margin_right = inner if side == 0 else WING_MARGIN
		wing.add_theme_stylebox_override("panel", style)
		wing.size = Vector2(width, WING_HEIGHT)
		var gap := 0.0 if medallion else 6.0
		wing.position = Vector2(SCREEN.x / 2 - width - gap if side == 0 else SCREEN.x / 2 + gap, RADAR_TOP + (RADAR_SIZE - WING_HEIGHT) / 2)
		var picked: Array = stats.slice(0, half) if side == 0 else stats.slice(half)
		for i in picked.size():
			if i > 0:
				var bar := ColorRect.new()
				bar.color = Color(PANEL_EDGE, 0.2)
				bar.custom_minimum_size = Vector2(2, 44)
				bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(bar)
			var cell := VBoxContainer.new()
			cell.custom_minimum_size.x = STAT_WIDTH - (2 if i > 0 else 0)
			cell.alignment = BoxContainer.ALIGNMENT_CENTER
			cell.add_theme_constant_override("separation", -4)
			row.add_child(cell)
			var line := HBoxContainer.new()
			line.alignment = BoxContainer.ALIGNMENT_CENTER
			line.add_theme_constant_override("separation", 8)
			cell.add_child(line)
			var icon := _icon(picked[i]["icon"], PANEL_TEXT, 28)
			line.add_child(icon)
			var value := _title("", 32, PANEL_TEXT)
			line.add_child(value)
			var caption := _label(picked[i]["label"], 17, PANEL_MUTED)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(caption)
			overview_cells.append({"value": value, "icon": icon})
	# O nome do lugar fica embaixo do radar (ou das asas), e a missão logo abaixo.
	var bottom := RADAR_TOP + (RADAR_SIZE if medallion else (RADAR_SIZE + WING_HEIGHT) / 2)
	overview_title.position = Vector2(0, bottom + 2)
	quest_chip.position.y = bottom + 44
	_ignore_mouse(overview)


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
	const FILL := Color(0.098, 0.118, 0.165, 0.95)
	const EDGE := Color("f2ca76")
	const TEXT := Color("f5efdf")
	const ORBIT := 0.52 # onde os ícones ficam, em fração do raio
	const ICON := 0.24 # tamanho do ícone, em fração do radar
	const MIN_APART := 0.8 # radianos: ícones na mesma direção se afastam um pouco (a ponta na borda continua exata)
	var xp := -1.0
	var center_text := ""
	var center_note := ""
	var title_font: Font
	var pins := [] # {icon, angle, spot, color}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists("res://assets/fonts/LilitaOne-Regular.ttf"):
			title_font = load("res://assets/fonts/LilitaOne-Regular.ttf")

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
		if spots.size() == 2:
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
			var icon: Control = pin["icon"]
			icon.color = targets[i]["color"]
			icon.position = pin["spot"] - icon.custom_minimum_size / 2
			icon.queue_redraw()
		queue_redraw()

	func _draw() -> void:
		var mid := size / 2
		var radius := size.x / 2 - 3
		draw_circle(mid, radius, FILL)
		draw_arc(mid, radius, 0.0, TAU, 72, Color(EDGE, 0.75), 3.0, true)
		if xp >= 0.0: # trilho e progresso da experiência, por dentro da borda
			draw_arc(mid, radius - 7, 0.0, TAU, 72, Color(EDGE, 0.15), 6.0, true)
			draw_arc(mid, radius - 7, -PI / 2, -PI / 2 + TAU * clampf(xp, 0.0, 1.0), 72, EDGE, 6.0, true)
		if not pins.is_empty():
			draw_circle(mid, 6.0, TEXT)
			for pin in pins:
				# disco atrás do ícone: lê como um marcador do mapa
				var disc := size.x * ICON * 0.66
				draw_circle(pin["spot"], disc, Color(0.03, 0.04, 0.06, 0.85))
				draw_arc(pin["spot"], disc, 0.0, TAU, 32, Color(pin["color"], 0.8), 2.0, true)
		if center_text != "" and title_font != null:
			draw_string(title_font, mid + Vector2(-size.x / 2, 16), center_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 48, TEXT)
			draw_string(get_theme_default_font(), mid + Vector2(-size.x / 2, 44), center_note, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color(EDGE, 0.9))


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
		var count_label := _title("", 20, Color.WHITE)
		count_label.add_theme_color_override("font_outline_color", Color.BLACK)
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


## Destaca na fila todas as vezes de `unit` e apaga as dos outros; null tira o destaque.
func highlight(unit) -> void:
	if unit == highlighted:
		return
	highlighted = unit
	if last_state != null:
		_refresh_timeline(last_state)


## Prevê na fila a magia que o menu oferece: o mago sai da frente e o selo
## de magia aparece na vez em que ela seria solta. null desfaz a prévia.
func preview_cast(state, unit, time: int) -> void:
	var next := {} if unit == null else {unit: time}
	if next == cast_preview:
		return
	cast_preview = next
	_refresh_timeline(state)


func _refresh_timeline(state) -> void:
	last_state = state
	for child in timeline.get_children():
		timeline.remove_child(child)
		child.queue_free()
	if timeline_tween != null:
		timeline_tween.kill()
	timeline.position.y = TIMELINE_Y
	# Fora de combate não há fila para mostrar.
	timeline.visible = state.in_combat() and state.turn_order().size() > 1
	var order: Array = state.timeline(TIMELINE_SIZE, cast_preview)
	# Magia que sai depois do fim da fila: a última vaga vira o selo dela, com as ações que faltam além.
	var beyond := 0
	for unit in state.units:
		if unit.alive() and (not unit.pending.is_empty() or cast_preview.has(unit)):
			var at: int = state.actions_until(unit, cast_preview)
			if at >= TIMELINE_SIZE and (beyond == 0 or at - TIMELINE_SIZE + 1 < beyond):
				beyond = at - TIMELINE_SIZE + 1
				order[TIMELINE_SIZE - 1] = unit
	# Quem está em foco mas é lento demais para caber na fila toma a última vaga, com as ações que faltam.
	var focus_beyond := 0
	if highlighted != null and highlighted.alive() and not order.has(highlighted):
		focus_beyond = state.actions_until(highlighted, cast_preview) - TIMELINE_SIZE + 1
		order[TIMELINE_SIZE - 1] = highlighted
		beyond = 0
	# Esteira: quem acabou de jogar sobe e some, os outros sobem um degrau e o novo entra por baixo.
	var shift := _shift_between(timeline_units, order)
	var strip: Array = timeline_units.slice(0, shift) + order
	var seen := {}
	var departed_seen := {}
	var boxes := []
	for i in strip.size():
		var leaving: bool = i < shift
		# Na prévia de magia, a vez atual já foi gasta: ninguém leva o selo amarelo.
		var first: bool = cast_preview.is_empty() and i == 0
		var far: int = beyond if not leaving and i == strip.size() - 1 else 0
		var box := _timeline_box(strip[i], first, departed_seen if leaving else seen, far)
		if focus_beyond > 0 and not leaving and i == strip.size() - 1:
			box.add_child(_later_label(focus_beyond))
		if leaving:
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		timeline.add_child(box)
		boxes.append(box)
	timeline_units = order
	if shift == 0:
		return
	var distance := (PORTRAIT_SIZE + 5) * shift
	timeline_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	timeline_tween.tween_property(timeline, "position:y", TIMELINE_Y - distance, TIMELINE_SLIDE_TIME)
	for i in shift:
		timeline_tween.tween_property(boxes[i], "modulate:a", 0.0, TIMELINE_SLIDE_TIME)
	for i in range(boxes.size() - shift, boxes.size()):
		var fade_to: float = boxes[i].modulate.a
		boxes[i].modulate.a = 0.0
		timeline_tween.tween_property(boxes[i], "modulate:a", fade_to, TIMELINE_SLIDE_TIME)


## Quantos lugares a fila andou: o menor k em que `before` sem os k primeiros bate com o
## começo de `after` (a última vaga pode ser o selo de uma magia distante). 0 quando a
## ordem mudou de outro jeito, como esperar ou preparar magia: sem esteira.
func _shift_between(before: Array, after: Array) -> int:
	for k in range(1, mini(4, before.size())):
		var overlap := mini(before.size() - k, after.size() - 1)
		if overlap < 4:
			break
		var same := true
		for i in overlap:
			if before[k + i] != after[i]:
				same = false
				break
		if same:
			return k
	return 0


func _timeline_box(unit, first: bool, seen: Dictionary, beyond: int) -> PanelContainer:
	var color := PLAYER_COLOR if unit.team == Data.Team.PLAYER else ENEMY_COLOR
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	if unit == highlighted:
		box.add_theme_stylebox_override("panel", _box(Color(0.62, 0.64, 0.7), FOCUS_COLOR, 6, 8, 4))
		box.custom_minimum_size = Vector2(PORTRAIT_SIZE + 22, PORTRAIT_SIZE)
	else:
		box.add_theme_stylebox_override("panel", _box(Color(0.42, 0.44, 0.5), ACTIVE_COLOR if first else color, 3 if first else 2, 8, 4))
		if highlighted != null:
			box.modulate = Color(1, 1, 1, 0.45)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_timeline_input.bind(unit))
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % unit.type_id)
	var info: Dictionary = meta[unit.type_id]
	atlas.region = Rect2(0, 0, info["cell_w"], info["cell_h"])
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(portrait)
	# A primeira vez de quem carrega magia é quando ela é solta.
	var far := beyond > 0
	if far or (not seen.has(unit) and (not unit.pending.is_empty() or cast_preview.has(unit))):
		box.add_theme_stylebox_override("panel", _box(Color(0.42, 0.44, 0.5), CAST_COLOR, 5, 8, 4))
		box.custom_minimum_size.x = PORTRAIT_SIZE + 22
		var flame := Icon.new()
		flame.setup("flame", CAST_COLOR, 26)
		flame.size_flags_horizontal = Control.SIZE_SHRINK_END
		flame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.add_child(flame)
		var charging := Label.new()
		charging.text = "MAGIA"
		charging.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		charging.add_theme_font_size_override("font_size", 17)
		charging.add_theme_color_override("font_color", CAST_COLOR)
		charging.add_theme_color_override("font_outline_color", Color.BLACK)
		charging.add_theme_constant_override("outline_size", 6)
		charging.size_flags_vertical = Control.SIZE_SHRINK_END
		box.add_child(charging)
		if far:
			box.add_child(_later_label(beyond))
	# O nome de quem está em foco fica ao lado da fila, não no mapa.
	if unit == highlighted and not seen.has(unit):
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(holder)
		var name_tag := Label.new()
		name_tag.text = unit.display_name
		name_tag.position = Vector2(box.custom_minimum_size.x + 6, PORTRAIT_SIZE / 2.0 - 34)
		name_tag.add_theme_font_size_override("font_size", 28)
		name_tag.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
		name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		name_tag.add_theme_constant_override("outline_size", 10)
		holder.add_child(name_tag)
		var role_tag := Label.new()
		role_tag.text = unit.role
		role_tag.position = name_tag.position + Vector2(2, 36)
		role_tag.add_theme_font_size_override("font_size", 17)
		role_tag.add_theme_color_override("font_color", Color.WHITE)
		role_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		role_tag.add_theme_constant_override("outline_size", 6)
		holder.add_child(role_tag)
	seen[unit] = true
	return box


## "+N": quantas ações além do fim da fila.
func _later_label(count: int) -> Label:
	var later := Label.new()
	later.text = "+%d" % count
	later.add_theme_font_size_override("font_size", 17)
	later.add_theme_color_override("font_color", Color.WHITE)
	later.add_theme_color_override("font_outline_color", Color.BLACK)
	later.add_theme_constant_override("outline_size", 6)
	later.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	later.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return later


func _on_timeline_input(event: InputEvent, unit) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		unit_picked.emit(unit)


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
