extends Node2D
## Protótipo: luta na plataforma do elevador (scenes/luta_elevador.tscn, F6 no Godot).
## Os heróis chegam pela ponte; o elevador do meio sobe com os inimigos; a luta começa.
## As regras são as do jogo (battle_state.gd + ai.gd); aqui fica só a tela.
##
## Clique numa casa azul: anda. Clique num inimigo: ataca com a habilidade escolhida.
## 1-4: escolhe a habilidade. Espaço: encerra o turno. A: heróis no automático.
## M: mostra a grade inteira (chão e bloqueios). Roda: zoom. Esc: volta ao menu.

const Arena = preload("res://scripts/prototipo/arena_elevador.gd")
const AI = preload("res://scripts/ai.gd")
const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const UnitView = preload("res://scripts/unit_view.gd")

const UNIT_META := "res://assets/units/meta.json"
const AUDIO := "res://assets/audio/combate/"
const UNIT_SCALE := 0.5 # folhas de ~180 px → ~90 px, do tamanho das caixas e da carroça
const CHEST := Vector2(0, -42) # meio do corpo, de onde saem os tiros e os números
const WALK_SPEED := 230.0 # pixels por segundo na chegada pela ponte
const STEP_SECONDS := 0.17 # um passo de casa em casa na luta
const RISE_SECONDS := 3.2
const ZOOM_FIT := 0.64 # a imagem inteira cabe em 1280x720
const ZOOM_MAX := 1.5
const VIEW_CENTER := Vector2(1000, 600)
const PLAYER_COLOR := Color(0.4, 0.82, 1.0)
const ENEMY_COLOR := Color(1.0, 0.36, 0.3)
const MOVE_COLOR := Color(0.35, 0.7, 1.0, 0.32)
const TARGET_COLOR := Color(1.0, 0.3, 0.25, 0.42)
const HELP_COLOR := Color(0.4, 1.0, 0.5, 0.38)
const AREA_COLOR := Color(1.0, 0.6, 0.15, 0.35)

## Para os testes: pula a chegada e a subida do elevador.
var skip_intro := false
## Heróis jogados pela IA (tecla A).
var auto_heroes := false

var arena: Arena
var state
var meta: Dictionary
var views := {} # unidade → UnitView
var background: Sprite2D
var shaft: Polygon2D
var lift_clip: Polygon2D
var lift_piece: Polygon2D
var marks: Node2D
var world: Node2D
var effects: Node2D
var camera: Camera2D
var shake := 0.0

var phase := "intro" # intro → luta → fim
var busy := true
var grid_alpha := 0.0
var show_all := false
var selected := "" # habilidade escolhida do herói da vez
var hover := Vector2i(-1, -1)

var turn_label: Label
var order_label: RichTextLabel
var hint_label: Label
var buttons: HBoxContainer
var banner: Label
var end_panel: PanelContainer


func _ready() -> void:
	arena = Arena.new()
	state = arena.new_battle()
	meta = JSON.parse_string(FileAccess.get_file_as_string(UNIT_META))

	background = Sprite2D.new()
	background.texture = load(arena.data["imagem"])
	background.centered = false
	add_child(background)
	_build_lift()

	marks = Node2D.new()
	marks.draw.connect(_draw_marks)
	add_child(marks)

	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	_build_front_pieces()

	effects = Node2D.new()
	effects.z_index = 700
	add_child(effects)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = background.texture.get_width()
	camera.limit_bottom = background.texture.get_height()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 4.0
	add_child(camera)

	_build_hud()
	_build_units()
	if skip_intro:
		_finish_rise()
		grid_alpha = 1.0
		_set_zoom(ZOOM_FIT)
		camera.position = VIEW_CENTER
		phase = "luta"
		_run_battle()
	else:
		_intro()


# --- Montagem ----------------------------------------------------------------

