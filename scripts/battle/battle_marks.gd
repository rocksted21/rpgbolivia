extends RefCounted

## Destaques no tabuleiro (caminho, alcance, área), a dica do rodapé e os
## marcadores de turno e de ordem.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

const TREE_SEE_THROUGH := 0.45
const STEP_COLOR := Color(0.27, 0.67, 1.0, 0.35)
const PATH_COLOR := Color(0.27, 0.67, 1.0, 0.7)
const REACH_FILL := Color(1.0, 0.55, 0.1, 0.3)
const TARGET_COLOR := Color(0.92, 0.24, 0.24, 0.55)
const NEXT_ENEMY_ARROW := Color(0.95, 0.3, 0.25)
const ROAM_HINT := "Clique para andar  ·  Segure Q/E para girar  ·  Tab troca de herói  ·  G alterna fila e separados"
const SIGHT_COLOR := Color(0.95, 0.25, 0.2, 0.28)
const DEFAULT_HINT := "Toque numa casa azul para andar ou num personagem para agir. Segure para ver detalhes."
const END_TURN_KEY_HINT := "Espaço encerra o turno."
# Magia é roxa para não se confundir com o laranja do alcance.
const AREA_COLOR := Color(0.72, 0.3, 1.0, 0.6)

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


# Anel grosso que pulsa na casa do personagem em foco, com o nome em cima dele.
func _build_focus_marker() -> void:
	battle.focus_ring = battle.board_art._new_hex_line(Color(1.0, 0.95, 0.3), 12)
	battle.focus_ring.visible = false
	if battle.focus_tween != null:
		battle.focus_tween.kill()
	battle.focus_tween = battle.create_tween().set_loops()
	battle.focus_tween.tween_property(battle.focus_ring, "modulate:a", 0.35, 0.45)
	battle.focus_tween.tween_property(battle.focus_ring, "modulate:a", 1.0, 0.45)


## Marca no mapa e na fila o mesmo personagem, seja ele vindo do toque no mapa ou na fila.
func _sync_focus() -> void:
	var shown = _shown_unit() if not battle.busy else null
	battle.hud.highlight(shown)
	if shown == null or not shown.alive():
		battle.focus_ring.visible = false
		return
	battle._place_ground_marker(battle.focus_ring, shown.pos)
	battle.focus_ring.z_index = battle._z(battle._row(shown.pos)) + 4 # abaixo do personagem (+5)
	battle.focus_ring.visible = true


## Seta amarela em quem joga e vermelha no próximo inimigo; os números ficam prontos
## para quando forem pedidos.
func _refresh_turn_markers() -> void:
	var order: Array = battle.state.turn_order()
	for unit in battle.views:
		if not order.has(unit) or battle._free_roam():
			battle.views[unit].hide_arrow()
	if battle._free_roam():
		if battle.selected != null and battle.views.has(battle.selected):
			battle.views[battle.selected].show_arrow(battle.ACTIVE_COLOR)
		return
	var next_enemy = null
	for unit in order.slice(1):
		if unit.team == Data.Team.ENEMY:
			next_enemy = unit
			break
	for i in order.size():
		var view = battle.views[order[i]]
		view.set_order(i + 1, i == 0)
		if i == 0:
			view.show_arrow(battle.ACTIVE_COLOR)
		elif order[i] == next_enemy:
			view.show_arrow(NEXT_ENEMY_ARROW)
		else:
			view.hide_arrow()


# Os números mudam a quase toda ação, então só aparecem quando pedidos: todos pelo
# botão de ordem, ou só o da unidade inspecionada.
func _refresh_order_badges() -> void:
	var shown = _shown_unit() if not battle.busy else null
	for unit in battle.views:
		battle.views[unit].set_order_visible(battle.show_order or unit == shown)


func _on_order_toggled(on: bool) -> void:
	battle.show_order = on
	_refresh_order_badges()


