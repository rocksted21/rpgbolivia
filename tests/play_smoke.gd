extends SceneTree
## Joga uma luta inteira pela janela de verdade, com mouse, toque e teclas simulados,
## e salva screenshots. Rodar (sem --headless):
## godot --path combate --script tests/play_smoke.gd -- <pasta-dos-screenshots>

const Hex = preload("res://scripts/hex.gd")
const AI = preload("res://scripts/ai.gd")
const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

const MAX_TURNS := 200
const TIMEOUT_SECONDS := 170.0
const FAR_CELL := Vector2i(3, 4)
const OFF_BOARD := Vector2(845, 700)
const SCREEN := Rect2(0, 0, 1280, 720)

var view
var shots_dir := ""
var failed := false


func _initialize() -> void:
	shots_dir = OS.get_cmdline_user_args()[0]
	# A luta de teste não pode dar pontos no save de verdade.
	HeroProgress.path = "user://test_progress_smoke.cfg"
	DirAccess.remove_absolute(HeroProgress.path)
	create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(func():
		print("TIMEOUT: a luta não terminou")
		quit(2))
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()


func _run() -> void:
	await _frames(2) # a cena só entra na árvore depois de _initialize
	await _wait_ready()
	await _frames(5)
	_shot("1_inicio")
	await _test_markers()
	await _test_inspect_with_mouse()
	await _test_inspect_with_touch()
	await _test_self_menu()
	await _test_far_click()
	await _test_order_stays_on()

	var turns := 0
	var shot_menu := false
	var tested_adjacent := false
	var tested_hotkey := false
	while view.state.winner() < 0 and turns < MAX_TURNS:
		await _wait_ready()
		if view.state.winner() >= 0:
			break
		var unit = view.state.active_unit()
		if not tested_adjacent:
			tested_adjacent = await _test_click_does_not_attack(unit)
		var action: Dictionary = AI.decide(view.state, unit)
		turns += 1
		match action["kind"]:
			"step":
				var aimable: bool = view._cell_options(action["cell"]).any(func(option): return option["kind"] == "ability")
				_click(action["cell"])
				await _frames(2)
				if aimable: # dá para mirar ali: o menu pergunta se é para andar ou para mirar
					var step_index := _option_index("step")
					_expect(step_index >= 0 and not view.busy, "casa onde dá para mirar pergunta antes de andar")
					await _press(view.hud.menu_buttons[step_index])
				_expect(view.busy or unit.pos == action["cell"], "tocar na casa anda (direto ou pelo menu)")
			"ability":
				_click(action["cell"])
				await _frames(2)
				var index := _option_index("ability", action["id"])
				_expect(index >= 0, "o menu da casa oferece %s" % Data.ABILITIES[action["id"]]["name"])
				_expect(SCREEN.encloses(view.hud.menu.get_global_rect()), "o menu cabe na tela")
				if not shot_menu and Data.ABILITIES[action["id"]]["kind"] == "attack":
					shot_menu = true
					_expect(view.menu_options[index]["detail"].begins_with("−"), "o menu mostra o dano")
					_shot("6_menu_no_alvo")
				if not tested_hotkey and index >= 0:
					tested_hotkey = true
					_key(KEY_1 + index) # atalho do PC: o número da opção
				elif index >= 0:
					await _press(view.hud.menu_buttons[index])
			_:
				_key(KEY_SPACE)
		await _frames(2)
		Engine.time_scale = 3.0

	# As regras terminam antes da animação: espera o painel de fim aparecer.
	while not view.hud.end_panel.visible:
		await process_frame
	Engine.time_scale = 1.0
	await _frames(30)
	_shot("7_fim")
	_expect(tested_adjacent, "chegou a testar clique em inimigo colado")
	_expect(tested_hotkey, "chegou a testar o atalho numérico")
	var winner: int = view.state.winner()
	print("turnos do jogador: %d, vencedor: %s" % [turns, "jogador" if winner == Data.Team.PLAYER else "inimigo"])

	view.hud.restart_pressed.emit()
	await _frames(3)
	_expect(view.state.units.all(func(u): return u.hp == u.max_hp), "todos voltam com vida cheia")
	await _wait_ready()
	_expect(view.state.winner() < 0, "lutar de novo reinicia a batalha")
	await _test_too_close()
	await _test_far_heal()
	await _test_terrain_warning()
	await _test_ground_aim()
	quit(1 if failed else 0)