## O poço escuro, a plataforma recortada da própria imagem e a "janela" que esconde
## o que ainda está abaixo da borda da frente.
func _build_lift() -> void:
	var hole := Arena._points(arena.data["elevador"]["buraco"])
	shaft = Polygon2D.new()
	shaft.polygon = hole
	shaft.vertex_colors = PackedColorArray([Color(0.05, 0.05, 0.07), Color(0.09, 0.08, 0.1), Color(0.05, 0.05, 0.07), Color(0.01, 0.01, 0.02)])
	add_child(shaft)

	# Só a borda da frente do buraco esconde; para cima, a janela é aberta.
	var left := hole[0]
	var bottom := hole[3]
	var right := hole[2]
	lift_clip = Polygon2D.new()
	lift_clip.polygon = PackedVector2Array([left, bottom, right, Vector2(right.x, -400), Vector2(left.x, -400)])
	lift_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	add_child(lift_clip)

	lift_piece = Polygon2D.new()
	lift_piece.polygon = hole
	lift_piece.uv = hole
	lift_piece.texture = background.texture
	lift_clip.add_child(lift_piece)
	_set_lift(arena.lift_depth())


func _set_lift(offset: float) -> void:
	lift_piece.position.y = offset
	var light := 1.0 - 0.75 * clampf(offset / arena.lift_depth(), 0.0, 1.0)
	lift_piece.modulate = Color(light, light, light * 1.05)
	for unit in state.units:
		if unit.team == Data.Team.ENEMY and views.has(unit) and views[unit].get_parent() == lift_clip:
			views[unit].position = arena.cell_to_screen(unit.pos) + Vector2(0, offset)
			views[unit].modulate = lift_piece.modulate
			# A barra fica por cima de tudo (z próprio) e escaparia do recorte do poço.
			views[unit].hp_fill.get_parent().visible = offset <= 0.0


func _build_front_pieces() -> void:
	var pieces: Dictionary = arena.data.get("frente", {})
	var names := pieces.keys()
	names.sort()
	for piece_name in names:
		var piece: Dictionary = pieces[piece_name]
		var base := float(piece["base"])
		var holder := Node2D.new()
		holder.name = piece_name
		holder.position = Vector2(0, base)
		var polygon := Polygon2D.new()
		var points := Arena._points(piece["pontos"])
		polygon.polygon = points
		polygon.uv = points
		polygon.texture = background.texture
		polygon.position = Vector2(0, -base)
		holder.add_child(polygon)
		world.add_child(holder)


func _build_units() -> void:
	for unit in state.units:
		var view := UnitView.new()
		var hero: bool = unit.team == Data.Team.PLAYER
		if hero:
			world.add_child(view)
			view.position = arena.cell_to_screen(unit.pos)
		else:
			lift_clip.add_child(view)
		view.setup(unit, PLAYER_COLOR if hero else ENEMY_COLOR, meta[Data.art(unit.type_id)])
		view.scale = Vector2.ONE * UNIT_SCALE
		view.face_toward(Vector2(1, -0.5) if hero else Vector2(-1, 0.5))
		views[unit] = view
	_set_lift(arena.lift_depth())


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	turn_label = _label(24)
	turn_label.position = Vector2(16, 10)
	hud.add_child(turn_label)
	order_label = RichTextLabel.new()
	order_label.bbcode_enabled = true
	order_label.fit_content = true
	order_label.scroll_active = false
	order_label.position = Vector2(16, 44)
	order_label.size = Vector2(700, 30)
	order_label.add_theme_font_size_override("normal_font_size", 17)
	order_label.add_theme_constant_override("outline_size", 5)
	order_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_child(order_label)
	var help := _label(15)
	help.text = "Clique: andar / atacar  ·  1-4: habilidade  ·  Espaço: encerrar turno  ·  A: automático  ·  M: grade  ·  Esc: sair"
	help.position = Vector2(16, 692)
	help.modulate.a = 0.8
	hud.add_child(help)

	hint_label = _label(19)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.position = Vector2(0, 588)
	hint_label.size = Vector2(1280, 30)
	hud.add_child(hint_label)
	buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.position = Vector2(0, 626)
	buttons.size = Vector2(1280, 50)
	buttons.add_theme_constant_override("separation", 8)
	hud.add_child(buttons)

	banner = _label(64)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.position = Vector2(0, 250)
	banner.size = Vector2(1280, 120)
	banner.modulate.a = 0.0
	hud.add_child(banner)

	end_panel = PanelContainer.new()
	end_panel.visible = false
	end_panel.position = Vector2(490, 380)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	end_panel.add_child(box)
	var again := Button.new()
	again.text = "Lutar de novo"
	again.custom_minimum_size = Vector2(140, 44)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	box.add_child(again)
	var leave := Button.new()
	leave.text = "Sair"
	leave.custom_minimum_size = Vector2(140, 44)
	leave.pressed.connect(_leave)
	box.add_child(leave)
	hud.add_child(end_panel)


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 7)
	return label


