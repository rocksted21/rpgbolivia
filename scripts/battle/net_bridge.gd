extends RefCounted

## Online: envia os comandos deste jogador e aplica o que o dono da sala manda.


var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


func _submit_online(kind: String, cell: Vector2i, ability := "", hero = null, followers := []) -> void:
	var actor = hero if hero != null else battle._actor()
	if not battle.online_session.can_control(actor): return
	if not battle._free_roam():
		if battle.busy: return
		battle.input_ctl._close_menu()
	elif battle.busy and kind != "travel" and kind != "stop": return
	else:
		battle.input_ctl._close_menu()
	battle.online_session.submit({kind = kind, cell = cell, ability = ability, hero = actor.uid, followers = followers.map(func(u): return u.uid)})


func _network_command(sender: int, command: Dictionary) -> void:
	if not battle.online_session.playing or not battle.online_session.relay.is_master or battle.state.winner() >= 0: return
	var cell: Variant = command.get("cell", battle.NO_CELL)
	if not cell is Vector2i: return
	var kind := str(command.get("kind", ""))
	var hero = battle.state.unit_by_uid(int(command.get("hero", 0))) if command.get("hero") is int else null
	# Herói fora da luta (ou sem luta nenhuma) anda livre, mesmo com outra luta acontecendo.
	if battle.exploring and (not battle.state.in_combat() or (hero != null and battle.state.is_hero(hero) and not battle.state.is_fighting(hero))):
		if hero == null or not battle.state.is_hero(hero) or not hero.alive() or battle.online_session.owner_of(hero) != sender: return
		match kind:
			"travel":
				var followers := []
				if command.get("followers") is Array:
					for uid in command["followers"]:
						var member = battle.state.unit_by_uid(int(uid)) if uid is int else null
						if member != null and member != hero and battle.state.is_hero(member) and member.alive() and battle.online_session.owner_of(member) == sender and not member in followers:
							followers.append(member)
				battle.roam_ctl._start_file(hero, followers, cell)
			"stop": battle.roam_ctl._end_chain(hero)
			"ability":
				var id: String = str(command.get("ability", ""))
				if not battle.busy and id in hero.abilities and cell in battle.state.valid_targets(hero, id):
					battle._perform(battle.state.do_ability(hero, id, cell))
		return
	if battle.busy or command.get("revision", -1) != battle.online_session.revision: return
	var unit = battle.state.active_unit()
	if battle.online_session.owner_of(unit) != sender or not unit.pending.is_empty(): return
	match kind:
		"wait": battle._perform(battle.state.do_wait(unit))
		"step":
			if battle.state.unit_at(cell) == null and battle.state.move_cells(unit).has(cell): battle._perform(battle.state.do_move(unit, cell))
		"jump":
			if battle.state.jump_cells(unit).has(cell): battle._perform(battle.state.do_jump(unit, cell))
		"ability":
			var id: String = str(command.get("ability", ""))
			if id in unit.abilities and cell in battle.state.valid_targets(unit, id):
				battle._perform(battle.state.do_ability(unit, id, cell))


func _network_packet(_packet: Dictionary) -> void:
	if battle.remote_playing or not battle.online_session.playing or battle.online_session.relay.is_master: return
	battle.remote_playing = true
	while not battle.online_session.packets.is_empty():
		var packet: Dictionary = battle.online_session.packets.pop_front()
		if int(packet.revision) <= battle.online_session.revision: continue
		battle.online_session.revision = int(packet.revision)
		var roam: bool = packet.get("roam", false)
		if not roam:
			battle.busy = true
			battle.input_ctl._close_menu()
		battle.online_session.apply_snapshot(packet.snapshot)
		var events: Array = packet.events
		for event in events:
			for key in ["unit", "target"]:
				if event.has(key): event[key] = battle.state.unit_by_uid(int(event[key]))
			if event.has("units"):
				event["units"] = event["units"].map(func(uid): return battle.state.unit_by_uid(int(uid)))
		await battle.event_player._play(events, roam)
		battle.event_player._match_views()
		for unit in battle.views:
			if not battle.moving.has(unit):
				battle.views[unit].position = battle.feet_of(unit.pos)
				battle.views[unit].z_index = battle._z(battle._row(unit.pos)) + 5
				battle.battle_camera.set_elevation(battle._cell_elevation(unit.pos), battle.views[unit])
			battle.views[unit].set_hp(unit.hp)
			battle.views[unit].visible = unit.alive()
			if unit.alive():
				battle.views[unit].rotation = 0.0
				battle.views[unit].modulate.a = 1.0
		battle.busy = not bool(packet.ready)
		battle.hud.refresh(battle.state)
		if battle.state.winner() < 0:
			battle._place_ground_marker(battle.active_outline, battle.state.active_unit().pos)
			battle.active_outline.visible = not battle._free_roam()
			if battle.state.in_combat() and not battle._free_roam():
				battle._focus_turn(battle.state.active_unit())
			elif battle.camera_unit != battle.selected:
				battle.input_ctl._select(battle._actor())
			battle.journey_ui._update_journey()
		battle.marks_ctl._refresh_turn_markers()
		battle.marks_ctl._refresh_overlays()
		battle.marks_ctl._update_hint()
		if battle.state.winner() >= 0:
			battle.busy = true
			battle.journey_ui._show_result(battle.state.winner())
	battle.remote_playing = false


func _room_status() -> void:
	if not battle.online_session.playing or battle.hud == null:
		return
	battle.hud.set_party_owners(battle._owner_names())
	if battle.selected != null and not battle.online_session.can_control(battle.selected) and battle._free_roam():
		battle.input_ctl._select(battle._first_mine())
	if battle.hud.group_open():
		battle._open_group()
	battle.input_ctl._refresh_end_turn()
	battle.marks_ctl._refresh_turn_markers()
	battle.marks_ctl._update_hint()


func _leave_online() -> void:
	battle.online_session.leave()
	battle.get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")


func _network_lost(_reason: String) -> void:
	battle.get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")
