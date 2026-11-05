extends SceneTree
## Joga muitos turnos pela tela e acusa se o jogo ficar preso (TRAVOU). Sem mexer no mouse: chama o que os botões chamam.
const AI = preload("res://scripts/ai.gd")
const Hex = preload("res://scripts/hex.gd")
var view
func _initialize(): _run.call_deferred()
func _info(state):
	var u = state.active_unit()
	return "active %s team %d pos %s clock %d moved %d pending %s combat %s busy %s" % [u.type_id, u.team, u.pos, u.clock, u.moved, u.pending, state.in_combat(), view.busy]
func _ready_or_stuck(state, tag) -> bool:
	var n := 0
	while (view.busy or not view.walk_paths.is_empty()) and state.winner() < 0:
		await process_frame
		n += 1
		if n > 2500:
			printerr("TRAVOU[", tag, "] ", _info(state))
			return false
	return true
func _run():
	Engine.time_scale = 10.0
	root.set_meta("world_hero", ["guardiao", "duelista", "mago", "druida"])
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	var state = view.state
	printerr("modo exploring ", view.exploring, " town ", view.town)
	var combats := 0
	var was := false
	var acts := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 170000 and state.winner() < 0 and acts < 4000:
		if not await _ready_or_stuck(state, "loop"):
			quit(1)
			return
		acts += 1
		for m in state.party:
			m.hp = maxi(m.hp, m.max_hp / 2) if m.alive() else m.hp
		var u = state.active_unit() if state.in_combat() else state.party[0]
		if state.in_combat() != was:
			was = state.in_combat()
			if was: combats += 1; printerr("combate ", combats, " inimigos ", state.foes().size(), " ", acts)
		if state.in_combat():
			if u.team == 0 or state.is_hero(u):
				var roll := randi() % 4
				if roll == 0:
					view._end_turn()
				else:
					var a = AI.decide(state, u)
					match a["kind"]:
						"ability": view._perform(state.do_ability(u, a["id"], a["cell"]))
						"step":
							var cells = state.move_cells(u).keys()
							view._perform(state.do_move(u, cells[randi() % cells.size()] if roll == 1 and not cells.is_empty() else a["cell"]))
						_: view._end_turn()
			else:
				printerr("nao-ocupado na vez do inimigo! ", _info(state))
				await process_frame
		else:
			var opts = Hex.neighbors(u.pos).filter(func(c): return state.can_step(u, c))
			if opts.is_empty():
				await process_frame
			else:
				var far = -1
				var pick = opts[0]
				for c in opts:
					var d = Hex.distance(c, state.start_cell)
					if d > far: far = d; pick = c
				view._perform(state.do_step(u, pick))
		await process_frame
	printerr("fim acts ", acts, " combates ", combats, " vencedor ", state.winner())
	quit()
