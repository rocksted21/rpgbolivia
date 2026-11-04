extends Node2D

# Resolve services after the content pack is mounted by the thin installer.
var music_manager:
	get: return get_node("/root/MusicManager")

var online_session:
	get: return get_node("/root/OnlineSession")

var sound_manager:
	get: return get_node("/root/SoundManager")

## Tela do combate: desenha o tabuleiro, recebe o input e anima os eventos das regras.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const BattleState = preload("res://scripts/battle_state.gd")
const AI = preload("res://scripts/ai.gd")
const UnitView = preload("res://scripts/unit_view.gd")
const Hud = preload("res://scripts/hud.gd")
const BattleCamera = preload("res://scripts/battle_camera.gd")

const BOARD_POS := Vector2(250, 142) # sem painel lateral: o tabuleiro fica no meio, a fila à esquerda
const BOARD_SCALE := 0.5
const TILE_WIDTH := 186
const ROW_STEP := 160
const SIDE_HEIGHT := 29 # altura da lateral do tile; empilhar tiles a cada 29 px forma o penhasco
const LAYERS_PER_LEVEL := 4 # 116 px por nível; a altura é projetada na vertical
const FOREST_HEIGHT := 1.65
const FEET := Vector2(93, 125)
const NO_CELL := Vector2i(-1, -1)
const HOLD_TIME := 0.45
const SCENERY_BASE := {3: 1, 6: 7, 10: 9, 11: 9}

const STEP_COLOR := Color(0.27, 0.67, 1.0, 0.35)
const REACH_FILL := Color(1.0, 0.55, 0.1, 0.3)
const REACH_LINE := Color(1.0, 0.6, 0.15, 0.95)
const TARGET_COLOR := Color(0.92, 0.24, 0.24, 0.55)
const INSPECT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const NEXT_ENEMY_ARROW := Color(0.95, 0.3, 0.25)
const DEFAULT_HINT := "Toque numa casa azul para andar ou num personagem para agir. Segure para ver detalhes."
# Magia é roxa para não se confundir com o laranja do alcance.
const AREA_COLOR := Color(0.72, 0.3, 1.0, 0.6)
const CHARGE_COLOR := Color(0.72, 0.3, 1.0, 0.42)
const ACTIVE_COLOR := Color(1.0, 0.84, 0.35)
const CAST_INK := Color(1.0, 0.62, 0.15)
# Animação de cada magia (tiras em assets/fx/<elemento>, geradas pelo build_assets).
# projectile voa do mago até o alvo; impact toca no alvo, ou em cada casa da área se per_cell.
# Posição do impacto: ground põe a base do efeito no chão; senão o centro fica `lift` acima dos pés.
# ring_delay: o anel em volta do centro começa depois. Escalas são no tabuleiro, que está a 0.5:
# escala 2 dá 1 pixel do efeito por pixel de tela.
# sound: som do impacto, do grupo Combate do SoundManager; cast_sound: o do projétil (fire_cast).
const SPELL_FX := {
	"faisca": {"impact": "fogo/small_fire", "impact_scale": 4.0, "ground": true, "sound": &"fire_hit"},
	"labareda": {"impact": "fogo/fire", "impact_scale": 3.0, "ground": true, "sound": &"flame"},
	"bola_fogo": {"projectile": "fogo/fireball", "impact": "fogo/explosion", "impact_scale": 2.0, "lift": 90, "sound": &"fire_hit"},
	"pilar_fogo": {"impact": "fogo/fire_pillar", "impact_scale": 2.0, "ground": true, "sound": &"flame"},
	"golpe_solar": {"impact": "fogo/sun_strike", "impact_scale": 2.0, "lift": 90, "sound": &"explosion"},
	"flor_fogo": {"impact": "fogo/fire_flower", "impact_scale": 2.0, "lift": 40, "sound": &"fire_hit"},
	"explosao": {"projectile": "fogo/fireball", "impact": "fogo/explosion", "impact_scale": 2.0, "per_cell": true, "lift": 40, "ring_delay": 0.12, "sound": &"explosion"},
	"poca_lava": {"impact": "fogo/lava_puddle", "impact_scale": 2.0, "per_cell": true, "lift": 0, "sound": &"flame"},
	"chuva_lava": {"impact": "fogo/lava_drop", "impact_scale": 3.0, "per_cell": true, "ground": true, "ring_delay": 0.1, "sound": &"fire_hit"},
	"geiser_magma": {"impact": "fogo/magma_geyser", "impact_scale": 2.0, "ground": true, "sound": &"explosion"},
	"furacao_fogo": {"impact": "fogo/fire_hurricane", "impact_scale": 3.0, "lift": 60, "sound": &"flame"},
	"fenix": {"impact": "fogo/phoenix", "impact_scale": 4.0, "lift": 120, "sound": &"explosion"},
	"escudo_fogo": {"impact": "fogo/fire_shield", "impact_scale": 2.0, "lift": 90, "sound": &"flame"},
	"gota": {"impact": "agua/water_drop", "impact_scale": 4.0, "ground": true, "sound": &"water"},
	"chicote_agua": {"impact": "agua/water_whip", "impact_scale": 2.0, "lift": 90, "sound": &"water"},
	"bola_agua": {"projectile": "agua/waterball", "projectile_turn": PI, "cast_sound": &"water", "impact": "agua/splash", "impact_scale": 3.0, "ground": true, "sound": &"water"},
	"estaca_gelo": {"impact": "agua/ice_spike", "impact_scale": 2.0, "ground": true, "sound": &"ice"},
	"cristal_gelo": {"impact": "agua/ice_crystal", "impact_scale": 4.0, "ground": true, "sound": &"ice"},
	"floco_neve": {"impact": "agua/snowflake", "impact_scale": 3.0, "lift": 60, "sound": &"ice"},
	"estilhaco_gelo": {"impact": "agua/ice_burst", "impact_scale": 2.0, "per_cell": true, "lift": 40, "ring_delay": 0.12, "sound": &"ice"},
	"onda": {"impact": "agua/splash", "impact_scale": 3.0, "per_cell": true, "ground": true, "ring_delay": 0.1, "sound": &"water"},
	"geiser": {"impact": "agua/geyser", "impact_scale": 2.0, "ground": true, "sound": &"water"},
	"redemoinho": {"impact": "agua/water_hurricane", "impact_scale": 3.0, "lift": 60, "sound": &"water"},
	"kraken": {"impact": "agua/kraken", "impact_scale": 5.0, "lift": 120, "sound": &"water"},
	"chama": {"impact": "fogo/fire_pillar", "impact_scale": 2.0, "per_cell": true, "ground": true, "sound": &"flame"},
}
const PROJECTILE_SCALE := 2.0
const FX_FPS := 16.0