func _unit(type_id: String):
	return view.state.units.filter(func(u): return u.type_id == type_id)[0]


func _place(unit, cell: Vector2i) -> void:
	unit.pos = cell
	view.views[unit].position = view.feet_of(cell)
	view.battle_camera.set_elevation(view._cell_elevation(cell), view.views[unit])
	view.views[unit].z_index = cell.y * 10 + 5


func _make_active(unit) -> void:
	unit.moved = 0
	unit.clock = view.state.units.map(func(u): return u.clock).min() - 1
	view._advance()
	await _wait_ready()


func _test_too_close() -> void:
	var archer = _unit("besteiro")
	var imp = _unit("diabrete")
	_place(imp, _free_neighbor(archer))
	await _make_active(archer)
	_expect(not view.overlays[imp.pos].visible and not view.reach_lines[imp.pos].visible, "a casa colada no Besteiro fica sem laranja")
	_click(imp.pos)
	await _frames(2)
	var index := _option_index("blocked", "tiro")
	_expect(index >= 0 and view.hud.menu_buttons[index].disabled, "Tiro aparece apagado com inimigo colado (besteiro %s, diabrete %s, ativo %s, menu %s, opções %s)" % [archer.pos, imp.pos, view.state.active_unit().type_id, view.menu_cell, view.menu_options.map(func(o): return "%s:%s" % [o["kind"], o.get("id", "")])])
	_shot("8_perto_demais")
	_key(KEY_1 + index)
	await _frames(2)
	_expect(not view.busy and imp.hp == imp.max_hp, "o Tiro apagado não atira")
	_key(KEY_ESCAPE)
	await _frames(2)


# Floresta ao lado: o mouse mostra o aviso; o toque anda direto.
func _test_terrain_warning() -> void:
	var hero = _unit("guardiao")
	var forest: Vector2i = view.NO_CELL
	for row in view.state.rows():
		for col in view.state.cols():
			var cell := Vector2i(col, row)
			if view.state.tile_at(cell)["name"] == "Floresta" and view.state.unit_at(cell) == null:
				for side in Hex.neighbors(cell):
					if forest == view.NO_CELL and view.state.in_bounds(side) and view.state.unit_at(side) == null and view.state.tile_at(side)["walkable"] and view.state.elevation_at(side) == view.state.elevation_at(cell):
						_place(hero, side)
						forest = cell
	await _make_active(hero)
	var start: Vector2i = hero.pos
	_hover_at(view.cell_to_screen(forest))
	await _frames(2)
	_expect("menos dano" in view.hud.hint.text, "passar o mouse na floresta avisa da proteção")
	_shot("13_aviso_floresta")
	_click(forest)
	await _frames(2)
	await _wait_ready()
	_expect(hero.pos == forest and hero.pos != start, "tocar na floresta anda direto")


# Aliado ferido longe da Druida: a Cura aparece apagada, com o motivo.
func _test_far_heal() -> void:
	var mage = _unit("druida")
	var duelist = _unit("duelista")
	await _make_active(mage)
	var far: Vector2i = view.NO_CELL
	for cell in view.overlays:
		if Hex.distance(cell, mage.pos) == 4 and view.state.unit_at(cell) == null and view.state.tile_at(cell)["walkable"]:
			far = cell
			break
	_place(duelist, far)
	duelist.hp = duelist.max_hp - 6
	_click(duelist.pos)
	await _frames(2)
	var index := _option_index("blocked", "cura")
	_expect(index >= 0 and view.hud.menu_buttons[index].disabled, "Cura longe aparece apagada")
	_shot("12_cura_longe")
	_key(KEY_ESCAPE)
	await _frames(2)
	duelist.hp = duelist.max_hp