func _refresh_overlays() -> void:
	for cell in battle.trees:
		battle.trees[cell].modulate.a = TREE_SEE_THROUGH if _covers_a_unit(cell) else 1.0
	for cell in battle.forests:
		# A frente ainda encobre as pernas, mas deixa uma pista do ocupante.
		var occupant = battle.state.unit_at(cell)
		var clear := _covers_a_unit(cell)
		battle.forests[cell].back.modulate.a = TREE_SEE_THROUGH if clear else 1.0
		battle.forests[cell].front.modulate.a = TREE_SEE_THROUGH if clear else (0.82 if occupant != null and occupant.alive() else 1.0)
	_refresh_order_badges()
	for cell in battle.overlays:
		battle.overlays[cell].visible = false
		battle.reach_lines[cell].visible = false
	battle.inspect_outline.visible = false
	if not battle.busy:
		_mark_free_look()
	# Só a mira dos heróis aparece: ver onde a magia inimiga cai tornaria o mago dela inútil.
	# A IA também não olha a mira dos heróis, então os dois lados jogam no escuro.
	for unit in battle.state.units:
		if unit.alive() and unit.team == Data.Team.PLAYER and not unit.pending.is_empty():
			var ability: Dictionary = unit.ability(unit.pending["ability"])
			for cell in battle.state.area_of(unit.pending["tile"], ability["radius"]):
				_mark(cell, battle.CHARGE_COLOR)
	_sync_focus()


func _mark_free_look() -> void:
	var unit = battle._actor()
	var shown = _shown_unit()
	var focus: Vector2i = battle.menu_cell if battle.menu_cell != battle.NO_CELL else (shown.pos if shown != null else battle.NO_CELL)
	if focus != battle.NO_CELL:
		battle._place_ground_marker(battle.inspect_outline, focus)
		battle.inspect_outline.z_index = battle._z(battle._row(focus)) + 4
		battle.inspect_outline.visible = true
	var spell := _menu_spell()
	if spell != "":
		for cell in battle.state.area_of(battle.menu_cell, unit.ability(spell)["radius"]):
			_mark(cell, AREA_COLOR)
		return
	if battle._free_roam():
		if shown != null and shown != unit:
			for cell in battle.state.sight_cells(shown):
				_mark(cell, SIGHT_COLOR)
		elif battle.hover != battle.NO_CELL:
			for cell in battle.roam_ctl._roam_path(battle.hover):
				_mark(cell, STEP_COLOR)
		return
	if battle.exploring and shown != null and not battle.state.takes_turns(shown):
		for cell in battle.state.sight_cells(shown):
			_mark(cell, SIGHT_COLOR)
		return
	if shown != null and shown != unit:
		_mark_reach(shown)
		return
	var reach: Dictionary = battle.state.move_cells(unit)
	for cell in reach:
		_mark(cell, STEP_COLOR)
	if reach.has(battle.hover):
		for cell in battle.state.straight_path(battle.state.search(unit, battle.state.move_left(unit)), unit.pos, battle.hover):
			_mark(cell, PATH_COLOR)
	_mark_aim(unit)


## Magia carregada que o menu aberto oferece; a área dela fica pintada.
func _menu_spell() -> String:
	for option in battle.menu_options:
		if option["kind"] == "ability" and battle._actor().ability(option["id"])["kind"] == "charge":
			return option["id"]
	return ""


## Quem está sendo inspecionado: o do menu aberto ou, no mouse, o que está sob o cursor.
func _shown_unit():
	if battle.menu_cell != battle.NO_CELL:
		return battle.state.unit_at(battle.menu_cell)
	if battle.pinned != null:
		return battle.pinned
	return battle.state.unit_at(battle.hover) if battle.hover != battle.NO_CELL else null


func _mark_reach(unit) -> void:
	for cell in battle.state.attack_reach(unit):
		_mark_reach_cell(cell)
		var occupant = battle.state.unit_at(cell)
		if occupant != null and occupant.team != unit.team:
			_mark(cell, TARGET_COLOR)


