extends SceneTree
## Joga uma expedição pela tela de verdade e salva capturas. Rodar sem --headless:
## godot --path . --script tests/expedition_smoke.gd -- <pasta-das-capturas>

const Hex = preload("res://scripts/hex.gd")
const AI = preload("res://scripts/ai.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const GameSettings = preload("res://scripts/game_settings.gd")
const SaveGame = preload("res://scripts/save_game.gd")

const TIMEOUT_SECONDS := 240.0

var view
var dir := ""
var failed := false


func _initialize() -> void:
	dir = OS.get_cmdline_user_args()[0]
	# Uma partida de teste não pode mexer no save de verdade.
	HeroProgress.path = "user://test_progress_expedition.cfg"
	TownProgress.path = "user://test_town_smoke.cfg"
	GameSettings.path = "user://test_settings_smoke.cfg"
	SaveGame.path = "user://test_save_smoke.dat"
	DirAccess.remove_absolute(GameSettings.path)
	DirAccess.remove_absolute(HeroProgress.path)
	DirAccess.remove_absolute(TownProgress.path)
	create_timer(TIMEOUT_SECONDS, true, false, true).timeout.connect(func():
		print("TIMEOUT")
		quit(2))
	_run()


func _expect(ok: bool, text: String) -> void:
	if not ok:
		failed = true
		print("FALHOU: ", text)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [dir, shot_name])


func _wait_frames(count: int) -> void:
	for i in count:
		await process_frame


func _idle() -> void:
	await process_frame
	var guard := 0
	while (view.busy or not view.walk_paths.is_empty() or not view.moving.is_empty()) and view.state.winner() < 0 and guard < 6000:
		await process_frame
		guard += 1


