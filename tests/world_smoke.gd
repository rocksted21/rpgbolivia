extends SceneTree
## Joga a exploração pela tela de verdade e salva screenshots. Rodar sem --headless:
## godot --path . --script tests/world_smoke.gd -- <pasta-dos-screenshots> [herói]

const Hex = preload("res://scripts/hex.gd")
const AI = preload("res://scripts/ai.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

const TIMEOUT_SECONDS := 150.0
const MAX_ACTIONS := 120
const SCREEN := Rect2(0, 0, 1280, 720)

var view
var dir := ""
var failed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0]
	# Uma partida de teste não pode dar pontos no save de verdade.
	HeroProgress.path = "user://test_progress_world.cfg"
	DirAccess.remove_absolute(HeroProgress.path)
	root.set_meta("world_hero", args[1] if args.size() > 1 else "duelista")
	create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(func():
		print("TIMEOUT busy=%s vida=%d inimigos=%d" % [view.busy, view.state.hero.hp, view.state.enemies_of(view.state.hero).size()])
		quit(2))
	Engine.time_scale = float(OS.get_environment("WORLD_SPEED")) if OS.has_environment("WORLD_SPEED") else 1.0
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()


func _expect(ok: bool, text: String) -> void:
	if not ok:
		failed = true
		print("FALHOU: ", text)


func _idle() -> void:
	await process_frame
	var guard := 0
	while view.busy and view.state.winner() < 0 and guard < 3000:
		await process_frame
		guard += 1


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])