var hex_poly := PackedVector2Array([Vector2(93, 0), Vector2(185, 53), Vector2(185, 160), Vector2(93, 213), Vector2(0, 160), Vector2(0, 53)])
var state
var hud
var board: Node2D
var battle_camera: Node
var meta := {}
var fx_meta := {}
var views := {}
var overlays := {}
var reach_lines := {}
var forests := {}
var active_outline: Line2D
var inspect_outline: Line2D
var busy := true
var hover := NO_CELL
var menu_cell := NO_CELL # casa com o menu aberto
var menu_options := []
var show_order := false
var pressing := false
var press_cell := NO_CELL
var press_token := 0 # cada toque novo invalida o "segurar" do toque anterior
var pinned = null # unidade escolhida tocando na fila de turnos
var focus_ring: Line2D
var focus_tween: Tween
var remote_playing := false
var room_label: Label


func _ready() -> void:
	music_manager.play_combat()
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	fx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/meta.json"))
	_start_battle()
	if online_session.playing:
		online_session.command_received.connect(_network_command)
		online_session.packet_received.connect(_network_packet)
		online_session.connection_lost.connect(_network_lost)
		online_session.changed.connect(_room_status)
		var layer := CanvasLayer.new()
		add_child(layer)
		var row := HBoxContainer.new()
		row.position = Vector2(16, 626)
		layer.add_child(row)
		room_label = Label.new()
		room_label.add_theme_font_size_override("font_size", 18)
		row.add_child(room_label)
		var leave_button := Button.new()
		leave_button.text = "Sair da sala"
		sound_manager.bind_button(leave_button)
		leave_button.pressed.connect(_leave_online)
		row.add_child(leave_button)
		_room_status()
		_network_packet({})


func _exit_tree() -> void:
	music_manager.play_menu()


func _start_battle() -> void:
	state = online_session.state if online_session.playing else BattleState.from_data()
	views.clear()
	overlays.clear()
	reach_lines.clear()
	forests.clear()
	hover = NO_CELL
	menu_cell = NO_CELL
	menu_options = []
	show_order = false
	if board != null:
		board.queue_free()
	if battle_camera != null:
		battle_camera.queue_free()
	if hud != null:
		hud.queue_free()

	board = Node2D.new()
	board.position = BOARD_POS
	board.scale = Vector2.ONE * BOARD_SCALE
	add_child(board)
	battle_camera = BattleCamera.new()
	add_child(battle_camera)
	_build_tiles()
	for unit in state.units:
		_add_unit_view(unit)
	active_outline = _new_hex_line(ACTIVE_COLOR, 7)
	inspect_outline = _new_hex_line(INSPECT_COLOR, 7)
	inspect_outline.visible = false
	pinned = null
	_build_focus_marker()

	hud = Hud.new()
	add_child(hud)
	hud.setup(meta)
	hud.unit_picked.connect(_on_timeline_pick)
	hud.option_pressed.connect(_on_option_pressed)
	hud.order_toggled.connect(_on_order_toggled)
	hud.restart_pressed.connect(_leave_online if online_session.playing else _start_battle)
	if online_session.playing:
		for child in hud.end_label.get_parent().get_children():
			if child is Button: child.text = "Voltar ao Online"
	_advance()


# Anel grosso que pulsa na casa do personagem em foco, com o nome em cima dele.
func _build_focus_marker() -> void:
	focus_ring = _new_hex_line(Color(1.0, 0.95, 0.3), 12)
	focus_ring.visible = false
	if focus_tween != null:
		focus_tween.kill()
	focus_tween = create_tween().set_loops()
	focus_tween.tween_property(focus_ring, "modulate:a", 0.35, 0.45)
	focus_tween.tween_property(focus_ring, "modulate:a", 1.0, 0.45)


## Marca no mapa e na fila o mesmo personagem, seja ele vindo do toque no mapa ou na fila.
func _sync_focus() -> void:
	var shown = _shown_unit() if not busy else null
	hud.highlight(shown)
	if shown == null or not shown.alive():
		focus_ring.visible = false
		return
	_place_ground_marker(focus_ring, shown.pos)
	focus_ring.z_index = shown.pos.y * 10 + 4 # abaixo do personagem (+5)
	focus_ring.visible = true


func _on_timeline_pick(unit) -> void:
	if busy or not unit.alive():
		return
	_close_menu()
	pinned = null if pinned == unit else unit
	_refresh_overlays()
	_update_hint()
	sound_manager.play_ui(&"switch3")


func _build_tiles() -> void:
	for row in state.rows():
		for col in state.cols():
			var cell := Vector2i(col, row)
			var base := Vector2(_column_x(cell), row * ROW_STEP)
			var layers: int = state.elevation_at(cell) * LAYERS_PER_LEVEL
			for layer in layers:
				_add_tile(9, base - Vector2(0, layer * SIDE_HEIGHT), row, layer * SIDE_HEIGHT)
			var terrain_id: int = state.terrain[row][col]
			_add_tile(SCENERY_BASE.get(terrain_id, terrain_id), cell_origin(cell), row, layers * SIDE_HEIGHT)
			if SCENERY_BASE.has(terrain_id):
				_add_scenery(terrain_id, cell)
			var overlay := Polygon2D.new()
			overlay.polygon = hex_poly
			_place_ground_marker(overlay, cell)
			overlay.z_index = row * 10 + 1
			overlay.visible = false
			board.add_child(overlay)
			overlays[cell] = overlay
			var line := _new_hex_line(REACH_LINE, 5)
			_place_ground_marker(line, cell)
			line.z_index = row * 10 + 2
			line.visible = false
			reach_lines[cell] = line


