extends Control
## Interface da Cidade-Farol: botões no canto e as janelas de moradores e da party.

signal depart(party: Array)
signal party_changed(party: Array) # nova party; o primeiro é o líder
signal skills_requested
signal menu_requested
signal changed

const Data = preload("res://scripts/game_data.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const Town = preload("res://scripts/town_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Content = preload("res://scripts/town_content.gd")
const Brass = preload("res://scripts/hud/brass.gd") # latão e vinho, como o HUD e o Diário
const Icon = preload("res://scripts/icon.gd")
const HeroRoster = preload("res://scripts/hero_roster.gd") # heróis ainda não recrutados ficam como "?"

const SCREEN := Vector2(1280, 720)
const WINDOW_WIDTH := 720
const CORNER_WIDTH := 200
const INK := Color("2a1319")
const PANEL := Color("16090c")
const GOLD := Color("f2ca76")
const TEXT := Color("f4dcb8")
const MUTED := Color("cdb596")
const GOOD := Color("9fe39a")
const PORTRAIT := 124
const SCROLL_HEIGHT := 400
const CHOICE_WIDTH := 330
const CORNER_BOTTOM := SCREEN.y - 12 - 92 - 8 # logo acima das cartas da party
const DEPART_SIZE := Vector2(236, 38) # aba dourada pendurada na faixa do topo
const DEPART_TOP := 42.0 # a faixa do topo tem 44 de altura: a aba encosta na borda dela
const SLOT_SIZE := Vector2(160, 150)

var sound_manager:
	get: return get_node("/root/SoundManager")

var action_button: Button
var log_button: Button
var nearby := {}
var window: Control
var party := [] # a party da cidade, em ordem: o primeiro é o líder
var draft := [] # a party sendo montada na janela
var hero_buttons := {}
var slot_row: HBoxContainer
var save_button: Button
var start_button: Button
var party_button: Button
var depart_button: Button
var units_meta := {}
var portrait_regions := {} # herói: o pedaço do primeiro quadro que tem desenho


## `can_edit`: a party pode mudar aqui (online a party é a da sala).
func setup(chosen: Array, can_edit := true) -> void:
	party = chosen.duplicate()
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	units_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	party_button = _button(self, "Configurar Party")
	_place_corner(party_button, 56, CORNER_BOTTOM - 56)
	party_button.pressed.connect(open_party_setup)
	party_button.visible = can_edit
	depart_button = _depart_tab()
	action_button = _button(self, "")
	_place_corner(action_button, 56, CORNER_BOTTOM - 56 - 8 - 56)
	action_button.visible = false
	action_button.pressed.connect(func(): open_person(nearby))
	log_button = _button(self, "")
	_place_corner(log_button, 56, 392) # abaixo da coluna de botões
	log_button.pressed.connect(open_log)
	refresh()


## Atualiza o que muda quando se compra, aceita ou entrega algo.
func refresh() -> void:
	log_button.text = "Missões (%d)" % (TownProgress.quests_with("active").size() + TownProgress.quests_with("ready").size())


func _place_corner(button: Button, height: float, y: float) -> void:
	button.custom_minimum_size = Vector2(CORNER_WIDTH, height)
	button.size = button.custom_minimum_size
	button.clip_text = true
	button.position = Vector2(SCREEN.x - CORNER_WIDTH - 16, y)


func window_open() -> bool:
	return window != null


## Quem está perto do herói selecionado. Muda o botão de conversar.
func set_nearby(person: Dictionary) -> void:
	if person == nearby:
		return
	nearby = person
	action_button.visible = not person.is_empty()
	if not person.is_empty():
		action_button.text = ("Ler: %s" if person["service"] == "board" else "Falar: %s") % person["name"]


func open_person(person: Dictionary) -> void:
	if person["service"] == "board":
		open_board(person)
		return
	if person.get("needs", "") != "" and person["needs"] not in TownProgress.rescued():
		var ruins := _open(person["name"])
		_paragraph(ruins, Town.MISSING_TEXT)
		_close_button(ruins)
		return
	if person["service"] == "guide" and TownProgress.story_pending():
		_tell_story(person, TownProgress.pending_pages(), 0)
		return
	_conversation(person, _greeting(person))
	TownProgress.set_stage_seen(person["id"])
	if not TownProgress.met(person["id"]):
		TownProgress.set_met(person["id"])
		changed.emit() # conhecer alguém pode mudar o objetivo do topo


func _greeting(person: Dictionary) -> String:
	var talk: Dictionary = Content.TALK[person["id"]]
	if not TownProgress.met(person["id"]):
		return talk["first"]
	if talk.has("defeat") and not TownProgress.last_won():
		return talk["defeat"][TownProgress.expeditions() % talk["defeat"].size()]
	var stage := TownProgress.story_stage()
	var stages: Dictionary = talk.get("stages", {})
	if stages.has(stage) and TownProgress.stage_seen(person["id"]) < stage:
		return stages[stage] # a fala do capítulo, uma vez
	if TownProgress.beacons() > 0 and talk.has("after_beacon") and TownProgress.expeditions() % 2 == 1:
		return talk["after_beacon"]
	return talk["greetings"][TownProgress.expeditions() % talk["greetings"].size()]


## A conversa: retrato, a fala e o que dá para responder.
func _conversation(person: Dictionary, text: String) -> void:
	var body := _open(person["name"])
	_speech(body, person["art"], text)
	var choices := GridContainer.new()
	choices.columns = 2
	choices.add_theme_constant_override("h_separation", 10)
	choices.add_theme_constant_override("v_separation", 10)
	body.add_child(choices)
	_add_quest_choices(choices, person)
	_add_service_choice(choices, person)
	for topic in _topics(person["id"]):
		_choice(choices, topic[0]).pressed.connect(func(): _conversation(person, topic[1]))
	_choice(choices, "Até mais").pressed.connect(close_window)


## Retrato e fala lado a lado.
func _speech(body: Control, art: String, text: String) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	body.add_child(top)
	top.add_child(_portrait(art))
	var said := _label(text, 21, TEXT)
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.custom_minimum_size.x = WINDOW_WIDTH - 44 - PORTRAIT - 18
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(said)


## Perguntas fixas, as que a história já abriu e as dos guardiões que caíram.
func _topics(id: String) -> Array:
	var talk: Dictionary = Content.TALK[id]
	var out: Array = talk["topics"].duplicate()
	var stage := TownProgress.story_stage()
	var opened: Dictionary = talk.get("topics_at", {})
	for at in opened:
		if at <= stage:
			out.append(opened[at])
	var tales: Dictionary = talk.get("guardians", {})
	for kind in TownProgress.guardians():
		if tales.has(kind):
			out.append(tales[kind])
	return out


## O guia conta os capítulos que faltam, uma fala por vez. No fim, diz o que fazer.
func _tell_story(person: Dictionary, pages: Array, index: int) -> void:
	var page: Array = pages[index]
	var speaker := _person(page[0])
	var body := _open(speaker.get("name", person["name"]))
	_speech(body, speaker.get("art", person["art"]), page[1])
	var row := _row(body)
	var last := index == pages.size() - 1
	_button(row, "Entendi" if last else "Continuar", true).pressed.connect(func():
		if not last:
			_tell_story(person, pages, index + 1)
			return
		TownProgress.hear_story()
		TownProgress.set_met(person["id"])
		changed.emit()
		_conversation(person, TownProgress.objective_help()))


func _person(id: String) -> Dictionary:
	for person in Town.people():
		if person["id"] == id:
			return person
	return {}


func _add_quest_choices(choices: Control, person: Dictionary) -> void:
	for id in TownProgress.quests_of(person["id"]):
		var quest: Dictionary = Content.QUESTS[id]
		match TownProgress.quest_status(id):
			"ready":
				_choice(choices, "? Entregar: %s" % quest["title"], true).pressed.connect(func(): _turn_in(person, id))
			"available":
				_choice(choices, "! Pedido: %s" % quest["title"], true).pressed.connect(func(): _offer(person, id))
			"active":
				_choice(choices, "%s (%d/%d)" % [quest["title"], TownProgress.quest_progress(id), quest["target"]]).disabled = true


func _add_service_choice(choices: Control, person: Dictionary) -> void:
	match person["service"]:
		"resident":
			var service: String = Exp.RESIDENTS[person["id"]]["service"]
			_choice(choices, "Ver: %s" % service).pressed.connect(func(): _open_resident(person))
		"shop":
			_choice(choices, "Ver o que tem à venda").pressed.connect(func(): open_shop(person))
		"memories":
			_choice(choices, "Ouvir as memórias").pressed.connect(func(): _open_memories(person))
		"skills":
			_choice(choices, "Treinar (árvores de skills)").pressed.connect(func(): skills_requested.emit())
		"beacon":
			_choice(choices, "Como está a cidade?").pressed.connect(func(): _open_beacon(person))
		"guide":
			_choice(choices, "O que eu faço agora?", true).pressed.connect(func(): _conversation(person, TownProgress.objective_help()))
			var told := TownProgress.story_heard()
			if told >= 0:
				_choice(choices, "Conte de novo").pressed.connect(func(): _tell_story(person, Content.STORY[told]["pages"], 0))
	# Quem tem outro serviço também pode vender (o Ferreiro forja, a Padeira assa...).
	if person["service"] != "shop" and Content.ITEM_ORDER.any(func(id): return Content.ITEMS[id]["seller"] == person["id"]):
		_choice(choices, "Ver o que tem à venda").pressed.connect(func(): open_shop(person))


func _offer(person: Dictionary, id: String) -> void:
	var quest: Dictionary = Content.QUESTS[id]
	var body := _open(quest["title"])
	_paragraph(body, quest["offer"])
	_paragraph(body, "Objetivo: %s" % quest["goal"], GOLD)
	_paragraph(body, "Recompensa: %s" % _reward_text(quest["reward"]), GOOD)
	var row := _row(body)
	_button(row, "Aceitar", true).pressed.connect(func():
		TownProgress.accept_quest(id)
		changed.emit()
		_conversation(person, "Conto com você."))
	_button(row, "Agora não").pressed.connect(func(): _conversation(person, _greeting(person)))


func _turn_in(person: Dictionary, id: String) -> void:
	if not TownProgress.complete_quest(id):
		return
	sound_manager.play_sfx(&"victory")
	changed.emit()
	var quest: Dictionary = Content.QUESTS[id]
	_conversation(person, "%s\n\nRecebido: %s" % [quest["done"], _reward_text(quest["reward"])])


func _reward_text(reward: Dictionary) -> String:
	var parts := []
	if reward["brasas"] > 0:
		parts.append("%d brasas" % reward["brasas"])
	for item in reward["items"]:
		parts.append("%d× %s" % [reward["items"][item], Content.ITEMS[item]["name"]])
	return ", ".join(parts)


func _open_resident(person: Dictionary) -> void:
	var id: String = person["id"]
	var data: Dictionary = Exp.RESIDENTS[id]
	var body := _open(data["service"])
	_paragraph(body, "Brasas: %d" % TownProgress.brasas(), GOLD)
	var main_cost := TownProgress.next_cost(id)
	_offer_row(body, "%s (%d de %d)" % [data["service"], TownProgress.service_level(id), data["costs"].size()], data["effect"] % data["per_level"], main_cost, func():
		if TownProgress.buy(id):
			changed.emit()
			_open_resident(person))
	for upgrade_id in Content.UPGRADE_ORDER:
		var upgrade: Dictionary = Content.UPGRADES[upgrade_id]
		if upgrade["resident"] != id:
			continue
		_offer_row(body, "%s (%d de %d)" % [upgrade["name"], TownProgress.upgrade_level(upgrade_id), upgrade["costs"].size()], upgrade["effect"] % upgrade["per_level"], TownProgress.upgrade_cost(upgrade_id), func():
			if TownProgress.buy_upgrade(upgrade_id):
				changed.emit()
				_open_resident(person))
	_back_button(body, person)


## Uma linha com nome, efeito e botão de pagar. cost negativo: nível máximo.
func _offer_row(parent: Control, title: String, effect: String, cost: int, on_buy: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(_label(title, 20, TEXT))
	var detail := _label(effect, 16, MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = WINDOW_WIDTH - 44 - 200 - 12
	text.add_child(detail)
	var buy := _button(row, "%d brasas" % cost if cost >= 0 else "Máximo", true)
	buy.disabled = cost < 0 or cost > TownProgress.brasas()
	buy.pressed.connect(on_buy)
	return buy


func open_shop(person: Dictionary) -> void:
	var body := _open("%s: à venda" % person["name"])
	_paragraph(body, "Brasas: %d" % TownProgress.brasas(), GOLD)
	for id in Content.ITEM_ORDER:
		var item: Dictionary = Content.ITEMS[id]
		if item["seller"] != person["id"]:
			continue
		var have := TownProgress.item_count(id)
		var full: bool = have >= item["max"]
		var buy := _offer_row(body, "%s (na mochila: %d de %d)" % [item["name"], have, item["max"]], item["text"], -1 if full else item["price"], func():
			if TownProgress.buy_item(id):
				changed.emit()
				open_shop(person))
		if full:
			buy.text = "Mochila cheia"
	_back_button(body, person)


func _open_memories(person: Dictionary) -> void:
	var body := _open("Memórias")
	var note := TownProgress.last_note()
	if note != "":
		_paragraph(body, note, GOLD)
	var found := TownProgress.memories()
	if found == 0:
		_paragraph(body, Town.NO_MEMORY_TEXT)
	for i in found:
		_paragraph(body, Exp.MEMORIES[i])
	_back_button(body, person)


func _open_beacon(person: Dictionary) -> void:
	var body := _open("Cidade-Farol")
	_paragraph(body, Town.BEACON_TEXT)
	_paragraph(body, "Faróis acesos: %d   ·   Expedições: %d" % [TownProgress.beacons(), TownProgress.expeditions()], GOLD)
	var missing: Array = Exp.RESIDENT_ORDER.filter(func(id): return id not in TownProgress.rescued())
	if not missing.is_empty():
		_paragraph(body, "Ainda faltam na cidade: %s. Procure as vilas lá fora." % ", ".join(missing.map(func(id): return Exp.RESIDENTS[id]["name"])), MUTED)
	_paragraph(body, "Objetivo: %s" % TownProgress.objective(), GOLD)
	_back_button(body, person)


func open_board(_person: Dictionary = {}) -> void:
	var body := _open("Mural de Missões")
	_paragraph(body, Content.BOARD_TEXT, MUTED)
	_fill_quests(_scroll(body))
	_close_button(body)


## Missões e mochila, de qualquer lugar da cidade.
func open_log() -> void:
	var body := _open("Missões e mochila")
	var list := _scroll(body)
	_fill_quests(list)
	list.add_child(_label("Mochila", 22, GOLD))
	var carrying := false
	for id in Content.ITEM_ORDER:
		var count := TownProgress.item_count(id)
		if count > 0:
			carrying = true
			_paragraph(list, "%d× %s: %s" % [count, Content.ITEMS[id]["name"], Content.ITEMS[id]["text"]])
	if not carrying:
		_paragraph(list, "Vazia. A Mercadora fica na praça.", MUTED)
	_close_button(body)


func _fill_quests(list: Control) -> void:
	var names := {}
	for person in Town.people():
		names[person["id"]] = person["name"]
	var sections := [["ready", "Prontas para entregar", GOOD], ["active", "Em andamento", GOLD], ["available", "Pedidos novos", TEXT]]
	var any := false
	for section in sections:
		var quests: Array = TownProgress.quests_with(section[0])
		if quests.is_empty():
			continue
		any = true
		list.add_child(_label(section[1], 22, section[2]))
		for id in quests:
			var quest: Dictionary = Content.QUESTS[id]
			var progress := " (%d/%d)" % [TownProgress.quest_progress(id), quest["target"]] if section[0] != "available" else ""
			_paragraph(list, "%s%s · %s %s" % [quest["title"], progress, quest["goal"], "Fale com: %s." % names[quest["giver"]]])
	if not any:
		_paragraph(list, Content.NOTHING_TEXT, MUTED)


func _scroll(body: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WINDOW_WIDTH - 44, SCROLL_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	return list


## Só a figura do morador, sem as margens transparentes da arte.
func _portrait(art: String) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	frame.add_theme_stylebox_override("panel", _box(PANEL))
	var texture: Texture2D = load(Town.TOWN_ROOT % art)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(texture.get_image().get_used_rect())
	var picture := TextureRect.new()
	picture.texture = atlas
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(picture)
	return frame


func _choice(parent: Control, text: String, primary := false) -> Button:
	var button := _button(parent, text, primary)
	button.custom_minimum_size = Vector2(CHOICE_WIDTH, 48)
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 16)
	return button


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row


func _back_button(parent: Control, person: Dictionary) -> void:
	_button(parent, "Voltar").pressed.connect(func(): _conversation(person, _greeting(person)))


# --- Partir -------------------------------------------------------------------

## Aba dourada pendurada no meio da faixa do topo: sempre à vista, sem cobrir o mapa.
func _depart_tab() -> Button:
	var tab := Button.new()
	tab.focus_mode = Control.FOCUS_NONE
	tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tab.tooltip_text = "Ver a party e partir para a expedição"
	tab.custom_minimum_size = DEPART_SIZE
	tab.size = DEPART_SIZE
	tab.position = Vector2((SCREEN.x - DEPART_SIZE.x) / 2.0, DEPART_TOP)
	tab.add_theme_stylebox_override("normal", _tab_style(Brass.GOLD))
	tab.add_theme_stylebox_override("hover", _tab_style(Color("ffe1a0")))
	tab.add_theme_stylebox_override("pressed", _tab_style(Brass.GOLD.darkened(0.12)))
	tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(tab)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	var compass := Icon.new()
	compass.setup("compass", Brass.WINE_DEEP, 22)
	compass.angle = -PI / 4.0 # agulha para o nordeste: lê como bússola mesmo pequena
	compass.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(compass)
	var text := Brass.label("Partir em Expedição", 15, Brass.WINE_DEEP, 700)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	# Um brilho lento, para chamar o olho sem piscar.
	var glow := tab.create_tween().set_loops()
	glow.tween_property(tab, "self_modulate", Color(1.12, 1.08, 0.96), 1.4).set_trans(Tween.TRANS_SINE)
	glow.tween_property(tab, "self_modulate", Color.WHITE, 1.4).set_trans(Tween.TRANS_SINE)
	sound_manager.bind_button(tab)
	tab.pressed.connect(open_party)
	return tab


## Aba presa em cima: só os cantos de baixo são redondos e não tem borda no topo.
func _tab_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Brass.BRASS.darkened(0.25)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(Brass.WINE_DEEP, 0.85)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	style.anti_aliasing = true
	return style


## Antes de partir: quem vai, o que leva e o botão de sair da cidade.
func open_party() -> void:
	var body := _open("Partir em expedição")
	_paragraph(body, "A party sai da cidade e só volta quando a expedição acabar.", MUTED)
	var row := _lineup(body)
	for i in party.size():
		row.add_child(_slot(party[i], i == 0, false))
	var carried: Array = Content.ITEM_ORDER.filter(func(id): return TownProgress.item_count(id) > 0).map(func(id):
		return "%d× %s" % [TownProgress.item_count(id), Content.ITEMS[id]["name"]])
	if not carried.is_empty():
		_paragraph(body, "Na mochila: %s" % ", ".join(carried), GOLD)
	var buttons := _row(body)
	_close_button(buttons, "Ficar na cidade")
	if party_button.visible:
		var change := _button(buttons, "Configurar Party")
		change.pressed.connect(open_party_setup)
	start_button = _button(buttons, "Partir", true)
	start_button.disabled = party.is_empty()
	start_button.pressed.connect(_depart)


func _depart() -> void:
	depart.emit(party.duplicate())


# --- Configurar a party ----------------------------------------------------------

## Escolhe quem forma a party e quem lidera. O líder é quem anda com o jogador na cidade.
func open_party_setup() -> void:
	draft = party.duplicate()
	var body := _open("Party")
	_paragraph(body, "O primeiro é o líder: é com ele que você anda pela cidade. Os outros ficam cuidando da vida até a próxima expedição. Toque num herói da fila para ele liderar.", MUTED)
	slot_row = _lineup(body)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	hero_buttons.clear()
	for id in Data.WORLD_HEROES:
		var button := _button(grid, "")
		_fill_hero(button, id, units_meta[id])
		if not HeroRoster.is_unlocked(id):
			_lock_hero(button, id)
		hero_buttons[id] = button
	var buttons := _row(body)
	_close_button(buttons, "Cancelar")
	var menu := _button(buttons, "Menu principal")
	menu.pressed.connect(func(): menu_requested.emit())
	save_button = _button(buttons, "Salvar party", true)
	save_button.pressed.connect(_save_party)
	_show_party()


func _lineup(body: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	return row


## Uma vaga da fila: retrato, nome e o selo de líder. `pick`: tocar faz ele liderar.
func _slot(id: String, leads: bool, pick: bool) -> Control:
	var slot := Button.new()
	slot.focus_mode = Control.FOCUS_NONE
	slot.custom_minimum_size = SLOT_SIZE
	var style := Brass.panel(Color("3b3a2c") if leads else PANEL, GOLD if leads else Brass.BRASS_DIM, 3 if leads else 1, 8, 6, 0)
	for key in ["normal", "hover", "pressed", "disabled"]:
		slot.add_theme_stylebox_override(key, style if key != "hover" or not pick else Brass.panel(Brass.WINE_LIFT, GOLD, 2, 8, 6, 0))
	slot.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if pick and not leads:
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.tooltip_text = "Tornar líder"
		slot.pressed.connect(func(): _make_leader(id))
		sound_manager.bind_button(slot)
	else:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE if not pick else Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(column)
	var tag := _label("★ Líder" if leads else " ", 15, GOLD)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tag)
	var portrait := _hero_portrait(id, 92)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(portrait)
	var hero_name := _label(Data.UNIT_TYPES[id]["name"], 16, TEXT)
	hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_name.clip_text = true
	hero_name.custom_minimum_size.x = SLOT_SIZE.x - 12
	column.add_child(hero_name)
	return slot


## Vaga vazia da fila, para mostrar quantos ainda cabem.
func _empty_slot() -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE
	var style := Brass.panel(Color(PANEL, 0.5), Color(Brass.BRASS_DIM, 0.45), 1, 8, 6, 0)
	slot.add_theme_stylebox_override("panel", style)
	var hint := _label("vaga livre", 15, Brass.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(hint)
	return slot


func _hero_portrait(id: String, side: float) -> TextureRect:
	var info: Dictionary = units_meta[id]
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % id)
	if not portrait_regions.has(id):
		# O quadro tem muita sobra transparente: recorta só o herói, para ele encher a vaga.
		var cell := Rect2i(0, 0, info["cell_w"], info["cell_h"])
		var used := atlas.atlas.get_image().get_region(cell).get_used_rect()
		portrait_regions[id] = Rect2(used) if used.size.x > 0 else Rect2(cell)
	atlas.region = portrait_regions[id]
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2.ONE * side
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return portrait


func _fill_hero(button: Button, id: String, _info: Dictionary) -> void:
	var data: Dictionary = Data.UNIT_TYPES[id]
	# A grade de 2 colunas foi pensada para 3 fileiras (6 heróis); com mais, os cartões encolhem.
	var rows := ceili(Data.WORLD_HEROES.size() / 2.0)
	var height := minf(72.0, (72.0 * 3 + 20 - 10 * (rows - 1)) / rows)
	button.custom_minimum_size = Vector2(340, height)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	row.add_child(_hero_portrait(id, minf(64.0, height - 6)))
	var text := VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(_label(data["name"], 20, TEXT))
	var role := _label(data["role"], 14, MUTED)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.add_child(role)
	button.pressed.connect(func(): _toggle(id))


## Tocar num herói da lista: entra no fim da fila, ou sai dela.
## Herói fora do roster: silhueta, "???" e só a dica de onde ele está. Não entra na party.
func _lock_hero(button: Button, id: String) -> void:
	button.disabled = true
	button.mouse_default_cursor_shape = Control.CURSOR_ARROW
	button.tooltip_text = HeroRoster.hint(id)
	var row: Control = button.get_child(0)
	row.get_child(0).modulate = HeroRoster.LOCKED_TINT
	var words: Array = row.get_child(1).get_children()
	words[0].text = HeroRoster.LOCKED_NAME
	words[1].text = HeroRoster.hint(id)
	words[1].add_theme_color_override("font_color", Brass.DIM)


func _toggle(id: String) -> void:
	if not HeroRoster.is_unlocked(id):
		return
	if id in draft:
		draft.erase(id)
	elif draft.size() < Data.PARTY_SIZE:
		draft.append(id)
	_show_party()


func _make_leader(id: String) -> void:
	draft.erase(id)
	draft.push_front(id)
	_show_party()


func _show_party() -> void:
	for id in hero_buttons:
		var chosen: bool = id in draft
		var style := _box(Color("3b3a2c") if chosen else PANEL)
		if chosen:
			style.border_color = GOLD
			style.set_border_width_all(3)
		hero_buttons[id].add_theme_stylebox_override("normal", style)
	for child in slot_row.get_children():
		slot_row.remove_child(child)
		child.queue_free()
	for i in Data.PARTY_SIZE:
		slot_row.add_child(_slot(draft[i], i == 0, true) if i < draft.size() else _empty_slot())
	save_button.disabled = draft.is_empty()


func _save_party() -> void:
	if draft.is_empty():
		return
	close_window()
	if draft != party:
		party = draft.duplicate()
		party_changed.emit(party.duplicate())


# --- Peças da janela -----------------------------------------------------------

func close_window() -> void:
	if window != null:
		window.queue_free()
		window = null


## Abre uma janela centralizada, que bloqueia os cliques no mapa. Devolve onde pôr o conteúdo.
func _open(title: String) -> Control:
	close_window()
	# z_index só muda o desenho; o clique segue a ordem na árvore. Sem isto, o HUD
	# criado depois (cartas da party, faixa do topo) rouba os cliques da janela.
	move_to_front()
	window = ColorRect.new()
	(window as ColorRect).color = Color(0, 0, 0, 0.55)
	window.size = SCREEN
	add_child(window)
	var center := CenterContainer.new()
	center.size = SCREEN
	window.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size.x = WINDOW_WIDTH
	var style := Brass.panel(INK, Brass.BRASS, 2, 6, 22, 4)
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	box.add_child(body)
	body.add_child(_label(title, 30, GOLD))
	return body


func _close_button(parent: Control, text := "Voltar") -> void:
	var close := _button(parent, text)
	close.pressed.connect(close_window)


func _paragraph(parent: Control, text: String, color := TEXT) -> void:
	var label := _label(text, 19, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WINDOW_WIDTH - 44
	parent.add_child(label)


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Brass.font(700 if font_size >= 22 else 400))
	label.add_theme_font_size_override("font_size", font_size - 2)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(parent: Control, text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 52)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Brass.style_button(button, primary)
	button.add_theme_font_size_override("font_size", 16)
	if not primary: # por cima do mapa o botão precisa de fundo
		button.add_theme_stylebox_override("normal", Brass.panel(Brass.WINE, Brass.BRASS, 2, 4, 8))
	parent.add_child(button)
	sound_manager.bind_button(button)
	return button


func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