func _run() -> void:
	root.set_meta("world_hero", ["guardiao", "duelista", "mago", "druida"])
	root.set_meta("town", true)
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	await _idle()
	await _wait_frames(60)
	_expect(view.town and view.state.foes().is_empty(), "o jogo começa na cidade")
	_expect(view.hud.journey.text.contains("Cidade-Farol"), "o topo mostra a cidade")
	await _shot("1_cidade_inicio")
	await _test_town()
	await _idle()
	await _wait_frames(30)
	var state = view.state
	_expect(state.has_method("result"), "a cena abre uma expedição")
	_expect(state.potions == 1 and view.hud.potion_button.visible, "a poção comprada vai junto")
	_expect(view.hud.tracker.text.contains("A Primeira Chama"), "a expedição mostra a missão aceita")
	state.party[0].hp = 1
	view.hud.potion_button.pressed.emit()
	_expect(state.party[0].hp > 1 and state.potions == 0 and not view.hud.potion_button.visible, "a poção cura pela tela")
	await _shot("2_inicio_expedicao")
	_expect(view.hud.objective.text.contains("Farol"), "a bússola aponta o farol")
	await _test_volume()

	# Ruínas: marca no mapa, recompensa e a marca some.
	var ruin: Variant = _cell_of(state, "ruina")
	await _bring_party(state, ruin, 3)
	await _wait_frames(30)
	await _shot("3_marca_no_mapa")
	_expect(view.landmark_nodes.has(ruin), "as ruínas têm marca no mapa")
	await _bring_party(state, ruin, 1)
	view._perform([])
	await _idle()
	await _shot("4_ruinas")
	_expect(state.landmarks[ruin]["state"] == "done", "visitar ruínas funciona pela tela")
	_expect(not view.landmark_nodes.has(ruin), "a marca some depois da visita")
	_expect(state.brasas > 0, "ganhou brasas")

	var memory: Variant = _cell_of(state, "memoria")
	await _bring_party(state, memory, 1)
	view._perform([])
	await _idle()
	await _wait_frames(4)
	await _shot("5_memoria")
	_expect(state.memories.size() == 1, "encontrou a memória")

	# Vila: luta contra os guardas até o resgate.
	var village: Variant = _cell_of(state, "vila")
	await _bring_party(state, village, 1)
	view._perform([])
	await _idle()
	await _wait_frames(4)
	await _shot("6_vila_atacada")
	_expect(state.in_combat(), "a vila começa um combate")
	await _fight(state)
	await _shot("7_vila_salva")
	_expect(not state.rescued.is_empty(), "a vila resgatou um morador")

	# Farol: o chefe e a vitória.
	await _bring_party(state, state.beacon_cell, 2)
	await _wait_frames(10)
	await _shot("8_farol")
	view._perform([])
	await _idle()
	await _wait_frames(10)
	await _shot("9_chefe")
	_expect(state.boss != null and view.views.has(state.boss), "o chefe aparece na tela")
	_expect(state.in_combat(), "o chefe começa o combate")
	# Duas ações reais contra o chefe e depois encurta a luta: testa a tela, não o equilíbrio.
	for i in 2:
		await _one_action(state)
	state.boss.hp = 1
	for member in state.alive_party():
		member.hp = member.max_hp
	await _fight(state)
	var waited := 0
	while not view.hud.end_panel.visible and waited < 2000:
		await process_frame
		waited += 1
	await _wait_frames(4)
	await _shot("10_vitoria")
	_expect(state.winner() == view.Data.Team.PLAYER, "derrotar o chefe vence")
	_expect(not view.landmark_nodes.has(state.beacon_cell), "o farol aceso perde a marca de objetivo")
	_expect(view.hud.end_panel.visible, "tela de fim aparece")
	_expect(view.hud.end_label.text.contains("farol"), "o fim fala do farol")
	_expect(view.hud.end_note.text.contains("A Primeira Chama"), "o fim avisa da missão cumprida")
	_expect(TownProgress.beacons() == 1 and TownProgress.brasas() > 0, "o resultado foi salvo")
	_expect(not TownProgress.rescued().is_empty(), "o morador foi salvo na cidade")
	view.hud.restart_pressed.emit()
	await _idle()
	await _wait_frames(60)
	_expect(view.town and not view.expedition, "a expedição volta para a cidade")
	_expect(view.hud.objective.text.contains("Faróis acesos 1"), "a cidade mostra o farol")
	await _shot("11_cidade_depois")
	await _test_growth()
	print("Expedição: ", "FALHOU" if failed else "OK")
	DirAccess.remove_absolute(HeroProgress.path)
	DirAccess.remove_absolute(TownProgress.path)
	quit(1 if failed else 0)


## Anda até um morador, conversa, abre a party e parte.
func _test_town() -> void:
	var state = view.state
	# Andar pela cidade usa o mesmo clique da exploração.
	var from: Vector2i = view.selected.pos
	var target: Vector2i = state.area_of(from, 2).filter(func(c): return Hex.distance(c, from) == 2 and state.tile_at(c)["walkable"] and state.unit_at(c) == null)[0]
	view._click(target)
	await _wait_frames(90)
	_expect(view.selected.pos != from, "clicar anda pela cidade")
	await _idle()
	var person: Dictionary = state.people.values().filter(func(p): return p["id"] == "taverneira")[0]
	await _put_party_near(state, person["cell"])
	await _wait_frames(40)
	await _shot("1b_taverna")
	_expect(view.town_panels.nearby == person, "a cidade percebe quem está perto")
	_expect(view.town_panels.action_button.visible, "aparece o botão de falar")
	view.town_panels.action_button.pressed.emit()
	_expect(view.town_panels.window_open(), "falar abre a janela")
	await _wait_frames(3)
	await _shot("1c_conversa")
	view.town_panels.close_window()
	for other in state.people.values():
		view.town_panels.open_person(other)
		_expect(view.town_panels.window_open(), "a conversa abre: %s" % other["name"])
		view.town_panels.close_window()
	await _test_city_life(state)
	view.town_panels.open_party()
	await _wait_frames(3)
	await _shot("1d_party")
	var old_state = view.state
	view.town_panels.start_button.pressed.emit()
	await _wait_frames(3)
	_expect(view.state != old_state and view.expedition and not view.town, "partir abre a expedição")


