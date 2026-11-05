extends CanvasLayer

# Resolve services after the content pack is mounted by the thin installer.
var sound_manager:
	get: return get_node("/root/SoundManager")

## Interface: fila de turnos à esquerda e um menu que abre em cima da casa tocada.

const GameSettings = preload("res://scripts/game_settings.gd")
const VOLUME_WIDTH := 136
const VOLUME_PANEL_WIDTH := 260
const VOLUME_Y := 74

signal option_pressed(index: int)
signal order_toggled(on: bool)
signal restart_pressed
signal skills_pressed
signal menu_pressed
signal party_pressed(unit)
signal rotate_held(direction: int) # -1 ou 1 enquanto o botão está apertado; 0 ao soltar
signal together_toggled(on: bool)
signal unit_picked(unit)

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
var volume_button: Button
var volume_panel: PanelContainer
var volume_slider: HSlider
var volume_mute: Button
var objective: Label
var detail: Label
var end_menu_button: Button
var party_row: HBoxContainer
var party_cards := {} # herói -> {panel, fill, status}
var together_button: Button
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

	_build_volume()

	# Cartão de detalhes: cobre a tela toda para que o toque que fecha não caia no tabuleiro.
	card = ColorRect.new()
	card.color = Color(0, 0, 0, 0.55)
	card.size = SCREEN
	card.visible = false
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			hide_card())
	add_child(card)


## Botão de volume, no canto, com um painel que abre embaixo dele.
func _build_volume() -> void:
	GameSettings.apply()
	volume_button = _corner_button("", Vector2(SCREEN.x - VOLUME_WIDTH - MARGIN, VOLUME_Y), VOLUME_WIDTH)
	volume_panel = PanelContainer.new()
	volume_panel.position = Vector2(SCREEN.x - VOLUME_PANEL_WIDTH - MARGIN, VOLUME_Y + 54)
	volume_panel.custom_minimum_size.x = VOLUME_PANEL_WIDTH
	volume_panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.95), Color(1.0, 0.85, 0.4), 2, 8, 10))
	volume_panel.visible = false
	add_child(volume_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	volume_panel.add_child(column)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.value = GameSettings.volume()
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.custom_minimum_size.y = 36
	column.add_child(volume_slider)
	volume_mute = Button.new()
	volume_mute.toggle_mode = true
	volume_mute.button_pressed = GameSettings.muted()
	volume_mute.focus_mode = Control.FOCUS_NONE
	volume_mute.text = "Silenciar"
	volume_mute.custom_minimum_size.y = 44
	sound_manager.bind_button(volume_mute, &"switch1")
	column.add_child(volume_mute)
	volume_button.pressed.connect(func(): volume_panel.visible = not volume_panel.visible)
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


func _show_volume() -> void:
	volume_button.text = "Sem som" if GameSettings.muted() or GameSettings.volume() == 0 else "Volume %d%%" % GameSettings.volume()


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
	var tag := _label("PREPARANDO", 15, SPELL_INK)
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
func show_menu(anchor: Vector2, title: String, title_team: int, info: String, options: Array) -> void:
	hide_menu()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	menu.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var name_label := _label(title, 26, MENU_INK if title_team < 0 else (PLAYER_INK if title_team == Data.Team.PLAYER else DAMAGE_INK))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
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
		menu_buttons.append(_add_option(list, options[i], i))
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
	var detail := _label(option["detail"], 26 if tone != "" else 18, DAMAGE_INK if tone == "damage" else (HEAL_INK if tone == "heal" else ink))
	detail.size_flags_vertical = Control.SIZE_FILL
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(detail)
	# A linha fica sobreposta ao botão (não é contêiner): a largura mínima vem dela.
	button.custom_minimum_size.x = row.get_combined_minimum_size().x + 32 + row.get_theme_constant("separation")
	return button


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


## Barra da party, embaixo: mostra a vida de todos e seleciona o herói. `owners` tem o nome
## do jogador de cada herói no online.
func setup_party(heroes: Array, owners: Dictionary) -> void:
	party_row = HBoxContainer.new()
	party_row.position = Vector2(90, 606)
	party_row.add_theme_constant_override("separation", 8)
	add_child(party_row)
	for unit in heroes:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(200, 62)
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
		var name_label := _label(title, 15, Color.WHITE)
		name_label.clip_text = true
		name_label.custom_minimum_size.x = 130
		column.add_child(name_label)
		var back := ColorRect.new()
		back.color = Color(0, 0, 0, 0.7)
		back.custom_minimum_size = Vector2(130, 10)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(back)
		var fill := ColorRect.new()
		fill.color = PLAYER_COLOR
		fill.size = Vector2(130, 10)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(fill)
		var status := _label("", 13, Color(0.85, 0.87, 0.92))
		column.add_child(status)
		party_cards[unit] = {"panel": panel, "fill": fill, "status": status}
	var rotate_left := _corner_button("⟲ Q", Vector2(SCREEN.x - 300, MARGIN), 90)
	rotate_left.button_down.connect(func(): rotate_held.emit(-1))
	rotate_left.button_up.connect(func(): rotate_held.emit(0))
	var rotate_right := _corner_button("E ⟳", Vector2(SCREEN.x - 202, MARGIN), 90)
	rotate_right.button_down.connect(func(): rotate_held.emit(1))
	rotate_right.button_up.connect(func(): rotate_held.emit(0))
	together_button = _corner_button("", Vector2(SCREEN.x - 104, MARGIN), 92)
	together_button.toggle_mode = true
	together_button.button_pressed = true
	together_button.toggled.connect(func(on):
		_show_together(on)
		together_toggled.emit(on))
	_show_together(true)


func _corner_button(text: String, at: Vector2, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	button.position = at
	button.custom_minimum_size = Vector2(width, 48)
	sound_manager.bind_button(button, &"switch1")
	add_child(button)
	return button


func _show_together(on: bool) -> void:
	together_button.text = "Em fila" if on else "Separados"


func set_together(on: bool) -> void:
	together_button.button_pressed = on


func update_party(current) -> void:
	for unit in party_cards:
		var card: Dictionary = party_cards[unit]
		card.fill.size.x = 130.0 * clampf(float(unit.hp) / unit.max_hp, 0.0, 1.0)
		card.status.text = "%d/%d" % [unit.hp, unit.max_hp] if unit.alive() else "caído"
		card.panel.modulate.a = 1.0 if unit.alive() else 0.5
		var border := ACTIVE_COLOR if unit == current else Color(0.3, 0.33, 0.4)
		card.panel.add_theme_stylebox_override("panel", _box(Color(0.1, 0.11, 0.14, 0.92), border, 3 if unit == current else 1, 8, 6))


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
		charging.add_theme_font_size_override("font_size", 15)
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
