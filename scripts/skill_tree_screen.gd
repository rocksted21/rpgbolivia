extends Control
## Tela das árvores de skills: escolhe o herói, vê os ramos e compra nós.
## Toda a regra fica em skill_data e hero_progress; aqui só se mostra e se chama.

const Data = preload("res://scripts/game_data.gd")
const Skills = preload("res://scripts/skill_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const Unit = preload("res://scripts/unit.gd")
const Icon = preload("res://scripts/icon.gd")

const INK := Color("191e2a")
const PANEL := Color("252d3e")
const PANEL_DIM := Color("1f2533")
const GOLD := Color("f2ca76")
const TEXT := Color("f5efdf")
const DIM := Color("9da5b5")
const LOCKED := Color("6b7385")
const LINE_OFF := Color("3a4358")
const STAT_ICONS := {"hp": ["heart", Color("ef6b5b")], "atk": ["sword", Color("e2a35a")], "def": ["shield", Color("5aa6ff")], "speed": ["bolt", GOLD]}
const KIND_ICONS := {"attack": "sword", "charge": "flame", "heal": "heart", "guard": "shield"}

signal bought(type_id: String, node_id: String)
signal closed

const NODE_SIZE := Vector2(196, 92)
const ROW_GAP := 20
const COLUMN_GAP := 16

var sound_manager:
	get: return get_node("/root/SoundManager")

var meta := {}
var hero := ""
var selected := ""
var hero_buttons := {}
var node_buttons := {}
var tree_column: VBoxContainer
var detail_column: VBoxContainer
# Aberta por cima do jogo (cartas da party): mostra só esses heróis e fecha sem trocar de cena.
var embedded := false
var only_heroes := []
var start_hero := ""
var live := false # no meio de uma partida: redistribuir só vale fora dela


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var row := HBoxContainer.new()
	row.position = Vector2(16, 16)
	row.size = Vector2(1248, 688)
	row.add_theme_constant_override("separation", 16)
	add_child(row)

	var heroes := VBoxContainer.new()
	heroes.custom_minimum_size.x = 190
	heroes.add_theme_constant_override("separation", 8)
	row.add_child(heroes)
	for type_id in _heroes():
		_hero_button(heroes, type_id)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	heroes.add_child(spacer)
	var back := _button(heroes, "Fechar" if embedded else "Voltar", false)
	back.pressed.connect(_back)

	tree_column = VBoxContainer.new()
	tree_column.custom_minimum_size.x = NODE_SIZE.x * 3 + COLUMN_GAP * 2
	tree_column.add_theme_constant_override("separation", 10)
	row.add_child(tree_column)

	var side := PanelContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_stylebox_override("panel", _box(PANEL_DIM, Color.TRANSPARENT, 0, 16))
	row.add_child(side)
	detail_column = VBoxContainer.new()
	detail_column.add_theme_constant_override("separation", 10)
	side.add_child(detail_column)

	_select_hero(start_hero if start_hero in _heroes() else _heroes()[0])


func _heroes() -> Array:
	var all := Skills.hero_types()
	if only_heroes.is_empty():
		return all
	return only_heroes.filter(func(type_id): return type_id in all)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _back() -> void:
	if embedded:
		closed.emit()
		queue_free()
		return
	get_tree().change_scene_to_file(str(get_tree().root.get_meta("skills_back", "res://scenes/main_menu.tscn")))


func _select_hero(type_id: String) -> void:
	hero = type_id
	selected = ""
	_render()


func _render() -> void:
	for type_id in hero_buttons:
		_style_hero_button(type_id)
	_render_tree()
	_render_detail()


# --- Coluna de heróis --------------------------------------------------------

func _hero_button(parent: Control, type_id: String) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(190, 92)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_select_hero.bind(type_id))
	sound_manager.bind_button(button)
	parent.add_child(button)
	var inner := HBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("separation", 8)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inner)
	inner.add_child(_face(type_id))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(column)
	var name_label := _label(column, Data.UNIT_TYPES[type_id]["name"], 18, TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var points := _label(column, "", 16, GOLD)
	hero_buttons[type_id] = {"button": button, "points": points}


func _style_hero_button(type_id: String) -> void:
	var entry: Dictionary = hero_buttons[type_id]
	var current: bool = type_id == hero
	var fill := PANEL if current else PANEL_DIM
	var border := GOLD if current else Color.TRANSPARENT
	for state in ["normal", "hover", "pressed"]:
		entry["button"].add_theme_stylebox_override(state, _box(fill, border, 2, 8))
	var free := HeroProgress.available(type_id)
	entry["points"].text = "Nv %d · %d %s" % [HeroProgress.level(type_id), free, "ponto" if free == 1 else "pontos"]
	entry["points"].add_theme_color_override("font_color", GOLD if free > 0 else DIM)


func _face(type_id: String) -> TextureRect:
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % type_id)
	var sheet: Dictionary = meta[type_id]
	atlas.region = Rect2(0, 0, sheet["cell_w"], sheet["cell_h"] * 0.6)
	var face := TextureRect.new()
	face.texture = atlas
	face.custom_minimum_size = Vector2(56, 56)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sheet.get("pixel", false):
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return face