# Mirar a magia numa casa vazia, prevendo para onde o inimigo vai andar.
func _test_ground_aim() -> void:
	var mage = _unit("mago")
	await _make_active(mage)
	var target: Vector2i = view.NO_CELL
	for cell in view.state.cells_in_range(mage, "flor_fogo"):
		if view.state.unit_at(cell) == null and view.state.tile_at(cell)["walkable"]:
			target = cell
			break
	_click(target)
	await _frames(2)
	var index := _option_index("ability", "flor_fogo")
	_expect(index >= 0 and mage.pos != target, "tocar numa casa vazia ao alcance oferece a magia")
	_shot("9_mirar_no_chao")
	await _press(view.hud.menu_buttons[index])
	_expect(not mage.pending.is_empty() and mage.pending["tile"] == target, "a magia fica mirada na casa vazia")
	await _wait_ready()
	_expect(view.overlays[target].visible and view.overlays[target].color == view.CHARGE_COLOR, "a área da magia do herói fica marcada")
	_expect(view.views[mage].status.text.begins_with("magia em"), "o mago mostra a contagem até a magia sair")
	_shot("9b_carregando")

	var witch = _unit("feiticeira")
	var aim: Vector2i = view.state.cells_in_range(witch, "chama")[0]
	view.state.do_ability(witch, "chama", aim)
	view._refresh_overlays()
	var shown: Array = view.state.area_of(aim, 1).filter(func(c): return view.overlays[c].visible and view.overlays[c].color == view.CHARGE_COLOR)
	_expect(shown.is_empty(), "a área da magia inimiga fica escondida")
	await _test_hold_card(witch)


# Segurar o dedo no inimigo mostra o que ele prepara, sem dizer onde cai.
func _test_hold_card(witch) -> void:
	var pos: Vector2 = view.cell_to_screen(witch.pos)
	_button(MOUSE_BUTTON_LEFT, true, pos)
	await create_timer(view.HOLD_TIME + 0.2).timeout
	_expect(view.hud.card_open() and view.hud.card_spell != null, "segurar na Feiticeira mostra a magia dela")
	_expect(not view.hud.menu_open(), "segurar não abre o menu de ações")
	await _frames(20) # deixa o filminho andar um pouco antes da foto
	_shot("10_cartao_magia")
	_button(MOUSE_BUTTON_LEFT, false, pos)
	await _frames(2)
	_expect(view.hud.card_open() and not view.hud.menu_open(), "soltar o dedo não fecha nem vira toque")
	_click_at(OFF_BOARD)
	await _frames(2)
	_expect(not view.hud.card_open(), "tocar fecha o cartão")
	_button(MOUSE_BUTTON_RIGHT, true, pos)
	await _frames(2)
	_expect(view.hud.card_open(), "botão direito no personagem abre o cartão")
	_click_at(OFF_BOARD)
	await _frames(2)
	var skeleton = _unit("esqueleto")
	_button(MOUSE_BUTTON_RIGHT, true, view.cell_to_screen(skeleton.pos))
	await _frames(10)
	var golpe: Dictionary = view._card_ability(skeleton, "golpe")
	_expect(view.hud.card_open() and golpe.has("hero_amount"), "a ficha do Esqueleto mostra o dano no herói da vez")
	_shot("11_ficha_ataque")
	_click_at(OFF_BOARD)
	await _frames(2)


func _button(index: MouseButton, pressed: bool, pos: Vector2) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = index
	button.pressed = pressed
	button.position = pos
	button.global_position = pos
	root.push_input(button)


func _option_index(kind: String, id := "") -> int:
	for i in view.menu_options.size():
		var option: Dictionary = view.menu_options[i]
		if option["kind"] == kind and option.get("id", "") == id:
			return i
	return -1


