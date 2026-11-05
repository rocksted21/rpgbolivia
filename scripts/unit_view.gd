extends Node2D
## Desenho de uma unidade: sprite animado e barra de vida.

signal anim_done

enum Anim { IDLE, WALK, ATTACK, HURT, STRONG }
enum Facing { SIDE, SOUTH, NORTH }

# Folhas com direção (PixelLab): as 4 primeiras linhas são as do Anim, de lado;
# depois vêm frente e costas. Parado só existe de frente.
const DIRECTION_ROWS := {
	Anim.IDLE: {Facing.SIDE: 0, Facing.SOUTH: 0, Facing.NORTH: 0},
	Anim.WALK: {Facing.SIDE: 1, Facing.SOUTH: 4, Facing.NORTH: 5},
	Anim.ATTACK: {Facing.SIDE: 2, Facing.SOUTH: 6, Facing.NORTH: 7},
	Anim.HURT: {Facing.SIDE: 3, Facing.SOUTH: 8, Facing.NORTH: 9},
	# Ataque forte (habilidades): só nas folhas novas; sem ele, usa o ataque.
	Anim.STRONG: {Facing.SIDE: 10, Facing.SOUTH: 11, Facing.NORTH: 12},
}
const STRONG_ROWS := 13
# Mais vertical que isso, a unidade vira de frente ou de costas.
const VERTICAL_RATIO := 1.0
const FPS := 16.0
const BAR_SIZE := Vector2(120, 12)
const BADGE_SIZE := 60.0
const ARROW_GAP := 14.0
const ARROW_GAP_OVER_BADGE := 62.0
const BOUNCE_SPEED := 6.0
const BOUNCE_HEIGHT := 10.0
# Marcadores por cima de todo o tabuleiro: nada pode cobrir a ordem de turno.
const MARKER_Z := 800
const ACTIVE_BADGE := Color(1.0, 0.84, 0.2)

var unit
var sprite: Sprite2D
var hp_fill: ColorRect
var status: Label
var team_color: Color
var head_y := 0.0
var badge: Label
var badge_style: StyleBoxFlat
var arrow: Node2D
var arrow_gap := ARROW_GAP
var bounce_time := 0.0
var row := Anim.IDLE
var looping := true
var walking_now := false # o que volta a tocar depois de um ataque ou de um tranco
var frame_pos := 0.0
var frames := 10
var row_frames := []
var directional := false
var facing := Facing.SIDE
var visual_root: Node2D
var shadow: Polygon2D


func setup(p_unit, p_team_color: Color, meta: Dictionary) -> void:
	unit = p_unit
	team_color = p_team_color
	head_y = -float(meta["height"])
	frames = int(meta["frames"])
	row_frames = meta.get("row_frames", [])
	directional = meta.get("directions", false)
	# Sombra de contato, ancorada nos pés e atrás do sprite.
	shadow = Polygon2D.new()
	var shadow_points := PackedVector2Array()
	for i in 32:
		var angle := TAU * i / 32.0
		shadow_points.append(Vector2(cos(angle) * 57, sin(angle) * 13 - 2))
	shadow.polygon = shadow_points
	shadow.color = Color(0.04, 0.06, 0.03, 0.32)
	add_child(shadow)
	visual_root = Node2D.new()
	add_child(visual_root)
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/units/%s.png" % unit.type_id)
	sprite.hframes = frames
	sprite.vframes = row_frames.size() if not row_frames.is_empty() else Anim.STRONG
	sprite.offset = Vector2(0, meta["cell_h"] / 2.0 - meta["feet_y"])
	if meta.get("pixel", false):
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual_root.add_child(sprite)

	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.75)
	bar.size = BAR_SIZE
	bar.position = Vector2(-BAR_SIZE.x / 2, 8)
	bar.z_as_relative = false
	bar.z_index = MARKER_Z - 2
	visual_root.add_child(bar)
	hp_fill = ColorRect.new()
	hp_fill.color = team_color
	hp_fill.size = BAR_SIZE - Vector2(4, 4)
	hp_fill.position = Vector2(2, 2)
	bar.add_child(hp_fill)

	status = Label.new()
	status.add_theme_font_size_override("font_size", 26)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 8)
	status.position = Vector2(-BAR_SIZE.x / 2, 22)
	visual_root.add_child(status)

	_build_markers()

	frame_pos = randf() * frames
	set_hp(unit.hp)
	face_right(unit.team == 0)


