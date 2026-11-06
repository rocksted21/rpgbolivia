extends RefCounted

## Entrada do combate e da exploração: cliques, teclas, o menu de ações da casa,
## a ficha da unidade e a troca de herói.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Skills = preload("res://scripts/skill_data.gd")

const DRAG_START := 14.0 # pixels antes de o toque virar arrasto da câmera
const TWIST_START := 0.08 # radianos de torção com dois dedos antes de girar
const PINCH_IN := 1.3 # abrir os dedos nessa proporção aproxima; fechar o inverso afasta
const TURN_DRAG := 0.007 # radianos por pixel ao arrastar com o botão do meio
const ABILITY_ICONS := {
	"golpe": "sword", "rapido": "sword", "giro": "sword", "golpe_pesado": "sword", "estocada": "sword", "adaga": "sword", "coronhada": "sword",
	"tiro": "arrow", "virote_pesado": "arrow", "tiro_longo": "arrow", "perfurante": "arrow", "tiro_rapido": "arrow", "saraivada": "arrow", "chuva_virotes": "arrow",
	"cura": "heart", "clareira": "heart", "agua_vital": "heart",
	"guarda": "shield", "escudo_fogo": "shield", "provocar": "shield", "aparar": "shield", "casca": "shield", "manto_agua": "shield",
	"escudada": "shield", "interpor": "shield", "carga": "bolt", "marcar": "sword", "investida": "bolt", "sangria": "heart", "chute": "sword",
	"virote_marcador": "arrow", "tiro_perna": "arrow", "espinhos_venenosos": "star", "bencao": "star",
} # o resto das magias usa o ícone do elemento

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


func _on_timeline_pick(unit) -> void:
	if battle.busy or not unit.alive():
		return
	_close_menu()
	battle.pinned = null if battle.pinned == unit else unit
	battle.marks_ctl._refresh_overlays()
	battle.marks_ctl._update_hint()
	battle.sound_manager.play_ui(&"switch3")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_handle_touch(event)
		return
	# Arrastar com o botão do meio gira a câmera, inclusive na vez dos inimigos.
	if battle.exploring and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		battle._set_view_angle(battle.view_angle + event.relative.x * TURN_DRAG)
		return
	# Com zoom, arrastar a partir de uma casa sem inimigo move a câmera (mouse e um dedo).
	if event is InputEventMouseMotion and battle.pressing and battle.drag_ok and battle.gesture.is_empty():
		if not battle.dragging and event.position.distance_to(battle.press_pos) > DRAG_START:
			battle.dragging = true
			battle.press_token += 1 # não abre o cartão de quem estava embaixo do dedo
		if battle.dragging:
			battle._pan_by(event.relative)
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z:
		battle._set_zoomed(not battle.zoomed)
		return
	if event is InputEventMouseButton:
		_handle_button(event)
		return
	if battle.busy:
		return
	if event is InputEventMouseMotion:
		# Toque vira mouse emulado; sem este filtro ele deixaria um "hover" preso.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var cell := battle._pick_cell(event.position)
		if cell != battle.hover:
			battle.hover = cell
			if battle.state.unit_at(cell) != null:
				battle.pinned = null # passar o mouse por outro personagem troca o foco
			battle.marks_ctl._refresh_overlays()
			battle.marks_ctl._update_hint()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if battle.menu_cell != battle.NO_CELL or not battle._free_roam():
				_close_menu()
			else:
				battle.roam_ctl._stop_selected()
		elif battle._free_roam() and event.keycode == KEY_TAB:
			_select_next()
		elif battle._free_roam() and event.keycode == KEY_G:
			battle.hud.set_together(not battle.together)
		elif event.keycode == KEY_SPACE:
			_end_turn()
		elif event.keycode >= KEY_1 and event.keycode < KEY_1 + battle.menu_options.size():
			_on_option_pressed(event.keycode - KEY_1)