func _test_markers() -> void:
	var order: Array = view.state.turn_order()
	_expect(_badges_shown().is_empty(), "números começam escondidos")
	_expect(view.views[order[0]].arrow.visible, "quem joga tem seta")
	var enemies: Array = order.filter(func(u): return u.team == Data.Team.ENEMY)
	_expect(view.views[enemies[0]].arrow.visible, "o próximo inimigo tem seta")
	_expect(not view.views[enemies[1]].arrow.visible, "os outros inimigos não têm seta")
	await _press(view.hud.order_button)
	var numbers_ok := true
	for i in order.size():
		numbers_ok = numbers_ok and view.views[order[i]].badge.text == str(i + 1)
	_expect(numbers_ok and _badges_shown().size() == order.size(), "o botão mostra o número de todos")
	_shot("1b_ordem_ligada")
	await _press(view.hud.order_button)
	_expect(_badges_shown().is_empty(), "o botão esconde os números de novo")


func _badges_shown() -> Array:
	return view.views.keys().filter(func(u): return view.views[u].badge.visible)


func _test_order_stays_on() -> void:
	await _press(view.hud.order_button)
	_key(KEY_SPACE)
	await _frames(2)
	await _wait_ready()
	_expect(_badges_shown().size() == view.state.turn_order().size(), "a ordem ligada continua depois do turno")
	await _press(view.hud.order_button)
	_expect(_badges_shown().is_empty(), "desligar a ordem esconde os números")


func _enemy():
	return view.state.units.filter(func(u): return u.alive() and u.team == Data.Team.ENEMY)[3] # Feiticeira


func _test_inspect_with_mouse() -> void:
	var enemy = _enemy()
	_hover(enemy.pos)
	await _frames(3)
	_expect(view._shown_unit() == enemy, "passar o mouse mostra o alcance")
	_expect(view.reach_lines[view.state.attack_reach(enemy)[0]].visible, "casas do alcance ficam marcadas")
	_expect(_badges_shown() == [enemy], "passar o mouse mostra só o número dele")
	_expect(not view.hud.menu_open(), "passar o mouse não abre menu")
	_shot("2_mouse_em_inimigo")
	_click(enemy.pos)
	await _frames(2)
	_expect(view.menu_cell == enemy.pos and not view.busy, "clicar no inimigo fixa a inspeção dele")
	_expect(view.menu_options.size() == view.state.active_unit().abilities.filter(func(id): return Data.ABILITIES[id]["kind"] != "revive").size() and view.menu_options.all(func(o): return o["kind"] == "blocked"), "inimigo longe mostra as habilidades apagadas")
	_hover_at(OFF_BOARD)
	await _frames(2)
	_expect(view._shown_unit() == enemy, "o menu aberto continua sem o mouse")
	_click_at(OFF_BOARD)
	await _frames(2)
	_expect(view.menu_cell == view.NO_CELL, "clicar fora fecha a inspeção")


func _test_inspect_with_touch() -> void:
	var enemy = _enemy()
	var active = view.state.active_unit()
	var pos: Vector2i = active.pos
	await _tap(view.cell_to_screen(enemy.pos))
	_expect(view.menu_cell == enemy.pos, "tocar no inimigo mostra o alcance dele")
	_expect(view.hover == view.NO_CELL, "toque não deixa hover preso")
	_expect(_badges_shown() == [enemy], "tocar mostra só o número dele")
	_shot("3_toque_em_inimigo")
	await _tap(view.cell_to_screen(enemy.pos))
	_expect(view.menu_cell == view.NO_CELL and _badges_shown().is_empty(), "tocar de novo fecha e esconde o número")
	await _tap(view.cell_to_screen(enemy.pos))
	var neighbor := _free_neighbor(active)
	await _tap(view.cell_to_screen(neighbor))
	_expect(view.menu_cell == view.NO_CELL and active.pos == pos and not view.busy, "tocar numa casa com inspeção aberta só fecha, não anda (ativo %s em %s->%s, vizinho %s, menu %s, cartão %s, busy %s)" % [active.type_id, pos, active.pos, neighbor, view.menu_cell, view.hud.card_open(), view.busy])
	var other = _unit("besteiro") # longe do menu da Feiticeira, que pode cobrir os vizinhos dela
	await _tap(view.cell_to_screen(enemy.pos))
	await _tap(view.cell_to_screen(other.pos))
	_expect(view.menu_cell == other.pos, "tocar em outro personagem troca o menu")
	_key(KEY_ESCAPE)
	await _frames(2)
	_expect(view.menu_cell == view.NO_CELL, "Esc fecha a inspeção")