func _build_markers() -> void:
	badge_style = StyleBoxFlat.new()
	badge_style.set_corner_radius_all(int(BADGE_SIZE / 2))
	badge_style.set_border_width_all(4)
	badge_style.border_color = Color.BLACK
	badge = Label.new()
	badge.add_theme_stylebox_override("normal", badge_style)
	badge.add_theme_font_size_override("font_size", 38)
	badge.add_theme_color_override("font_color", Color.BLACK)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.position = Vector2(-BADGE_SIZE / 2, head_y - BADGE_SIZE + 6)
	badge.z_as_relative = false
	badge.z_index = MARKER_Z
	badge.visible = false
	visual_root.add_child(badge)

	var points := PackedVector2Array([Vector2(-30, -40), Vector2(30, -40), Vector2(0, 0)])
	arrow = Node2D.new()
	arrow.z_as_relative = false
	arrow.z_index = MARKER_Z + 1
	arrow.visible = false
	visual_root.add_child(arrow)
	var fill := Polygon2D.new()
	fill.name = "Fill"
	fill.polygon = points
	arrow.add_child(fill)
	var outline := Line2D.new()
	outline.points = points
	outline.closed = true
	outline.width = 5
	outline.default_color = Color.BLACK
	arrow.add_child(outline)


func _process(delta: float) -> void:
	bounce_time += delta
	arrow.position.y = head_y - arrow_gap + sin(bounce_time * BOUNCE_SPEED) * BOUNCE_HEIGHT
	frame_pos += delta * FPS
	var sheet_row := _sheet_row()
	var count := _row_frames(sheet_row)
	if frame_pos >= count:
		if looping:
			frame_pos = fmod(frame_pos, count)
		else:
			looping = true
			row = Anim.WALK if walking_now else Anim.IDLE
			frame_pos = 0.0
			sheet_row = _sheet_row()
			anim_done.emit()
	sprite.frame = sheet_row * frames + int(frame_pos)


## Quantos frames a linha `sheet_row` tem; folhas antigas têm todas iguais.
static func row_frame_count(meta: Dictionary, sheet_row: int) -> int:
	var counts: Array = meta.get("row_frames", [])
	return int(counts[sheet_row]) if sheet_row < counts.size() else int(meta["frames"])


func _sheet_row() -> int:
	var anim := row
	if anim == Anim.STRONG and not (directional and row_frames.size() >= STRONG_ROWS):
		anim = Anim.ATTACK
	return DIRECTION_ROWS[anim][facing] if directional else int(anim)


func _row_frames(sheet_row: int) -> int:
	return int(row_frames[sheet_row]) if sheet_row < row_frames.size() else frames


# Os sprites do jogo olham para a esquerda.
func face_right(right: bool) -> void:
	sprite.flip_h = right


## Vira para onde `delta` aponta: de lado (espelhando) ou, nas folhas com
## direção, de frente/costas quando o movimento é mais vertical.
func face_toward(delta: Vector2) -> void:
	if not is_zero_approx(delta.x):
		face_right(delta.x > 0)
	facing = Facing.SIDE
	if directional and absf(delta.y) > absf(delta.x) * VERTICAL_RATIO:
		facing = Facing.SOUTH if delta.y > 0 else Facing.NORTH


func play_once(anim: Anim) -> void:
	row = anim
	looping = false
	frame_pos = 0.0
	await anim_done


## Não corta uma animação que está tocando: quem espera por ela (o turno inteiro) ficaria
## preso para sempre. Quem chega andando e já ataca passa por aqui no meio do golpe.
func set_walking(walking: bool) -> void:
	walking_now = walking
	if looping:
		row = Anim.WALK if walking else Anim.IDLE


func set_jump_height(height: float) -> void:
	visual_root.position.y = -height
	shadow.scale = Vector2.ONE * lerpf(1.0, 0.55, clampf(height / 110.0, 0.0, 1.0))


func set_hp(hp: int) -> void:
	hp_fill.size.x = (BAR_SIZE.x - 4) * float(hp) / unit.max_hp


## Texto embaixo da barra de vida. Com cor (magia carregando) vira um selo
## escuro e maior, para dar para ler a contagem de longe.
func set_status(text: String, color := Color.WHITE) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)
	var badge_mode := color != Color.WHITE
	status.add_theme_font_size_override("font_size", 34 if badge_mode else 26)
	if badge_mode:
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(0.1, 0.06, 0.02, 0.85)
		pill.border_color = color
		pill.set_border_width_all(3)
		pill.set_corner_radius_all(14)
		pill.content_margin_left = 12
		pill.content_margin_right = 12
		status.add_theme_stylebox_override("normal", pill)
	else:
		status.remove_theme_stylebox_override("normal")
	# O selo passa por cima das casas da fileira de baixo, como os números da ordem.
	status.z_as_relative = not badge_mode
	status.z_index = MARKER_Z - 1 if badge_mode else 0
	status.reset_size()
	status.position = Vector2(-status.get_combined_minimum_size().x / 2 if badge_mode else -BAR_SIZE.x / 2, 22)


## Número de ordem em cima da cabeça; quem está na vez fica com o círculo amarelo.
func set_order(order: int, is_active: bool) -> void:
	badge.text = str(order)
	badge_style.bg_color = ACTIVE_BADGE if is_active else team_color


func set_order_visible(shown: bool) -> void:
	badge.visible = shown
	arrow_gap = ARROW_GAP_OVER_BADGE if shown else ARROW_GAP


func show_arrow(color: Color) -> void:
	arrow.get_node("Fill").color = color
	arrow.visible = true


func hide_arrow() -> void:
	arrow.visible = false
