extends RefCounted

## Caminhada livre fora de combate: rotas, fila da party, passos e o desenho
## contínuo de quem anda.

const Hex = preload("res://scripts/hex.gd")

const WALK_SMOOTH := 8.0 # arredonda as curvas: o desenho persegue o caminho, sem quinas
const MAX_WALK_FRAME := 0.05
const WALK_SETTLE := 1.5 # distância em que o herói já é considerado parado
const FACE_HOLD := 0.4 # tempo mínimo olhando para um lado, para não ficar virando
const FACE_FOLLOW := 2.5 # quão rápido o olhar acompanha a direção da caminhada
const FACE_TURN := 1.3 # precisa ser bem mais vertical que horizontal para virar de frente ou de costas
const FACE_KEEP := 0.75 # e bem menos para voltar a olhar de lado
const FACE_SIDE_FLIP := 0.3 # andando quase na vertical, não troca de lado à toa
const CATCH_UP := 0.7 # quanto o seguidor acelera por casa de atraso
const FILE_RETRY := 0.05
const FILE_PATIENCE := 1.5

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


func _ground(cell: Vector2i) -> Vector2:
	return Vector2(battle._column_x(cell), cell.y * battle.ROW_STEP) + battle.FEET


func _level_height(cell: Vector2i) -> float:
	return battle.state.elevation_at(cell) * battle.level_layers * battle.SIDE_HEIGHT


# As regras movem de casa em casa; a tela não. Cada unidade percorre as casas numa linha só,
# sem parar entre elas, e o desenho persegue essa linha: as curvas ficam redondas e os
# degraus viram rampas. Passos que chegam adiantados (fila, rede) só apressam um pouco.

func _begin_walk(unit, from: Vector2i, to: Vector2i, duration: float) -> void:
	var view = battle.views[unit]
	if not battle.walks.has(unit):
		battle.walks[unit] = {
			"from": from, "to": to, "progress": 0.0, "duration": duration, "queue": [],
			"ground": view.position + Vector2(0, _level_height(from)), "level": _level_height(from),
			"heading": Vector2.ZERO, "face_wait": 0.0,
		}
		battle.moving[unit] = true
		view.set_walking(true)
		view.set_jump_height(0.0)
		view.face_toward((_ground(to) - _ground(from)).rotated(battle.view_angle))
	else:
		battle.walks[unit]["queue"].append({"to": to, "duration": duration})


func _update_walks(frame_time: float) -> void:
	var delta := minf(frame_time, MAX_WALK_FRAME) # um quadro lento não vira um salto na tela
	for unit in battle.walks.keys():
		var view = battle.views.get(unit)
		var walk: Dictionary = battle.walks[unit]
		if view == null or not is_instance_valid(view):
			battle.walks.erase(unit)
			battle.moving.erase(unit)
			continue
		var queue: Array = walk["queue"]
		walk["progress"] += delta * (1.0 + queue.size() * 0.5) / walk["duration"]
		while walk["progress"] >= 1.0 and not queue.is_empty():
			var next: Dictionary = queue.pop_front()
			walk["progress"] -= 1.0
			walk["from"] = walk["to"]
			walk["to"] = next["to"]
			walk["duration"] = next["duration"]
		# Esperando o próximo passo, o avanço não acumula: senão ele pularia casas ao chegar.
		walk["progress"] = minf(walk["progress"], 1.0)
		var progress: float = walk["progress"]
		var goal: Vector2 = _ground(walk["from"]).lerp(_ground(walk["to"]), progress)
		var goal_level: float = lerpf(_level_height(walk["from"]), _level_height(walk["to"]), progress)
		var blend := 1.0 - exp(-delta * WALK_SMOOTH)
		var previous: Vector2 = walk["ground"]
		walk["ground"] = previous.lerp(goal, blend)
		walk["level"] = lerpf(walk["level"], goal_level, blend)
		view.position = walk["ground"] - Vector2(0, walk["level"])
		battle.battle_camera.set_elevation(walk["level"] * battle.BOARD_SCALE, view)
		view.z_index = battle._z(maxi(battle._row(walk["from"]), battle._row(walk["to"]))) + 5
		_steer(view, walk, walk["ground"] - previous, delta)
		if progress >= 1.0 and queue.is_empty() and walk["ground"].distance_to(goal) < WALK_SETTLE:
			_finish_walk(unit)