# Só usa vizinhos que estejam fora do menu e possam receber o toque.
func _free_neighbor(unit) -> Vector2i:
	for cell in Hex.neighbors(unit.pos):
		var covered: bool = view.hud.menu_open() and view.hud.menu.get_global_rect().has_point(view.cell_to_screen(cell))
		if view.state.can_step(unit, cell) and not covered and view._pick_cell(view.cell_to_screen(cell)) == cell:
			return cell
	return unit.pos


func _test_self_menu() -> void:
	var active = view.state.active_unit()
	_click(active.pos)
	await _frames(2)
	_expect(_option_index("wait") >= 0, "tocar no próprio herói oferece Esperar")
	_expect(view.hud.menu_buttons.size() == view.menu_options.size(), "um botão por opção")
	_shot("4_menu_do_heroi")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = OFF_BOARD
	root.push_input(right)
	await _frames(2)
	_expect(not view.hud.menu_open(), "botão direito fecha o menu")


func _test_far_click() -> void:
	var walker = view.state.active_unit()
	var start: Vector2i = walker.pos
	var far: Vector2i = FAR_CELL
	for cell in view.overlays:
		if view.state.unit_at(cell) == null and not view.state.move_cells(walker).has(cell) and view._cell_options(cell).is_empty():
			far = cell
	_click(far)
	await _frames(2)
	_expect(not view.hud.menu_open() and walker.pos == start, "tocar longe não anda nem abre menu")
	_shot("5_tocar_longe")


func _test_click_does_not_attack(unit) -> bool:
	if unit.team != Data.Team.PLAYER:
		return false
	for enemy in view.state.enemies_of(unit):
		if Hex.distance(unit.pos, enemy.pos) == 1:
			var hp: int = enemy.hp
			_click(enemy.pos)
			await _frames(2)
			_expect(enemy.hp == hp and not view.busy and view.menu_cell == enemy.pos, "clicar em inimigo colado só abre o menu")
			_click(enemy.pos)
			await _frames(2)
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	print("%s: %s" % ["ok" if condition else "FALHOU", label])
	if not condition:
		failed = true


func _wait_ready() -> void:
	while view.busy and view.state.winner() < 0:
		await process_frame
	await process_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _hover(cell: Vector2i) -> void:
	_hover_at(view.cell_to_screen(cell))


func _hover_at(pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion)


func _click(cell: Vector2i) -> void:
	_click_at(view.cell_to_screen(cell))


func _click_at(pos: Vector2) -> void:
	_hover_at(pos)
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = pos
		button.global_position = pos
		root.push_input(button)


func _press(button: Button) -> void:
	# Uma magia pode estar abaixo da parte visível da lista rolável.
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
			await _frames(2)
			break
		ancestor = ancestor.get_parent()
	_click_at(button.get_global_rect().get_center())
	await _frames(3)
	_hover_at(OFF_BOARD)
	await _frames(2)


# Passa pelo caminho real do toque: Input converte em mouse emulado.
func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = 0
		touch.pressed = pressed
		touch.position = pos
		Input.parse_input_event(touch)
		Input.flush_buffered_events()
		await process_frame
	await _frames(2)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = pressed
		root.push_input(key)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])
