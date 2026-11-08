extends RefCounted
## Desafios de Arena na tela. A party chega num local "desafio" da expedição, aceita a janela e a
## mesma cena troca de state: a expedição fica guardada aqui, `_start_battle` monta a arena
## (arena_state.gd, mapa de arena_data.gd) e, no fim, monta a expedição de volta no mesmo tile.
## Trocar o state na cena (e não de cena) mantém a expedição inteira em memória, sem save no meio.
## Salvar fica bloqueado durante o desafio (battle_view._save_game).

const Data = preload("res://scripts/game_data.gd")
const Arena = preload("res://scripts/arena_data.gd")
const ArenaState = preload("res://scripts/arena_state.gd")
const Brass = preload("res://scripts/hud/brass.gd")
const Icon = preload("res://scripts/icon.gd")
const HeroBag = preload("res://scripts/hero_bag.gd") # o prêmio garantido: a Chama Viva (HeroBag.ORB)

const SCREEN := Vector2(1280, 720) # a mesma tela lógica do hud.gd
const WINDOW_LAYER := 110
const FADE_LAYER := 120
const FADE_TIME := 0.45
const SETTLE_TIME := 0.35 # deixa terminar o que a caminhada ainda estava animando antes de trocar
const LOST_COLOR := Color(1.0, 0.45, 0.35)
const RECRUIT_COLOR := Color("7fb6ff")
const WINDOW_WIDTH := 620.0

var battle # a tela (battle_view.gd)
var active := false # a arena está na tela
var saved = null # a expedição guardada enquanto a arena roda
var cell := Vector2i.ZERO # o local do desafio
var arena = null # ArenaState em jogo
var swap := {} # o próximo _start_battle usa isto no lugar do menu/save
var rewards := [] # eventos da recompensa, tocados quando a party volta ao mapa
var angle := 0.0 # giro da câmera na expedição: a arena é vista de frente
var finishing := false
var window: CanvasLayer
var fade: CanvasLayer


func _init(host: Node) -> void:
	battle = host


## battle_view._start_battle: {state, exploring, expedition} para entrar ou voltar; {} = nada.
func take_swap() -> Dictionary:
	var out := swap
	swap = {}
	return out


# --- Entrada --------------------------------------------------------------------

