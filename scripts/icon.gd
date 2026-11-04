extends Control
## Ícones simples desenhados em código: o kit não traz ícones de interface.
## Coordenadas num quadrado de 0 a 1, escaladas pelo tamanho do controle.

var kind := ""
var color := Color.BLACK


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
