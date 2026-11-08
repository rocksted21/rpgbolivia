extends RefCounted
## A "forma tática" do mapa fixo. No mapa sorteado (expedition_layout.gd) ela abre zonas, serras
## e platôs; nos Subúrbios tudo isso já vem da planta, então aqui só ficam as perguntas que o
## resto do jogo faz (zonas, serra, área andável), com as respostas da planta.

const Hex = preload("res://scripts/hex.gd")

var gen
var start: Vector2i
var zones := [] # sem zonas sorteadas: os bairros são da planta
var ridge := {} # nenhuma serra a proteger
var repairs := 0
var radius := 999 # sem raio: a borda é a da planta


func _init(p_gen, p_start: Vector2i) -> void:
	gen = p_gen
	start = p_start


func zone_at(cell: Vector2i) -> int:
	return 0 if gen.cells.has(cell) else -1


## Casas alcançáveis a pé a partir do início, com a mesma regra de degrau do movimento.
func walk_area() -> Dictionary:
	var seen := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		var height: int = gen.sample(current)["elevation"]
		for next in Hex.neighbors(current):
			if seen.has(next) or not gen.cells.has(next) or not gen.walkable(next):
				continue
			if absi(gen.sample(next)["elevation"] - height) > 1:
				continue
			seen[next] = true
			frontier.append(next)
	return seen


## A planta já foi conferida por tools/build_suburbios_map.py; aqui não se abre nada.
func check_map(_extra: Array) -> void:
	pass
