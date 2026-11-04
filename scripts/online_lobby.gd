extends Control

# Resolve services after the content pack is mounted by the thin installer.
var online_session:
	get: return get_node("/root/OnlineSession")

var sound_manager:
	get: return get_node("/root/SoundManager")

## Lista de salas e, dentro da sala, a escolha de heróis. Mesmo transporte do Raid Alien.
const Data = preload("res://scripts/game_data.gd")
const Icon = preload("res://scripts/icon.gd")
const UnitView = preload("res://scripts/unit_view.gd")
const INK := Color("191e2a")
const TEXT := Color("f5efdf")
const DIM := Color("9da5b5")
const GOLD := Color("f2ca76")
const CARD_FILL := Color("252d3e")
const CARD_HOVER := Color("2e374b")
const FREE_BORDER := Color("3a4458")
## Cor de cada jogador, pela ordem de entrada na sala.
const PLAYER_COLORS := [Color("5aa6ff"), Color("6fd08c"), Color("ff9a4d"), Color("e978c8")]
const CARD_SIZE := Vector2(224, 396)
const CARD_ABILITIES := 3
const PORTRAIT_HEIGHT := 150
const CARD_FPS := 10.0
const ANIM_IDLE := 0
const ANIM_ATTACK := 2
var status: Label
var heading: Label
var room_list: VBoxContainer
var player_row: HBoxContainer
var hero_row: HBoxContainer
var hero_cards := []
var unit_meta := {}
var fields: HBoxContainer
var name_input: LineEdit
var start_button: Button
var create_button: Button
var refresh_button: Button
var leave_button: Button
var browser_header: HBoxContainer
var pagination: HBoxContainer
var previous_button: Button
var next_button: Button
var page_label: Label
var rooms: Array = []
var page := 0
const ROOMS_PER_PAGE := 4
var pending := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	heading = _label(column, "SALAS ONLINE", 36)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fields = HBoxContainer.new()
	fields.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(fields)
	name_input = _field(fields, "Seu nome", online_session.player_name, 220)
	name_input.max_length = 20
	browser_header = HBoxContainer.new()
	column.add_child(browser_header)
	var list_heading := _label(browser_header, "SALAS ABERTAS", 24)
	list_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_button = _button(browser_header, "ATUALIZAR", _refresh)
	status = _label(column, "Buscando salas…", 18)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_row = HBoxContainer.new()
	player_row.alignment = BoxContainer.ALIGNMENT_CENTER
	player_row.add_theme_constant_override("separation", 10)
	column.add_child(player_row)
	unit_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	hero_row = HBoxContainer.new()
	hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_row.add_theme_constant_override("separation", 16)
	hero_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(hero_row)
	for hero in online_session.hero_count():
		hero_cards.append(_hero_card(hero))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	room_list = VBoxContainer.new()
	room_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(room_list)
	pagination = HBoxContainer.new()
	pagination.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(pagination)
	previous_button = _button(pagination, "ANTERIOR", _change_page.bind(-1))
	page_label = _label(pagination, "", 18)
	next_button = _button(pagination, "PRÓXIMA", _change_page.bind(1))
	create_button = _button(column, "CRIAR SALA", _create)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	leave_button = _button(actions, "VOLTAR", _back)
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button = _button(actions, "INICIAR COMBATE", online_session.start_match)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Dourado quando dá para começar, como o botão principal do menu.
	start_button.add_theme_stylebox_override("normal", _box(GOLD, GOLD, 0, 10, 20))
	start_button.add_theme_stylebox_override("hover", _box(Color("ffe0a0"), Color("ffe0a0"), 0, 10, 20))
	start_button.add_theme_stylebox_override("pressed", _box(Color("d5aa58"), Color("d5aa58"), 0, 10, 20))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		start_button.add_theme_color_override(state, INK)
	online_session.changed.connect(_update)
	online_session.relay.room_list_changed.connect(_rooms)
	online_session.relay.room_list_failed.connect(func(_reason): status.text = "Não foi possível buscar as salas. Toque em ATUALIZAR para tentar de novo.")
	online_session.match_started.connect(_begin)
	_update()
	_refresh()
	var refresh_timer := Timer.new()
	refresh_timer.wait_time = 30.0
	refresh_timer.timeout.connect(func():
		if not pending and not online_session.relay.in_room(): online_session.relay.refresh_room_list())
	add_child(refresh_timer)
	refresh_timer.start()

func _process(delta: float) -> void:
	if not hero_row.visible: return
	for card in hero_cards:
		card.time += delta
		var sheet: Dictionary = unit_meta[card.type_id]
		var frame := int(card.time * CARD_FPS)
		# Ao ser escolhido, o herói faz o gesto de ataque uma vez e volta a ficar parado.
		if card.row == ANIM_ATTACK and frame >= UnitView.row_frame_count(sheet, ANIM_ATTACK):
			card.row = ANIM_IDLE
			card.time = 0.0
			frame = 0
		frame %= UnitView.row_frame_count(sheet, card.row)
		card.atlas.region = Rect2(frame * sheet.cell_w, card.row * sheet.cell_h, sheet.cell_w, sheet.cell_h)

