extends RefCounted

## Textos e telas da jornada e da expedição: objetivo, bússola, missão, poção e resultado.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const TownContent = preload("res://scripts/town_content.gd")
const BattleCamera = preload("res://scripts/battle_camera.gd")
const Skills = preload("res://scripts/skill_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

const COMPASS_ARROWS := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
const DANGER_HOT := Color(1.0, 0.42, 0.32)
const CAMP_ICONS := {"camp": "tent", "garden": "ruin", "shrine": "candle", "crossing": "house"}
const LANDMARK_ICONS := {"vila": "house", "ruina": "ruin", "emboscada": "ruin", "fonte": "drop", "memoria": "star", "bau": "chest", "lanterna": "lantern"}
const DANGER_CALM := Color(0.62, 0.9, 0.55)

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


func _update_journey() -> void:
	if battle.town:
		battle.town_mode._update_town()
		return
	battle.hud.show_overview(not battle.state.in_combat())
	var danger: int = battle.state.danger()
	var heat := clampf((danger - 1) / 5.0, 0.0, 1.0)
	var stats := [
		{"icon": "heart", "value": "%d/%d" % [battle.state.alive_party().size(), battle.state.party.size()], "label": "Heróis", "color": Color(1.0, 0.45, 0.45)},
		{"icon": "steps", "value": battle.state.farthest, "label": "Distância", "color": Color(0.8, 0.72, 0.58)},
		{"icon": "skull", "value": battle.state.kills, "label": "Abates", "color": Color(0.9, 0.9, 0.86)},
		{"icon": "warning", "value": danger, "label": "Perigo", "color": DANGER_CALM.lerp(DANGER_HOT, heat), "ink": DANGER_CALM.lerp(DANGER_HOT, heat)},
	]
	var title: String = Data.BIOMES[battle.state.biome_at(battle.camera_cell)]["name"]
	if not battle.expedition:
		battle.hud.set_overview(title, stats)
		return
	stats.append({"icon": "flame", "value": battle.state.brasas, "label": "Brasas", "color": Color(1.0, 0.68, 0.3)})
	stats.append({"icon": "star", "value": battle.state.level, "label": "Nível", "color": Color(1.0, 0.85, 0.35)})
	battle.hud.set_overview(title, stats, _level_info(), _compass_chips())
	battle.board_art.refresh_lantern_area()
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
		var awards: bool = not battle.online_session.playing or battle.online_session.relay.is_master # online: tudo no save do dono
		for unit in battle.state.units:
			if unit.team == Data.Team.PLAYER and awards:
				types.append(unit.type_id)
		battle._reward_fight() # abates da última luta (na arena, a luta toda)
		var xp_gain: int = gain * Skills.END_XP_PER_POINT
		var raised := HeroProgress.add_xp(types.filter(func(type_id): return Skills.has_tree(type_id)), xp_gain)
		battle._report_progress(types, xp_gain, raised)
		if xp_gain > 0 and (not types.is_empty() or not awards):
			note = "+%d XP para cada herói" % xp_gain
		if not raised.is_empty():
			note += "\nLevel up: %s" % ", ".join(raised.map(func(type_id): return Data.UNIT_TYPES[type_id]["name"]))
		battle._update_party_progress()
	for id in battle.quests_finished:
		note += "%sMissão cumprida: %s" % ["\n" if note != "" else "", TownContent.QUESTS[id]["title"]]
	battle.quests_finished = []
	if battle.expedition and won and battle.state.boss != null: # as últimas palavras do guardião
		var farewell: String = Exp.BOSS_FAREWELL.get(battle.state.boss.type_id, "")
		if farewell != "":
			note = farewell + ("\n\n" + note if note != "" else "")
	battle.hud.show_end(_end_text() if battle.exploring else ("Vitória!" if won else "Derrota"), note)


## Nível da expedição e quanto falta: a barra enche entre um nível e o próximo.
func _level_info() -> Dictionary:
	var left: int = battle.state.xp_to_next()
	if left < 0:
		return {"level": battle.state.level, "fraction": 1.0, "note": "máx."}
	var floor_xp: int = Exp.LEVEL_XP[battle.state.level - 1]
	var span: int = maxi(1, Exp.LEVEL_XP[battle.state.level] - floor_xp)
	return {"level": battle.state.level, "fraction": float(battle.state.xp - floor_xp) / span, "note": "faltam %d XP" % left}


## Farol, a próxima lanterna e o local aberto mais perto, no radar: só o ícone e a direção,
## já girada com a câmera. O farol só aparece depois da última lanterna (ou se a party o achou).
func _compass_chips() -> Array:
	var chips := []
	if battle.state.beacon_known():
		chips.append(_compass("Farol", battle.state.beacon_cell, "lighthouse", battle.BEACON_COLOR))
	var lantern: Variant = battle.state.next_lantern()
	if lantern != null:
		var target: Dictionary = battle.state.lantern_target(lantern)
		var label: String = battle.state.landmark_label(lantern)
		if target["radius"] > 0:
			label += " (área)"
		var chip := _compass(label, target["cell"], LANDMARK_ICONS["lanterna"], Exp.LANDMARKS["lanterna"]["color"])
		chip["spread"] = _area_spread(target["cell"], target["radius"])
		chips.append(chip)
	var open: Array = battle.state.open_landmarks(battle.camera_cell)
	var fort = battle.state.fort
	if not fort.cells.is_empty() and battle.state.landmarks[fort.center]["state"] != "done":
		chips.append(_compass("Forte da Vigília", fort.center, "shield", Exp.LANDMARKS["forte"]["color"]))
		open.erase(fort.center)
	if not open.is_empty() and (battle.state.far_compass or Hex.distance(open[0], battle.camera_cell) <= Exp.COMPASS_RADIUS or battle.state.lit_near(open[0])):
		var cell: Vector2i = open[0]
		var icon := "tent"
		var color := Color(0.85, 0.7, 0.5)
		if battle.state.camps.centers.has(cell):
			icon = CAMP_ICONS.get(battle.state.camps.sites.get(cell, ""), "tent")
		elif battle.state.landmarks.has(cell):
			var kind: String = battle.state.landmarks[cell]["kind"]
			icon = LANDMARK_ICONS.get(kind, "star")
			color = Exp.LANDMARKS[kind]["color"]
		chips.append(_compass(battle.state.landmark_label(cell), cell, icon, color))
	return chips


func _compass(label: String, cell: Vector2i, icon: String, color: Color) -> Dictionary:
	var away: Vector2 = (battle.board_art._flat_point(cell) - battle.board_art._flat_point(battle.camera_cell)).rotated(battle.view_angle)
	return {"label": label, "icon": icon, "color": color, "angle": Vector2(away.x, away.y * BattleCamera.GROUND_TILT).angle()}


## Quanto do radar a área cobre, em radianos para cada lado: perto, a faixa abre;
## dentro da área, o radar todo acende. 0 = ponto exato.
func _area_spread(cell: Vector2i, radius: int) -> float:
	if radius <= 0:
		return 0.0
	var away := Hex.distance(cell, battle.camera_cell)
	if away <= radius:
		return PI
	return asin(float(radius) / away)


## A primeira missão aceita, somando o que a expedição já fez por ela.
func _quest_tracker() -> String:
	var result: Dictionary = battle.state.result()
	for id in TownProgress.quests_with("active"):
		var quest: Dictionary = TownContent.QUESTS[id]
		var done: int = mini(TownProgress.quest_progress(id) + int(result["tally"].get(quest["count"], 0)), quest["target"])
		return "Missão: %s (%d/%d)" % [quest["title"], done, quest["target"]]
	var fort = battle.state.fort
	if not fort.cells.is_empty() and battle.state.landmarks[fort.center]["state"] != "done":
		return "Escudo vermelho · Domine o Forte da Vigília"
	var lantern: Variant = battle.state.next_lantern()
	if lantern != null:
		return "Objetivo: acenda a lanterna %d de %d" % [battle.state.landmarks[lantern]["order"] + 1, Exp.LANTERNS.size()]
	return "Objetivo: %s" % TownContent.EXPEDITION_GOAL


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
