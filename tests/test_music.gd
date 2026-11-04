extends SceneTree
## godot --headless --path . --script tests/test_music.gd

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _playing_tracks(manager: Node) -> Array[AudioStreamPlayer]:
	var tracks: Array[AudioStreamPlayer] = []
	for player in manager.get_node("Combate").get_children():
		if player.playing:
			tracks.append(player)
	return tracks


func _run() -> void:
	var manager := root.get_node("MusicManager")
	_expect(manager.get_node("Combate").get_child_count() == 4, "As quatro músicas estão na cena")
	var background := manager.get_node("Menu/DigitalHope") as AudioStreamPlayer
	_expect(_playing_tracks(manager).is_empty(), "Autoload não inicia músicas de combate")
	_expect(background.playing and background.stream.loop, "Digital Hope inicia em loop")
	_expect(background.bus == &"Music/Menu", "Digital Hope segue o volume do grupo Menu")
	background.seek(10.0)
	var initial_menu := load("res://scenes/main_menu.tscn").instantiate() as Node
	root.add_child(initial_menu)
	await process_frame
	initial_menu.queue_free()
	await process_frame
	# O lobby também contém a seleção de personagens.
	var lobby := load("res://scenes/online_lobby.tscn").instantiate() as Node
	root.add_child(lobby)
	await process_frame
	manager.play_menu()
	_expect(background.playing and background.get_playback_position() >= 9.0, "Música continua entre telas sem reiniciar")
	lobby.queue_free()
	await process_frame
	for player in manager.get_node("Combate").get_children():
		_expect(player.stream != null and not player.stream.loop, "Faixa carregada sem loop individual")
		_expect(player.bus == &"Music/Combate", "Faixa segue o volume do grupo de música")
	var battle := load("res://main.tscn").instantiate() as Node
	root.add_child(battle)
	await process_frame
	var playing := _playing_tracks(manager)
	_expect(playing.size() == 1, "Entrar no combate toca uma única música")
	_expect(not background.playing, "Digital Hope para durante o combate")
	if playing.size() == 1:
		var first := playing[0]
		manager.play_combat()
		_expect(_playing_tracks(manager) == playing, "Reiniciar reprodução não troca a faixa em andamento")
		first.finished.emit()
		playing = _playing_tracks(manager)
		_expect(playing.size() == 1 and playing[0] != first, "Próxima faixa não repete a anterior")
	battle.queue_free()
	await process_frame
	_expect(_playing_tracks(manager).is_empty(), "Sair do combate para a música")
	_expect(background.playing, "Sair do combate volta a Digital Hope")
	var menu := load("res://scenes/main_menu.tscn").instantiate() as Node
	root.add_child(menu)
	await process_frame
	_expect(_playing_tracks(manager).is_empty(), "Menu não toca músicas de combate")
	menu.queue_free()
	await process_frame
	manager.stop()
	root.get_node("OnlineSession").relay.stop_room_list()
	# Aguarda o servidor de áudio liberar os playbacks encerrados antes de sair.
	await create_timer(0.2).timeout
	print("Musicas: carregamento, troca de faixa e ciclo de combate; %d falhas" % failures)
	quit(1 if failures > 0 else 0)
