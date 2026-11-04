extends Control
## Filminho da magia no cartão: a bola cai no centro e a área acende de dentro para
## fora, em loop. Mostra o tamanho da área, nunca onde ela vai cair no tabuleiro.

const LOOP := 2.4
const FALL_TIME := 0.7
const BURST_TIME := 0.5
const FADE_START := 1.5
const HEX_SIZE := 24.0
const GROUND := Color(0.42, 0.58, 0.28)
const EDGE := Color(0, 0, 0, 0.35)
const MARGIN := 12.0
const DROP_HEIGHT := 70.0 # espaço acima da área para a bola cair

var radius := 1
var color := Color(0.72, 0.3, 1.0)
var time := 0.0


func setup(p_radius: int, p_color: Color) -> void:
	radius = p_radius
	color = p_color
	var span := 2 * radius + 1
	custom_minimum_size = Vector2(span * sqrt(3.0) * HEX_SIZE + MARGIN * 2, span * 1.5 * HEX_SIZE + HEX_SIZE + DROP_HEIGHT + MARGIN)


func _process(delta: float) -> void:
	time = fmod(time + delta, LOOP)
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x / 2, (size.y + DROP_HEIGHT) / 2)
	var fall := clampf(time / FALL_TIME, 0.0, 1.0)
	var burst := clampf((time - FALL_TIME) / BURST_TIME, 0.0, 1.0)
	var fade := clampf((time - FADE_START) / (LOOP - FADE_START), 0.0, 1.0)
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			var pos := center + Vector2(HEX_SIZE * sqrt(3.0) * (q + r / 2.0), HEX_SIZE * 1.5 * r)
			var ring := (absi(q) + absi(r) + absi(q + r)) / 2
			var lit := 0.0
			if burst > 0.0:
				lit = clampf(burst * (radius + 1) - ring, 0.0, 1.0) * (1.0 - fade)
			var points := _hex(pos)
			draw_colored_polygon(points, GROUND.lerp(color, lit * 0.9))
			points.append(points[0])
			draw_polyline(points, EDGE, 2.0)
	if fall < 1.0:
		var ball := center + Vector2(-50, -DROP_HEIGHT).lerp(Vector2.ZERO, fall)
		draw_circle(ball, 10.0, color.lightened(0.5))
		draw_circle(ball, 6.0, Color.WHITE)


func _hex(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 90.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
	return points
