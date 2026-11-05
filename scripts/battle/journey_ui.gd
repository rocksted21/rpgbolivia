extends RefCounted

## Textos e telas da jornada e da expedição: objetivo, bússola, missão, poção e resultado.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const TownContent = preload("res://scripts/town_content.gd")
const Skills = preload("res://scripts/skill_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

const COMPASS_ARROWS := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


func _update_journey() -> void:
	if battle.town:
		battle.town_mode._update_town()
		return
	battle.hud.set_journey(battle.state.alive_party().size(), battle.state.party.size(), battle.state.farthest, battle.state.kills, battle.state.danger(), Data.BIOMES[battle.state.biome_at(battle.camera_cell)]["name"])
	if battle.expedition:
		battle.hud.set_objective(_objective_text())
		battle.hud.set_tracker(_quest_tracker())
	battle.hud.update_party(battle.selected if battle._free_roam() else battle.state.active_unit())


## Fim de luta: dá os pontos e mostra o resultado. Online, só dos heróis deste jogador;
## na exploração, que só acaba com a queda, o ganho vem da distância e dos abates.
func _show_result(result: int) -> void:
	var won := result == Data.Team.PLAYER
	var note := ""
	battle.hud.save_allowed = false # a partida acabou: carregar ainda vale
	if battle.exploring: # a vida no topo da tela precisa mostrar a queda
		_update_journey()
	if not battle.rewarded:
		battle.rewarded = true
		var gain: int = Skills.WIN_POINTS if won else Skills.LOSS_POINTS
		if battle.exploring:
			gain = Skills.journey_points(battle.state.kills, battle.state.farthest)
		if battle.expedition:
			battle.quests_finished = TownProgress.record(battle.state.result())
			battle.town_mode._set_return_to_town()
			if won:
				battle.board_art._rebuild_cell(battle.state.beacon_cell) # o farol acende
		var types := []
		for unit in battle.state.units:
			if unit.team == Data.Team.PLAYER and (not battle.online_session.playing or battle.online_session.can_control(unit)):
				types.append(unit.type_id)
		var before := 0
		for type_id in types:
			before += HeroProgress.earned(type_id)
		var count := HeroProgress.award(types, gain)
		if count == 1: # perto do teto, o herói pode ganhar menos que o previsto
			var after := 0
			for type_id in types:
				after += HeroProgress.earned(type_id)
			gain = after - before
		if count > 0:
			note = "+%d %s de skill%s" % [gain, "pontos" if gain > 1 else "ponto", " para %d heróis" % count if count > 1 else ""]
	for id in battle.quests_finished:
		note += "%sMissão cumprida: %s" % ["\n" if note != "" else "", TownContent.QUESTS[id]["title"]]
	battle.quests_finished = []
	battle.hud.show_end(_end_text() if battle.exploring else ("Vitória!" if won else "Derrota"), note)


## Nível, brasas e para onde ir, com a seta já girada conforme a câmera.
func _objective_text() -> String:
	var growth := "máx." if battle.state.xp_to_next() < 0 else "%d XP" % battle.state.xp_to_next()
	var text := "Nível %d (%s)   ·   Brasas %d   ·   Farol %s" % [battle.state.level, growth, battle.state.brasas, _direction_to(battle.state.beacon_cell)]
	var open: Array = battle.state.open_landmarks(battle.camera_cell)
	if not open.is_empty() and (battle.state.far_compass or Hex.distance(open[0], battle.camera_cell) <= Exp.COMPASS_RADIUS):
		text += "   ·   %s %s" % [battle.state.landmark_label(open[0]), _direction_to(open[0])]
	return text


## A primeira missão aceita, somando o que a expedição já fez por ela.
func _quest_tracker() -> String:
	var result: Dictionary = battle.state.result()
	for id in TownProgress.quests_with("active"):
		var quest: Dictionary = TownContent.QUESTS[id]
		var done: int = mini(TownProgress.quest_progress(id) + int(result["tally"].get(quest["count"], 0)), quest["target"])
		return "Missão: %s (%d/%d)" % [quest["title"], done, quest["target"]]
	return ""


func _use_potion() -> void:
	if battle.state.winner() >= 0:
		return
	var events: Array = battle.state.use_potion()
	if events.is_empty():
		battle.hud.set_hint("A party está com a vida cheia.")
		return
	battle.sound_manager.play_sfx(&"heal")
	for event in events:
		battle.event_player._play_regen(event)
	battle.hud.set_potions(battle.state.potions)
	_update_journey()


func _direction_to(cell: Vector2i) -> String:
	var away: Vector2 = (battle.board_art._flat_point(cell) - battle.board_art._flat_point(battle.camera_cell)).rotated(battle.view_angle)
	var sector := posmod(roundi(away.angle() / (TAU / COMPASS_ARROWS.size())), COMPASS_ARROWS.size())
	return "%s %d" % [COMPASS_ARROWS[sector], Hex.distance(cell, battle.camera_cell)]


func _end_text() -> String:
	if battle.expedition:
		var saved: Dictionary = battle.state.result()
		var title: String = "O farol voltou a brilhar!" if saved["won"] else "A party caiu na escuridão"
		var kept := "%d brasas levadas" % saved["brasas"]
		return "%s\n%s · %d resgate%s · nível %d" % [title, kept, saved["rescued"].size(), "" if saved["rescued"].size() == 1 else "s", battle.state.level]
	return "Fim da jornada\n%d casas de distância · %d inimigos derrotados" % [battle.state.farthest, battle.state.kills]