# --- Árvore ------------------------------------------------------------------

func _render_tree() -> void:
	_clear(tree_column)
	node_buttons.clear()
	var info: Dictionary = Data.UNIT_TYPES[hero]
	_label(tree_column, info["name"], 30, TEXT)
	_label(tree_column, info["role"], 17, GOLD)
	var unlocked := HeroProgress.unlocked(hero)
	var earned := HeroProgress.earned(hero)
	_level_row(tree_column)
	_label(tree_column, "%d pontos livres · %d de %d ganhos no total" % [HeroProgress.available(hero), earned, Skills.MAX_POINTS], 17, DIM)
	var grid := Control.new()
	var branches: Array = Skills.tree(hero)
	grid.custom_minimum_size = Vector2(tree_column.custom_minimum_size.x, 36 + (NODE_SIZE.y + ROW_GAP) * 4)
	tree_column.add_child(grid)
	for b in branches.size():
		var x: float = b * (NODE_SIZE.x + COLUMN_GAP)
		var title := _label(grid, branches[b]["name"], 18, GOLD)
		title.position = Vector2(x, 0)
		title.size = Vector2(NODE_SIZE.x, 28)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var nodes: Array = branches[b]["nodes"]
		for tier in nodes.size():
			var y: float = 36 + tier * (NODE_SIZE.y + ROW_GAP)
			if tier > 0:
				var bought: bool = nodes[tier - 1]["id"] in unlocked
				var link := ColorRect.new()
				link.color = GOLD if bought else LINE_OFF
				link.position = Vector2(x + NODE_SIZE.x / 2 - 2, y - ROW_GAP)
				link.size = Vector2(4, ROW_GAP)
				grid.add_child(link)
			_node_button(grid, nodes[tier], Vector2(x, y), tier, unlocked, earned)


## Nível e barra de experiência do herói, em cima da árvore.
func _level_row(parent: Control) -> void:
	var level := HeroProgress.level_info(hero)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	_label(row, "Nível %d" % level["level"], 20, GOLD)
	var back := Panel.new()
	back.custom_minimum_size = Vector2(260, 14)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.add_theme_stylebox_override("panel", _box(PANEL_DIM, Color.TRANSPARENT, 0, 0))
	row.add_child(back)
	var fill := Panel.new()
	fill.size = Vector2(260 * clampf(level["fraction"], 0.0, 1.0), 14)
	fill.add_theme_stylebox_override("panel", _box(GOLD, Color.TRANSPARENT, 0, 0))
	back.add_child(fill)
	if level["max"]:
		_label(row, "máximo", 17, DIM)
	else:
		_label(row, "%d / %d XP" % [HeroProgress.xp(hero), Skills.HERO_LEVEL_XP[level["level"]]], 17, DIM)


func _node_button(parent: Control, node: Dictionary, at: Vector2, tier: int, unlocked: Array, earned: int) -> void:
	var id: String = node["id"]
	var owned: bool = id in unlocked
	var can_buy := Skills.can_unlock(hero, unlocked, id, earned)
	var open := Skills.requirement_met(hero, unlocked, id)
	var button := Button.new()
	button.position = at
	button.size = NODE_SIZE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var fill := GOLD if owned else (PANEL if open else PANEL_DIM)
	var border := TEXT if id == selected else (GOLD if can_buy else Color.TRANSPARENT)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, _box(fill, border, 2, 8))
	button.pressed.connect(func():
		selected = id
		_render())
	sound_manager.bind_button(button)
	parent.add_child(button)
	node_buttons[id] = button

	var ink := INK if owned else (TEXT if open else LOCKED)
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(inner)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(head)
	var icon := Icon.new()
	var kind := _node_icon(node)
	icon.setup(kind[0], ink if owned else (kind[1] if open else LOCKED), 22)
	head.add_child(icon)
	var name_label := _label(inner, node["name"], 16, ink)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var status := "comprado" if owned else ("%d pt" % Skills.TIER_COST[tier])
	var cost := _label(inner, status, 13, INK if owned else (GOLD if can_buy else LOCKED))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _node_icon(node: Dictionary) -> Array:
	if node.has("unlock"):
		var ability: Dictionary = Data.ABILITIES[node["unlock"]]
		if ability.has("shot") and ability["shot"] == "kit/arrow":
			return ["arrow", TEXT]
		var kind: String = KIND_ICONS.get(ability["kind"], "star")
		return [kind, GOLD]
	for stat in node.get("stats", {}):
		return STAT_ICONS[stat]
	return ["star", GOLD]