func _prepare(persist := true) -> bool:
	online_session.player_name = name_input.text.strip_edges().left(20)
	if online_session.player_name.is_empty(): online_session.player_name = "Jogador"
	if persist: online_session.save_preferences()
	return true

func _refresh() -> void:
	if pending or online_session.relay.in_room(): return
	if _prepare(false):
		status.text = "Buscando salas…"
		online_session.relay.refresh_room_list()

func _create() -> void:
	if pending or online_session.relay.in_room(): return
	if _prepare():
		pending = true
		online_session.create_room()

func _join(code: String) -> void:
	if pending or online_session.relay.in_room(): return
	if _prepare():
		pending = true
		online_session.join_room(code)

func _leave() -> void:
	pending = false
	online_session.leave()
	_refresh()

func _back() -> void:
	if pending or online_session.relay.in_room():
		_leave()
		return
	online_session.relay.stop_room_list()
	online_session.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _update() -> void:
	var in_room: bool = online_session.relay.in_room()
	pending = online_session.relay.state in [1, 2]
	status.text = online_session.notice
	name_input.editable = not in_room and not pending
	fields.visible = not in_room
	heading.text = "SALAS ONLINE"
	create_button.visible = not in_room
	create_button.disabled = pending
	create_button.text = "CONECTANDO…" if pending else "CRIAR SALA"
	refresh_button.disabled = in_room or pending
	browser_header.visible = not in_room
	leave_button.text = "SAIR DA SALA" if in_room else ("CANCELAR" if pending else "VOLTAR")
	start_button.visible = in_room and online_session.relay.is_master
	start_button.disabled = not online_session.can_start()
	player_row.visible = in_room
	hero_row.visible = in_room
	if in_room:
		heading.text = "SALA DE %s · %d/4" % [online_session.players.get(online_session.original_host, "Jogador"), online_session.players.size()]
		status.text = _room_status()
		_render_players()
		_render_heroes()
	room_list.get_parent().visible = not in_room
	room_list.visible = not in_room and not pending
	pagination.visible = not in_room and not pending and rooms.size() > ROOMS_PER_PAGE

func _player_color(id: int) -> Color:
	var index: int = online_session.player_order().find(id)
	return PLAYER_COLORS[index % PLAYER_COLORS.size()] if index >= 0 else DIM

func _room_status() -> String:
	var me: int = online_session.relay.my_id
	var waiting := []
	for id in online_session.player_order():
		if id != me and online_session.heroes_of(id).is_empty(): waiting.append(str(online_session.players[id]))
	if online_session.heroes_of(me).is_empty():
		return "Toque nos heróis que você quer controlar."
	if online_session.players.size() < 2:
		return "Aguardando outro jogador entrar na sala…"
	if not waiting.is_empty():
		if online_session.picks.size() >= Data.PARTY_SIZE:
			return "A party está cheia. Libere um herói para %s." % ", ".join(waiting)
		return "Aguardando %s escolher." % ", ".join(waiting)
	if online_session.relay.is_master:
		return "Tudo pronto! A party tem %d de %d heróis." % [online_session.picks.size(), Data.PARTY_SIZE]
	return "Tudo pronto. Aguardando o dono iniciar a jornada."

func _render_players() -> void:
	for child in player_row.get_children():
		player_row.remove_child(child)
		child.queue_free()
	for id in online_session.player_order():
		var color := _player_color(id)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _box(CARD_FILL, color, 2, 18, 14))
		player_row.add_child(chip)
		var count: int = online_session.heroes_of(id).size()
		var text := str(online_session.players[id])
		if id == online_session.relay.my_id: text += " (você)"
		if id == online_session.original_host: text += " · dono"
		text += "  ·  " + ("escolhendo…" if count == 0 else "%d herói%s" % [count, "" if count == 1 else "s"])
		var label := _label(chip, text, 18)
		label.add_theme_color_override("font_color", color)

func _render_heroes() -> void:
	var me: int = online_session.relay.my_id
	for hero in hero_cards.size():
		var card: Dictionary = hero_cards[hero]
		var picker: int = online_session.picks.get(hero, 0)
		var border := FREE_BORDER
		var tag_fill := Color("1d2330")
		var tag_ink := DIM
		var tag_text := "TOQUE PARA ESCOLHER"
		if picker == me:
			border = _player_color(me)
			tag_fill = border
			tag_ink = INK
			tag_text = "VOCÊ · toque para liberar"
		elif picker != 0:
			border = _player_color(picker)
			tag_fill = border
			tag_ink = INK
			tag_text = str(online_session.players.get(picker, "Jogador"))
		elif online_session.picks.size() >= Data.PARTY_SIZE:
			tag_text = "FORA DA PARTY"
		var taken: bool = picker != 0 and picker != me
		var width := 4 if picker != 0 else 2
		var button: Button = card.button
		button.disabled = taken
		button.modulate = Color(1, 1, 1, 0.7) if taken else Color.WHITE
		button.add_theme_stylebox_override("normal", _box(CARD_FILL, border, width, 16, 0))
		button.add_theme_stylebox_override("disabled", _box(CARD_FILL, border, width, 16, 0))
		button.add_theme_stylebox_override("hover", _box(CARD_HOVER, GOLD if picker == 0 else border, width, 16, 0))
		button.add_theme_stylebox_override("pressed", _box(CARD_HOVER, GOLD, width, 16, 0))
		card.tag.add_theme_stylebox_override("panel", _box(tag_fill, tag_fill, 0, 10, 8))
		card.tag_label.text = tag_text
		card.tag_label.add_theme_color_override("font_color", tag_ink)
		if picker == me and card.picker != me:
			card.row = ANIM_ATTACK
			card.time = 0.0
		card.picker = picker