## Para o herói da vez, o laranja é onde ele consegue mirar: no arqueiro e no mago a
## casa colada fica sem cor, e dá para ver na hora que ali ele não acerta.
func _mark_aim(unit) -> void:
	for id in unit.abilities:
		var kind: String = unit.ability(id)["kind"]
		if kind != "attack" and kind != "charge":
			continue
		for cell in battle.state.cells_in_range(unit, id):
			_mark_reach_cell(cell)
			var occupant = battle.state.unit_at(cell)
			if occupant != null and occupant.team != unit.team:
				_mark(cell, TARGET_COLOR)


func _mark_reach_cell(cell: Vector2i) -> void:
	if not battle.reach_lines.has(cell):
		return
	battle.reach_lines[cell].visible = true
	if not battle.overlays[cell].visible:
		_mark(cell, REACH_FILL)


## As árvores são altas: as das duas fileiras da frente podem esconder quem está atrás.
func _covers_a_unit(cell: Vector2i) -> bool:
	if not battle.exploring:
		return false
	for unit in battle.state.units:
		if unit.alive() and battle._row(cell) > battle._row(unit.pos) and Hex.distance(cell, unit.pos) <= 2:
			return true
	return false


func _mark(cell: Vector2i, color: Color) -> void:
	if battle.overlays.has(cell):
		battle.overlays[cell].color = color
		battle.overlays[cell].visible = true


func _preview_text(unit, id: String, target) -> String:
	var result: Dictionary = battle.state.preview_attack(unit, id, target)
	return "−%d flanco" % result["amount"] if result["flank"] else "−%d" % result["amount"]


func _update_hint() -> void:
	battle.input_ctl._refresh_end_turn()
	if battle.busy:
		return
	var unit = battle._actor()
	if battle.online_session.playing and not battle._free_roam():
		var owner: int = battle.online_session.owner_of(unit)
		battle.hud.set_hint("Vez de %s · %s%s" % [unit.display_name, battle.online_session.players.get(owner, "Dono"), " · você joga" if battle.online_session.can_control(unit) else " · aguardando"])
		return
	if battle.hud.menu_open():
		battle.hud.set_hint("")
		return
	var shown = _shown_unit()
	if battle._free_roam() and (shown == null or shown == unit):
		battle.hud.set_hint(ROAM_HINT)
		return
	if shown != null:
		var text := "%s: %s" % [shown.display_name, battle.input_ctl._menu_info(shown).to_lower()]
		if not shown.pending.is_empty():
			text += ". Preparando magia: segure para ver"
		if battle.menu_cell != battle.NO_CELL and shown.team != unit.team:
			text += ". Fora do seu alcance, toque de novo para fechar."
		battle.hud.set_hint(text)
	elif battle.hover != battle.NO_CELL and battle.input_ctl._can_walk_to(unit, battle.hover):
		var notes := battle.input_ctl._terrain_notes(unit, battle.hover)
		battle.hud.set_hint("%s%s" % [battle.state.tile_name_at(battle.hover), ": " + ". ".join(notes) if not notes.is_empty() else ""])
	elif battle._free_roam():
		battle.hud.set_hint(DEFAULT_HINT)
	else:
		battle.hud.set_hint(_turn_hint(unit))


## Quanto resta do turno, em palavras.
func _turn_hint(unit) -> String:
	var steps: int = battle.state.steps_left(unit)
	var walk: String = "%d %s" % [steps, "casa" if steps == 1 else "casas"] if steps > 0 else "sem passos"
	return "%s · Atacar encerra o turno · %s" % [walk, END_TURN_KEY_HINT]


func _refresh_hover() -> void:
	if battle.hover == battle.NO_CELL:
		return
	battle.hover = battle._pick_cell(battle.get_viewport().get_mouse_position())
	_refresh_overlays()
	_update_hint()
