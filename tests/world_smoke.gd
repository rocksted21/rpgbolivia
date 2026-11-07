extends SceneTree
## Joga a exploração pela tela de verdade e salva screenshots. Rodar sem --headless:
## godot --path . --script tests/world_smoke.gd -- <pasta-dos-screenshots> [herói]

const Hex = preload("res://scripts/hex.gd")
const AI = preload("res://scripts/ai.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const Data = preload("res://scripts/game_data.gd")

const TIMEOUT_SECONDS := 150.0
const MAX_ACTIONS := 60
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
	root.set_meta("world_hero", [args[1]] if args.size() > 1 else Data.DEFAULT_PARTY)
	create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(func():
		print("TIMEOUT busy=%s heróis=%d inimigos=%d" % [view.busy, view.state.alive_party().size(), view.state.foes().size()])
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
	while (view.busy or not view.walk_paths.is_empty() or not view.moving.is_empty()) and view.state.winner() < 0 and guard < 6000:
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
	_expect(state.units.size() == state.party.size(), "começa só com a party")
	var fps_begin := Time.get_ticks_usec()
	for i in 30:
		await process_frame
	print("quadro médio em repouso: %.1f ms" % ((Time.get_ticks_usec() - fps_begin) / 30000.0))
	_expect(not view.hud.timeline.visible, "sem fila fora de combate")
	_expect(view._free_roam(), "começa explorando")
	_expect(not view.active_outline.visible, "sem marca de turno fora de combate")
	await _test_rotation(state)
	await _test_walking(state)
	var start: Vector2i = state.start_cell
	var saw_enemy := false
	var saw_combat := false
	var saw_return := false
	var actions := 0
	var slowest := 0.0
	while state.winner() < 0 and actions < MAX_ACTIONS:
		actions += 1
		saw_enemy = saw_enemy or not state.foes().is_empty()
		var fighting: bool = state.in_combat()
		saw_combat = saw_combat or fighting
		if fighting:
			_expect(not view._free_roam(), "combate tira da exploração")
			_expect(view.hud.timeline.visible, "fila aparece em combate")
			var hero = state.active_unit()
			_expect(state.is_hero(hero), "o jogo só espera ordem de herói")
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
		else:
			_expect(not view.hud.timeline.visible, "sem fila na exploração")
			var goal = _roam_goal(state, 5)
			if goal == null:
				break
			var began := Time.get_ticks_usec()
			await _click(goal)
			slowest = maxf(slowest, (Time.get_ticks_usec() - began) / 1000.0)
			await _idle()
			if state.in_combat() and not FileAccess.file_exists("%s/3_combate.png" % dir):
				await _shot("3_combate")
			if state.in_combat() and state.party.size() > 1 and not saw_combat:
				var close := 0
				for a in state.alive_party():
					for b in state.alive_party():
						if a != b and Hex.distance(a.pos, b.pos) == 1:
							close += 1
				print("heróis colados logo após abrir: ", close / 2)
		_expect(view.cell_nodes.size() < 900, "mapa carregado limitado (%d casas)" % view.cell_nodes.size())
		for unit in state.units:
			if unit.alive():
				_expect(view.views.has(unit), "toda unidade viva tem desenho")
	await _shot("4_mais_longe")
	_expect(saw_enemy, "inimigos apareceram")
	_expect(saw_combat, "houve combate")
	print("voltou à exploração depois de lutar: ", saw_return)
	print("ações %d, distância %d, abates %d, casas carregadas %d, nós %d, clique mais lento %.1f ms" % [actions, state.farthest, state.kills, view.cell_nodes.size(), view.board.get_child_count(), slowest])
	if state.winner() < 0: # se a jornada já acabou, chamar de novo apagaria o aviso de pontos
		for member in state.party:
			member.hp = 0
		await _idle()
		view._advance()
	# A animação da queda termina antes de a tela de fim aparecer.
	var waited := 0
	while not view.hud.end_panel.visible and waited < 2000:
		await process_frame
		waited += 1
	await _shot("5_fim")
	_expect(view.hud.end_panel.visible, "tela de fim aparece")
	_expect(view.hud.end_note.visible and view.hud.end_note.text.contains("skill"), "fim da jornada avisa os pontos ganhos")
	_expect(view.hud.overview_text.contains("Heróis 0/"), "topo da tela mostra a queda")
	var old_state = view.state
	view.hud.restart_pressed.emit()
	await _idle()
	_expect(view.state != old_state and view.state.alive_party().size() == view.state.party.size(), "nova jornada recomeça")
	_expect(view.state.units.size() == view.state.party.size() and view.views.size() == view.state.party.size(), "nova jornada sem restos da anterior")
	_expect(view.exploring and not view.hud.end_panel.visible, "nova jornada volta ao jogo")
	print("Exploração: ", "FALHOU" if failed else "OK")
	quit(1 if failed else 0)


## Giro em passos fixos (e qualquer ângulo por código): cliques certos e ninguém fora do lugar em qualquer ângulo.
func _test_rotation(state) -> void:
	var hero = view._actor()
	var positions: Array = state.party.map(func(u): return u.pos)
	var angles := [0.0, 0.4, 1.05, 2.1, PI, 4.2, 5.6]
	for angle in angles:
		view.view_target = angle # sem isso o giro em passos puxaria de volta
		view._set_view_angle(angle)
		view.map_refresh = 0.0
		view._sync_world(view.camera_cell)
		view._refresh_depths()
		await process_frame
		var center: Vector2 = view.cell_to_screen(hero.pos)
		_expect(SCREEN.has_point(center), "herói na tela no ângulo %.2f" % angle)
		_expect(view.overlays.has(hero.pos), "mapa carregado em volta do herói no ângulo %.2f" % angle)
		for cell in Hex.neighbors(hero.pos):
			if view.overlays.has(cell) and state.can_step(hero, cell):
				_expect(view._pick_cell(view.cell_to_screen(cell)) == cell, "clique acha a casa %s no ângulo %.2f" % [cell, angle])
			_expect(view.cell_to_screen(cell).distance_to(center) < 200.0, "vizinha perto na tela no ângulo %.2f" % angle)
		await _shot("2_giro_%d" % roundi(rad_to_deg(angle)))
	view._set_view_angle(0.0)
	view._sync_world(view.camera_cell)
	_expect(state.party.map(func(u): return u.pos) == positions, "girar não move ninguém")
	# Q/E gira um passo fixo: desliza sem salto e para exatamente no ângulo do passo.
	view.view_target = 0.0
	view.turn_hold = 1
	await process_frame
	await process_frame # process_frame sai antes do _process: espera um quadro inteiro
	view.turn_hold = 0
	var last: float = view.view_angle
	var largest := 0.0
	for i in 90:
		await process_frame
		var step := angle_difference(last, view.view_angle)
		largest = maxf(largest, absf(step))
		last = view.view_angle
	_expect(largest < 0.5, "o giro não dá saltos (%.3f)" % largest) # bem menos que um passo (1,57), mesmo com fps baixo
	_expect(is_equal_approx(view.view_angle, view.TURN_STEP), "para no ângulo do passo (%.3f)" % view.view_angle)
	var stopped: float = view.view_angle
	for i in 10:
		await process_frame
	_expect(view.view_angle == stopped, "fica parado no ângulo do passo")
	# Arrastar pouco não gira; arrastar o bastante gira um passo.
	view.drag_turn(view.TURN_STEP * 0.1)
	_expect(is_equal_approx(view.view_target, view.TURN_STEP), "arrasto curto não gira")
	view.drag_turn(view.TURN_STEP * 0.3)
	_expect(is_equal_approx(view.view_target, view.TURN_STEP * 2.0), "arrasto longo gira um passo")
	view.view_target = 0.0
	# Andar com a câmera girada.
	view.view_target = 1.0
	view._set_view_angle(1.0)
	view._sync_world(view.camera_cell)
	var goal = _roam_goal(state, 3)
	if goal != null:
		var at: Vector2i = hero.pos
		view._click(goal)
		await _idle()
		_expect(hero.pos != at or state.in_combat(), "herói anda com a câmera girada")
		await _shot("2_andou_girado")
	view.view_target = 0.0
	view._set_view_angle(0.0)
	view._sync_world(view.camera_cell)


func _test_walking(state) -> void:
	if state.party.size() < 2:
		return
	# Em fila: um clique move a party inteira, um herói atrás do outro.
	var goal = _roam_goal(state, 8)
	var before: Array = state.party.map(func(u): return u.pos)
	var leader = view._actor()
	view._click(goal)
	_expect(view.walk_goals.has(leader), "o selecionado puxa a fila")
	_expect(view.file_next.size() == state.party.size() - 1, "todos entram na fila (%d)" % view.file_next.size())
	# Andam ao mesmo tempo: mais de um herói dando passos no mesmo instante.
	var together_seen := false
	var trail_seen := false
	var far_off := 0.0
	var trail := {}
	for i in 200:
		await process_frame
		together_seen = together_seen or view.step_wait.values().filter(func(w): return w > 0.0).size() >= 2
		# O desenho nunca pode se separar da casa em que o herói está.
		for member in state.party:
			far_off = maxf(far_off, view.views[member].position.distance_to(view.feet_of(member.pos)))
		if view.walk_paths.is_empty() and view.moving.is_empty():
			break
		# Quem vem atrás pisa onde o da frente pisou.
		trail[leader.pos] = true
		var behind = view.file_next.get(leader)
		if behind != null and trail.has(behind.pos):
			trail_seen = true
	_expect(together_seen, "heróis andam ao mesmo tempo")
	_expect(far_off < 420.0, "o desenho acompanha a casa do herói (%.0f)" % far_off)
	await _idle()
	var moved := 0
	for i in state.party.size():
		if state.party[i].pos != before[i]:
			moved += 1
	_expect(moved >= 2 or state.in_combat(), "party andou junta (%d)" % moved)
	if not state.in_combat():
		_expect(trail_seen, "seguidor anda pelas casas do líder")
		var links := 0
		for ahead in view.file_next:
			if Hex.distance(ahead.pos, view.file_next[ahead].pos) <= 2: # folga do seguidor (FOLLOW_SLACK)
				links += 1
		_expect(links >= state.party.size() - 2, "ao parar, a fila continua colada (%d elos)" % links)
		await _shot("2_party_em_fila")
	if state.in_combat():
		return
	# Separados: só o selecionado anda.
	view.hud.set_together(false)
	view._on_party_pick(state.party[1])
	_expect(view.selected == state.party[1], "barra da party seleciona o herói")
	_expect(view.camera_unit == state.party[1], "câmera vai para o herói selecionado")
	var solo_from: Array = state.party.map(func(u): return u.pos)
	var solo_goal = _roam_goal(state, 3)
	if solo_goal != null and state.unit_at(solo_goal) == null:
		view._click(solo_goal)
		await _idle()
		_expect(state.party[0].pos == solo_from[0] or state.in_combat(), "separados, os outros ficam parados")
	if not state.in_combat():
		view._select_next()
		_expect(view.selected != state.party[1], "Tab troca de herói")
		# Outro herói anda enquanto o primeiro ainda caminha.
		var first = view.selected
		var far = _roam_goal(state, 6)
		if far != null:
			view._click(far)
			view._select_next()
			var second_goal = _roam_goal(state, 4)
			if second_goal != null and state.unit_at(second_goal) == null and not view.walk_paths.is_empty():
				view._click(second_goal)
				_expect(view.walk_paths.has(first), "dar ordem a outro herói não para o primeiro")
			view._stop_selected()
			await _idle()
	view.hud.set_together(true)
	view._select(state.alive_party()[0])


## Casa livre a até `reach` casas na direção de sair do início.
func _roam_goal(state, reach: int):
	var path: Array = _route(state)
	return path[mini(reach, path.size()) - 1] if not path.is_empty() else null


func _route(state) -> Array:
	var found: Dictionary = state.search(view._actor())
	var goal = null
	var best := -1
	for cell in found["cost"]:
		var far: int = Hex.distance(cell, state.start_cell)
		if far > best:
			best = far
			goal = cell
	return state.path_from_search(found, goal)
