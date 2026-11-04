extends SceneTree
## Rode simultaneamente -- host e -- guest contra o relay da porta 18787.
var session
var view
var host_role := false
var expected := {}
var acknowledged := false
var picked := false
var sent_done := false
var actions := 0
var last_revision := -1
var fought := false
var deadline := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	session = root.get_node("OnlineSession")
	session.configure(_relay())
	host_role = "host" in OS.get_cmdline_user_args()
	session.player_name = "Dono" if host_role else "Amigo"
	session.relay.frame_received.connect(_frame)
	deadline = Time.get_ticks_msec() + 45000
	session.relay.join_room("PAIRTEST", host_role, {build = "combate-tatico", title = "Pair test"})
	while not session.playing:
		if Time.get_ticks_msec() > deadline:
			push_error("Timeout na sala")
			quit(1)
			return
		if session.players.size() == 2 and not picked:
			picked = true
			session.pick_hero(5 if host_role else 3)
		if host_role and session.can_start(): session.start_match()
		await process_frame
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not session.playing: break
		if host_role and acknowledged:
			print("PAIR HOST PASS: ações e confirmação do convidado")
			quit(0)
			return
		if not host_role and not expected.is_empty() and session.revision == expected.revision and not view.remote_playing:
			if session.snapshot() != expected.snapshot:
				push_error("Divergência no estado renderizado")
				quit(1)
				return
			for unit in view.views:
				if unit.alive() and not view.moving.has(unit) and not view.views[unit].position.is_equal_approx(view.feet_of(unit.pos)):
					push_error("Sprite fora da casa sincronizada")
					quit(1)
					return
			session._send({type = "test_ack"}, true)
			print("PAIR GUEST PASS: animações, posições e estado sincronizados")
			await create_timer(0.3).timeout
			quit(0)
			return
		if view.busy or view.remote_playing or not view.moving.is_empty() or not view.walk_paths.is_empty(): continue
		var state = session.state
		if host_role and actions >= 10 and fought and not sent_done:
			sent_done = true
			session._send({type = "test_done", revision = session.revision, snapshot = session.snapshot()})
		if sent_done or not expected.is_empty(): continue
		if session.revision == last_revision: continue
		if state.in_combat():
			fought = true
			var unit = state.active_unit()
			if not session.can_control(unit): continue
			last_revision = session.revision
			view._submit_online("wait", Vector2i(-1, -1))
			if host_role: actions += 1
		else:
			if fought and not host_role: continue
			last_revision = session.revision
			var mine = view._first_mine()
			var steps: Array = preload("res://scripts/hex.gd").neighbors(mine.pos).filter(func(cell): return state.can_step(mine, cell))
			if not steps.is_empty():
				view._travel(steps[0])
			if host_role:
				actions += 1
				if actions == 4: # o inimigo aparece perto, e os dois lados entram em combate
					var foe = state.add_unit("mumia", 1, mine.pos + Vector2i(4, 0))
					view._add_unit_view(foe)
					view._play([{type = "spawn_ok"}], true)
	push_error("Timeout no combate em duas instâncias")
	quit(1)

func _frame(sender: int, payload: PackedByteArray) -> void:
	var message: Variant = bytes_to_var(payload)
	if not message is Dictionary: return
	if message.get("type") == "test_done" and sender == session.original_host: expected = message
	if message.get("type") == "test_ack" and host_role: acknowledged = true

## COMBATE_RELAY=wss://combate-tatico-relay.fly.dev testa contra o servidor publicado.
func _relay() -> String:
	var address := OS.get_environment("COMBATE_RELAY")
	return "ws://127.0.0.1:18787" if address.is_empty() else address
