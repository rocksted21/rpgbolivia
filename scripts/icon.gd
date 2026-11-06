extends Control
## Ícones simples desenhados em código: o kit não traz ícones de interface.
## Coordenadas num quadrado de 0 a 1, escaladas pelo tamanho do controle.

const HOLE := Color(0.08, 0.09, 0.12) # olhos da caveira

var kind := ""
var color := Color.BLACK
var angle := 0.0: # só a bússola usa: para onde a agulha aponta, na tela
	set(value):
		if not is_equal_approx(value, angle):
			angle = value
			queue_redraw()


func setup(p_kind: String, p_color: Color, p_size: float) -> void:
	kind = p_kind
	color = p_color
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := maxf(2.0, size.x * 0.1)
	match kind:
		"sword":
			_line(0.3, 0.7, 0.88, 0.12, w)
			_line(0.16, 0.56, 0.44, 0.84, w)
			_line(0.3, 0.7, 0.1, 0.9, w * 1.3)
		"shield":
			_outline([0.5, 0.08, 0.88, 0.22, 0.84, 0.56, 0.5, 0.92, 0.16, 0.56, 0.12, 0.22], w)
		"bolt":
			_fill([0.6, 0.04, 0.16, 0.56, 0.47, 0.56, 0.4, 0.96, 0.84, 0.42, 0.53, 0.42])
		"heart":
			draw_circle(_p(0.31, 0.36), size.x * 0.21, color)
			draw_circle(_p(0.69, 0.36), size.x * 0.21, color)
			_fill([0.11, 0.42, 0.89, 0.42, 0.5, 0.9])
		"hexagon":
			_outline([0.5, 0.06, 0.88, 0.28, 0.88, 0.72, 0.5, 0.94, 0.12, 0.72, 0.12, 0.28], w)
		"star":
			var points := []
			for i in 10:
				var radius := 0.46 if i % 2 == 0 else 0.2
				var angle := deg_to_rad(36.0 * i - 90.0)
				points.append_array([0.5 + cos(angle) * radius, 0.52 + sin(angle) * radius])
			_fill(points)
		"hourglass":
			_line(0.18, 0.08, 0.82, 0.08, w)
			_line(0.18, 0.92, 0.82, 0.92, w)
			_outline([0.26, 0.1, 0.74, 0.1, 0.5, 0.5, 0.74, 0.9, 0.26, 0.9, 0.5, 0.5], w)
		"eye_off":
			draw_arc(_p(0.5, 0.95), size.x * 0.55, deg_to_rad(222), deg_to_rad(318), 16, color, w)
			draw_arc(_p(0.5, 0.05), size.x * 0.55, deg_to_rad(42), deg_to_rad(138), 16, color, w)
			draw_circle(_p(0.5, 0.5), size.x * 0.11, color)
			_line(0.14, 0.14, 0.86, 0.86, w)
		"warning":
			_outline([0.5, 0.08, 0.94, 0.88, 0.06, 0.88], w)
			_line(0.5, 0.36, 0.5, 0.6, w)
			draw_circle(_p(0.5, 0.74), w * 0.6, color)
		"flame":
			_fill([0.5, 0.04, 0.76, 0.4, 0.82, 0.68, 0.5, 0.96, 0.18, 0.68, 0.26, 0.42, 0.4, 0.56])
		"drop":
			draw_circle(_p(0.5, 0.62), size.x * 0.28, color)
			_fill([0.5, 0.06, 0.76, 0.56, 0.24, 0.56])
		"arrow":
			_line(0.14, 0.86, 0.8, 0.2, w)
			_fill([0.9, 0.1, 0.56, 0.18, 0.82, 0.44])
			_line(0.14, 0.86, 0.14, 0.66, w)
			_line(0.14, 0.86, 0.34, 0.86, w)
		"steps":
			_oval(0.32, 0.5, 0.12, 0.2)
			_oval(0.32, 0.82, 0.08, 0.09)
			_oval(0.68, 0.24, 0.12, 0.2)
			_oval(0.68, 0.56, 0.08, 0.09)
		"skull":
			draw_circle(_p(0.5, 0.42), size.x * 0.36, color)
			_fill([0.3, 0.6, 0.7, 0.6, 0.66, 0.9, 0.34, 0.9])
			draw_circle(_p(0.36, 0.46), size.x * 0.1, HOLE)
			draw_circle(_p(0.64, 0.46), size.x * 0.1, HOLE)
			draw_colored_polygon(_points([0.5, 0.6, 0.44, 0.7, 0.56, 0.7]), HOLE)
		"people":
			draw_circle(_p(0.68, 0.3), size.x * 0.14, color.darkened(0.25))
			_half_oval(0.68, 0.84, 0.24, 0.36, color.darkened(0.25))
			draw_circle(_p(0.38, 0.36), size.x * 0.17, color)
			_half_oval(0.38, 0.98, 0.3, 0.42, color)
		"compass":
			var center := _p(0.5, 0.5)
			var radius := size.x * 0.44
			draw_arc(center, radius, 0.0, TAU, 24, Color(color, 0.6), maxf(1.5, w * 0.7), true)
			var dir := Vector2.from_angle(angle)
			var side := dir.orthogonal() * radius * 0.26
			draw_colored_polygon(PackedVector2Array([center + dir * radius * 0.82, center + side, center - side]), color)
			draw_colored_polygon(PackedVector2Array([center - dir * radius * 0.6, center + side, center - side]), Color(color, 0.35))
		"turn_left", "turn_right":
			_turn_arrow(kind == "turn_left", w)
		"zoom_in", "zoom_out":
			draw_arc(_p(0.42, 0.42), size.x * 0.3, 0.0, TAU, 24, color, w, true)
			_line(0.64, 0.64, 0.9, 0.9, w * 1.6)
			_line(0.29, 0.42, 0.55, 0.42, w)
			if kind == "zoom_in":
				_line(0.42, 0.29, 0.42, 0.55, w)