func _new_hex_line(color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.closed = true
	line.points = hex_poly
	line.material = battle_camera.ground_material
	board.add_child(line)
	return line


func _add_tile(id: int, pos: Vector2, row: int, height := 0.0) -> void:
	# Malha subdividida: a perspectiva acompanha a textura até nas bordas dos hexes.
	# Um Sprite2D teria só quatro vértices e abriria frestas entre casas vizinhas.
	var tile := Polygon2D.new()
	var texture: Texture2D = load("res://assets/tiles/%d.png" % id)
	tile.texture = texture
	var vertices := PackedVector2Array()
	var faces: Array[PackedInt32Array] = []
	const COLUMNS := 6
	const ROWS := 8
	for y in ROWS + 1:
		for x in COLUMNS + 1:
			vertices.append(Vector2(x * texture.get_width() / float(COLUMNS), y * texture.get_height() / float(ROWS)))
	for y in ROWS:
		for x in COLUMNS:
			var i := y * (COLUMNS + 1) + x
			faces.append(PackedInt32Array([i, i + 1, i + COLUMNS + 2, i + COLUMNS + 1]))
	tile.polygon = vertices
	tile.uv = vertices
	tile.polygons = faces
	var mat: ShaderMaterial = battle_camera.surface_material(height * BOARD_SCALE).duplicate()
	mat.set_shader_parameter("tile_surface", true)
	mat.set_shader_parameter("tile_origin", board.global_transform * pos)
	mat.set_shader_parameter("tile_scale", BOARD_SCALE)
	tile.material = mat
	tile.position = pos
	tile.z_index = row * 10
	board.add_child(tile)


func _add_scenery(id: int, cell: Vector2i) -> void:
	if id == 3:
		var back := _scenery_layer(id, cell, 3, FOREST_HEIGHT, 1)
		var front := _scenery_layer(id, cell, 6, FOREST_HEIGHT, 2)
		forests[cell] = {"back": back, "front": front}
	else:
		_scenery_layer(id, cell, 3)


func _scenery_layer(id: int, cell: Vector2i, depth: int, height := 1.0, slice := 0) -> Sprite2D:
	var prop := Sprite2D.new()
	prop.texture = load("res://assets/tiles/%d.png" % id)
	prop.centered = false
	prop.scale.y = height
	prop.position = cell_origin(cell) + Vector2(0, 160 * (1.0 - height))
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.z_index = cell.y * 10 + depth
	board.add_child(prop)
	battle_camera.add_billboard(prop, Vector2(93, 160 * height), _cell_elevation(cell))
	prop.material.set_shader_parameter("scenery", true)
	prop.material.set_shader_parameter("scenery_base", load("res://assets/tiles/%d.png" % SCENERY_BASE[id]))
	prop.material.set_shader_parameter("scenery_slice", slice)
	return prop


func _add_unit_view(unit) -> void:
	var view := UnitView.new()
	board.add_child(view)
	view.setup(unit, Hud.PLAYER_COLOR if unit.team == Data.Team.PLAYER else Hud.ENEMY_COLOR, meta[unit.type_id])
	view.position = feet_of(unit.pos)
	view.z_index = unit.pos.y * 10 + 5
	views[unit] = view
	battle_camera.add_billboard(view, Vector2.ZERO, _cell_elevation(unit.pos))


## Altura em unidades da tela lógica; a grade e os custos continuam iguais.
func _cell_elevation(cell: Vector2i) -> float:
	return state.elevation_at(cell) * LAYERS_PER_LEVEL * SIDE_HEIGHT * BOARD_SCALE


func _place_ground_marker(item: CanvasItem, cell: Vector2i) -> void:
	item.position = cell_origin(cell)
	item.material = battle_camera.surface_material(_cell_elevation(cell))


func _height_at_point(point: Vector2) -> float:
	var nearest := INF
	var height := 0.0
	for cell in overlays:
		var distance: float = point.distance_squared_to(feet_of(cell))
		if distance < nearest:
			nearest = distance
			height = _cell_elevation(cell)
	return height


func _add_effect_billboard(item: CanvasItem, offset: Vector2) -> void:
	battle_camera.add_billboard(item, offset, _height_at_point(item.position + offset))


func _column_x(cell: Vector2i) -> int:
	return cell.x * TILE_WIDTH + (cell.y & 1) * TILE_WIDTH / 2


func cell_origin(cell: Vector2i) -> Vector2:
	var level: int = state.elevation_at(cell) * LAYERS_PER_LEVEL
	return Vector2(_column_x(cell), cell.y * ROW_STEP - level * SIDE_HEIGHT)


func feet_of(cell: Vector2i) -> Vector2:
	return cell_origin(cell) + FEET


## Centro da casa em coordenadas de tela (usado também pelo teste de jogo).
func cell_to_screen(cell: Vector2i) -> Vector2:
	return battle_camera.project(board.global_transform * (cell_origin(cell) + Vector2(93, 107)), _cell_elevation(cell))


func _cell_at(screen: Vector2) -> Vector2i:
	for row in range(state.rows() - 1, -1, -1): # as linhas da frente cobrem as de trás
		for col in state.cols():
			var cell := Vector2i(col, row)
			var projected := PackedVector2Array()
			for point in hex_poly:
				projected.append(battle_camera.project(board.global_transform * (cell_origin(cell) + point), _cell_elevation(cell)))
			if Geometry2D.is_point_in_polygon(screen, projected):
				return cell
	return NO_CELL


## Com a câmera baixa, a cabeça pode estar sobre outra casa. Seleciona o
## personagem visível por seus pixels opacos, respeitando a ordem do desenho.
func _pick_cell(screen: Vector2) -> Vector2i:
	var ground_cell := _cell_at(screen)
	# Mantém o centro de cada hex acessível para movimento e mira no chão,
	# mesmo quando o corpo de alguém na fileira da frente passa por cima dele.
	if ground_cell != NO_CELL and screen.distance_to(cell_to_screen(ground_cell)) <= 14.0:
		return ground_cell
	var candidates: Array = views.values()
	candidates.sort_custom(func(a, b): return a.z_index > b.z_index)
	for view in candidates:
		if not view.visible or not view.unit.alive():
			continue
		var anchor: Vector2 = view.global_position
		var height: float = battle_camera.elevation_of(view)
		var original: Vector2 = anchor + (screen - battle_camera.project(anchor, height)) / battle_camera.depth_scale(anchor.y + height)
		if view.sprite.is_pixel_opaque(view.sprite.to_local(original)):
			return view.unit.pos
	return ground_cell


# --- Laço de turnos ----------------------------------------------------------

func _advance() -> void:
	if online_session.playing and not online_session.relay.is_master:
		busy = true
		return
	busy = true
	pinned = null
	_close_menu()
	_refresh_overlays()
	while true:
		var result: int = state.winner()
		if result >= 0:
			online_session.publish([], true)
			sound_manager.play_sfx(&"victory" if result == Data.Team.PLAYER else &"defeat")
			hud.show_end("Vitória!" if result == Data.Team.PLAYER else "Derrota")
			return
		var unit = state.active_unit()
		_place_ground_marker(active_outline, unit.pos)
		active_outline.z_index = unit.pos.y * 10 + 3
		_refresh_turn_markers()
		hud.refresh(state)
		hud.set_hint("")
		if not unit.pending.is_empty():
			await _play(state.resolve_pending(unit))
			continue
		if unit.team == Data.Team.ENEMY:
			await get_tree().create_timer(0.2).timeout
			await _play(AI.apply(state, unit, AI.decide(state, unit)))
			continue
		break
	busy = false
	hud.refresh(state)
	_refresh_turn_markers()
	_refresh_overlays()
	_update_hint()
	online_session.publish([], true)


func _perform(events: Array) -> void:
	busy = true
	_close_menu()
	hud.set_hint("")
	_refresh_overlays()
	await _play(events)
	_advance()


## Seta amarela em quem joga e vermelha no próximo inimigo; os números ficam prontos
## para quando forem pedidos.
func _refresh_turn_markers() -> void:
	var order: Array = state.turn_order()
	var next_enemy = null
	for unit in order.slice(1):
		if unit.team == Data.Team.ENEMY:
			next_enemy = unit
			break
	for i in order.size():
		var view = views[order[i]]
		view.set_order(i + 1, i == 0)
		if i == 0:
			view.show_arrow(ACTIVE_COLOR)
		elif order[i] == next_enemy:
			view.show_arrow(NEXT_ENEMY_ARROW)
		else:
			view.hide_arrow()


# Os números mudam a quase toda ação, então só aparecem quando pedidos: todos pelo
# botão de ordem, ou só o da unidade inspecionada.
func _refresh_order_badges() -> void:
	var shown = _shown_unit() if not busy else null
	for unit in views:
		views[unit].set_order_visible(show_order or unit == shown)


func _on_order_toggled(on: bool) -> void:
	show_order = on
	_refresh_order_badges()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event)
		return
	if busy:
		return
	if event is InputEventMouseMotion:
		# Toque vira mouse emulado; sem este filtro ele deixaria um "hover" preso.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var cell := _pick_cell(event.position)
		if cell != hover:
			hover = cell
			if state.unit_at(cell) != null:
				pinned = null # passar o mouse por outro personagem troca o foco
			_refresh_overlays()
			_update_hint()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_close_menu()
		elif event.keycode == KEY_SPACE:
			if online_session.playing:
				_submit_online("wait", NO_CELL)
			else:
				_perform(state.do_wait(state.active_unit()))
		elif event.keycode >= KEY_1 and event.keycode < KEY_1 + menu_options.size():
			_on_option_pressed(event.keycode - KEY_1)


