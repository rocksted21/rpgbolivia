extends RefCounted

## Cidade-Farol: monta a cidade, os nomes e marcas dos moradores e a partida.

const ExpeditionState = preload("res://scripts/expedition_state.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const TownPanels = preload("res://scripts/town_panels.gd")
const TownLife = preload("res://scripts/town_life.gd")
const TownData = preload("res://scripts/town_data.gd")

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


func _set_return_to_town() -> void:
	var root := battle.get_tree().root
	root.set_meta(battle.TOWN_META, true)
	root.set_meta(battle.EXPEDITION_META, false)


func _setup_town() -> void:
	battle.town_panels = TownPanels.new()
	battle.town_panels.z_index = battle.TOWN_PANELS_LAYER # por cima das linhas do topo, criadas depois
	battle.hud.add_child(battle.town_panels)
	battle.town_panels.setup(_party_types())
	battle.town_panels.depart.connect(_depart)
	battle.town_panels.skills_requested.connect(func(): battle.get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	battle.town_panels.menu_requested.connect(battle._back_to_menu)
	battle.town_panels.changed.connect(_town_changed)
	battle.town_life = TownLife.new()
	battle.add_child(battle.town_life)
	battle.town_life.setup(battle)


func _town_changed() -> void:
	battle.town_panels.refresh()
	_update_town()
	for cell in battle.person_labels:
		_show_person_mark(cell)


func _party_types() -> Array:
	return battle.state.party.map(func(unit): return unit.type_id)


func _depart(party_types: Array) -> void:
	if battle.online_session.playing: # online: a party é a da sala; só o dono decide a partida
		if battle.online_session.relay.is_master:
			battle.online_session.relocate(ExpeditionState.new(_party_types(), randi(), battle.online_session.match_builds(), TownProgress.expedition_setup()))
		else:
			battle.hud.show_banner("Só o dono da sala pode partir.", battle.LEVEL_INK)
		return
	var root := battle.get_tree().root
	root.set_meta("world_hero", party_types)
	root.set_meta(battle.TOWN_META, false)
	root.set_meta(battle.EXPEDITION_META, true)
	battle.online_session.leave()
	battle._start_battle()


func _update_town() -> void:
	var saved: Array = TownProgress.rescued()
	var people: int = TownData.BASE_PEOPLE + saved.size() * TownData.PEOPLE_PER_RESCUE + TownProgress.beacons() * TownData.PEOPLE_PER_BEACON
	var city_level: int = 1 + saved.size() + TownProgress.beacons()
	battle.hud.set_overview("Cidade-Farol", [
		{"icon": "heart", "value": "%d/%d" % [battle.state.alive_party().size(), battle.state.party.size()], "label": "Heróis", "color": Color(1.0, 0.45, 0.45)},
		{"icon": "people", "value": people, "label": "Habitantes", "color": Color(0.7, 0.82, 1.0)},
		{"icon": "flame", "value": TownProgress.brasas(), "label": "Brasas", "color": Color(1.0, 0.68, 0.3)},
		{"icon": "star", "value": TownProgress.beacons(), "label": "Faróis", "color": Color(1.0, 0.85, 0.35)},
	], {"level": city_level, "fraction": -1.0, "name": "Cidade"})
	battle.hud.update_party(battle.selected)


## Nome de quem mora aqui, com o aviso de que dá para conversar.
func _add_person_name(cell: Vector2i, row: int) -> void:
	if not battle.state.people.has(cell) or not battle.state.is_present(battle.state.people[cell]):
		return
	var name_label := Label.new()
	name_label.position = battle.feet_of(cell) + Vector2(-140, -176)
	name_label.custom_minimum_size = Vector2(280, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.z_index = battle._z(row) + 7
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 8)
	battle.board.add_child(name_label)
	battle.building.append(name_label)
	battle.battle_camera.add_billboard(name_label, Vector2(140, 176), battle._cell_elevation(cell))
	battle.person_labels[cell] = name_label
	_show_person_mark(cell)


## "!" tem pedido novo, "?" tem missão para entregar. Sem nada, só o nome.
func _show_person_mark(cell: Vector2i) -> void:
	var name_label = battle.person_labels[cell]
	if not is_instance_valid(name_label): # a casa saiu de perto e será refeita ao voltar
		return
	var person: Dictionary = battle.state.people[cell]
	var mark: String = TownProgress.person_mark(person["id"])
	name_label.text = "%s %s" % [mark, person["name"]] if mark != "" else person["name"]
	var color: Color = Color("9fe39a") if mark == "?" else (battle.BEACON_COLOR if mark == "!" else Color(0.92, 0.9, 0.82))
	name_label.add_theme_color_override("font_color", color)
