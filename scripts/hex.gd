extends RefCounted
## Grade hexagonal "pointy-top" em coordenadas offset odd-r (Vector2i(coluna, linha)).

# Sentido horário a partir do leste: a direção oposta de i é sempre (i + 3) % 6.
const DIRS_EVEN := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
const DIRS_ODD := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]


static func neighbor(cell: Vector2i, dir: int) -> Vector2i:
	var dirs: Array = DIRS_ODD if cell.y & 1 else DIRS_EVEN
	return cell + dirs[dir]


static func neighbors(cell: Vector2i) -> Array:
	var out := []
	for dir in 6:
		out.append(neighbor(cell, dir))
	return out


static func direction_to(from: Vector2i, to: Vector2i) -> int:
	for dir in 6:
		if neighbor(from, dir) == to:
			return dir
	return -1


static func distance(a: Vector2i, b: Vector2i) -> int:
	var aq := a.x - (a.y - (a.y & 1)) / 2
	var bq := b.x - (b.y - (b.y & 1)) / 2
	var dq := aq - bq
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2