## Olha para a direção geral da caminhada: o zigue-zague das casas não faz o herói virar.
func _steer(view, walk: Dictionary, moved: Vector2, delta: float) -> void:
	walk["heading"] = walk["heading"].lerp(moved, 1.0 - exp(-delta * FACE_FOLLOW))
	walk["face_wait"] -= delta
	if walk["face_wait"] > 0.0 or walk["heading"].length() < 0.01:
		return
	var seen: Vector2 = walk["heading"].rotated(battle.view_angle)
	var was: Array = [view.sprite.flip_h, view.facing]
	var vertical: bool = absf(seen.y) > absf(seen.x) * (FACE_KEEP if view.facing != view.Facing.SIDE else FACE_TURN)
	var sideways: bool = absf(seen.x) > absf(seen.y) * FACE_SIDE_FLIP
	if vertical:
		view.facing = view.Facing.SOUTH if seen.y > 0 else view.Facing.NORTH
	else:
		view.facing = view.Facing.SIDE
	if sideways or not vertical:
		view.face_right(seen.x > 0)
	if [view.sprite.flip_h, view.facing] != was:
		walk["face_wait"] = FACE_HOLD


func _finish_walk(unit) -> void:
	battle.walks.erase(unit)
	battle.moving.erase(unit)
	var view = battle.views[unit]
	view.set_walking(false)
	view.position = battle.feet_of(unit.pos)
	view.z_index = battle._z(battle._row(unit.pos)) + 5
	battle.battle_camera.set_elevation(battle._cell_elevation(unit.pos), view)
	battle.overlays_dirty = true


## Rota do herói até a casa; se não dá para chegar nela, até a casa alcançável mais próxima.
func _route(hero, target: Vector2i, found: Dictionary) -> Array:
	var goal := target
	if not found["cost"].has(goal):
		var nearest := Hex.distance(hero.pos, target)
		goal = hero.pos
		for cell in found["cost"]:
			var distance := Hex.distance(cell, target)
			if distance < nearest:
				nearest = distance
				goal = cell
	return battle.state.straight_path(found, hero.pos, goal)


func _roam_path(target: Vector2i) -> Array:
	var hero = battle._actor()
	if battle.roam_from != hero.pos or battle.roam_for != hero:
		battle.roam_search = battle.state.search(hero)
		battle.roam_from = hero.pos
		battle.roam_for = hero
	return _route(hero, target, battle.roam_search)


## Manda o herói selecionado até a casa; em fila, os outros heróis do jogador vão atrás dele.
func _travel(target: Vector2i) -> void:
	var hero = battle._actor()
	battle.input_ctl._close_menu()
	if not battle.online_session.can_control(hero):
		return
	var followers := []
	if battle.together:
		followers = battle.state.alive_party().filter(func(u): return u != hero and battle.online_session.can_control(u))
		followers.sort_custom(func(a, b): return Hex.distance(a.pos, hero.pos) < Hex.distance(b.pos, hero.pos))
	if battle.online_session.playing:
		battle.net_bridge._submit_online("travel", target, "", hero, followers)
	else:
		_start_file(hero, followers, target)
	battle.hover = battle.NO_CELL
	battle.marks_ctl._refresh_overlays()


func _stop_selected() -> void:
	if battle.online_session.playing:
		battle.net_bridge._submit_online("stop", battle._actor().pos, "", battle._actor())
	else:
		_end_chain(battle._actor())


## Cada seguidor primeiro alcança quem está à frente; depois, pisa nas casas que ele deixa.
func _start_file(leader, followers: Array, target: Vector2i) -> void:
	for member in [leader] + followers:
		_end_walk(member)
		battle.file_next.erase(member)
		for ahead in battle.file_next.keys():
			if battle.file_next[ahead] == member:
				battle.file_next.erase(ahead)
	var path := _route(leader, target, battle.state.search(leader))
	if path.is_empty():
		return
	battle.walk_paths[leader] = path
	battle.walk_goals[leader] = target
	var ahead = leader
	for member in followers:
		battle.file_next[ahead] = member
		var trail := _route(member, ahead.pos, battle.state.search(member))
		if not trail.is_empty():
			battle.walk_paths[member] = trail
		ahead = member


