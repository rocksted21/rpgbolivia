extends RefCounted

## Fila de turnos à esquerda: quem age, em que ordem, e a prévia das magias.

const Data = preload("res://scripts/game_data.gd")
const Icon = preload("res://scripts/icon.gd")

const CAST_COLOR := Color(1.0, 0.55, 0.1)
const TIMELINE_SLIDE_TIME := 0.4
const FOCUS_COLOR := Color(1.0, 1.0, 1.0)
const TIMELINE_SIZE := 10
const PORTRAIT_SIZE := 60

var hud: BattleHud # a tela dona deste módulo


func _init(host: Node) -> void:
	hud = host


## Destaca na fila todas as vezes de `unit` e apaga as dos outros; null tira o destaque.
func highlight(unit) -> void:
	if unit == hud.highlighted:
		return
	hud.highlighted = unit
	if hud.last_state != null:
		_refresh_timeline(hud.last_state)


## Prevê na fila a magia que o menu oferece: o mago sai da frente e o selo
## de magia aparece na vez em que ela seria solta. null desfaz a prévia.
func preview_cast(state, unit, time: int) -> void:
	var next := {} if unit == null else {unit: time}
	if next == hud.cast_preview:
		return
	hud.cast_preview = next
	_refresh_timeline(state)


func _refresh_timeline(state) -> void:
	hud.last_state = state
	for child in hud.timeline.get_children():
		hud.timeline.remove_child(child)
		child.queue_free()
	if hud.timeline_tween != null:
		hud.timeline_tween.kill()
	hud.timeline.position.y = hud.TIMELINE_Y
	# Fora de combate não há fila para mostrar.
	hud.timeline.visible = state.in_combat() and state.turn_order().size() > 1
	var order: Array = state.timeline(TIMELINE_SIZE, hud.cast_preview)
	# Magia que sai depois do fim da fila: a última vaga vira o selo dela, com as ações que faltam além.
	var beyond := 0
	for unit in state.units:
		if unit.alive() and (not unit.pending.is_empty() or hud.cast_preview.has(unit)):
			var at: int = state.actions_until(unit, hud.cast_preview)
			if at >= TIMELINE_SIZE and (beyond == 0 or at - TIMELINE_SIZE + 1 < beyond):
				beyond = at - TIMELINE_SIZE + 1
				order[TIMELINE_SIZE - 1] = unit
	# Quem está em foco mas é lento demais para caber na fila toma a última vaga, com as ações que faltam.
	var focus_beyond := 0
	if hud.highlighted != null and hud.highlighted.alive() and not order.has(hud.highlighted):
		focus_beyond = state.actions_until(hud.highlighted, hud.cast_preview) - TIMELINE_SIZE + 1
		order[TIMELINE_SIZE - 1] = hud.highlighted
		beyond = 0
	# Esteira: quem acabou de jogar sobe e some, os outros sobem um degrau e o novo entra por baixo.
	var shift := _shift_between(hud.timeline_units, order)
	var strip: Array = hud.timeline_units.slice(0, shift) + order
	var seen := {}
	var departed_seen := {}
	var boxes := []
	for i in strip.size():
		var leaving: bool = i < shift
		# Na prévia de magia, a vez atual já foi gasta: ninguém leva o selo amarelo.
		var first: bool = hud.cast_preview.is_empty() and i == 0
		var far: int = beyond if not leaving and i == strip.size() - 1 else 0
		var box := _timeline_box(strip[i], first, departed_seen if leaving else seen, far)
		if focus_beyond > 0 and not leaving and i == strip.size() - 1:
			box.add_child(_later_label(focus_beyond))
		if leaving:
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.timeline.add_child(box)
		boxes.append(box)
	hud.timeline_units = order
	if shift == 0:
		return
	var distance := (PORTRAIT_SIZE + 5) * shift
	hud.timeline_tween = hud.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hud.timeline_tween.tween_property(hud.timeline, "position:y", hud.TIMELINE_Y - distance, TIMELINE_SLIDE_TIME)
	for i in shift:
		hud.timeline_tween.tween_property(boxes[i], "modulate:a", 0.0, TIMELINE_SLIDE_TIME)
	for i in range(boxes.size() - shift, boxes.size()):
		var fade_to: float = boxes[i].modulate.a
		boxes[i].modulate.a = 0.0
		hud.timeline_tween.tween_property(boxes[i], "modulate:a", fade_to, TIMELINE_SLIDE_TIME)


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
	var color := hud.PLAYER_COLOR if unit.team == Data.Team.PLAYER else hud.ENEMY_COLOR
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	if unit == hud.highlighted:
		box.add_theme_stylebox_override("panel", hud._box(Color(0.62, 0.64, 0.7), FOCUS_COLOR, 6, 8, 4))
		box.custom_minimum_size = Vector2(PORTRAIT_SIZE + 22, PORTRAIT_SIZE)
	else:
		box.add_theme_stylebox_override("panel", hud._box(Color(0.42, 0.44, 0.5), hud.ACTIVE_COLOR if first else color, 3 if first else 2, 8, 4))
		if hud.highlighted != null:
			box.modulate = Color(1, 1, 1, 0.45)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_timeline_input.bind(unit))
	var portrait := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/units/%s.png" % unit.type_id)
	var info: Dictionary = hud.meta[unit.type_id]
	atlas.region = Rect2(0, 0, info["cell_w"], info["cell_h"])
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(portrait)
	# A primeira vez de quem carrega magia é quando ela é solta.
	var far := beyond > 0
	if far or (not seen.has(unit) and (not unit.pending.is_empty() or hud.cast_preview.has(unit))):
		box.add_theme_stylebox_override("panel", hud._box(Color(0.42, 0.44, 0.5), CAST_COLOR, 5, 8, 4))
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
	if unit == hud.highlighted and not seen.has(unit):
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
		hud.unit_picked.emit(unit)