# --- Chegada: ponte e elevador ------------------------------------------------

func _intro() -> void:
	busy = true
	_set_zoom(1.0)
	camera.position = Vector2(420, 860)
	camera.reset_smoothing()
	var bridge := arena.bridge_path()
	var heroes: Array = state.units.filter(func(u): return u.team == Data.Team.PLAYER)
	var last: Tween = null
	for i in heroes.size():
		var unit = heroes[i]
		var view: Node2D = views[unit]
		view.position = bridge[0]
		view.visible = false
		var route := bridge.duplicate()
		route.append(arena.cell_to_screen(unit.pos))
		var tween := create_tween()
		tween.tween_interval(i * 0.55)
		tween.tween_callback(func():
			view.visible = true
			view.set_walking(true))
		var from: Vector2 = bridge[0]
		for k in range(1, route.size()):
			var to: Vector2 = route[k]
			tween.tween_callback(view.face_toward.bind(to - from))
			tween.tween_property(view, "position", to, from.distance_to(to) / WALK_SPEED)
			from = to
		tween.tween_callback(func():
			view.set_walking(false)
			view.face_toward(Vector2(1, -0.5)))
		last = tween
	# A câmera acompanha o primeiro e depois abre para a praça inteira.
	var camera_tween := create_tween()
	camera_tween.tween_property(camera, "position", Vector2(560, 800), 2.6)
	await last.finished
	_sound("sfx_movement_portal3.wav", -4.0)
	var open := create_tween().set_parallel()
	open.tween_property(camera, "zoom", Vector2.ONE * ZOOM_FIT, 1.2).set_trans(Tween.TRANS_SINE)
	open.tween_property(camera, "position", VIEW_CENTER, 1.2).set_trans(Tween.TRANS_SINE)
	await open.finished
	await _rise()
	await _show_banner("A luta começa!")
	phase = "luta"
	_run_battle()


## O elevador sobe com os inimigos: tremor, vapor nas engrenagens e o baque no fim.
func _rise() -> void:
	var depth := arena.lift_depth()
	var clank := 0.0
	var start_time := 0.0
	_sound("sfx_exp_cluster2.wav", -8.0)
	while start_time < RISE_SECONDS:
		var delta := get_process_delta_time()
		start_time += delta
		var t := clampf(start_time / RISE_SECONDS, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - t, 2.2)
		_set_lift(depth * (1.0 - eased))
		shake = 3.5
		clank += delta
		if clank > 0.45:
			clank = 0.0
			_sound("sfx_exp_shortest_soft%d.wav" % (1 + randi() % 5), -10.0)
			for gear in arena.data["elevador"]["engrenagens"]:
				_steam(Vector2(gear[0], gear[1]))
		await get_tree().process_frame
	_finish_rise()
	shake = 14.0
	_sound("sfx_sounds_impact10.wav", -2.0)
	_sound("sfx_exp_short_hard1.wav", -6.0)
	for gear in arena.data["elevador"]["engrenagens"]:
		_steam(Vector2(gear[0], gear[1]), 1.6)
	var grid_in := create_tween()
	grid_in.tween_property(self, "grid_alpha", 1.0, 0.6)