## Conversa, missão, loja e registro, pelos botões da tela.
func _test_city_life(state) -> void:
	var panels = view.town_panels
	var keeper: Dictionary = state.people.values().filter(func(p): return p["id"] == "guarda")[0]
	var label: Label = view.person_labels.get(keeper["cell"])
	if label != null:
		_expect(label.text.begins_with("!"), "o Faroleiro mostra que tem pedido")
	panels.open_person(keeper)
	await _wait_frames(3)
	await _shot("1e_conversa_faroleiro")
	var offer: Button = _find_button(panels.window, "! Pedido")
	_expect(offer != null, "a conversa oferece a missão")
	offer.pressed.emit()
	await _wait_frames(3)
	await _shot("1f_missao")
	_find_button(panels.window, "Aceitar").pressed.emit()
	_expect(TownProgress.quest_status("primeira_chama") == "active", "aceitar pela tela funciona")
	if label != null:
		_expect(not label.text.begins_with("!"), "a marca some depois de aceitar")
	panels.close_window()
	TownProgress.record({"won": false, "brasas": 40, "rescued": [], "memories": 0})
	var seller: Dictionary = state.people.values().filter(func(p): return p["id"] == "mercadora")[0]
	await _put_party_near(state, seller["cell"])
	await _wait_frames(30)
	await _shot("1g_mercadora")
	panels.open_person(seller)
	_find_button(panels.window, "Ver o que tem").pressed.emit()
	await _wait_frames(3)
	await _shot("1h_loja")
	var before := TownProgress.brasas()
	_find_button(panels.window, "8 brasas").pressed.emit()
	_expect(TownProgress.brasas() == before - 8 and TownProgress.item_count("pocao") == 1, "comprar pela tela funciona")
	panels.close_window()
	panels.log_button.pressed.emit()
	await _wait_frames(3)
	await _shot("1i_missoes")
	panels.close_window()
	var board: Dictionary = state.people.values().filter(func(p): return p["id"] == "mural")[0]
	panels.open_person(board)
	await _wait_frames(3)
	await _shot("1j_mural")
	panels.close_window()
	view.town_life.say(view.selected.pos, "Boa sorte lá fora!")
	await _wait_frames(70)
	await _shot("1k_vida")


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text.contains(text):
		return node
	for child in node.get_children():
		var found: Button = _find_button(child, text)
		if found != null:
			return found
	return null


## Depois do resgate, a forja ou a tenda existem e vendem melhorias.
func _test_growth() -> void:
	var state = view.state
	var resident: String = TownProgress.rescued()[0]
	var person: Dictionary = state.people.values().filter(func(p): return p["id"] == resident)[0]
	_expect(not state.tile_at(person["cell"])["walkable"], "o morador resgatado está na cidade")
	await _put_party_near(state, person["cell"])
	await _wait_frames(40)
	await _shot("12_morador_resgatado")
	TownProgress.record({"won": false, "brasas": 100, "rescued": [], "memories": 0})
	var before := TownProgress.brasas()
	view.town_panels.open_person(person)
	await _wait_frames(3)
	await _shot("13_melhoria")
	_expect(TownProgress.buy(resident), "dá para comprar a melhoria")
	_expect(TownProgress.brasas() < before, "a melhoria cobra brasas")
	view.town_panels.close_window()
	view.town_panels.open_party()
	view.town_panels.close_window()


func _put_party_near(state, cell: Vector2i) -> void:
	var spots: Array = state.area_of(cell, 3).filter(func(spot):
		return state.tile_at(spot)["walkable"] and state.unit_at(spot) == null and Hex.distance(spot, cell) <= 2)
	spots.sort_custom(func(a, b): return Hex.distance(a, cell) < Hex.distance(b, cell))
	for i in state.party.size():
		var member = state.party[i]
		member.pos = spots[i]
		view.views[member].position = view.feet_of(member.pos)
		view.views[member].z_index = view._z(view._row(member.pos)) + 5
		view.battle_camera.set_elevation(view._cell_elevation(member.pos), view.views[member])
	view._follow(view.selected)
	view._sync_world(view.camera_cell)
	await process_frame