func _hero_card(hero: int) -> Dictionary:
	var type_id: String = Data.WORLD_HEROES[hero]
	var info: Dictionary = Data.UNIT_TYPES[type_id]
	var button := Button.new()
	# Mais heróis que cabem na largura: as cartas estreitam para a fileira caber na tela.
	var heroes: int = online_session.hero_count()
	button.custom_minimum_size = Vector2(minf(CARD_SIZE.x, (1240.0 - 16 * (heroes - 1)) / heroes), CARD_SIZE.y)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hero_row.add_child(button)
	sound_manager.bind_button(button)
	button.pressed.connect(online_session.pick_hero.bind(hero))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	button.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % type_id)
	var portrait := TextureRect.new()
	portrait.texture = atlas
	portrait.custom_minimum_size.y = PORTRAIT_HEIGHT
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if unit_meta[type_id].get("pixel", false):
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	column.add_child(portrait)
	var title := _label(column, info.name, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TEXT)
	var role := _label(column, info.role, 15)
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.add_theme_color_override("font_color", GOLD)
	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 4)
	column.add_child(stats)
	for stat in [["heart", Color("ef6b5b"), info.hp], ["sword", Color("e2a35a"), info.atk], ["shield", Color("5aa6ff"), info.def], ["bolt", GOLD, info.speed]]:
		var icon := Icon.new()
		icon.setup(stat[0], stat[1], 16)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats.add_child(icon)
		var value := _label(stats, str(stat[2]) + " ", 17)
		value.add_theme_color_override("font_color", TEXT)
	var names := []
	# Magos têm mais de uma dúzia de magias: a carta mostra as primeiras e quantas faltam.
	for ability in info.abilities.slice(0, CARD_ABILITIES): names.append(Data.ABILITIES[ability].name)
	if info.abilities.size() > CARD_ABILITIES:
		names.append("+%d magias" % (info.abilities.size() - CARD_ABILITIES))
	var abilities := _label(column, "\n".join(names), 15)
	abilities.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	abilities.add_theme_color_override("font_color", DIM)
	abilities.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tag := PanelContainer.new()
	column.add_child(tag)
	var tag_label := _label(tag, "", 15)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tag_label.clip_text = true
	_ignore_mouse(margin)
	return {button = button, atlas = atlas, type_id = type_id, tag = tag, tag_label = tag_label, row = ANIM_IDLE, time = randf(), picker = 0}

func _ignore_mouse(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_mouse(child)

func _rooms(available: Array) -> void:
	rooms = available
	page = mini(page, maxi(0, ceili(float(rooms.size()) / ROOMS_PER_PAGE) - 1))
	_render_rooms()

func _change_page(direction: int) -> void:
	page = clampi(page + direction, 0, maxi(0, ceili(float(rooms.size()) / ROOMS_PER_PAGE) - 1))
	_render_rooms()

func _render_rooms() -> void:
	for child in room_list.get_children():
		room_list.remove_child(child)
		child.queue_free()
	status.text = "NENHUMA SALA ABERTA\nCrie uma sala para jogar com amigos." if rooms.is_empty() else "Escolha uma sala para entrar."
	for room in rooms.slice(page * ROOMS_PER_PAGE, (page + 1) * ROOMS_PER_PAGE):
		var code: String = room.code
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 72
		room_list.add_child(row)
		var title := _label(row, room.title, 24)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var count := _label(row, "%d/%d" % [room.players, room.max_players], 24)
		count.custom_minimum_size.x = 100
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var full: bool = room.players >= room.max_players
		var enter := _button(row, "CHEIA" if full else "ENTRAR", _join.bind(code))
		enter.custom_minimum_size.x = 180
		enter.disabled = full
	var total := maxi(1, ceili(float(rooms.size()) / ROOMS_PER_PAGE))
	page_label.text = "  %d / %d  " % [page + 1, total]
	previous_button.disabled = page == 0
	next_button.disabled = page >= total - 1
	pagination.visible = total > 1 and not pending and not online_session.relay.in_room()

func _begin() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _field(parent: Node, placeholder: String, text: String, width: float) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.text = text
	field.custom_minimum_size = Vector2(width, 44)
	parent.add_child(field)
	return field

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	parent.add_child(button)
	sound_manager.bind_button(button)
	button.pressed.connect(action)
	return button

func _box(fill: Color, border: Color, width: int, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding / 2.0
	style.content_margin_bottom = padding / 2.0
	return style