## Dois dedos: torcer gira a câmera (fora da arena), abrir ou fechar muda o zoom.
## Um dedo só chega também como mouse emulado e cai no arrasto normal.
func _handle_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			battle.touches[event.index] = event.position
		else:
			battle.touches.erase(event.index)
		if battle.touches.size() == 2:
			battle.pressing = false # o primeiro dedo não vale mais como toque
			battle.dragging = false
			battle.press_token += 1
			var start: Array = battle.touches.values()
			battle.gesture = {"angle": (start[1] - start[0]).angle(), "distance": maxf(1.0, start[0].distance_to(start[1])), "turning": false, "pinched": false}
		elif battle.touches.size() < 2:
			battle.gesture = {}
		return
	battle.touches[event.index] = event.position
	if battle.touches.size() != 2 or battle.gesture.is_empty():
		return
	var points: Array = battle.touches.values()
	var angle: float = (points[1] - points[0]).angle()
	var twist := angle_difference(battle.gesture["angle"], angle)
	if battle.exploring and (battle.gesture["turning"] or absf(twist) > TWIST_START):
		battle.gesture["turning"] = true
		battle.gesture["angle"] = angle
		battle._set_view_angle(battle.view_angle + twist)
	if not battle.gesture["pinched"]:
		var ratio: float = points[0].distance_to(points[1]) / battle.gesture["distance"]
		if ratio > PINCH_IN or ratio < 1.0 / PINCH_IN:
			battle.gesture["pinched"] = true
			battle._set_zoomed(ratio > 1.0)


func _end_turn() -> void:
	if battle.busy or battle._free_roam():
		return
	if battle.online_session.playing:
		battle.net_bridge._submit_online("wait", battle.NO_CELL)
	else:
		battle._perform(battle.state.do_wait(battle.state.active_unit()))


## O botão só aparece quando é a vez de alguém que este jogador controla.
func _refresh_end_turn() -> void:
	var unit = battle.state.active_unit()
	var mine: bool = not battle.busy and battle.state.winner() < 0 and not battle._free_roam() and unit != null and unit.team == Data.Team.PLAYER and battle.online_session.can_control(unit)
	battle.hud.show_end_turn(mine)
	battle.hud.show_jump(mine and (battle.jump_mode or not battle.state.jump_cells(unit).is_empty()), battle.jump_mode)