## Plataforma no lugar: os inimigos passam para o mundo comum e o poço some.
func _finish_rise() -> void:
	_set_lift(0.0)
	for unit in state.units:
		var view: Node2D = views[unit]
		if view.get_parent() == lift_clip:
			view.reparent(world)
			view.position = arena.cell_to_screen(unit.pos)
			view.modulate = Color.WHITE
			view.hp_fill.get_parent().visible = true
	shaft.visible = false
	lift_clip.visible = false


func _steam(spot: Vector2, strength := 1.0) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.85, 0.85, 0.9, 0.55))
	gradient.set_color(1, Color(0.85, 0.85, 0.9, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var puff := Sprite2D.new()
	puff.texture = texture
	puff.position = spot + Vector2(randf_range(-20, 20), randf_range(-10, 10))
	puff.scale = Vector2.ONE * 0.8 * strength
	effects.add_child(puff)
	var tween := puff.create_tween().set_parallel()
	tween.tween_property(puff, "position", puff.position + Vector2(randf_range(-30, 30), -90 * strength), 1.4)
	tween.tween_property(puff, "scale", Vector2.ONE * 2.4 * strength, 1.4)
	tween.tween_property(puff, "modulate:a", 0.0, 1.4)
	tween.chain().tween_callback(puff.queue_free)


func _show_banner(text: String, hold := 0.9) -> void:
	banner.text = text
	var tween := create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.25)
	tween.tween_interval(hold)
	tween.tween_property(banner, "modulate:a", 0.0, 0.4)
	await tween.finished


# --- Laço de turnos -------------------------------------------------------------

func _run_battle() -> void:
	busy = true
	while phase == "luta":
		if state.winner() != -1:
			_finish()
			return
		var unit = state.active_unit()
		_refresh_hud(unit)
		if not unit.pending.is_empty():
			await _play(state.resolve_pending(unit))
			continue
		if unit.team == Data.Team.ENEMY or auto_heroes:
			if unit.moved == 0:
				await get_tree().create_timer(0.25).timeout
			await _play(AI.apply(state, unit, AI.decide(state, unit)))
			continue
		_begin_player_turn(unit)
		return


func _begin_player_turn(unit) -> void:
	busy = false
	if selected == "" or not unit.abilities.has(selected):
		selected = ""
		for id in unit.abilities:
			if unit.ability(id)["kind"] == "attack":
				selected = id
				break
	_build_buttons(unit)
	_refresh_hud(unit)
	_update_hint()
	marks.queue_redraw()


## O herói da vez faz algo; depois a fila segue sozinha até a próxima vez do jogador.
func _player_do(events: Array) -> void:
	if events.is_empty():
		return
	busy = true
	_clear_buttons()
	hint_label.text = ""
	marks.queue_redraw()
	await _play(events)
	_run_battle()


func _finish() -> void:
	phase = "fim"
	busy = true
	_clear_buttons()
	hint_label.text = ""
	marks.queue_redraw()
	var won: bool = state.winner() == Data.Team.PLAYER
	_sound("sfx_sounds_fanfare1.wav" if won else "sfx_sounds_negative1.wav")
	banner.text = "Vitória!" if won else "Derrota..."
	banner.modulate = Color(1.0, 0.9, 0.5, 0.0) if won else Color(1.0, 0.5, 0.45, 0.0)
	create_tween().tween_property(banner, "modulate:a", 1.0, 0.4)
	turn_label.text = "A plataforma está limpa." if won else "A party caiu na plataforma."
	order_label.text = ""
	end_panel.visible = true


# --- Entrada do jogador --------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := arena.screen_to_cell(get_global_mouse_position())
		if cell != hover:
			hover = cell
			_update_hint()
			marks.queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_click(arena.screen_to_cell(get_global_mouse_position()))
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(camera.zoom.x * 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(camera.zoom.x / 1.1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_leave()
			KEY_M:
				show_all = not show_all
				marks.queue_redraw()
			KEY_A:
				auto_heroes = not auto_heroes
				_show_banner("Automático: ligado" if auto_heroes else "Automático: desligado", 0.4)
				if auto_heroes and phase == "luta" and not busy:
					_clear_buttons()
					_run_battle()
			KEY_SPACE:
				_end_turn()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var unit = _player_unit()
				var index: int = event.keycode - KEY_1
				if unit != null and index < unit.abilities.size():
					_choose(unit.abilities[index])


func _player_unit():
	if busy or phase != "luta":
		return null
	var unit = state.active_unit()
	return unit if unit.team == Data.Team.PLAYER else null


func _click(cell: Vector2i) -> void:
	var unit = _player_unit()
	if unit == null or cell.x < 0:
		return
	if selected != "" and state.valid_targets(unit, selected).has(cell):
		_player_do(state.do_ability(unit, selected, cell))
		return
	if state.move_cells(unit).has(cell):
		_player_do(state.do_move(unit, cell))
		return
	# Clicou num inimigo fora da habilidade escolhida: usa a primeira que alcança.
	for id in unit.abilities:
		if unit.ability(id)["kind"] == "attack" and state.valid_targets(unit, id).has(cell):
			selected = id
			_player_do(state.do_ability(unit, id, cell))
			return


func _choose(id: String) -> void:
	var unit = _player_unit()
	if unit == null:
		return
	var ability: Dictionary = unit.ability(id)
	# Guarda e outras de "só em mim": saem na hora.
	if ability["range"] == 0 and ability["kind"] == "guard":
		_player_do(state.do_ability(unit, id, unit.pos))
		return
	selected = id
	_build_buttons(unit)
	_update_hint()
	marks.queue_redraw()


func _end_turn() -> void:
	var unit = _player_unit()
	if unit != null:
		_player_do(state.do_wait(unit))


func _leave() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _set_zoom(value: float) -> void:
	camera.zoom = Vector2.ONE * clampf(value, ZOOM_FIT, ZOOM_MAX)


# --- HUD ----------------------------------------------------------------------

func _refresh_hud(unit) -> void:
	for other in views:
		views[other].hide_arrow()
	if unit != null and unit.alive():
		views[unit].show_arrow(Color(1.0, 0.84, 0.2))
		var who := "Sua vez: " if unit.team == Data.Team.PLAYER and not auto_heroes else "Vez de: "
		turn_label.text = "%s%s  (%d/%d)" % [who, unit.display_name, unit.hp, unit.max_hp]
		if unit.team == Data.Team.PLAYER and not unit.pending.is_empty():
			turn_label.text += "  · carregando magia"
		elif unit.team == Data.Team.PLAYER:
			turn_label.text += "  · %d passos" % state.steps_left(unit)
	var parts := []
	for next in state.timeline(7):
		var color := "#7fd4ff" if next.team == Data.Team.PLAYER else "#ff7a6e"
		parts.append("[color=%s]%s[/color]" % [color, next.display_name])
	order_label.text = "A seguir: " + "  ›  ".join(parts)


func _clear_buttons() -> void:
	for child in buttons.get_children():
		child.queue_free()


func _build_buttons(unit) -> void:
	_clear_buttons()
	for i in unit.abilities.size():
		var id: String = unit.abilities[i]
		var ability: Dictionary = unit.ability(id)
		var button := Button.new()
		button.text = "%d  %s" % [i + 1, ability["name"]]
		button.custom_minimum_size = Vector2(130, 42)
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = state.valid_targets(unit, id).is_empty() and ability["kind"] != "guard"
		if id == selected:
			button.modulate = Color(1.0, 0.85, 0.4)
		button.pressed.connect(_choose.bind(id))
		buttons.add_child(button)
	var wait := Button.new()
	wait.text = "Espaço  Encerrar"
	wait.custom_minimum_size = Vector2(150, 42)
	wait.focus_mode = Control.FOCUS_NONE
	wait.pressed.connect(_end_turn)
	buttons.add_child(wait)


func _update_hint() -> void:
	var unit = _player_unit()
	if unit == null:
		hint_label.text = ""
		return
	var target = state.unit_at(hover) if hover.x >= 0 else null
	if selected != "" and state.valid_targets(unit, selected).has(hover):
		var ability: Dictionary = unit.ability(selected)
		if ability["kind"] == "attack" and target != null:
			var preview: Dictionary = state.preview_attack(unit, selected, target)
			var extra := ""
			if preview["flank"]:
				extra += "  · flanco!"
			if preview["amount"] >= target.hp:
				extra += "  · derruba"
			hint_label.text = "%s em %s: %d de dano%s" % [ability["name"], target.display_name, preview["amount"], extra]
		else:
			hint_label.text = "%s aqui" % ability["name"]
	elif state.move_cells(unit).has(hover):
		hint_label.text = "Andar até aqui"
	elif target != null:
		hint_label.text = "%s  %d/%d" % [target.display_name, target.hp, target.max_hp]
	else:
		var ability_name: String = unit.ability(selected)["name"] if selected != "" else "—"
		hint_label.text = "%s: clique num inimigo marcado de vermelho, ou ande pelas casas azuis" % ability_name


# --- Marcas no chão --------------------------------------------------------------

func _draw_marks() -> void:
	if grid_alpha <= 0.0 and not show_all:
		return
	for row in arena.rows:
		for col in arena.cols:
			var cell := Vector2i(col, row)
			if arena.walkable(cell):
				marks.draw_polyline(_closed(arena.cell_outline(cell)), Color(1, 1, 1, 0.2 * grid_alpha), 1.5)
				if show_all:
					marks.draw_colored_polygon(arena.cell_outline(cell), Color(0.2, 1, 0.3, 0.2))
			elif show_all:
				marks.draw_colored_polygon(arena.cell_outline(cell), Color(1, 0, 0, 0.25))
	# Magias carregando: a área onde vão cair.
	for unit in state.units:
		if unit.alive() and not unit.pending.is_empty():
			var ability: Dictionary = unit.ability(unit.pending["ability"])
			for cell in state.area_of(unit.pending["tile"], ability.get("radius", 0)):
				if arena.walkable(cell):
					marks.draw_colored_polygon(arena.cell_outline(cell), AREA_COLOR)
	var unit = _player_unit()
	if unit == null:
		return
	for cell in state.move_cells(unit):
		marks.draw_colored_polygon(arena.cell_outline(cell, 0.88), MOVE_COLOR)
	if selected != "":
		var ability: Dictionary = unit.ability(selected)
		var color := TARGET_COLOR if ability["kind"] == "attack" or ability["kind"] == "charge" else HELP_COLOR
		for cell in state.valid_targets(unit, selected):
			if arena.walkable(cell):
				marks.draw_colored_polygon(arena.cell_outline(cell, 0.88), color)
		if ability["kind"] == "charge" and state.valid_targets(unit, selected).has(hover):
			for cell in state.area_of(hover, ability.get("radius", 0)):
				if arena.walkable(cell):
					marks.draw_colored_polygon(arena.cell_outline(cell, 0.7), AREA_COLOR)
	marks.draw_polyline(_closed(arena.cell_outline(unit.pos)), Color(1.0, 0.84, 0.2, 0.9), 3.0)
	if hover.x >= 0 and arena.walkable(hover):
		marks.draw_polyline(_closed(arena.cell_outline(hover)), Color(1, 1, 1, 0.85), 2.5)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out


func _process(delta: float) -> void:
	if grid_alpha > 0.0 and grid_alpha < 1.0:
		marks.queue_redraw()
	if shake > 0.0:
		camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake) * 0.6)
		shake = maxf(0.0, shake - delta * 30.0)
	else:
		camera.offset = Vector2.ZERO
	# Com zoom, a câmera acompanha quem está agindo.
	if phase == "luta" and camera.zoom.x > ZOOM_FIT + 0.05:
		var unit = state.active_unit()
		if unit != null and views.has(unit):
			camera.position = views[unit].position
	elif phase != "intro":
		camera.position = VIEW_CENTER


# --- Eventos das regras → animação ----------------------------------------------

func _play(events: Array) -> void:
	for event in events:
		match event["type"]:
			"move":
				await _move(event)
			"attack":
				await _attack(event)
			"damage":
				_damage(event)
				await get_tree().create_timer(0.22).timeout
			"death":
				_death(event["target"])
				await get_tree().create_timer(0.35).timeout
			"heal", "regen":
				var target = event.get("target", event["unit"])
				views[target].set_hp(target.hp)
				_popup(views[target].position + CHEST, "+%d" % event["amount"], Color(0.45, 1.0, 0.5))
				_sound("sfx_sounds_powerup3.wav", -8.0)
				await get_tree().create_timer(0.25).timeout
			"revive":
				var body = event["unit"]
				views[body].stand_up()
				views[body].set_hp(body.hp)
				views[body].modulate = Color.WHITE
				_popup(views[body].position + CHEST, "De pé!", Color(1.0, 0.9, 0.5))
				await get_tree().create_timer(0.3).timeout
			"status":
				var target = event["target"]
				views[target].set_status(", ".join(target.status_names()), Color(1.0, 0.85, 0.4))
				_popup(views[target].position + CHEST + Vector2(0, -26), Data.STATUS[event["status"]]["name"], Color(1.0, 0.85, 0.4))
			"status_end":
				var target = event["target"]
				views[target].set_status(", ".join(target.status_names()))
			"guard", "buff":
				var who = event.get("target", event["unit"])
				var label: String = event.get("label", "Guarda") if event["type"] == "buff" else "Guarda"
				_popup(views[who].position + CHEST, label, Color(0.6, 0.85, 1.0))
				_sound("sfx_sound_bling.wav", -10.0)
				await get_tree().create_timer(0.3).timeout
			"cast_start":
				views[event["unit"]].set_aura(Color(1.0, 0.55, 0.2))
				_popup(views[event["unit"]].position + CHEST, Data.ABILITIES[event["ability"]]["name"] if Data.ABILITIES.has(event["ability"]) else "Magia", Color(1.0, 0.7, 0.3))
				_sound("sfx_sounds_powerup8.wav", -8.0)
				marks.queue_redraw()
				await get_tree().create_timer(0.35).timeout
			"cast_resolve":
				views[event["unit"]].clear_aura()
				await _blast(event["cells"])
	marks.queue_redraw()
	_refresh_hud(state.active_unit())


func _move(event: Dictionary) -> void:
	var unit = event["unit"]
	var view: Node2D = views[unit]
	var to := arena.cell_to_screen(event["to"])
	var seconds := STEP_SECONDS
	if event.get("push", false):
		seconds = 0.12 * Hex.distance(event["from"], event["to"])
	elif event.get("dash", false):
		seconds = 0.22
	if not event.get("push", false):
		view.face_toward(to - view.position)
		view.set_walking(true)
	var tween := create_tween()
	tween.tween_property(view, "position", to, seconds)
	await tween.finished
	view.set_walking(false)


func _attack(event: Dictionary) -> void:
	var unit = event["unit"]
	var target = event["target"]
	var view: Node2D = views[unit]
	var target_view: Node2D = views[target]
	var toward: Vector2 = target_view.position - view.position
	view.face_toward(toward)
	var id: String = event.get("ability", "")
	var ability: Dictionary = unit.ability(id) if id != "" and unit.abilities.has(id) else {}
	var ranged: bool = not ability.is_empty() and ability["range"] > 1 and not ability.get("dash", false)
	view.play_once(UnitView.Anim.STRONG if id != "" and id != unit.abilities[0] else UnitView.Anim.ATTACK)
	if event.has("label") and event["label"] != "":
		_popup(view.position + CHEST + Vector2(0, -30), String(event["label"]), Color(1, 1, 1, 0.9), 20)
	if ranged:
		await get_tree().create_timer(0.18).timeout
		await _shot(view.position + CHEST, target_view.position + CHEST, ability.get("shot", ""))
	else:
		view.lunge(toward.normalized() * 70.0, 0.14)
		await get_tree().create_timer(0.16).timeout


func _shot(from: Vector2, to: Vector2, kind: String) -> void:
	var color := Color(1.0, 0.55, 0.2)
	if kind == "kit/arrow":
		color = Color(0.95, 0.85, 0.65)
		_sound("sfx_wpn_missilelaunch.wav", -16.0)
	elif kind == "kit/magic":
		color = Color(0.5, 1.0, 0.55)
	var bolt := Polygon2D.new()
	var points := PackedVector2Array()
	for k in 12:
		var angle := TAU * k / 12.0
		points.append(Vector2(cos(angle) * 9, sin(angle) * 6))
	bolt.polygon = points
	bolt.color = color
	bolt.position = from
	effects.add_child(bolt)
	var tween := bolt.create_tween()
	tween.tween_property(bolt, "position", to, clampf(from.distance_to(to) / 1400.0, 0.12, 0.35))
	await tween.finished
	bolt.queue_free()


func _damage(event: Dictionary) -> void:
	var target = event["target"]
	var view: Node2D = views[target]
	view.set_hp(target.hp)
	view.flash(Color(7, 7, 7) if target.team == Data.Team.ENEMY else Color(4, 1, 1))
	view.knock(Vector2(randf_range(-12, 12), -6))
	if target.alive():
		view.play_once(UnitView.Anim.HURT)
	var text := str(event["amount"])
	if event.get("flank", false):
		text += " flanco"
	_popup(view.position + CHEST, text, Color(1.0, 0.95, 0.9) if target.team == Data.Team.ENEMY else Color(1.0, 0.45, 0.4))
	_sound("sfx_wpn_punch%d.wav" % (1 + randi() % 3), -6.0)
	shake = maxf(shake, 4.0)


func _death(target) -> void:
	var view: Node2D = views[target]
	view.set_status("")
	view.hide_arrow()
	view.lie_down()
	if target.team == Data.Team.ENEMY:
		_sound("sfx_deathscream_alien%d.wav" % (2 + randi() % 5), -8.0)
		var tween := view.create_tween()
		tween.tween_interval(0.7)
		tween.tween_property(view, "modulate:a", 0.0, 0.6)
	else:
		_sound("sfx_deathscream_human%d.wav" % (1 + randi() % 9), -8.0)
		view.modulate = Color(0.7, 0.7, 0.75)


func _blast(cells: Array) -> void:
	_sound("sfx_exp_medium3.wav", -6.0)
	shake = maxf(shake, 8.0)
	for cell in cells:
		if not arena.walkable(cell):
			continue
		var flare := Polygon2D.new()
		flare.polygon = arena.cell_outline(cell, 0.95)
		flare.color = Color(1.0, 0.6, 0.2, 0.75)
		effects.add_child(flare)
		var tween := flare.create_tween()
		tween.tween_property(flare, "modulate:a", 0.0, 0.5)
		tween.tween_callback(flare.queue_free)
	await get_tree().create_timer(0.25).timeout


func _popup(spot: Vector2, text: String, color: Color, size := 30) -> void:
	var label := _label(size)
	label.text = text
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(240, 40)
	label.position = spot - Vector2(120, 20)
	effects.add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 50, 0.9).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


func _sound(file: String, volume := 0.0) -> void:
	var stream = load(AUDIO + file)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