func _test_volume() -> void:
	var hud = view.hud
	_expect(hud.options_button.text == "Opções", "o canto mostra o botão de opções")
	_expect(not hud.options_open(), "o menu começa fechado")
	hud.options_button.pressed.emit()
	_expect(hud.options_open() and paused, "o botão abre o menu e pausa o jogo")
	_expect(hud.volume_label.text == "Volume: 100%", "o menu mostra o volume")
	hud.volume_slider.value = 35
	_expect(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.35), "o controle abaixa o volume")
	_expect(hud.volume_label.text == "Volume: 35%", "o texto acompanha o volume")
	hud.save_button.pressed.emit()
	_expect(SaveGame.exists() and hud.options_note.text == "Jogo salvo!", "salvar grava o jogo")
	_expect(not hud.load_button.disabled, "depois de salvar dá para carregar")
	await _wait_frames(3)
	await _shot("2b_opcoes")
	hud.volume_mute.button_pressed = true
	_expect(AudioServer.is_bus_mute(0) and hud.volume_label.text == "Volume: sem som", "silenciar funciona")
	hud.volume_slider.value = 60
	_expect(not AudioServer.is_bus_mute(0), "mexer no volume tira do silêncio")
	for child in hud.options_panel.get_child(0).get_children():
		if child is Button and child.text == "Sair do jogo":
			child.pressed.emit()
	_expect(hud.quit_panel.visible and not hud.options_panel.visible, "sair pede confirmação")
	await _wait_frames(3)
	await _shot("2c_sair_confirmar")
	for child in hud.quit_panel.get_child(0).get_child(2).get_children():
		if child.text == "Cancelar":
			child.pressed.emit()
	_expect(hud.options_panel.visible and not hud.quit_panel.visible, "cancelar volta ao menu")
	hud.close_options()
	_expect(not hud.options_open() and not paused, "voltar ao jogo fecha e despausa")
	DirAccess.remove_absolute(GameSettings.path)
	DirAccess.remove_absolute(SaveGame.path)
	GameSettings.apply()


func _cell_of(state, kind: String) -> Variant:
	for cell in state.landmarks:
		if state.landmarks[cell]["kind"] == kind:
			return cell
	return null


## Leva a party para perto de um local sem andar o caminho todo.
func _bring_party(state, cell: Vector2i, gap: int) -> void:
	for unit in state.foes():
		if not state.engaged.has(unit):
			state.units.erase(unit)
			view._remove_view(unit)
	state.steps_until_spawn = 999.0
	var ring: Array = state.area_of(cell, gap + 2).filter(func(spot):
		return state.tile_at(spot)["walkable"] and Hex.distance(spot, cell) >= gap and state.unit_at(spot) == null)
	ring.sort_custom(func(a, b): return Hex.distance(a, cell) < Hex.distance(b, cell))
	for i in state.party.size():
		var member = state.party[i]
		member.pos = ring[i]
		view.views[member].position = view.feet_of(member.pos)
		view.views[member].z_index = view._z(view._row(member.pos)) + 5
		view.battle_camera.set_elevation(view._cell_elevation(member.pos), view.views[member])
	view._follow(view.selected)
	view._sync_world(view.camera_cell)
	view._update_journey()
	await process_frame


func _one_action(state) -> void:
	var hero = state.active_unit()
	var action: Dictionary = AI.decide(state, hero)
	if action["kind"] == "ability":
		view._perform(state.do_ability(hero, action["id"], action["cell"]))
	elif action["kind"] == "step":
		view._perform(state.do_move(hero, action["cell"]))
	else:
		view._perform(state.do_wait(hero))
	await _idle()


func _fight(state) -> void:
	var actions := 0
	while state.in_combat() and state.winner() < 0 and actions < 300:
		actions += 1
		for member in state.alive_party():
			member.hp = member.max_hp # aqui a luta só precisa terminar
		await _one_action(state)
	await _idle()