# --- Detalhes ----------------------------------------------------------------

func _render_detail() -> void:
	_clear(detail_column)
	var unlocked := HeroProgress.unlocked(hero)
	var preview = Unit.new(hero, Data.Team.PLAYER, Vector2i.ZERO, unlocked)
	_label(detail_column, "Atributos", 16, GOLD)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	detail_column.add_child(stats)
	for entry in [["hp", preview.max_hp], ["atk", preview.atk], ["def", preview.def], ["speed", preview.speed]]:
		var icon := Icon.new()
		icon.setup(STAT_ICONS[entry[0]][0], STAT_ICONS[entry[0]][1], 18)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats.add_child(icon)
		_label(stats, str(entry[1]) + "  ", 18, TEXT)
	_label(detail_column, "Habilidades: %d" % preview.abilities.size(), 15, DIM)
	detail_column.add_child(HSeparator.new())

	if selected == "":
		var hint := _label(detail_column, "Toque num nó da árvore para ver o que ele faz.", 16, DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		_render_selected(unlocked, preview)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_child(spacer)
	var note := _label(detail_column, "Cada nível dá 1 ponto. Os heróis ganham experiência derrotando inimigos e no fim de cada luta ou jornada." + (" Redistribuir: fora da partida." if live else " Redistribuir é grátis."), 16, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if live:
		return
	var reset := _button(detail_column, "Redistribuir pontos", false)
	reset.disabled = unlocked.is_empty()
	reset.pressed.connect(func():
		HeroProgress.reset(hero)
		_render())


func _render_selected(unlocked: Array, preview) -> void:
	var found := Skills.locate(hero, selected)
	var node: Dictionary = found["node"]
	var title := _label(detail_column, node["name"], 24, TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var description := _label(detail_column, node["desc"], 16, TEXT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if node.has("unlock"):
		var summary := _label(detail_column, _ability_summary(preview, node["unlock"]), 15, DIM)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if selected in unlocked:
		_label(detail_column, "Comprado", 16, GOLD)
		return
	var cost: int = Skills.TIER_COST[found["tier"]]
	var buy := _button(detail_column, "Comprar · %d %s" % [cost, "ponto" if cost == 1 else "pontos"], true)
	if not Skills.requirement_met(hero, unlocked, selected):
		buy.disabled = true
		var previous: String = Skills.tree(hero)[found["branch"]]["nodes"][found["tier"] - 1]["name"]
		var need := _label(detail_column, "Requer %s." % previous, 15, DIM)
		need.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	elif not Skills.can_unlock(hero, unlocked, selected, HeroProgress.earned(hero)):
		buy.disabled = true
		_label(detail_column, "Pontos insuficientes.", 15, DIM)
	buy.pressed.connect(func():
		if HeroProgress.unlock(hero, selected):
			bought.emit(hero, selected)
			_render())


## Números da habilidade com os atributos atuais do herói.
func _ability_summary(preview, ability_id: String) -> String:
	var ability: Dictionary = preview.ability(ability_id)
	var parts := []
	match ability["kind"]:
		"attack", "charge":
			parts.append("Dano base %d" % roundi(preview.atk * ability["power"]))
			parts.append(Data.range_text(ability))
		"heal":
			parts.append("Cura %d" % ability["heal"])
			parts.append(Data.range_text(ability))
		"guard":
			parts.append("Guarda, em si")
	parts.append("tempo %d" % maxi(1, roundi(ability["time"] * 10.0 / preview.speed)))
	return " · ".join(parts)


# --- Peças -------------------------------------------------------------------

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else TEXT)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK if primary else TEXT)
	button.add_theme_color_override("font_disabled_color", LOCKED)
	button.add_theme_stylebox_override("normal", _box(GOLD if primary else PANEL, Color.TRANSPARENT, 0, 8))
	button.add_theme_stylebox_override("hover", _box(Color("ffe0a0"), Color.TRANSPARENT, 0, 8))
	button.add_theme_stylebox_override("pressed", _box(Color("d5aa58"), Color.TRANSPARENT, 0, 8))
	button.add_theme_stylebox_override("disabled", _box(PANEL_DIM, Color.TRANSPARENT, 0, 8))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(button)
	sound_manager.bind_button(button)
	return button


func _box(fill: Color, border: Color, width: int, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(margin)
	return style
