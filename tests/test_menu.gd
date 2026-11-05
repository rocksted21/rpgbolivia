extends SceneTree
## Confere o menu e salva capturas. Rodar sem --headless para ter as imagens:
## godot --path . --script tests/test_menu.gd -- <pasta>

const TownProgress = preload("res://scripts/town_progress.gd")
const GameSettings = preload("res://scripts/game_settings.gd")

var failed := 0
var dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0] if not args.is_empty() else ""
	TownProgress.path = "user://test_menu_town.cfg"
	GameSettings.path = "user://test_menu_settings.cfg"
	var config := ConfigFile.new()
	config.set_value("town", "brasas", 245)
	config.set_value("town", "beacons", 1)
	config.set_value("town", "expeditions", 3)
	config.save(TownProgress.path)
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failed += 1
		print("FALHOU: ", what)


func _shot(menu_name: String) -> void:
	for i in 12:
		await process_frame
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, menu_name])


func _run() -> void:
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.menu_buttons.size() == 6, "seis botões")
	check(menu.single_player.has_focus(), "começa em Jornada Solo")
	check(menu.counters.text == "Brasas: 245\nFaróis: 1/4", "contadores vêm do jogo: " + menu.counters.text)
	check(menu.version_label.text.begins_with("versão "), "mostra a versão")
	for button in menu.menu_buttons:
		check(button.pressed.get_connections().size() > 0, "botão ligado")
		check(button.size.x > 300.0 and button.size.y > 50.0, "botão clicável")
	await _shot("menu_1_inicio")
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	root.push_input(down)
	await process_frame
	check(menu.menu_buttons[1].has_focus(), "seta para baixo vai ao próximo botão")
	menu.menu_buttons[3].grab_focus()
	await _shot("menu_2_memorias_aceso")
	menu.menu_buttons[3].pressed.emit()
	check(menu.open_modal == menu.archive, "arquivo abre")
	await _shot("menu_3_arquivo")
	menu._close_modal()
	check(menu.open_modal == null and menu.menu_buttons[3].has_focus(), "fechar volta ao botão")
	menu.menu_buttons[4].grab_focus()
	menu.menu_buttons[4].pressed.emit()
	check(menu.open_modal == menu.options, "ajustes abrem")
	menu.volume_slider.value = 25
	check(GameSettings.volume() == 25, "volume salvo")
	check(menu.volume_chip.text == "Volume 25%", "volume no canto")
	await _shot("menu_4_ajustes")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	root.push_input(cancel)
	await process_frame
	check(menu.open_modal == null, "Esc fecha a janela")
	menu.queue_free()
	await process_frame
	for scene in ["res://scenes/online_lobby.tscn", "res://scenes/skill_tree.tscn"]:
		check(ResourceLoader.exists(scene), "tela existe: " + scene)
	DirAccess.remove_absolute(TownProgress.path)
	DirAccess.remove_absolute(GameSettings.path)
	print("MENU: ", "FALHOU (%d)" % failed if failed > 0 else "OK")
	quit(1 if failed > 0 else 0)
