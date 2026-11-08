extends SceneTree
## Protótipo da luta do elevador: a grade cabe na praça, heróis começam na ponte,
## inimigos em cima do elevador, tudo é alcançável e uma luta de robôs termina.
## Rodar: godot --headless --path . --script tests/test_luta_elevador.gd

const Arena = preload("res://scripts/prototipo/arena_elevador.gd")
const AI = preload("res://scripts/ai.gd")
const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	var arena := Arena.new()
	var floor_cells: Array[Vector2i] = []
	for row in arena.rows:
		for col in arena.cols:
			var cell := Vector2i(col, row)
			if arena.walkable(cell):
				floor_cells.append(cell)
			check(arena.screen_to_cell(arena.cell_to_screen(cell)) == cell, "o clique no centro da casa %s volta para ela" % cell)
	check(floor_cells.size() >= 45, "a praça tem chão suficiente (%d casas)" % floor_cells.size())
	check(arena.lift_cells.size() >= 9, "o elevador tem casas suficientes (%d)" % arena.lift_cells.size())

	var state = arena.new_battle()
	for unit in state.units:
		check(arena.walkable(unit.pos), "%s começa no chão (%s)" % [unit.type_id, unit.pos])
		var on_lift := arena.lift_cells.has(unit.pos)
		if unit.team == Data.Team.ENEMY:
			check(on_lift, "%s sobe no elevador" % unit.type_id)
		else:
			check(not on_lift, "%s começa fora do elevador" % unit.type_id)
	var taken := {}
	for unit in state.units:
		check(not taken.has(unit.pos), "ninguém começa na mesma casa (%s)" % unit.pos)
		taken[unit.pos] = true

	# Todo chão se liga ao começo dos heróis (nenhuma ilha).
	var start: Vector2i = state.units[0].pos
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for next in Hex.neighbors(cell):
			if arena.walkable(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	check(seen.size() == floor_cells.size(), "todo o chão é alcançável (%d de %d)" % [seen.size(), floor_cells.size()])

	# Luta de robôs: os dois lados jogados pela IA terminam em algum momento.
	var actions := 0
	while state.winner() == -1 and actions < 3000:
		var unit = state.active_unit()
		if not unit.pending.is_empty():
			state.resolve_pending(unit)
		else:
			AI.apply(state, unit, AI.decide(state, unit))
		actions += 1
	check(state.winner() != -1, "a luta de robôs termina (%d ações)" % actions)
	print("luta de robôs: venceu %s em %d ações" % ["a party" if state.winner() == Data.Team.PLAYER else "o elevador", actions])

	var scene: Node2D = load("res://scenes/luta_elevador.tscn").instantiate()
	scene.skip_intro = true
	scene.auto_heroes = true
	root.add_child(scene)
	_watch(scene)


func _watch(scene: Node2D) -> void:
	await process_frame
	check(scene.views.size() == scene.state.units.size(), "toda unidade tem desenho")
	check(not scene.lift_clip.visible, "sem a chegada, o elevador já está em cima")
	for i in 120:
		await process_frame
	check(scene.phase == "luta" or scene.phase == "fim", "a tela segue jogando sem erro")
	print("luta_elevador: %d checagens, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)