# O toque vira clique ao soltar, para dar tempo de saber se a pessoa está segurando.
# Segurar num personagem (ou o botão direito) abre o cartão dele, até no turno inimigo.
func _handle_button(event: InputEventMouseButton) -> void:
	var cell := _pick_cell(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if state.unit_at(cell) != null:
			_show_card(state.unit_at(cell))
		elif not busy:
			_close_menu()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		press_token += 1
		if event.pressed:
			pressing = true
			press_cell = cell
			if state.unit_at(cell) != null:
				var token := press_token
				get_tree().create_timer(HOLD_TIME).timeout.connect(func(): _on_hold(token))
		elif pressing:
			pressing = false
			if not busy:
				_click(press_cell)


func _on_hold(token: int) -> void:
	if token != press_token or not pressing:
		return
	pressing = false # o soltar depois do cartão não vale como toque
	var unit = state.unit_at(press_cell)
	if unit != null:
		_show_card(unit)


func _show_card(unit) -> void:
	var order: int = state.turn_order().find(unit) + 1
	var info := {
		"title": unit.display_name,
		"team": unit.team,
		"type_id": unit.type_id,
		"hp": unit.hp,
		"max_hp": unit.max_hp,
		"order": order,
		"atk": unit.atk,
		"def": unit.def,
		"speed": unit.speed,
		"abilities": unit.abilities.map(func(id): return _card_ability(unit, id)),
	}
	if not unit.pending.is_empty():
		var ability: Dictionary = Data.ABILITIES[unit.pending["ability"]]
		var radius: int = ability["radius"]
		info["spell"] = {
			"name": ability["name"],
			"radius": radius,
			"cells": 1 + 3 * radius * (radius + 1),
			"power": roundi(unit.atk * ability["power"]),
			"actions": state.actions_until(unit),
			"secret": unit.team != Data.Team.PLAYER,
		}
	hud.show_card(info)


const ABILITY_ICONS := {"golpe": "sword", "rapido": "sword", "tiro": "arrow", "cura": "heart", "guarda": "shield", "escudo_fogo": "shield"} # o resto das magias usa o fogo


# Magias sem ícone próprio usam o do elemento: a pasta do efeito (fogo/, agua/).
func _spell_icon(id: String) -> String:
	if not SPELL_FX.has(id):
		return "star"
	return "drop" if SPELL_FX[id]["impact"].begins_with("agua/") else "flame"


## Dados de uma habilidade para a ficha: alcance, efeito, tempo e quanto tiraria do herói da vez.
func _card_ability(unit, id: String) -> Dictionary:
	var ability: Dictionary = Data.ABILITIES[id]
	var out := {"name": ability["name"], "icon": ABILITY_ICONS.get(id, _spell_icon(id)), "time": state.time_for(ability["time"], unit)}
	if ability["kind"] == "charge":
		out["time"] = "%d + %d" % [state.cast_time_for(unit, id), state.recovery_time_for(unit, id)]
		out["time_hint"] = "Conjuração + recuperação após o impacto"
	if ability["kind"] == "guard":
		out["range"] = ""
	elif ability["min_range"] > 1:
		out["range"] = "%d-%d" % [ability["min_range"], ability["range"]]
	else:
		out["range"] = str(ability["range"])
	match ability["kind"]:
		"heal":
			out["amount"] = "+%d" % ability["heal"]
			out["amount_icon"] = "heart"
		"guard":
			out["amount"] = "½ dano"
			out["amount_icon"] = "shield"
		_:
			out["amount"] = str(roundi(unit.atk * ability["power"]))
			out["amount_icon"] = "star"
	var hero = state.active_unit()
	if ability["kind"] == "attack" and hero.team == Data.Team.PLAYER and unit.team != Data.Team.PLAYER:
		out["hero_type"] = hero.type_id
		out["hero_amount"] = state.preview_attack(unit, id, hero)["amount"]
	return out


# Mesmas regras para mouse e toque: casa vizinha livre anda na hora; qualquer outra
# casa abre o menu com o que dá para fazer nela. Nada acontece sem tocar numa opção.
func _click(cell: Vector2i) -> void:
	if pinned != null:
		pinned = null
		_refresh_overlays()
		_update_hint()
	if menu_cell != NO_CELL:
		var other_unit: bool = cell != menu_cell and cell != NO_CELL and state.unit_at(cell) != null
		_close_menu() # tocar fora só fecha, para não andar sem querer
		if not other_unit:
			return
	if cell == NO_CELL:
		return
	var unit = state.active_unit()
	# Se alguma ação mira essa casa, o menu pergunta: assim dá para mirar no chão
	# onde o inimigo ainda vai pisar sem o herói sair andando.
	var aimable := _cell_options(cell).any(func(option): return option["kind"] == "ability")
	# Casa comum anda na hora; se o terreno muda o jogo (tempo, dano, altura), pergunta antes.
	if state.unit_at(cell) == null and state.can_step(unit, cell) and not aimable and _terrain_notes(unit, cell).is_empty():
		if online_session.playing:
			_submit_online("step", cell)
		else:
			_perform(state.do_step(unit, cell))
		return
	_open_menu(cell)


## O que muda para o herói se ele for para essa casa, em frases curtas.
func _terrain_notes(unit, cell: Vector2i) -> Array:
	var notes := []
	var tile: Dictionary = state.tile_at(cell)
	var normal: int = state.time_for(Data.STEP_TIME, unit)
	var cost: int = state.time_for(state.step_cost(unit.pos, cell), unit)
	if cost != normal:
		var reasons := []
		if tile["cost"] > 0:
			reasons.append(tile["name"].to_lower())
		if state.elevation_at(cell) > state.elevation_at(unit.pos):
			reasons.append("subida")
		notes.append("Passo custa %d de tempo (normal %d): %s" % [cost, normal, " e ".join(reasons)])
	if tile["damage"] < 1.0:
		notes.append("Aqui você leva %d%% menos dano" % roundi((1.0 - tile["damage"]) * 100))
	var climb: int = state.elevation_at(cell) - state.elevation_at(unit.pos)
	var percent := roundi(Data.HEIGHT_MULT_PER_LEVEL * 100)
	if climb > 0:
		notes.append("Mais alto: +%d%% de dano em quem está abaixo" % (percent * climb))
	elif climb < 0:
		notes.append("Mais baixo: −%d%% de dano em quem está acima" % (percent * -climb))
	return notes


func _open_menu(cell: Vector2i) -> void:
	var occupant = state.unit_at(cell)
	var options := _cell_options(cell)
	if options.is_empty() and occupant == null:
		return
	menu_cell = cell
	menu_options = options
	# Sem ações, um menu só cobriria o alcance que a pessoa quer ver: a informação vai na dica.
	if not options.is_empty():
		var title: String = occupant.display_name if occupant != null else state.tile_at(cell)["name"]
		var info: String = _menu_info(occupant) if occupant != null else "\n".join(_terrain_notes(state.active_unit(), cell))
		hud.show_menu(cell_to_screen(cell), title, occupant.team if occupant != null else -1, info, options)
	# A fila mostra onde a magia seria solta, antes de confirmar.
	var spell := _menu_spell()
	if spell != "":
		var unit = state.active_unit()
		hud.preview_cast(state, unit, state.cast_time_for(unit, spell))
	_refresh_overlays()
	_update_hint()


func _close_menu() -> void:
	if menu_cell == NO_CELL:
		return
	menu_cell = NO_CELL
	menu_options = []
	hud.hide_menu()
	hud.preview_cast(state, null, 0)
	_refresh_overlays()
	_update_hint()


func _cell_options(cell: Vector2i) -> Array:
	var unit = state.active_unit()
	var options := []
	for id in unit.abilities:
		if state.valid_targets(unit, id).has(cell):
			var option := _ability_option(unit, id, cell)
			option["kind"] = "ability"
			option["id"] = id
			option["label"] = Data.ABILITIES[id]["name"]
			options.append(option)
	if state.unit_at(cell) != null:
		options.append_array(_blocked_options(unit, state.unit_at(cell)))
	if cell == unit.pos:
		options.append({"kind": "wait", "label": "Esperar", "detail": "passa a vez"})
	elif state.unit_at(cell) == null:
		if state.can_step(unit, cell):
			options.append({"kind": "step", "label": "Andar", "detail": "tempo %d" % state.time_for(state.step_cost(unit.pos, cell), unit)})
		if not options.is_empty():
			options.append({"kind": "cancel", "label": "Cancelar", "detail": ""})
	return options


func _ability_option(unit, id: String, cell: Vector2i) -> Dictionary:
	var ability: Dictionary = Data.ABILITIES[id]
	var target = state.unit_at(cell)
	match ability["kind"]:
		"attack":
			return {"detail": _preview_text(unit, id, target), "tone": "damage"}
		"heal":
			return {"detail": "+%d" % mini(ability["heal"], target.max_hp - target.hp), "tone": "heal"}
		"guard":
			return {"detail": "metade do dano"}
		_:
			return {"detail": _area_text(unit, state.area_of(cell, ability["radius"])), "note": _cast_wait_text(state.cast_wait(unit, id))}


## Magia carregada não sai na hora: diz quantas ações dos outros passam antes
## e quanto isso dá em rodadas (todo mundo agindo uma vez).
func _cast_wait_text(actions: int) -> String:
	if actions == 0:
		return "solta já na sua próxima vez"
	var others: int = state.units.filter(func(u): return u.alive()).size() - 1
	var rounds := ceili(float(actions) / maxi(1, others))
	return "solta após %d aç%s (~%d rodada%s)" % [actions, "ão" if actions == 1 else "ões", rounds, "" if rounds == 1 else "s"]


# A magia acerta todo mundo na área, então o menu avisa quantos aliados vão junto.
func _area_text(unit, cells: Array) -> String:
	var enemies := 0
	var allies := 0
	for cell in cells:
		var occupant = state.unit_at(cell)
		if occupant != null:
			if occupant.team == unit.team:
				allies += 1
			else:
				enemies += 1
	var text := "%d inimigo%s" % [enemies, "" if enemies == 1 else "s"]
	if allies > 0:
		text += ", %d aliado%s" % [allies, "" if allies == 1 else "s"]
	return text


func _menu_info(occupant) -> String:
	if occupant == null:
		return ""
	return "Vida %d/%d, age em %dº" % [occupant.hp, occupant.max_hp, state.turn_order().find(occupant) + 1]


func _on_option_pressed(index: int) -> void:
	if busy or index < 0 or index >= menu_options.size():
		return
	var option: Dictionary = menu_options[index]
	if option.get("disabled", false):
		return
	var cell := menu_cell
	var unit = state.active_unit()
	if online_session.playing and option["kind"] != "cancel":
		_submit_online(option["kind"], cell, option.get("id", ""))
		return
	match option["kind"]:
		"ability":
			_perform(state.do_ability(unit, option["id"], cell))
		"wait":
			_perform(state.do_wait(unit))
		"step":
			_perform(state.do_step(unit, cell))
		"cancel":
			_close_menu()


# --- Destaques e dica --------------------------------------------------------

func _refresh_overlays() -> void:
	for cell in forests:
		# A frente ainda encobre as pernas, mas deixa uma pista do ocupante.
		var occupant = state.unit_at(cell)
		forests[cell].front.modulate.a = 0.82 if occupant != null and occupant.alive() else 1.0
	_refresh_order_badges()
	for cell in overlays:
		overlays[cell].visible = false
		reach_lines[cell].visible = false
	inspect_outline.visible = false
	if not busy:
		_mark_free_look()
	# Só a mira dos heróis aparece: ver onde a magia inimiga cai tornaria o mago dela inútil.
	# A IA também não olha a mira dos heróis, então os dois lados jogam no escuro.
	for unit in state.units:
		if unit.alive() and unit.team == Data.Team.PLAYER and not unit.pending.is_empty():
			var ability: Dictionary = Data.ABILITIES[unit.pending["ability"]]
			for cell in state.area_of(unit.pending["tile"], ability["radius"]):
				_mark(cell, CHARGE_COLOR)
	_sync_focus()


func _mark_free_look() -> void:
	var unit = state.active_unit()
	var shown = _shown_unit()
	var focus: Vector2i = menu_cell if menu_cell != NO_CELL else (shown.pos if shown != null else NO_CELL)
	if focus != NO_CELL:
		_place_ground_marker(inspect_outline, focus)
		inspect_outline.z_index = focus.y * 10 + 4
		inspect_outline.visible = true
	var spell := _menu_spell()
	if spell != "":
		for cell in state.area_of(menu_cell, Data.ABILITIES[spell]["radius"]):
			_mark(cell, AREA_COLOR)
		return
	if shown != null and shown != unit:
		_mark_reach(shown)
		return
	for cell in Hex.neighbors(unit.pos):
		if state.can_step(unit, cell):
			_mark(cell, STEP_COLOR)
	_mark_aim(unit)


## Magia carregada que o menu aberto oferece; a área dela fica pintada.
func _menu_spell() -> String:
	for option in menu_options:
		if option["kind"] == "ability" and Data.ABILITIES[option["id"]]["kind"] == "charge":
			return option["id"]
	return ""


## Quem está sendo inspecionado: o do menu aberto ou, no mouse, o que está sob o cursor.
func _shown_unit():
	if menu_cell != NO_CELL:
		return state.unit_at(menu_cell)
	if pinned != null:
		return pinned
	return state.unit_at(hover) if hover != NO_CELL else null


func _mark_reach(unit) -> void:
	for cell in state.attack_reach(unit):
		_mark_reach_cell(cell)
		var occupant = state.unit_at(cell)
		if occupant != null and occupant.team != unit.team:
			_mark(cell, TARGET_COLOR)


## Para o herói da vez, o laranja é onde ele consegue mirar: no arqueiro e no mago a
## casa colada fica sem cor, e dá para ver na hora que ali ele não acerta.
func _mark_aim(unit) -> void:
	for id in unit.abilities:
		var kind: String = Data.ABILITIES[id]["kind"]
		if kind != "attack" and kind != "charge":
			continue
		for cell in state.cells_in_range(unit, id):
			_mark_reach_cell(cell)
			var occupant = state.unit_at(cell)
			if occupant != null and occupant.team != unit.team:
				_mark(cell, TARGET_COLOR)


func _mark_reach_cell(cell: Vector2i) -> void:
	if not reach_lines.has(cell):
		return
	reach_lines[cell].visible = true
	if not overlays[cell].visible:
		_mark(cell, REACH_FILL)


func _mark(cell: Vector2i, color: Color) -> void:
	if overlays.has(cell):
		overlays[cell].color = color
		overlays[cell].visible = true


func _preview_text(unit, id: String, target) -> String:
	var result: Dictionary = state.preview_attack(unit, id, target)
	return "−%d flanco" % result["amount"] if result["flank"] else "−%d" % result["amount"]


func _update_hint() -> void:
	if busy:
		return
	var unit = state.active_unit()
	if online_session.playing:
		var owner: int = online_session.owner_of(unit)
		hud.set_hint("Vez de %s · %s%s" % [unit.display_name, online_session.players.get(owner, "Dono"), " · você joga" if online_session.can_control(unit) else " · aguardando"])
		return
	if hud.menu_open():
		hud.set_hint("")
		return
	var shown = _shown_unit()
	if shown != null:
		var text := "%s: %s" % [shown.display_name, _menu_info(shown).to_lower()]
		if not shown.pending.is_empty():
			text += ". Preparando magia: segure para ver"
		if menu_cell != NO_CELL and shown.team != unit.team:
			text += ". Fora do seu alcance, toque de novo para fechar."
		hud.set_hint(text)
	elif hover != NO_CELL and state.can_step(unit, hover):
		var tile: Dictionary = state.tile_at(hover)
		hud.set_hint("%s: passo custa tempo %d" % [tile["name"], state.time_for(state.step_cost(unit.pos, hover), unit)])
	else:
		hud.set_hint(DEFAULT_HINT)


# --- Animação dos eventos ----------------------------------------------------

func _play(events: Array) -> void:
	online_session.publish(events)
	for event in events:
		match event["type"]:
			"move":
				await _play_move(event)
			"attack":
				await _play_attack(event)
			"damage":
				await _play_damage(event)
			"heal":
				await _play_heal(event)
			"death":
				await _play_death(event)
			"guard":
				var id: String = event.get("ability", "")
				if SPELL_FX.has(id):
					await _play_spell_fx(id, Vector2.ZERO, [views[event["unit"]].position])
				else:
					sound_manager.play_sfx(&"guard")
				views[event["unit"]].set_status("em guarda")
			"cast_start":
				await _play_cast_start(event)
			"cast_resolve":
				await _play_cast_resolve(event)
	for unit in views:
		if unit.alive():
			_show_status(unit)


func _submit_online(kind: String, cell: Vector2i, ability := "") -> void:
	if busy or not online_session.can_control(state.active_unit()): return
	_close_menu()
	online_session.submit({kind = kind, cell = cell, ability = ability})


func _network_command(sender: int, command: Dictionary) -> void:
	if busy or not online_session.playing or not online_session.relay.is_master: return
	if command.get("revision", -1) != online_session.revision or state.winner() >= 0: return
	var unit = state.active_unit()
	if online_session.owner_of(unit) != sender or not unit.pending.is_empty(): return
	var cell: Variant = command.get("cell", NO_CELL)
	if not cell is Vector2i: return
	match str(command.get("kind", "")):
		"wait": _perform(state.do_wait(unit))
		"step":
			if state.in_bounds(cell) and state.can_step(unit, cell): _perform(state.do_step(unit, cell))
		"ability":
			var id: String = str(command.get("ability", ""))
			if id in unit.abilities and state.in_bounds(cell) and cell in state.valid_targets(unit, id):
				_perform(state.do_ability(unit, id, cell))


func _network_packet(_packet: Dictionary) -> void:
	if remote_playing or not online_session.playing or online_session.relay.is_master: return
	remote_playing = true
	while not online_session.packets.is_empty():
		var packet: Dictionary = online_session.packets.pop_front()
		if int(packet.revision) <= online_session.revision: continue
		online_session.revision = int(packet.revision)
		busy = true
		_close_menu()
		online_session.apply_snapshot(packet.snapshot)
		var events: Array = packet.events
		for event in events:
			for key in ["unit", "target"]:
				if event.has(key): event[key] = state.units[int(event[key])]
		await _play(events)
		for unit in views:
			views[unit].position = feet_of(unit.pos)
			battle_camera.set_elevation(_cell_elevation(unit.pos), views[unit])
			views[unit].set_hp(unit.hp)
			views[unit].visible = unit.alive()
		busy = not bool(packet.ready)
		hud.refresh(state)
		_place_ground_marker(active_outline, state.active_unit().pos)
		_refresh_turn_markers()
		_refresh_overlays()
		_update_hint()
		if state.winner() >= 0:
			busy = true
			hud.show_end("Vitória!" if state.winner() == Data.Team.PLAYER else "Derrota")
	remote_playing = false


func _room_status() -> void:
	if room_label == null: return
	room_label.text = "SALA DE %s · %d/4  " % [online_session.players.get(online_session.original_host, "Jogador"), online_session.players.size()]
	_update_hint()


func _leave_online() -> void:
	online_session.leave()
	get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")


func _network_lost(_reason: String) -> void:
	get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")


## Texto embaixo da unidade. Quem carrega magia mostra a contagem regressiva
## de ações até ela sair, a mesma do menu e da fila.
func _show_status(unit) -> void:
	if not unit.pending.is_empty():
		views[unit].set_status("magia em %d" % state.actions_until(unit), CAST_INK)
	else:
		views[unit].set_status("em guarda" if unit.guarding else "")


func _play_move(event: Dictionary) -> void:
	var view = views[event["unit"]]
	var from: Vector2 = feet_of(event["from"])
	var to: Vector2 = feet_of(event["to"])
	view.face_toward(to - from)
	view.z_index = maxi(event["from"].y, event["to"].y) * 10 + 5
	view.set_walking(true)
	sound_manager.play_sfx(&"step")
	var height_delta: int = state.elevation_at(event["to"]) - state.elevation_at(event["from"])
	var duration := 0.22 if height_delta == 0 else 0.48
	var tween := create_tween()
	tween.tween_method(_move_frame.bind(view, from, to, _cell_elevation(event["from"]), _cell_elevation(event["to"]), height_delta), 0.0, 1.0, duration)
	await tween.finished
	view.set_walking(false)
	view.set_jump_height(0.0)
	view.z_index = event["to"].y * 10 + 5
	_refresh_overlays()


func _move_frame(progress: float, view, from: Vector2, to: Vector2, from_height: float, to_height: float, height_delta: int) -> void:
	view.position = from.lerp(to, progress)
	battle_camera.set_elevation(lerpf(from_height, to_height, progress), view)
	var jump := 0.0
	if height_delta != 0:
		jump = sin(progress * PI) * (110.0 if height_delta > 0 else 65.0)
	view.set_jump_height(jump)


func _play_attack(event: Dictionary) -> void:
	var unit = event["unit"]
	var target = event["target"]
	var view = views[unit]
	view.face_toward(feet_of(target.pos) - view.position)
	# Quem apanha olha para quem bateu, para o tranco do dano sair na direção certa.
	views[target].face_toward(view.position - views[target].position)
	var id: String = event.get("ability", "")
	var magic := SPELL_FX.has(id)
	if not magic:
		sound_manager.play_sfx(&"swing") # golpe corpo a corpo ou disparo da flecha
	await view.play_once(UnitView.Anim.ATTACK)
	if id == "tiro":
		await _fly_projectile("kit/arrow", view.position + Vector2(0, -90), views[target].position + Vector2(0, -90))
		sound_manager.play_sfx(&"arrow_hit")
	elif magic:
		await _play_spell_fx(id, view.position + Vector2(0, -90), [views[target].position])
	else:
		sound_manager.play_sfx(&"melee_hit")


func _play_damage(event: Dictionary) -> void:
	var view = views[event["target"]]
	view.set_hp(event["hp"])
	var text := str(event["amount"])
	if event.get("flank", false):
		text += " flanco!"
	_float_text(view.position + Vector2(-20, -200), text, Color(1.0, 0.4, 0.3))
	sound_manager.play_sfx(&"hurt")
	view.play_once(UnitView.Anim.HURT)
	await get_tree().create_timer(0.25).timeout


func _play_heal(event: Dictionary) -> void:
	var view = views[event["target"]]
	view.set_hp(event["hp"])
	sound_manager.play_sfx(&"heal")
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/kit/heal.png")
	fx.scale = Vector2.ONE * 0.5
	fx.position = view.position + Vector2(0, -90)
	fx.z_index = 900
	board.add_child(fx)
	_add_effect_billboard(fx, Vector2(0, 90))
	var tween := create_tween()
	tween.tween_property(fx, "modulate:a", 0.0, 0.6)
	tween.tween_callback(fx.queue_free)
	_float_text(view.position + Vector2(-20, -200), "+%d" % event["amount"], Color(0.4, 1.0, 0.5))
	await tween.finished


# O kit não tem animação de morte: a unidade tomba e some.
func _play_death(event: Dictionary) -> void:
	var view = views[event["target"]]
	sound_manager.play_sfx(&"death_hero" if event["target"].team == Data.Team.PLAYER else &"death_monster")
	var tween := create_tween().set_parallel()
	tween.tween_property(view, "rotation", deg_to_rad(80 if view.sprite.flip_h else -80), 0.35)
	tween.tween_property(view, "modulate:a", 0.0, 0.5)
	await tween.finished
	view.visible = false


func _play_cast_start(event: Dictionary) -> void:
	var view = views[event["unit"]]
	view.face_toward(feet_of(event["tile"]) - view.position)
	_show_status(event["unit"])
	_refresh_overlays()
	sound_manager.play_sfx(&"charge")
	await view.play_once(UnitView.Anim.ATTACK)


func _play_cast_resolve(event: Dictionary) -> void:
	var view = views[event["unit"]]
	_refresh_overlays()
	await view.play_once(UnitView.Anim.ATTACK)
	var id: String = event["id"]
	var center: Vector2 = feet_of(event["tile"]) + Vector2(0, -20)
	if SPELL_FX.has(id):
		var spots := [feet_of(event["tile"])]
		if SPELL_FX[id].get("per_cell", false):
			var cells: Array = event["cells"].duplicate()
			cells.sort_custom(func(a, b): return Hex.distance(a, event["tile"]) < Hex.distance(b, event["tile"]))
			spots = cells.map(func(cell): return feet_of(cell))
		await _play_spell_fx(id, view.position + Vector2(0, -90), spots)
	else:
		await _fly_projectile("kit/magic", view.position + Vector2(0, -90), center)
	var flashes := []
	for cell in event["cells"]:
		var flash := Polygon2D.new()
		flash.polygon = hex_poly
		_place_ground_marker(flash, cell)
		flash.color = Color(1.0, 0.75, 0.3, 0.85)
		flash.position = cell_origin(cell)
		flash.z_index = 900
		board.add_child(flash)
		flashes.append(flash)
	var tween := create_tween().set_parallel()
	for flash in flashes:
		tween.tween_property(flash, "modulate:a", 0.0, 0.35)
	await tween.finished
	for flash in flashes:
		flash.queue_free()


## Projétil (se a magia tiver) do mago até o primeiro ponto, depois o impacto em todos os pontos.
## Os pontos são pés de casas (com per_cell, uma por casa, começando pelo centro da área).
func _play_spell_fx(id: String, from: Vector2, spots: Array) -> void:
	var spell: Dictionary = SPELL_FX[id]
	var ground: bool = spell.get("ground", false)
	var lift: float = spell.get("lift", 90)
	if spell.has("projectile"):
		var to: Vector2 = spots[0] - Vector2(0, 90 if ground else lift)
		var ball := _fx_sprite(spell["projectile"], PROJECTILE_SCALE)
		ball.position = from
		_add_effect_billboard(ball, Vector2(0, 90))
		# Os projéteis do pack voam para a direita; projectile_turn corrige os que não.
		ball.rotation = (to - from).angle() + spell.get("projectile_turn", 0.0)
		var duration := clampf(from.distance_to(to) / 1400.0, 0.15, 0.5)
		sound_manager.play_sfx(spell.get("cast_sound", &"fire_cast"))
		var flight := create_tween().set_parallel()
		flight.tween_property(ball, "position", to, duration)
		flight.tween_method(battle_camera.set_elevation.bind(ball), _height_at_point(from + Vector2(0, 90)), _height_at_point(spots[0]), duration)
		flight.tween_method(_loop_frames.bind(ball), 0.0, duration, duration)
		await flight.finished
		ball.queue_free()
	sound_manager.play_sfx(spell["sound"])
	var size: float = spell["impact_scale"]
	var frames: int = fx_meta[spell["impact"]]["frames"]
	var hits := []
	var burst := create_tween().set_parallel()
	for i in spots.size():
		var hit := _fx_sprite(spell["impact"], size)
		hit.position = spots[i]
		hit.position.y -= fx_meta[spell["impact"]]["h"] * size / 2.0 if ground else lift
		_add_effect_billboard(hit, Vector2(0, fx_meta[spell["impact"]]["h"] * size / 2.0 if ground else lift))
		var delay: float = spell.get("ring_delay", 0.0) if i > 0 else 0.0
		hit.visible = delay == 0.0
		burst.tween_callback(hit.show).set_delay(delay)
		burst.tween_property(hit, "frame", frames - 1, frames / FX_FPS).from(0).set_delay(delay)
		hits.append(hit)
	await burst.finished
	for hit in hits:
		hit.queue_free()


func _fx_sprite(fx_name: String, size: float) -> Sprite2D:
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/%s.png" % fx_name)
	fx.hframes = fx_meta[fx_name]["frames"]
	fx.scale = Vector2.ONE * size
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_index = 900
	board.add_child(fx)
	return fx


func _loop_frames(elapsed: float, fx: Sprite2D) -> void:
	fx.frame = int(elapsed * FX_FPS) % fx.hframes


func _fly_projectile(texture: String, from: Vector2, to: Vector2) -> void:
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/%s.png" % texture)
	fx.position = from
	fx.z_index = 900
	if texture == "kit/arrow":
		fx.rotation = (to - from).angle() - Vector2(-22, 12).angle() # inclinação da flecha no PNG
	else:
		fx.scale = Vector2.ONE * 1.6
	board.add_child(fx)
	var tween := create_tween()
	_add_effect_billboard(fx, Vector2(0, 90))
	var duration := clampf(from.distance_to(to) / 1800.0, 0.1, 0.4)
	tween.set_parallel()
	tween.tween_property(fx, "position", to, duration)
	tween.tween_method(battle_camera.set_elevation.bind(fx), _height_at_point(from + Vector2(0, 90)), _height_at_point(to + Vector2(0, 90)), duration)
	await tween.finished
	fx.queue_free()


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.z_index = 1000
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	board.add_child(label)
	_add_effect_billboard(label, Vector2(0, 200))
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", pos.y - 70, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


# Toda habilidade que serviria nesse alvo aparece; as que não dá para usar agora
# ficam apagadas dizendo o alcance que precisa (ou que a vida já está cheia).
func _blocked_options(unit, target) -> Array:
	var options := []
	var enemy: bool = target.team != unit.team
	for id in unit.abilities:
		var ability: Dictionary = Data.ABILITIES[id]
		var kind: String = ability["kind"]
		var fits: bool = (kind == "attack" and enemy) or kind == "charge" or (kind == "heal" and not enemy) or (kind == "guard" and target == unit)
		if not fits or state.valid_targets(unit, id).has(target.pos):
			continue
		var detail := _range_short(ability)
		if kind == "heal" and target.hp >= target.max_hp and Hex.distance(unit.pos, target.pos) <= ability["range"]:
			detail = "vida cheia"
		options.append({"kind": "blocked", "id": id, "label": ability["name"], "detail": detail, "disabled": true})
	return options


func _range_short(ability: Dictionary) -> String:
	if ability["min_range"] > 1:
		return "de %d a %d casas" % [ability["min_range"], ability["range"]]
	return "só colado" if ability["range"] == 1 else "até %d casas" % ability["range"]