## Seta curva de girar a câmera; `left` espelha para o sentido anti-horário.
func _turn_arrow(left: bool, width: float) -> void:
	var center := _p(0.5, 0.54)
	var radius := size.x * 0.32
	var from := deg_to_rad(30.0)
	var to := deg_to_rad(290.0)
	var arc := PackedVector2Array()
	for i in 17:
		arc.append(center + Vector2.from_angle(lerpf(from, to, i / 16.0)) * radius)
	var radial := Vector2.from_angle(to)
	var ahead := radial.orthogonal() # sentido em que o arco cresce
	var tip := arc[-1] + ahead * size.x * 0.2
	var head := PackedVector2Array([tip, arc[-1] + radial * size.x * 0.15, arc[-1] - radial * size.x * 0.15])
	if left:
		for i in arc.size():
			arc[i].x = size.x - arc[i].x
		for i in head.size():
			head[i].x = size.x - head[i].x
	draw_polyline(arc, color, width, true)
	draw_colored_polygon(head, color)


func _oval(x: float, y: float, rx: float, ry: float) -> void:
	var points := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		points.append(_p(x + cos(a) * rx, y + sin(a) * ry))
	draw_colored_polygon(points, color)


## Metade de cima de uma elipse: ombros das pessoas.
func _half_oval(x: float, y: float, rx: float, ry: float, tint: Color) -> void:
	var points := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		points.append(_p(x + cos(a) * rx, y + sin(a) * ry))
	draw_colored_polygon(points, tint)


func _p(x: float, y: float) -> Vector2:
	return Vector2(x, y) * size.x


func _line(x1: float, y1: float, x2: float, y2: float, width: float) -> void:
	draw_line(_p(x1, y1), _p(x2, y2), color, width, true)


func _points(coords: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, coords.size(), 2):
		out.append(_p(coords[i], coords[i + 1]))
	return out


func _fill(coords: Array) -> void:
	draw_colored_polygon(_points(coords), color)


func _outline(coords: Array, width: float) -> void:
	var points := _points(coords)
	points.append(points[0])
	draw_polyline(points, color, width, true)