# O toque vira clique ao soltar, para dar tempo de saber se a pessoa está segurando.
# Segurar num personagem (ou o botão direito) abre o cartão dele, até no turno inimigo.
func _handle_button(event: InputEventMouseButton) -> void:
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		battle._set_zoomed(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		return
	var cell := battle._pick_cell(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if battle.state.unit_at(cell) != null:
			_show_card(battle.state.unit_at(cell))
		elif not battle.busy:
			_close_menu()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		battle.press_token += 1
		if event.pressed:
			battle.pressing = true
			battle.press_cell = cell
			battle.press_pos = event.position
			battle.dragging = false
			var occupant = battle.state.unit_at(cell)
			battle.drag_ok = battle.zoomed and (occupant == null or occupant.team != Data.Team.ENEMY)
			if battle.state.unit_at(cell) != null:
				var token := battle.press_token
				battle.get_tree().create_timer(battle.HOLD_TIME).timeout.connect(func(): _on_hold(token))
		elif battle.pressing:
			battle.pressing = false
			if battle.dragging:
				battle.dragging = false
			elif not battle.busy:
				_click(battle.press_cell)


func _on_hold(token: int) -> void:
	if token != battle.press_token or not battle.pressing:
		return
	battle.pressing = false # o soltar depois do cartão não vale como toque
	var unit = battle.state.unit_at(battle.press_cell)
	if unit != null:
		_show_card(unit)


func _show_card(unit) -> void:
	var order: int = battle.state.turn_order().find(unit) + 1
	var info := {
		"title": unit.display_name,
		"team": unit.team,
		"type_id": unit.type_id,
		"hp": unit.hp,
		"max_hp": unit.max_hp,
		"order": order,
		"atk": unit.atk,
		"def": unit.def,
		"speed": unit.speed,
		"abilities": unit.abilities.map(func(id): return _card_ability(unit, id)),
	}
	if not unit.pending.is_empty():
		var ability: Dictionary = unit.ability(unit.pending["ability"])
		var radius: int = ability["radius"]
		info["spell"] = {
			"name": ability["name"],
			"radius": radius,
			"cells": 1 + 3 * radius * (radius + 1),
			"power": roundi(unit.atk * ability["power"]),
			"actions": battle.state.actions_until(unit),
			"secret": unit.team != Data.Team.PLAYER,
		}
	battle.hud.show_card(info)


# Magias sem ícone próprio usam o do elemento: a pasta do efeito (fogo/, agua/).
func _spell_icon(id: String) -> String:
	if not battle.SPELL_FX.has(id):
		return "star"
	return "drop" if battle.SPELL_FX[id]["impact"].begins_with("agua/") else "flame"


## Dados de uma habilidade para a ficha: alcance, efeito, tempo e quanto tiraria do herói da vez.
func _card_ability(unit, id: String) -> Dictionary:
	var ability: Dictionary = unit.ability(id)
	var out := {"name": ability["name"], "icon": ABILITY_ICONS.get(id, _spell_icon(id)), "time": battle.state.action_time(ability["time"], unit)}
	if ability["kind"] == "charge":
		out["time"] = "%d + %d" % [battle.state.cast_time_for(unit, id), battle.state.recovery_time_for(unit, id)]
		out["time_hint"] = "Conjuração + recuperação após o impacto"
	if ability["kind"] == "guard":
		out["range"] = ""
	elif ability["min_range"] > 1:
		out["range"] = "%d-%d" % [ability["min_range"], ability["range"]]
	else:
		out["range"] = str(ability["range"])
	match ability["kind"]:
		"heal":
			out["amount"] = "+%d" % ability["heal"]
			out["amount_icon"] = "heart"
		"guard":
			out["amount"] = "½ dano" if not unit.passives.has("guard_mult") else "%d%% dano" % roundi(unit.passives["guard_mult"] * 100)
			out["amount_icon"] = "shield"
		"buff":
			out["amount"] = "aliado"
			out["amount_icon"] = "heart"
		_:
			out["amount"] = str(roundi(unit.atk * ability["power"]))
			out["amount_icon"] = "star"
	out["effect"] = Data.effect_text(ability)
	var hero = battle._actor()
	if ability["kind"] == "attack" and hero.team == Data.Team.PLAYER and unit.team != Data.Team.PLAYER:
		out["hero_type"] = hero.type_id
		out["hero_amount"] = battle.state.preview_attack(unit, id, hero)["amount"]
	return out


# Mesmas regras para mouse e toque: casa vizinha livre anda na hora; qualquer outra
# casa abre o menu com o que dá para fazer nela. Nada acontece sem tocar numa opção.
func _click(cell: Vector2i) -> void:
	if battle.pinned != null:
		battle.pinned = null
		battle.marks_ctl._refresh_overlays()
		battle.marks_ctl._update_hint()
	if battle.menu_cell != battle.NO_CELL:
		var other_unit: bool = cell != battle.menu_cell and cell != battle.NO_CELL and battle.state.unit_at(cell) != null
		_close_menu() # tocar fora só fecha, para não andar sem querer
		if not other_unit:
			return
	if cell == battle.NO_CELL:
		return
	if battle._free_roam():
		var occupant = battle.state.unit_at(cell)
		if occupant == null:
			battle.roam_ctl._travel(cell)
		elif battle.state.is_hero(occupant) and battle.online_session.can_control(occupant) and occupant != battle.selected:
			_select(occupant)
		else:
			_open_menu(cell)
		return
	var unit = battle._actor()
	# Casa verde pula na hora: no modo pulo, qualquer uma; fora dele, as que andando não dá.
	if battle.state.jump_cells(unit).has(cell) and (battle.jump_mode or not _can_walk_to(unit, cell)):
		_jump(unit, cell)
		return
	if battle.jump_mode:
		_set_jump_mode(false)
	# Se alguma ação mira essa casa, o menu pergunta: assim dá para mirar no chão
	# onde o inimigo ainda vai pisar sem o herói sair andando.
	var aimable := _cell_options(cell).any(func(option): return option["kind"] == "ability")
	# Casa do alcance anda na hora, pelo caminho inteiro.
	if _can_walk_to(unit, cell) and not aimable:
		if battle.online_session.playing:
			battle.net_bridge._submit_online("step", cell)
		else:
			battle._perform(battle.state.do_move(unit, cell))
		return
	_open_menu(cell)


func _jump(unit, cell: Vector2i) -> void:
	if battle.online_session.playing:
		battle.jump_mode = false
		battle.net_bridge._submit_online("jump", cell)
	else:
		battle._perform(battle.state.do_jump(unit, cell))


func _set_jump_mode(on: bool) -> void:
	if on and (battle.busy or battle._free_roam() or battle.state.jump_cells(battle._actor()).is_empty()):
		battle.hud.set_hint("Sem movimento para pular agora (o pulo gasta %d casas)." % (Data.JUMP_TIME / Data.STEP_TIME))
		return
	battle.jump_mode = on
	_close_menu()
	_refresh_end_turn()
	battle.marks_ctl._refresh_overlays()
	battle.marks_ctl._update_hint()


func _can_walk_to(unit, cell: Vector2i) -> bool:
	return battle.state.unit_at(cell) == null and battle.state.move_cells(unit).has(cell)


## O que muda para o herói se ele for para essa casa, em frases curtas.
func _terrain_notes(unit, cell: Vector2i) -> Array:
	var notes := []
	var tile: Dictionary = battle.state.tile_at(cell)
	if tile["damage"] < 1.0:
		notes.append("Aqui você leva %d%% menos dano" % roundi((1.0 - tile["damage"]) * 100))
	var climb: int = battle.state.elevation_at(cell) - battle.state.elevation_at(unit.pos)
	var percent := roundi(Data.HEIGHT_MULT_PER_LEVEL * 100)
	if climb > 0:
		notes.append("Mais alto: +%d%% de dano em quem está abaixo" % (percent * climb))
	elif climb < 0:
		notes.append("Mais baixo: −%d%% de dano em quem está acima" % (percent * -climb))
	return notes


func _open_menu(cell: Vector2i) -> void:
	var occupant = battle.state.unit_at(cell)
	var options := _cell_options(cell)
	if options.is_empty() and occupant == null:
		return
	battle.menu_cell = cell
	battle.menu_options = options
	# Sem ações, um menu só cobriria o alcance que a pessoa quer ver: a informação vai na dica.
	if not options.is_empty():
		var title: String = occupant.display_name if occupant != null else battle.state.tile_name_at(cell)
		var info: String = "" if occupant != null else "\n".join(_terrain_notes(battle._actor(), cell))
		battle.hud.show_menu(battle.cell_to_screen(cell), title, occupant.team if occupant != null else -1, info, options, battle._menu_status(occupant))
	# A fila mostra onde a magia seria solta, antes de confirmar.
	var spell := battle.marks_ctl._menu_spell()
	if spell != "":
		var unit = battle._actor()
		battle.hud.preview_cast(battle.state, unit, battle.state.cast_time_for(unit, spell))
	battle.marks_ctl._refresh_overlays()
	battle.marks_ctl._update_hint()


func _close_menu() -> void:
	if battle.menu_cell == battle.NO_CELL:
		return
	battle.menu_cell = battle.NO_CELL
	battle.menu_options = []
	battle.hud.hide_menu()
	battle.hud.preview_cast(battle.state, null, 0)
	battle.marks_ctl._refresh_overlays()
	battle.marks_ctl._update_hint()


func _cell_options(cell: Vector2i) -> Array:
	var unit = battle._actor()
	var options := []
	for id in unit.abilities:
		if battle.state.valid_targets(unit, id).has(cell):
			var option := _ability_option(unit, id, cell)
			option["kind"] = "ability"
			option["id"] = id
			option["label"] = Data.ABILITIES[id]["name"]
			options.append(option)
	if battle.state.unit_at(cell) != null:
		options.append_array(_blocked_options(unit, battle.state.unit_at(cell)))
		if not battle._free_roam() and battle.state.unit_at(cell).team != unit.team and options.all(func(option): return option["kind"] == "blocked"):
			var spot: Vector2i = battle.state.approach_cell(unit, battle.state.unit_at(cell))
			if spot != battle.state.NO_MOVE:
				options.push_front({"kind": "approach", "cell": spot, "label": "Aproximar", "detail": "fica ao alcance"})
	if battle._free_roam():
		if cell != unit.pos:
			options.append({"kind": "travel", "label": "Ir até lá", "detail": "para ao ser visto"})
		options.append({"kind": "cancel", "label": "Cancelar", "detail": ""})
	elif cell == unit.pos:
		options.append({"kind": "wait", "label": "Encerrar turno", "detail": "passa a vez"})
	elif battle.state.unit_at(cell) == null:
		if _can_walk_to(unit, cell):
			options.append({"kind": "step", "label": "Andar", "detail": "até aqui"})
		if not options.is_empty():
			options.append({"kind": "cancel", "label": "Cancelar", "detail": ""})
	return options


func _ability_option(unit, id: String, cell: Vector2i) -> Dictionary:
	var ability: Dictionary = unit.ability(id)
	var target = battle.state.unit_at(cell)
	match ability["kind"]:
		"attack":
			var hit: Dictionary = battle.state.preview_attack(unit, id, target)
			var option := {"detail": battle.marks_ctl._preview_text(unit, id, target), "tone": "damage", "damage": hit["amount"], "flank": hit["flank"], "lethal": hit["amount"] >= target.hp}
			var effect := Data.effect_text(ability)
			if effect != "":
				option["note"] = effect
				option["note_icon"] = "star"
			return option
		"buff":
			return {"detail": Data.effect_text(ability), "tone": "heal"}
		"heal":
			var amount: int = mini(ability["heal"], target.max_hp - target.hp)
			var detail := "+%d" % amount
			return {"detail": detail + " e vizinhos" if ability.has("radius") else detail, "tone": "heal", "heal": amount}
		"guard":
			return {"detail": "atrai inimigos" if ability.has("taunt") else "reduz o dano"}
		_:
			return {"detail": _area_text(unit, battle.state.area_of(cell, ability["radius"])), "note": _cast_wait_text(battle.state.cast_wait(unit, id))}


## Magia carregada não sai na hora: diz quantas ações dos outros passam antes
## e quanto isso dá em rodadas (todo mundo agindo uma vez).
func _cast_wait_text(actions: int) -> String:
	if actions == 0:
		return "solta já na sua próxima vez"
	var others: int = battle.state.turn_order().size() - 1
	var rounds := ceili(float(actions) / maxi(1, others))
	return "solta após %d aç%s (~%d rodada%s)" % [actions, "ão" if actions == 1 else "ões", rounds, "" if rounds == 1 else "s"]


# A magia acerta todo mundo na área, então o menu avisa quantos aliados vão junto.
func _area_text(unit, cells: Array) -> String:
	var enemies := 0
	var allies := 0
	for cell in cells:
		var occupant = battle.state.unit_at(cell)
		if occupant != null:
			if occupant.team == unit.team:
				allies += 1
			else:
				enemies += 1
	var text := "%d inimigo%s" % [enemies, "" if enemies == 1 else "s"]
	if allies > 0:
		text += ", %d aliado%s" % [allies, "" if allies == 1 else "s"]
	return text


func _menu_info(occupant) -> String:
	if occupant == null:
		return ""
	if not battle.state.takes_turns(occupant):
		return "Vida %d/%d, ainda não viu você" % [occupant.hp, occupant.max_hp]
	return "Vida %d/%d, age em %dº" % [occupant.hp, occupant.max_hp, battle.state.turn_order().find(occupant) + 1]


func _on_option_pressed(index: int) -> void:
	if battle.busy or index < 0 or index >= battle.menu_options.size():
		return
	var option: Dictionary = battle.menu_options[index]
	if option.get("disabled", false):
		return
	var cell := battle.menu_cell
	var unit = battle._actor()
	if option["kind"] == "approach":
		cell = option["cell"]
		option = {"kind": "step"}
	if battle.online_session.playing and option["kind"] != "cancel" and option["kind"] != "travel" and option["kind"] != "jump_mode":
		battle.net_bridge._submit_online(option["kind"], cell, option.get("id", ""))
		return
	if option["kind"] == "jump_mode":
		_set_jump_mode(true)
		return
	match option["kind"]:
		"ability":
			battle._perform(battle.state.do_ability(unit, option["id"], cell))
		"wait":
			battle._perform(battle.state.do_wait(unit))
		"step":
			battle._perform(battle.state.do_move(unit, cell))
		"travel":
			battle.roam_ctl._travel(cell)
		"cancel":
			_close_menu()


func _select(unit) -> void:
	battle.selected = unit
	battle.roam_from = battle.NO_CELL
	battle._follow(unit)
	battle.marks_ctl._refresh_turn_markers()
	battle.marks_ctl._refresh_overlays()
	battle.marks_ctl._update_hint()
	battle.journey_ui._update_journey()


func _select_next() -> void:
	var mine: Array = battle.state.alive_party().filter(func(u): return battle.online_session.can_control(u))
	if mine.size() > 1:
		_select(mine[(mine.find(battle.selected) + 1) % mine.size()])


## Carta da party: só seleciona o herói (a árvore abre pelo selo LEVEL UP em cima dela).
func _on_party_pick(unit) -> void:
	if battle._free_roam() and unit.alive() and battle.online_session.can_control(unit):
		battle.sound_manager.play_ui(&"switch3")
		_select(unit)
	else:
		_on_timeline_pick(unit)


## Selo LEVEL UP em cima da carta: abre a árvore de talentos. Em combate, só depois dele.
func _on_level_up_pick(unit) -> void:
	if not battle.online_session.can_control(unit) or not Skills.has_tree(unit.type_id):
		return
	if not battle._free_roam():
		battle.hud.show_banner("Termine o combate para upar", battle.LEVEL_INK)
		return
	battle.sound_manager.play_ui(&"switch3")
	battle._open_tree(unit)


# Toda habilidade que serviria nesse alvo aparece; as que não dá para usar agora
# ficam apagadas dizendo o alcance que precisa (ou que a vida já está cheia).
func _blocked_options(unit, target) -> Array:
	var options := []
	var enemy: bool = target.team != unit.team
	for id in unit.abilities:
		var ability: Dictionary = unit.ability(id)
		var kind: String = ability["kind"]
		var fits: bool = (kind == "attack" and enemy) or kind == "charge" or ((kind == "heal" or kind == "buff") and not enemy) or (kind == "guard" and target == unit)
		if not fits or battle.state.valid_targets(unit, id).has(target.pos):
			continue
		var detail := _range_short(ability)
		if kind == "heal" and target.hp >= target.max_hp and Hex.distance(unit.pos, target.pos) <= ability["range"]:
			detail = "vida cheia"
		elif kind == "buff" and target == unit:
			detail = "só em aliado"
		elif ability.get("dash", false) and Hex.distance(unit.pos, target.pos) <= ability["range"] and Hex.distance(unit.pos, target.pos) >= ability["min_range"]:
			detail = "sem onde cair"
		options.append({"kind": "blocked", "id": id, "label": ability["name"], "detail": detail, "disabled": true})
	return options


func _range_short(ability: Dictionary) -> String:
	if ability["min_range"] > 1:
		return "de %d a %d casas" % [ability["min_range"], ability["range"]]
	return "só colado" if ability["range"] == 1 else "até %d casas" % ability["range"]
