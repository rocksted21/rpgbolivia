extends SceneTree
## godot --headless --path . --script tests/test_audio.gd

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var manager = root.get_node("SoundManager")
	var menu = manager.get_node("Menu")
	var master_bus := AudioServer.get_bus_index("SoundManager")
	var menu_bus := AudioServer.get_bus_index("UI")
	_expect(AudioServer.get_bus_send(menu_bus) == &"SoundManager", "Menu passa pelo volume geral")
	manager.volume = 50.0
	manager.set_menu_volume(0.5)
	_expect(is_equal_approx(menu.volume, 50.0), "API antiga atualiza o controle do node Menu")
	var combined := AudioServer.get_bus_volume_linear(master_bus) * AudioServer.get_bus_volume_linear(menu_bus)
	_expect(is_equal_approx(combined, 0.25), "50% geral e 50% Menu resultam em 25%")
	for player in menu.get_children():
		_expect(player.bus == &"UI", "Todos os sons do Menu seguem o grupo")
		_expect(is_equal_approx(player.volume_db, -10.0), "Volume individual do som é preservado")

	# Um novo grupo funciona sem configurar buses ou alterar o SoundManager.
	var characters := AudioGroup.new()
	characters.name = "Personagens"
	characters.volume = 80.0
	var container := Node2D.new()
	var player := AudioStreamPlayer2D.new()
	container.add_child(player)
	characters.add_child(container)
	manager.add_child(characters)
	var character_bus := AudioServer.get_bus_index(player.bus)
	_expect(player.bus != &"UI" and player.bus != &"Master", "Novo grupo ganha bus próprio")
	_expect(AudioServer.get_bus_send(character_bus) == &"SoundManager", "Personagens segue volume geral")
	_expect(is_equal_approx(AudioServer.get_bus_volume_linear(character_bus), 0.8), "Volume inicial do grupo é aplicado")
	var late_player := AudioStreamPlayer3D.new()
	container.add_child(late_player)
	_expect(late_player.bus == player.bus, "Players adicionados depois seguem o grupo")
	var subgroup := AudioGroup.new()
	subgroup.name = "Vozes"
	characters.add_child(subgroup)
	var voice := AudioStreamPlayer.new()
	subgroup.add_child(voice)
	_expect(AudioServer.get_bus_send(AudioServer.get_bus_index(voice.bus)) == player.bus, "Subgrupo segue seu grupo pai")
	manager.set_menu_muted(true)
	_expect(AudioServer.is_bus_mute(menu_bus), "Mute do Menu funciona")
	_expect(not AudioServer.is_bus_mute(character_bus), "Mute do Menu preserva Personagens")
	manager.muted = true
	_expect(AudioServer.is_bus_mute(master_bus), "Mute geral atua no bus pai de todos os grupos")
	manager.muted = false
	manager.volume = 100.0
	manager.set_menu_muted(false)
	manager.set_menu_volume(1.0)
	characters.queue_free()
	await process_frame

	# Todo som que o combate pede existe no grupo Combate e passa pelo volume geral.
	var combat = manager.get_node("Combate")
	_expect(AudioServer.get_bus_send(AudioServer.get_bus_index(&"Combate")) == &"SoundManager", "Combate passa pelo volume geral")
	# A tela também toca sons de UI; valide cada nome no grupo correto.
	var source := FileAccess.get_file_as_string("res://scripts/battle_view.gd")
	var ui_names := []
	for found in RegEx.create_from_string("play_ui\\(&\"(\\w+)\"").search_all(source):
		var sound_name := found.get_string(1)
		ui_names.append(sound_name)
		_expect(menu.has_node(sound_name), "Som de interface existe: %s" % sound_name)
	for found in RegEx.create_from_string("&\"(\\w+)\"").search_all(source):
		if found.get_string(1) in ui_names:
			continue
		_expect(combat.has_node(found.get_string(1)), "Som de combate existe: %s" % found.get_string(1))
	for sfx in combat.get_children():
		_expect(sfx.bus == &"Combate", "Som de combate segue o grupo: %s" % sfx.name)
		_expect(sfx.stream is AudioStreamRandomizer and sfx.stream.streams_count > 0, "Som de combate tem variações: %s" % sfx.name)
	root.get_node("MusicManager").stop()
	await create_timer(0.2).timeout
	print("Audio: hierarquia de volumes, grupos futuros e players dinamicos; %d falhas" % failures)
	quit(1 if failures > 0 else 0)
