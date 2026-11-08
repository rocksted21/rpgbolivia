extends RefCounted

## Janela da bolsa de cada herói (hero_bag.gd), aberta pelo botão da bolsa na carta da party.
## Mostra os espaços; a Chama Viva tem "Usar" (escolhe o ramo trancado) e qualquer item
## pode ir para outro herói da party, só fora de combate.

const Brass = preload("res://scripts/hud/brass.gd")
const HeroBag = preload("res://scripts/hero_bag.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const Skills = preload("res://scripts/skill_data.gd")

const WIDTH := 640.0

var hud: BattleHud # a tela dona deste módulo
var layer: CanvasLayer
var hero := "" # tipo do herói aberto
var party_types := []
var out_of_combat := true
var picking := {} # {index, action ("use" ou "give")}: o espaço escolhido, esperando o destino


func _init(host: Node) -> void:
	hud = host


func is_open() -> bool:
	return layer != null


## `party`: heróis da party (unidades). `free`: fora de combate (pode passar itens).
func show_bag(unit, party: Array, free: bool) -> void:
	party_types = []
	for member in party:
		if Skills.has_tree(member.type_id) and member.type_id not in party_types:
			party_types.append(member.type_id)
	hero = unit.type_id
	out_of_combat = free
	picking = {}
	_render()


func hide_bag() -> void:
	if layer != null:
		layer.queue_free()
		layer = null
	picking = {}


## Selo da bolsa em cada carta: quantos itens, e brilho roxo se tiver Chama Viva.
func refresh_buttons() -> void:
	for unit in hud.party_cards:
		var card: Dictionary = hud.party_cards[unit]
		if not card.has("bag"):
			continue
		var items := HeroBag.items(unit.type_id)
		var orb := HeroBag.ORB in items
		card["bag_count"].text = str(items.size()) if not items.is_empty() else ""
		card["bag_icon"].color = HeroBag.ORB_COLOR if orb else Brass.MUTED
		card["bag_icon"].queue_redraw()
		card["bag"].tooltip_text = "Bolsa (%d de %d)%s" % [items.size(), HeroBag.SIZE, ": tem Chama Viva!" if orb else ""]


func _render() -> void:
	if layer != null:
		layer.queue_free()
	layer = CanvasLayer.new()
	layer.layer = hud.layer + 5
	hud.add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = hud.SCREEN
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			hide_bag())
	layer.add_child(shade)
	var box: PanelContainer = hud.options_ui._options_box(WIDTH)
	layer.add_child(box)
	var column: VBoxContainer = box.get_child(0)
	column.add_theme_constant_override("separation", 10)
	column.add_child(hud.options_ui._options_title("Bolsa · %s" % HeroBag.hero_name(hero)))
	if party_types.size() > 1:
		column.add_child(_hero_tabs())
	var open := HeroProgress.open_branches(hero).size()
	var branches := Skills.tree(hero).size()
	var info := _text("Ramos da árvore abertos: %d de %d. %d de %d espaços usados." % [open, branches, HeroBag.items(hero).size(), HeroBag.SIZE], 16, Brass.MUTED)
	column.add_child(info)
	var items := HeroBag.items(hero)
	for index in HeroBag.SIZE:
		column.add_child(_slot(index, items[index] if index < items.size() else ""))
	if not picking.is_empty():
		column.add_child(_choices())
	if not HeroBag.editable():
		column.add_child(_text("Online: a bolsa é a do dono da sala; só ele mexe nela.", 15, Brass.DIM))
	elif not out_of_combat:
		column.add_child(_text("Em combate: passar itens só depois da luta.", 15, Brass.DIM))
	var close: Button = hud.options_ui._options_button(column, "Fechar")
	close.pressed.connect(hide_bag)
	hud.options_ui._center(box)


func _hero_tabs() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for type_id in party_types:
		var count := HeroBag.items(type_id).size()
		var tab: Button = hud.options_ui._side_button(row, "%s (%d)" % [HeroBag.hero_name(type_id), count], type_id == hero)
		tab.custom_minimum_size.y = 36
		tab.add_theme_font_size_override("font_size", 14)
		tab.pressed.connect(func():
			hero = type_id
			picking = {}
			_render())
	return row


func _slot(index: int, item_id: String) -> Control:
	var panel := PanelContainer.new()
	var chosen: bool = not picking.is_empty() and picking["index"] == index
	panel.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE_DEEP, HeroBag.ORB_COLOR if chosen else Brass.BRASS_DIM, 2, 6, 8, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	if item_id == "":
		row.add_child(_text("Vazio", 16, Brass.DIM))
		return panel
	var item := HeroBag.item_info(item_id)
	var icon: Control = HeroBag.item_icon(item_id, 44)
	row.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	words.add_child(Brass.label(item["name"], 17, item["color"], 700))
	var desc := _text(item["desc"], 14, Brass.TEXT)
	desc.custom_minimum_size.x = 330
	words.add_child(desc)
	var can_edit := HeroBag.editable()
	if item_id == HeroBag.ORB:
		var use := _small_button(row, "Usar")
		use.disabled = not can_edit or not HeroBag.wants_orb(hero)
		if HeroBag.editable() and not HeroBag.wants_orb(hero):
			use.tooltip_text = "Todos os ramos deste herói já estão abertos."
		use.pressed.connect(func():
			picking = {"index": index, "action": "use"}
			_render())
	var give := _small_button(row, "Passar")
	var targets := party_types.filter(func(type_id): return type_id != hero and HeroBag.free_slots(type_id) > 0)
	give.disabled = not can_edit or not out_of_combat or targets.is_empty()
	if can_edit and out_of_combat and targets.is_empty():
		give.tooltip_text = "Ninguém da party tem espaço livre."
	give.pressed.connect(func():
		picking = {"index": index, "action": "give"}
		_render())
	return panel


## O destino do espaço escolhido: um ramo trancado (Usar) ou outro herói (Passar).
func _choices() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var index: int = picking["index"]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	if picking["action"] == "use":
		column.add_child(_text("Qual ramo abrir? Fica aberto para sempre.", 16, HeroBag.ORB_COLOR))
		for branch in HeroProgress.locked_branches(hero):
			var branch_name: String = Skills.tree(hero)[branch]["name"]
			var open_button: Button = hud.options_ui._side_button(row, branch_name, true)
			open_button.pressed.connect(func():
				if HeroBag.use_orb(hero, index, branch):
					hud.show_banner("Ramo aberto: %s" % branch_name, HeroBag.ORB_COLOR)
				picking = {}
				refresh_buttons()
				_render())
	else:
		column.add_child(_text("Passar para quem?", 16, Brass.GOLD))
		for type_id in party_types:
			if type_id == hero or HeroBag.free_slots(type_id) <= 0:
				continue
			var to: Button = hud.options_ui._side_button(row, HeroBag.hero_name(type_id), true)
			to.pressed.connect(func():
				if out_of_combat and HeroBag.give(hero, index, type_id):
					hud.show_banner("Item passado para %s" % HeroBag.hero_name(type_id), Brass.GOLD)
				picking = {}
				refresh_buttons()
				_render())
	var cancel: Button = hud.options_ui._side_button(row, "Cancelar")
	cancel.pressed.connect(func():
		picking = {}
		_render())
	column.add_child(row)
	return column


func _small_button(parent: Control, text: String) -> Button:
	var button: Button = hud.options_ui._side_button(parent, text)
	button.custom_minimum_size = Vector2(86, 40)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 15)
	return button


func _text(text: String, size: int, color: Color) -> Label:
	var label := Brass.label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 60
	return label