## Evento "challenge" (arena_data.check_visit): a party chegou ao local. Pergunta se ela entra.
func offer(event: Dictionary) -> void:
	if active or window != null or battle.state.winner() >= 0:
		return
	var info: Dictionary = Arena.ARENAS.get(event.get("arena", ""), {})
	if info.is_empty():
		return
	if battle.online_session.playing:
		battle.hud.show_banner("Desafio: por enquanto só no modo solo", Arena.COLOR)
		return
	battle.roam_ctl._clear_walks() # a party para na entrada
	battle.sound_manager.play_sfx(&"charge")
	var column := _open_window(Arena.COLOR, true)
	column.add_child(_title("Desafio de Arena", 26, Brass.GOLD))
	column.add_child(_title(info["name"], 22, Arena.COLOR))
	column.add_child(_text(info["text"], 17, Brass.TEXT))
	column.add_child(_line("swords", Arena.COLOR, info["rule_text"]))
	column.add_child(_line("orb", HeroBag.ORB_COLOR, "Prêmio: " + Arena.reward_text(info, _prize_name())))
	if info.has("recruit"):
		column.add_child(_line("people_plus", RECRUIT_COLOR, "Se ele se render, o %s entra para o roster." % Data.UNIT_TYPES[info["recruit"]]["name"]))
	column.add_child(_text("A party entra com a vida de agora. Se perder, volta ao mapa com %d%% da vida e pode tentar de novo." % roundi(Arena.LOSS_HP * 100), 15, Brass.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var enter := _button(row, "Entrar no desafio", true)
	enter.pressed.connect(func(): _enter(event["cell"], event["arena"]))
	var later := _button(row, "Agora não")
	later.pressed.connect(_close_window)


func _enter(at: Vector2i, id: String) -> void:
	_close_window()
	if active or battle.state.in_combat() or battle.state.winner() >= 0:
		battle.hud.show_banner("Não dá para entrar no desafio agora", LOST_COLOR)
		return
	active = true
	finishing = false
	battle.busy = true
	battle.roam_ctl._clear_walks()
	await _fade_to(1.0)
	await battle.get_tree().create_timer(SETTLE_TIME).timeout
	saved = battle.state
	cell = at
	arena = ArenaState.new(id, saved.party, saved.danger())
	angle = battle.view_target
	battle.view_angle = 0.0
	battle.view_target = 0.0
	swap = {"state": arena, "exploring": false, "expedition": false}
	battle._start_battle()
	_dress_arena()
	await _fade_to(0.0)


## Arena montada: sem salvar, o líder com aura, aviso da regra e a faixa do objetivo no topo.
func _dress_arena() -> void:
	battle.hud.save_allowed = false
	if battle.has_node("Bloom"): # a arena original não tem bloom; o mapa recria o dele na volta
		battle.get_node("Bloom").queue_free()
	if arena.leader != null and battle.views.has(arena.leader):
		battle.views[arena.leader].set_elite(Arena.COLOR)
	var bar := Objective.new()
	bar.challenge = self
	battle.hud.add_child(bar) # some junto com o HUD quando a cena volta para o mapa
	if arena.rule == "blood":
		var pools := BloodPools.new()
		pools.challenge = self
		battle.board.add_child(pools) # some junto com o tabuleiro
	battle.hud.show_banner("Desafio: %s" % arena.info["name"], Arena.COLOR)
	battle.hud.show_detail(arena.info["rule_text"])


# --- Fim --------------------------------------------------------------------------

## battle_view._advance: a arena acabou. Experiência dos heróis, vida de volta e o prêmio.
func finish(result: int) -> void:
	if finishing or not active:
		return
	finishing = true
	battle.busy = true
	var won := result == Data.Team.PLAYER
	var info: Dictionary = arena.info
	await battle.get_tree().create_timer(0.6).timeout
	await battle._reward_fight(info["reward"]["hero_xp"] if won else 0) # XP dos heróis, no save
	_restore_heroes(won)
	var lines := []
	rewards = []
	if won:
		lines = _grant(info)
	else:
		lines.append("A party volta ao mapa com %d%% da vida." % roundi(Arena.LOSS_HP * 100))
		lines.append("O desafio continua lá: dá para tentar de novo.")
	_show_result(won, lines)


## A vida da arena volta para os heróis da expedição. Vitória: quem caiu levanta com um pouco.
## Derrota: todo mundo volta com LOSS_HP.
func _restore_heroes(won: bool) -> void:
	for copy in arena.heroes:
		var member = arena.heroes[copy]
		if not won:
			member.hp = maxi(1, roundi(member.max_hp * Arena.LOSS_HP))
		elif copy.alive():
			member.hp = mini(copy.hp, member.max_hp)
		else:
			member.hp = maxi(1, roundi(member.max_hp * Arena.WIN_REVIVE_HP))


## O prêmio vai direto para a expedição guardada; os eventos tocam quando o mapa voltar.
func _grant(info: Dictionary) -> Array:
	var reward: Dictionary = info["reward"]
	var events := []
	var lines := []
	var entry: Dictionary = saved.landmarks.get(cell, {})
	if not entry.is_empty():
		entry["state"] = "done"
		entry.erase("asked")
	saved.tally["challenges"] = saved.tally.get("challenges", 0) + 1
	saved.brasas += reward["brasas"]
	events.append({"type": "landmark", "cell": cell, "title": "Desafio vencido!", "detail": "%s · +%d brasas" % [info["name"], reward["brasas"]], "done": true, "color": Arena.COLOR})
	if info.has("recruit"): # o local "done" com "recruit" leva o herói ao roster (recruits.recruited)
		var hero_name: String = Data.UNIT_TYPES[info["recruit"]]["name"]
		entry["recruit"] = info["recruit"]
		events.append({"type": "landmark", "cell": cell, "title": "%s se junta à party!" % hero_name,
			"detail": "Ele se rendeu. Agora pode entrar na party, na Cidade-Farol.", "done": true, "color": RECRUIT_COLOR})
		lines.append("%s se junta à party!" % hero_name)
	if saved.has_method("grant_talent_orb"): # Chama Viva (expedition_state.gd / hero_bag.gd)
		var holder: String = saved.grant_talent_orb(events)
		if holder != "":
			lines.append("%s → %s" % [_prize_name(), Data.UNIT_TYPES[holder]["name"]])
		else:
			lines.append("%s perdida: as bolsas da party estão cheias" % _prize_name())
	lines.append("+%d brasas" % reward["brasas"])
	saved._gain_xp(reward["xp"], events)
	lines.append("+%d XP da expedição" % reward["xp"])
	if reward["hero_xp"] > 0:
		lines.append("+%d XP para cada herói de pé" % reward["hero_xp"])
	rewards = events
	return lines


func _show_result(won: bool, lines: Array) -> void:
	battle.sound_manager.play_sfx(&"victory" if won else &"defeat")
	var column := _open_window(Arena.COLOR if won else LOST_COLOR)
	column.add_child(_title("Desafio vencido!" if won else "Desafio perdido", 28, Brass.GOLD if won else LOST_COLOR))
	column.add_child(_title(arena.info["name"], 20, Arena.COLOR))
	for line in lines:
		var icon := "orb" if str(line).begins_with(_prize_name()) else ("swords" if won else "warning")
		if str(line).ends_with("party!"):
			icon = "people_plus"
		column.add_child(_line(icon, HeroBag.ORB_COLOR if icon == "orb" else (RECRUIT_COLOR if icon == "people_plus" else Arena.COLOR), line))
	var back := _button(column, "Voltar ao mapa", true)
	back.pressed.connect(_return)


func _return() -> void:
	if not active:
		return
	_close_window()
	await _fade_to(1.0)
	var events := rewards
	rewards = []
	swap = {"state": saved, "exploring": true, "expedition": true}
	active = false
	finishing = false
	saved = null
	arena = null
	battle._start_battle()
	if angle != 0.0:
		battle.view_target = angle
		battle._set_view_angle(angle)
	battle._update_party_progress()
	await _fade_to(0.0)
	if not events.is_empty() and battle.expedition:
		await battle.event_player._play(events)
		if battle.hud.has_method("refresh_bags"):
			battle.hud.refresh_bags()
		battle.journey_ui._update_journey()


# --- Janelas e transição -------------------------------------------------------------

func _open_window(edge: Color, dismissable := false) -> VBoxContainer:
	_close_window()
	window = CanvasLayer.new()
	window.layer = WINDOW_LAYER
	battle.add_child(window)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = SCREEN
	if dismissable:
		shade.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed:
				_close_window())
	window.add_child(shade)
	var center := CenterContainer.new()
	center.size = SCREEN
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = WINDOW_WIDTH
	panel.add_theme_stylebox_override("panel", Brass.panel(Brass.WINE, edge, 2, 6, 22, 4))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return column


func _close_window() -> void:
	if window != null:
		window.queue_free()
		window = null


## Tela preta por cima de tudo enquanto a cena troca (e trava os cliques no meio da troca).
func _fade_to(alpha: float) -> void:
	if fade == null:
		fade = CanvasLayer.new()
		fade.layer = FADE_LAYER
		var black := ColorRect.new()
		black.color = Color(0, 0, 0, 0)
		black.size = SCREEN
		fade.add_child(black)
		battle.add_child(fade)
	var cover: ColorRect = fade.get_child(0)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP if alpha > 0.0 else Control.MOUSE_FILTER_IGNORE
	var tween: Tween = battle.create_tween()
	tween.tween_property(cover, "color:a", alpha, FADE_TIME)
	await tween.finished


func _title(text: String, size: int, color: Color) -> Label:
	var label := Brass.label(text, size, color, 700)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _text(text: String, size: int, color: Color) -> Label:
	var label := Brass.label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WINDOW_WIDTH - 44
	return label


func _prize_name() -> String:
	return HeroBag.item_info(HeroBag.ORB)["name"]


## Linha com ícone. "orb" usa o sprite da Chama Viva (HeroBag.item_icon), como na bolsa.
func _line(kind: String, color: Color, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon: Control
	if kind == "orb":
		icon = HeroBag.item_icon(HeroBag.ORB, 28)
	else:
		var drawn := Icon.new()
		drawn.setup(kind, color, 28)
		icon = drawn
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var label := Brass.label(text, 17, Brass.TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WINDOW_WIDTH - 90
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _button(parent: Control, text: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 50
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Brass.style_button(button, primary)
	button.add_theme_font_size_override("font_size", 18)
	battle.sound_manager.bind_button(button, &"click3")
	parent.add_child(button)
	return button


## Duelo de sangue: as poças de arena_state.pools desenhadas no chão, acompanhando a regra.
class BloodPools extends Node:
	const POOL_COLOR := Color(0.62, 0.04, 0.08, 0.6)
	var challenge
	var marks := {} # casa -> Polygon2D

	func _process(_delta: float) -> void:
		var arena = challenge.arena
		if arena == null:
			return
		var battle = challenge.battle
		for cell in marks.keys():
			if not arena.pools.has(cell):
				marks[cell].queue_free()
				marks.erase(cell)
		for cell in arena.pools:
			if marks.has(cell):
				continue
			var pool := Polygon2D.new()
			pool.polygon = battle.hex_poly
			pool.color = POOL_COLOR
			battle._place_ground_marker(pool, cell)
			pool.z_index = battle._z(battle._row(cell)) + 1
			battle.board.add_child(pool)
			marks[cell] = pool


## Faixa no topo da arena: nome, regra e o andamento (rodada, reforços, vida do Campeão).
## Avisa "Reforços!" quando chega gente nova.
class Objective extends PanelContainer:
	const BrassUi = preload("res://scripts/hud/brass.gd")
	const ArenaInfo = preload("res://scripts/arena_data.gd")
	const WIDTH := 560.0
	const SCREEN_WIDTH := 1280.0
	var challenge
	var progress: Label
	var seen := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.x = WIDTH
		position = Vector2((SCREEN_WIDTH - WIDTH) / 2.0, 8)
		add_theme_stylebox_override("panel", BrassUi.panel(BrassUi.WINE, ArenaInfo.COLOR, 2, 4, 8, 2))
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 2)
		add_child(column)
		var info: Dictionary = challenge.arena.info
		var title := BrassUi.label("Desafio · %s" % info["name"], 17, ArenaInfo.COLOR, 700)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		progress = BrassUi.label("", 15, BrassUi.TEXT)
		progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(progress)
		for child in column.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seen = challenge.arena.arrivals

	func _process(_delta: float) -> void:
		var arena = challenge.arena
		if arena == null:
			return
		progress.text = arena.progress_text()
		if arena.arrivals != seen:
			seen = arena.arrivals
			challenge.battle.hud.show_banner("Reforços!", Color(1.0, 0.42, 0.3))