func _end_walk(hero) -> void:
	battle.walk_paths.erase(hero)
	battle.walk_goals.erase(hero)
	battle.file_blocked.erase(hero)


## Para o herói e quem vem atrás dele.
func _end_chain(hero) -> void:
	var member = hero
	while member != null:
		_end_walk(member)
		member = battle.file_next.get(member)


## Cada herói dá o próximo passo quando termina o anterior. Só quem simula anda aqui.
func _roam_tick(delta: float) -> void:
	if battle.online_session.playing and not battle.online_session.relay.is_master:
		return
	for hero in battle.step_wait.keys():
		battle.step_wait[hero] -= delta
	if battle.walk_paths.is_empty() or battle.busy:
		return
	if not battle._free_roam():
		_clear_walks()
		return
	for hero in battle.walk_paths.keys():
		if battle.walk_paths.has(hero) and battle.step_wait.get(hero, 0.0) <= 0.0:
			_roam_step(hero)
			if battle.busy:
				return


func _clear_walks() -> void:
	battle.walk_paths.clear()
	battle.walk_goals.clear()
	battle.file_next.clear()
	battle.file_blocked.clear()


func _roam_step(hero) -> void:
	var path: Array = battle.walk_paths[hero]
	if not hero.alive() or path.is_empty():
		_end_walk(hero)
		return
	var cell: Vector2i = path[0]
	if battle.walk_goals.has(hero):
		# Quem puxa a fila não fica preso aos que vêm atrás; sozinho, respeita o limite da party.
		if not battle.file_next.has(hero) and not battle.state.may_roam(hero, cell):
			_end_walk(hero)
			return
		if not battle.state.can_step(hero, cell): # alguém entrou na frente: tenta outra rota, uma vez
			var detour := _route(hero, battle.walk_goals[hero], battle.state.search(hero))
			if detour.is_empty() or not battle.state.can_step(hero, detour[0]):
				_end_walk(hero)
				return
			path = detour
			battle.walk_paths[hero] = path
			cell = path[0]
	elif not battle.state.can_step(hero, cell):
		# Seguidor: quem está na frente logo sai. Se não sair, ele para e espera a próxima ordem.
		battle.file_blocked[hero] = battle.file_blocked.get(hero, 0.0) + FILE_RETRY
		battle.step_wait[hero] = FILE_RETRY
		if battle.file_blocked[hero] > FILE_PATIENCE:
			_end_walk(hero)
		return
	battle.file_blocked.erase(hero)
	path.pop_front()
	if path.is_empty():
		_end_walk(hero)
	var from: Vector2i = hero.pos
	# Atrasado na fila, o seguidor acelera até colar em quem está à frente.
	var late: int = path.size() if not battle.walk_goals.has(hero) else 0
	var wait: float = battle.WALK_STEP / (1.0 + CATCH_UP * late)
	battle.step_wait[hero] = wait
	var events: Array = battle.state.do_step(hero, cell)
	for event in events:
		if event["type"] == "move":
			event["duration"] = wait
	var behind = null
	if battle.file_next.has(hero) and battle.file_next[hero].alive():
		behind = battle.file_next[hero]
		if not battle.walk_paths.has(behind):
			battle.walk_paths[behind] = []
		battle.walk_paths[behind].append(from)
	events.append_array(battle.state.tick())
	var fight := events.any(func(e): return e["type"] == "combat_start")
	if fight:
		_clear_walks()
		battle.busy = true
		battle.input_ctl._close_menu()
		battle.hud.set_hint("")
	await battle.event_player._play(events, true)
	battle.journey_ui._update_journey()
	if fight:
		battle.marks_ctl._refresh_overlays()
		await battle.get_tree().create_timer(battle.DEPLOY_TIME).timeout
		battle._advance()
	elif behind != null and battle.walk_paths.has(behind) and battle.step_wait.get(behind, 0.0) <= 0.0:
		_roam_step(behind) # quem está na fila pisa junto: a distância entre eles não muda