func _click(cell: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": # sem janela não há eventos de mouse
		view._click(cell)
		return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = view.cell_to_screen(cell)
		root.push_input(event)
		await process_frame


func _run() -> void:
	await _idle()
	await _shot("1_inicio")
	var state = view.state
	_expect(state.units.size() == 1, "começa só com o herói")
	var fps_begin := Time.get_ticks_usec()
	for i in 30:
		await process_frame
	print("quadro médio em repouso: %.1f ms" % ((Time.get_ticks_usec() - fps_begin) / 30000.0))
	_expect(not view.hud.timeline.visible, "sem fila quando está sozinho")
	var hero_screen: Vector2 = view.cell_to_screen(state.hero.pos)
	_expect(SCREEN.has_point(hero_screen), "herói na tela")
	# A seleção precisa funcionar com o mapa em qualquer lugar.
	for cell in Hex.neighbors(state.hero.pos):
		if view.overlays.has(cell) and state.can_step(state.hero, cell):
			_expect(view._pick_cell(view.cell_to_screen(cell)) == cell, "clique acha a casa %s" % cell)
	_expect(view._free_roam(), "começa explorando")
	_expect(not view.active_outline.visible, "sem marca de turno fora de combate")
	var start: Vector2i = state.hero.pos
	var saw_enemy := false
	var saw_combat := false
	var saw_long_walk := false
	var saw_return := false
	var actions := 0
	var moved := 0
	var slowest := 0.0
	# Parar a caminhada com um toque.
	var away = _roam_goal(state, 6)
	if away != null:
		var at: Vector2i = state.hero.pos
		view._click(away)
		_expect(view.busy and view.traveling, "clicar longe inicia a caminhada")
		await process_frame
		view.stop_travel = true
		await _idle()
		_expect(not view.traveling and not view.busy, "a caminhada para quando pedido")
		_expect(Hex.distance(at, state.hero.pos) < 6, "parou antes de chegar")
	while state.winner() < 0 and actions < MAX_ACTIONS:
		actions += 1
		var hero = state.hero
		saw_enemy = saw_enemy or not state.enemies_of(hero).is_empty()
		var fighting: bool = state.in_combat()
		saw_combat = saw_combat or fighting
		if fighting:
			_expect(not view._free_roam(), "combate tira da exploração")
			if state.turn_order().size() > 1:
				_expect(view.hud.timeline.visible, "fila aparece em combate")
		var before: Vector2i = hero.pos
		if not fighting:
			_expect(not view.hud.timeline.visible, "sem fila na exploração")
			var goal = _roam_goal(state, 5)
			if goal == null:
				break
			var began := Time.get_ticks_usec()
			await _click(goal)
			slowest = maxf(slowest, (Time.get_ticks_usec() - began) / 1000.0)
			await _idle()
			saw_long_walk = saw_long_walk or Hex.distance(before, hero.pos) >= 2
			if state.in_combat() and not FileAccess.file_exists("%s/3_combate.png" % dir):
				await _shot("3_combate")
		else:
			var action: Dictionary = AI.decide(state, hero)
			if action["kind"] == "ability":
				view._perform(state.do_ability(hero, action["id"], action["cell"]))
			elif action["kind"] == "step":
				await _click(action["cell"])
				if view.menu_cell != view.NO_CELL:
					# Terreno que muda o jogo pergunta antes: confirma pelo menu.
					view._on_option_pressed(view.menu_options.map(func(o): return o["kind"]).find("step"))
			else:
				view._perform(state.do_wait(hero))
			await _idle()
			saw_return = saw_return or (not state.in_combat() and state.winner() < 0)
		if hero.pos != before:
			moved += 1
			var center: Vector2 = view.cell_to_screen(hero.pos)
			_expect(center.distance_to(hero_screen) < 200.0, "câmera acompanha o herói (%s)" % center)
		_expect(view.cell_nodes.size() < 900, "mapa carregado limitado (%d casas)" % view.cell_nodes.size())
		for unit in state.units:
			if unit.alive():
				_expect(view.views.has(unit), "toda unidade viva tem desenho")
		if not state.in_combat() and not state.enemies_of(hero).is_empty() and not FileAccess.file_exists("%s/2_visao_do_inimigo.png" % dir):
			var foe = state.enemies_of(hero)[0]
			view.hover = foe.pos
			view._refresh_overlays()
			await _shot("2_visao_do_inimigo")
			view.hover = view.NO_CELL
			view._refresh_overlays()
	await _shot("4_mais_longe")
	_expect(moved > 5, "herói andou pelo mapa (%d passos)" % moved)
	_expect(saw_enemy, "inimigos apareceram")
	_expect(saw_long_walk, "um clique anda várias casas")
	_expect(saw_combat, "houve combate")
	print("voltou à exploração depois de lutar: ", saw_return)
	_expect(Hex.distance(start, state.hero.pos) > 0 or state.winner() >= 0, "saiu do início")
	print("passos %d, ações %d, distância %d, abates %d, casas carregadas %d, nós %d, passo mais lento %.1f ms" % [moved, actions, state.farthest, state.kills, view.cell_nodes.size(), view.board.get_child_count(), slowest])
	if state.hero.alive(): # se a jornada já acabou, chamar de novo apagaria o aviso de pontos
		state.hero.hp = 0
		view._advance()
	# A animação da queda termina antes de a tela de fim aparecer.
	var waited := 0
	while not view.hud.end_panel.visible and waited < 2000:
		await process_frame
		waited += 1
	await _shot("5_fim")
	_expect(view.hud.end_panel.visible, "tela de fim aparece")
	_expect(view.hud.end_note.visible and view.hud.end_note.text.contains("skill"), "fim da jornada avisa os pontos ganhos")
	_expect(view.hud.journey.text.contains("Vida 0/"), "topo da tela mostra a queda")
	var old_state = view.state
	view.hud.restart_pressed.emit()
	await _idle()
	_expect(view.state != old_state and view.state.hero.alive(), "nova jornada recomeça")
	_expect(view.state.units.size() == 1 and view.views.size() == 1, "nova jornada sem restos da anterior")
	_expect(view.exploring and not view.hud.end_panel.visible, "nova jornada volta ao jogo")
	print("Exploração: ", "FALHOU" if failed else "OK")
	quit(1 if failed else 0)


## Casa livre a até `reach` casas na direção de sair do início.
func _roam_goal(state, reach: int):
	var path: Array = _route(state)
	return path[mini(reach, path.size()) - 1] if not path.is_empty() else null


func _route(state) -> Array:
	var found: Dictionary = state.search(state.hero)
	var goal = null
	var best := -1
	for cell in found["cost"]:
		var far: int = Hex.distance(cell, state.start_cell)
		if far > best:
			best = far
			goal = cell
	return state.path_from_search(found, goal)


func _next_step(state):
	var found: Dictionary = state.search(state.hero)
	var goal = null
	var best := -1
	for cell in found["cost"]:
		var far: int = Hex.distance(cell, state.start_cell)
		if far > best:
			best = far
			goal = cell
	var path: Array = state.path_from_search(found, goal)
	return path[0] if not path.is_empty() else null
