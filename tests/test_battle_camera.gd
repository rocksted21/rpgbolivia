extends SceneTree
## Valida a seleção e o enquadramento da câmera; com renderização, salva uma prévia.

var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var battle = load("res://main.tscn").instantiate()
	root.add_child(battle)
	for i in 8:
		await process_frame
	while battle.busy:
		await process_frame
	await process_frame
	var screen := Rect2(105, 65, 1150, 605)
	for row in battle.state.rows():
		for col in battle.state.cols():
			var cell := Vector2i(col, row)
			var projected: Vector2 = battle.cell_to_screen(cell)
			_expect(battle._cell_at(projected) == cell, "seleção da casa %s" % cell)
			_expect(battle._pick_cell(projected) == cell, "centro acessível da casa %s" % cell)
			_expect(screen.has_point(projected), "casa %s dentro da tela" % cell)
	var camera = battle.battle_camera
	# Um nível muda a altura, sem alterar a escala/distância no chão.
	var ground := Vector2(600, 430)
	var raised: Vector2 = camera.project(ground - Vector2(0, 58), 58.0)
	_expect(is_equal_approx(camera.project(ground).y - raised.y, 58 * camera.depth_scale(ground.y)), "altura vertical preservada pela câmera")
	_expect(camera.depth_scale(600) > camera.depth_scale(200), "primeiro plano maior que o fundo")
	var back_left: Vector2 = camera.project(Vector2(300, 200))
	var back_right: Vector2 = camera.project(Vector2(1000, 200))
	var front_left: Vector2 = camera.project(Vector2(300, 600))
	var front_right: Vector2 = camera.project(Vector2(1000, 600))
	_expect(front_left.distance_to(front_right) > back_left.distance_to(back_right) * 1.4, "convergência visível das fileiras")
	for unit in battle.views:
		var view = battle.views[unit]
		var anchor: Vector2 = view.sprite.material.get_shader_parameter("ground_anchor")
		_expect(anchor.is_equal_approx(view.global_position), "sprite ancorado nos pés de %s" % unit.type_id)
		_expect(view.sprite.material == view.badge.material, "marcadores acompanham %s" % unit.type_id)
		_expect(view.hp_fill.mouse_filter == Control.MOUSE_FILTER_IGNORE, "barra não bloqueia cliques em %s" % unit.type_id)
		_expect(is_equal_approx(camera.elevation_of(view), battle._cell_elevation(unit.pos)), "altura do personagem %s" % unit.type_id)
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().is_empty():
		await RenderingServer.frame_post_draw
		var path := OS.get_cmdline_user_args()[0]
		root.get_texture().get_image().save_png(path)
		print("Prévia: ", path)
	await _test_forest_and_jump(battle)
	await _test_walk_during_attack(battle)
	print("Câmera: ", "FALHOU" if failed else "OK")
	quit(1 if failed else 0)


# O turno espera a animação do golpe: o fim da caminhada não pode cancelá-la.
func _test_walk_during_attack(battle) -> void:
	var actor = battle.views.values()[0]
	var done := [false]
	actor.set_walking(true)
	var attack := func():
		await actor.play_once(actor.Anim.ATTACK)
		done[0] = true
	attack.call()
	actor.set_walking(false)
	await create_timer(3.0).timeout
	_expect(done[0], "parar de andar no meio do golpe não prende o turno")
	_expect(actor.row == actor.Anim.IDLE, "depois do golpe, volta a ficar parado")


func _test_forest_and_jump(battle) -> void:
	var hero = battle.state.units.filter(func(u): return u.type_id == "guardiao")[0]
	var actor = battle.views[hero]
	var start := Vector2i(0, 2)
	var forest := Vector2i(0, 1)
	var front = battle.forests[forest].front
	var back = battle.forests[forest].back
	actor.position = battle.feet_of(start)
	battle.battle_camera.set_elevation(battle._cell_elevation(start), actor)
	hero.pos = forest
	battle._play_move({"unit": hero, "from": start, "to": forest})
	await create_timer(0.24).timeout
	_expect(actor.visual_root.position.y < -80.0, "salto tira o corpo do chão")
	_expect(actor.shadow.scale.x < 0.9, "sombra permanece no chão durante o salto")
	await _shot("salto")
	await create_timer(0.35).timeout
	_expect(actor.position.is_equal_approx(battle.feet_of(forest)), "aterrissagem na floresta elevada")
	_expect(is_zero_approx(actor.visual_root.position.y), "corpo volta ao chão ao aterrissar")
	_expect(is_equal_approx(battle.battle_camera.elevation_of(actor), battle._cell_elevation(forest)), "altura final do salto")
	_expect(back.z_index < actor.z_index and front.z_index > actor.z_index, "personagem entre as duas metades da floresta")
	_expect(front.material.get_shader_parameter("scenery_slice") == 2, "árvores da frente recortadas separadamente")
	_expect(back.material.get_shader_parameter("scenery_slice") == 1, "copa do fundo recortada separadamente")
	_expect(front.scale.y > 1.5, "árvores mais altas")
	_expect(is_equal_approx(battle.state.tile_at(forest).damage, 0.8), "proteção da floresta continua em 20%")
	battle.pinned = hero
	battle._refresh_overlays()
	battle._update_hint()
	await process_frame
	await _shot("dentro-da-floresta")
	# Saída descendente: animação e metadados devem voltar ao nível inferior.
	hero.pos = start
	await battle._play_move({"unit": hero, "from": forest, "to": start})
	_expect(is_zero_approx(actor.visual_root.position.y), "descida termina sem salto residual")
	_expect(is_zero_approx(battle.battle_camera.elevation_of(actor)), "descida volta ao nível zero")
	_expect(is_equal_approx(front.modulate.a, 1.0), "floresta vazia recupera a opacidade")


func _shot(suffix: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty():
		return
	await RenderingServer.frame_post_draw
	var path: String = OS.get_cmdline_user_args()[0]
	root.get_texture().get_image().save_png(path.get_basename() + "-" + suffix + ".png")


func _expect(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		failed = true
