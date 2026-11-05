extends RefCounted

## Ficha da unidade no estilo do mockup D1/D2: retrato, vida, atributos e habilidades.

const Data = preload("res://scripts/game_data.gd")
const SpellPreview = preload("res://scripts/spell_preview.gd")
const UnitView = preload("res://scripts/unit_view.gd")

const CARD_WIDTH := 620.0
const CARD_WIDTH_WIDE := 1000.0
const CARD_PORTRAIT_SIZE := Vector2(130, 150)
const STAT_FILL := Color(0.95, 0.9, 0.77)
const HP_ENEMY := Color(0.89, 0.29, 0.23)
const SPELL_INK := Color(0.35, 0.14, 0.66)
const CARD_FPS := 14.0
const SPELL_COLOR := Color(0.72, 0.3, 1.0)
const ANIM_ATTACK := 2 # linhas da folha de sprites: parado, andando, atacando, apanhando

var hud: BattleHud # a tela dona deste módulo


func _init(host: Node) -> void:
	hud = host


func card_open() -> bool:
	return hud.card.visible


## Ficha da unidade no estilo do mockup D1/D2: números com ícone em vez de frases.
## `info`: title, team, type_id, hp, max_hp, order, atk, def, speed, abilities e,
## se ela prepara magia, spell. Cada habilidade: name, icon, range, amount, amount_icon,
## time e, quando ameaça o herói da vez, hero_type e hero_amount.
func show_card(info: Dictionary) -> void:
	hide_card()
	hud.card_info = info
	var casting: bool = info.has("spell")
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = CARD_WIDTH
	panel.add_theme_stylebox_override("panel", hud._box(hud.MENU_FILL, hud.MENU_INK, 3, 20, 16))
	hud.card.add_child(panel)
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
	heading.add_child(hud._title(info["title"], 36, hud.PLAYER_INK if info["team"] == Data.Team.PLAYER else hud.DAMAGE_INK))
	heading.add_child(_hp_bar(info["hp"], info["max_hp"], info["team"]))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	heading.add_child(stats)
	for stat in [["sword", Color(0.7, 0.15, 0.12), info["atk"]], ["shield", Color(0.16, 0.44, 0.71), info["def"]], ["bolt", Color(0.76, 0.49, 0.0), info["speed"]]]:
		var chip := hud._pill(stat[0], stat[1], str(stat[2]), STAT_FILL, hud.MENU_INK, 50, 26)
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
	var footer := hud._label("Toque para fechar", 16, hud.MENU_INK)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	hud.card_row = ANIM_ATTACK if casting else hud.ANIM_IDLE
	hud.card_time = 0.0
	_update_card_frame()
	hud._ignore_mouse(panel) # qualquer toque no cartão chega ao fundo e fecha
	panel.reset_size()
	panel.position = (hud.SCREEN - panel.get_combined_minimum_size()) / 2
	hud.card.visible = true
	hud.sound_manager.play_ui(&"switch3")


# Retrato animado numa moldura da cor do time (roxa se prepara magia) com a vez no canto.
func _card_portrait(info: Dictionary, casting: bool) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size = CARD_PORTRAIT_SIZE
	var border := SPELL_COLOR if casting else (hud.PLAYER_COLOR if info["team"] == Data.Team.PLAYER else hud.ENEMY_COLOR)
	var box := Panel.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_stylebox_override("panel", hud._box(Color(0.29, 0.31, 0.37), border, 4, 16, 0))
	frame.add_child(box)
	var portrait := TextureRect.new()
	hud.card_atlas = AtlasTexture.new()
	hud.card_atlas.atlas = load("res://assets/units/%s.png" % info["type_id"])
	portrait.texture = hud.card_atlas
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(portrait)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", hud._box(hud.OPTION_FILL, hud.MENU_INK, 3, 22, 0))
	badge.custom_minimum_size = Vector2(46, 46)
	badge.position = Vector2(-12, -12)
	var order := hud._title("%dº" % info["order"] if info["order"] > 0 else "–", 20, hud.MENU_INK)
	order.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(order)
	frame.add_child(badge)
	return frame


func _hp_bar(hp: int, max_hp: int, team: int) -> Control:
	var bar := Panel.new()
	bar.custom_minimum_size.y = 30
	bar.add_theme_stylebox_override("panel", hud._box(Color(0.23, 0.1, 0.09), hud.MENU_INK, 2, 15, 0))
	var fill := Panel.new()
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.anchor_right = float(hp) / max_hp
	fill.add_theme_stylebox_override("panel", hud._box(hud.PLAYER_COLOR if team == Data.Team.PLAYER else HP_ENEMY, hud.MENU_INK, 2, 15, 0))
	bar.add_child(fill)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	center.add_child(row)
	row.add_child(hud._icon("heart", Color.WHITE, 16))
	row.add_child(hud._title("%d/%d" % [hp, max_hp], 20, Color.WHITE))
	return bar


