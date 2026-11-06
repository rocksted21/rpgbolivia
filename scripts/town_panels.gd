extends Control
## Interface da Cidade-Farol: botões no canto e as janelas de moradores e da party.

signal depart(party: Array)
signal skills_requested
signal menu_requested
signal changed

const Data = preload("res://scripts/game_data.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const Town = preload("res://scripts/town_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Content = preload("res://scripts/town_content.gd")

const SCREEN := Vector2(1280, 720)
const WINDOW_WIDTH := 720
const CORNER_WIDTH := 200
const INK := Color("191e2a")
const PANEL := Color("252d3e")
const GOLD := Color("f2ca76")
const TEXT := Color("f5efdf")
const MUTED := Color("aab2c2")
const GOOD := Color("9fe39a")
const PORTRAIT := 124
const SCROLL_HEIGHT := 400
const CHOICE_WIDTH := 330

var sound_manager:
	get: return get_node("/root/SoundManager")

var action_button: Button
var log_button: Button
var nearby := {}
var window: Control
var party := []
var hero_buttons := {}
var start_button: Button


func setup(chosen: Array) -> void:
	party = chosen.duplicate()
	size = SCREEN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var leave := _button(self, "Partir para a\nExpedição", true)
	_place_corner(leave, 76, SCREEN.y - 12 - 92 - 8 - 76) # acima das cartas da party
	leave.pressed.connect(open_party)
	action_button = _button(self, "")
	_place_corner(action_button, 56, SCREEN.y - 12 - 92 - 8 - 76 - 8 - 56)
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
	for person in Town.PEOPLE:
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
	for person in Town.PEOPLE:
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


func open_party() -> void:
	var body := _open("Party da expedição")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	var carried: Array = Content.ITEM_ORDER.filter(func(id): return TownProgress.item_count(id) > 0).map(func(id):
		return "%d× %s" % [TownProgress.item_count(id), Content.ITEMS[id]["name"]])
	if not carried.is_empty():
		_paragraph(body, "Na mochila: %s" % ", ".join(carried), GOLD)
	hero_buttons.clear()
	var units_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	for id in Data.WORLD_HEROES:
		var button := _button(grid, "")
		_fill_hero(button, id, units_meta[id])
		hero_buttons[id] = button
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	_close_button(row, "Ficar na cidade")
	var menu := _button(row, "Menu principal")
	menu.pressed.connect(func(): menu_requested.emit())
	start_button = _button(row, "", true)
	start_button.pressed.connect(_depart)
	_show_party()


func _fill_hero(button: Button, id: String, info: Dictionary) -> void:
	var data: Dictionary = Data.UNIT_TYPES[id]
	button.custom_minimum_size = Vector2(340, 92)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % id)
	atlas.region = Rect2(0, 0, info["cell_w"], info["cell_h"])
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(84, 84)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
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


func _toggle(id: String) -> void:
	if id in party:
		party.erase(id)
	elif party.size() < Data.PARTY_SIZE:
		party.append(id)
	_show_party()


func _show_party() -> void:
	for id in hero_buttons:
		var chosen: bool = id in party
		var style := _box(Color("3b3a2c") if chosen else PANEL)
		if chosen:
			style.border_color = GOLD
			style.set_border_width_all(4)
		hero_buttons[id].add_theme_stylebox_override("normal", style)
	start_button.disabled = party.is_empty()
	start_button.text = "Partir com %d de %d" % [party.size(), Data.PARTY_SIZE]


func _depart() -> void:
	var chosen := []
	for id in Data.WORLD_HEROES: # ordem fixa: a mesma party sempre sai igual
		if id in party:
			chosen.append(id)
	depart.emit(chosen)


# --- Peças da janela -----------------------------------------------------------

func close_window() -> void:
	if window != null:
		window.queue_free()
		window = null


## Abre uma janela centralizada, que bloqueia os cliques no mapa. Devolve onde pôr o conteúdo.
func _open(title: String) -> Control:
	close_window()
	window = ColorRect.new()
	(window as ColorRect).color = Color(0, 0, 0, 0.55)
	window.size = SCREEN
	add_child(window)
	var center := CenterContainer.new()
	center.size = SCREEN
	window.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size.x = WINDOW_WIDTH
	var style := _box(INK)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_content_margin_all(22)
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
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(parent: Control, text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 52)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", INK if primary else TEXT)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_stylebox_override("normal", _box(GOLD if primary else PANEL))
	button.add_theme_stylebox_override("hover", _box(Color("ffe0a0")))
	button.add_theme_stylebox_override("pressed", _box(Color("d5aa58")))
	button.add_theme_stylebox_override("disabled", _box(Color("1f2533")))
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