# Um botão por habilidade: ícone grande, nome e selos de alcance, efeito e tempo.
# compact encolhe tudo para caber em três colunas.
func _ability_row(ability: Dictionary, compact := false) -> Control:
	var k := 0.7 if compact else 1.0
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", hud._box(Color.WHITE, Color(0.9, 0.85, 0.71), 2, 16, 6 if compact else 10))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", roundi(12 * k))
	row.add_child(line)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(60, 60) * k
	tile.add_theme_stylebox_override("panel", hud._box(hud.OPTION_FILL, hud.OPTION_FILL, 0, 14, 0))
	var tile_center := CenterContainer.new()
	tile_center.add_child(hud._icon(ability["icon"], hud.MENU_INK, 34 * k))
	tile.add_child(tile_center)
	line.add_child(tile)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", roundi(6 * k))
	line.add_child(text)
	text.add_child(hud._title(ability["name"], roundi(26 * k), hud.MENU_INK))
	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 6)
	text.add_child(badges)
	if ability["range"] != "":
		badges.add_child(hud._pill("hexagon", Color(0.82, 0.42, 0.0), ability["range"], Color(1.0, 0.89, 0.76), hud.MENU_INK, roundi(30 * k), roundi(18 * k)))
	badges.add_child(hud._pill(ability["amount_icon"], hud.DAMAGE_INK if ability["amount_icon"] == "star" else hud.HEAL_INK, ability["amount"], Color(0.98, 0.83, 0.81), hud.MENU_INK, roundi(30 * k), roundi(18 * k)))
	var time_badge := hud._pill("hourglass", Color(0.29, 0.31, 0.37), str(ability["time"]), Color(0.89, 0.9, 0.93), hud.MENU_INK, roundi(30 * k), roundi(18 * k))
	time_badge.tooltip_text = ability.get("time_hint", "Tempo até poder agir novamente")
	badges.add_child(time_badge)
	if ability.get("effect", "") != "":
		# Efeito extra (empurra, marca, envenena...) numa linha curta embaixo dos números.
		var effect: Label = hud._title(ability["effect"], roundi(18 * k), hud.MENU_INK)
		effect.modulate.a = 0.75
		text.add_child(effect)
	if ability.has("hero_type"):
		var threat := PanelContainer.new()
		threat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		threat.add_theme_stylebox_override("panel", hud._box(Color(0.98, 0.83, 0.81), Color(0.98, 0.83, 0.81), 0, 30, 6))
		var threat_row := HBoxContainer.new()
		threat_row.add_theme_constant_override("separation", 8)
		threat.add_child(threat_row)
		threat_row.add_child(_face(ability["hero_type"]))
		threat_row.add_child(hud._title("−%d" % ability["hero_amount"], 32, hud.DAMAGE_INK))
		line.add_child(threat)
	return row


# Rosto do herói ameaçado: o primeiro quadro da folha, cortado na cabeça.
func _face(type_id: String) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", hud._box(Color(0.29, 0.31, 0.37), hud.PLAYER_COLOR, 3, 12, 2))
	var face := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % type_id)
	var sheet: Dictionary = hud.meta[type_id]
	atlas.region = Rect2(0, 0, sheet["cell_w"], sheet["cell_h"] * 0.6)
	face.texture = atlas
	face.custom_minimum_size = Vector2(44, 44)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(face)
	return box


func _spell_block(spell: Dictionary) -> Control:
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel", hud._box(Color(0.94, 0.89, 1.0), SPELL_COLOR, 3, 16, 12))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	block.add_child(line)
	hud.card_spell = SpellPreview.new()
	hud.card_spell.setup(spell["radius"], SPELL_COLOR)
	line.add_child(hud.card_spell)
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 8)
	line.add_child(text)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	text.add_child(header)
	var tag := hud._label("PREPARANDO", 15, SPELL_INK)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(tag)
	header.add_child(hud._title(spell["name"], 30, SPELL_INK))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	text.add_child(grid)
	grid.add_child(hud._pill("hexagon", SPELL_COLOR, "%d casas" % spell["cells"], Color.WHITE, hud.MENU_INK, 40, 19))
	grid.add_child(hud._pill("star", hud.DAMAGE_INK, "até %d" % spell["power"], Color.WHITE, hud.MENU_INK, 40, 19))
	grid.add_child(hud._pill("hourglass", Color(0.29, 0.31, 0.37), "solta em %d ações" % spell["actions"], Color.WHITE, hud.MENU_INK, 40, 19))
	if spell["secret"]:
		grid.add_child(hud._pill("eye_off", Color.WHITE, "local secreto", Color(0.16, 0.14, 0.25), Color.WHITE, 40, 19))
	else:
		grid.add_child(hud._pill("warning", Color(0.76, 0.49, 0.0), "pega aliados", Color.WHITE, hud.MENU_INK, 40, 19))
	for pill in grid.get_children():
		pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return block


func hide_card() -> void:
	if hud.card.visible:
		hud.sound_manager.play_ui(&"switch4")
	hud.card.visible = false
	hud.card_spell = null
	for child in hud.card.get_children():
		hud.card.remove_child(child)
		child.queue_free()


# Quem prepara magia aparece fazendo o gesto de ataque em loop; os outros, parados.
func _update_card_frame() -> void:
	var sheet: Dictionary = hud.meta[hud.card_info["type_id"]]
	var frame := int(hud.card_time * CARD_FPS) % UnitView.row_frame_count(sheet, hud.card_row)
	hud.card_atlas.region = Rect2(frame * sheet["cell_w"], hud.card_row * sheet["cell_h"], sheet["cell_w"], sheet["cell_h"])
