extends SceneTree
## Regras da Cidade-Farol, sem tela. Rodar: godot --headless --path . --script tests/test_town.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Town = preload("res://scripts/town_data.gd")
const TownState = preload("res://scripts/town_state.gd")
const Content = preload("res://scripts/town_content.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Expedition = preload("res://scripts/expedition_state.gd")
const Exp = preload("res://scripts/expedition_data.gd")

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	test_walking()
	test_art()
	test_growth()
	test_roads()
	test_content()
	test_shop()
	test_upgrades()
	test_quests()
	test_story()
	test_lights()
	DirAccess.remove_absolute(TownProgress.path)
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _new(rescued := []):
	return TownState.new(Data.DEFAULT_PARTY, 5, {}, {"rescued": rescued})


func _reachable(state) -> Dictionary:
	for member in state.party:
		member.pos = Vector2i(999, 999)
	var seen := {Town.plaza(): true}
	var frontier := [Town.plaza()]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_back()
		for next in Hex.neighbors(current):
			if seen.has(next) or not state.tile_at(next)["walkable"]:
				continue
			if absi(state.elevation_at(next) - state.elevation_at(current)) > 1:
				continue
			seen[next] = true
			frontier.append(next)
	return seen


func test_walking() -> void:
	var state = _new(["ferreiro", "curandeira"])
	check(state.tile_at(Town.plaza())["walkable"], "a praça é caminhável")
	for member in state.party:
		check(state.tile_at(member.pos)["walkable"], "%s começa em casa livre" % member.type_id)
	check(state.foes().is_empty() and state.tick().is_empty(), "a cidade não tem inimigos")
	check(state.winner() < 0, "a cidade não acaba")
	var seen := _reachable(state)
	check(seen.size() > 120, "a cidade é grande (%d casas)" % seen.size())
	for spot in [Vector2i(17, 8), Vector2i(9, 12), Vector2i(18, 24), Vector2i(27, 15)]:
		check(seen.has(spot), "as ruas levam ao farol, aos bairros e ao cais: %s" % spot)
	for spot in state.people:
		var near: Array = Hex.neighbors(spot).filter(func(cell): return seen.has(cell))
		check(not near.is_empty(), "dá para chegar até %s" % state.people[spot]["name"])
	for cell in seen:
		check(state.levels.has(cell), "o caminho não sai da ilha")
	check(not state.tile_at(Vector2i(200, 200))["walkable"], "em volta da cidade é água")


func test_art() -> void:
	var state = _new(["ferreiro", "curandeira"])
	var model_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/town/modelos/meta.json"))
	for model in Town.MODELS:
		check(model_meta.has(model), "%s tem desenho de todos os lados" % model)
		check(int(model_meta.get(model, {}).get("views", 0)) >= 8, "%s tem ângulos suficientes" % model)
	for cell in state.props:
		for prop in state.props[cell]:
			check(ResourceLoader.exists(prop["path"]), "arte existe: %s" % prop["path"])
	for cell in state.levels:
		for piece in state.ground_overlays(cell):
			check(ResourceLoader.exists(piece), "peça de piso existe: %s" % piece)
	var width: int = Town.map_rows()[0].length()
	for line in Town.map_rows():
		check(line.length() == width, "a planta é retangular")
	check(ResourceLoader.exists("res://assets/town/calcada.png"), "calçada existe")
	var cells := {}
	for building in Town.buildings():
		for cell in state._disc(building["cell"], building["radius"]):
			check(not cells.has(cell), "prédios não se sobrepõem em %s" % cell)
			cells[cell] = true
	for person in Town.people():
		check(not cells.has(person["cell"]), "%s fica fora dos prédios" % person["name"])


## Nenhum enfeite pode fechar uma rua ou o caminho de quem anda pela cidade.
func test_roads() -> void:
	var state = _new(["ferreiro", "curandeira"])
	var seen := _reachable(state)
	for cell in Town.road_cells():
		if state.levels.has(cell):
			check(seen.has(cell), "a rua continua aberta em %s" % cell)
	for cell in Town.walk_route():
		check(seen.has(cell), "quem passeia chega a %s" % cell)
	for art in Town.WALKER_ART:
		check(ResourceLoader.exists(Town.TOWN_ROOT % art), "arte de quem passeia: %s" % art)


func test_content() -> void:
	for person in Town.people():
		check(ResourceLoader.exists(Town.TOWN_ROOT % person["art"]), "%s tem arte" % person["name"])
		if person["service"] != "board":
			check(Content.TALK.has(person["id"]), "%s tem conversa" % person["name"])
	var ids: Array = Town.people().map(func(person): return person["id"])
	for id in Content.QUESTS:
		var quest: Dictionary = Content.QUESTS[id]
		check(id in Content.QUEST_ORDER, "%s está na ordem" % id)
		check(quest["giver"] in ids, "%s tem quem pediu" % id)
		for item in quest["reward"]["items"]:
			check(Content.ITEMS.has(item), "%s dá um item que existe" % id)
	for id in Content.ITEMS:
		check(id in Content.ITEM_ORDER and Content.ITEMS[id]["seller"] in ids, "%s tem quem venda" % id)


func _clean_save() -> void:
	TownProgress.path = "user://test_town_rules.cfg"
	DirAccess.remove_absolute(TownProgress.path)


func _give(brasas: int) -> void:
	TownProgress.record({"won": false, "brasas": brasas, "rescued": ["ferreiro", "curandeira"], "memories": 0})


func test_shop() -> void:
	_clean_save()
	check(not TownProgress.buy_item("pocao"), "sem brasas não compra")
	_give(60)
	check(TownProgress.buy_item("pocao") and TownProgress.brasas() == 52, "a loja cobra o preço")
	check(TownProgress.item_count("pocao") == 1, "o item vai para a mochila")
	check(TownProgress.buy_item("pedra") and not TownProgress.buy_item("pedra"), "o limite da mochila vale")
	check(TownProgress.buy_item("amuleto"), "compra o amuleto")
	var setup := TownProgress.expedition_setup()
	check(setup["atk"] == 2 and setup["potions"] == 1 and setup["brasa_bonus"] == 1, "os itens valem na expedição")
	var trip = Expedition.new(Data.DEFAULT_PARTY, 5, {}, setup)
	check(trip.potions == 1, "a poção vai junto")
	check(trip.use_potion().is_empty() and trip.potions == 1, "com a vida cheia, a poção não é gasta")
	var hurt = trip.party[0]
	hurt.hp = 1
	check(not trip.use_potion().is_empty() and hurt.hp > 1, "a poção cura")
	check(trip.potions == 0 and trip.use_potion().is_empty(), "sem poção, nada acontece")
	trip.brasas = 10
	check(trip.result()["brasas"] == 7, "o amuleto rende mais, mesmo na derrota (5 + 50%)")
	TownProgress.record(trip.result())
	check(TownProgress.item_count("pocao") == 0 and TownProgress.item_count("pedra") == 0, "a expedição gasta o que levou")
	check(TownProgress.expedition_setup()["atk"] == 0, "o efeito não passa para a próxima")


func test_upgrades() -> void:
	_clean_save()
	check(TownProgress.upgrade_cost("armadura") == -1, "sem o ferreiro não há armadura")
	_give(100)
	check(TownProgress.buy_upgrade("armadura") and TownProgress.brasas() == 80, "a forja cobra")
	check(TownProgress.buy_upgrade("frascos"), "a enfermaria vende frascos")
	var setup := TownProgress.expedition_setup()
	check(setup["def"] == 1 and setup["potions"] == 1 and setup["free_potions"] == 1, "as melhorias valem")
	var trip = Expedition.new(Data.DEFAULT_PARTY, 5, {}, setup)
	check(trip.party[0].def == Data.UNIT_TYPES[trip.party[0].type_id]["def"] + 1, "a armadura protege")
	trip.party[0].hp = 1
	trip.use_potion()
	check(trip.result()["bag_potions_used"] == 0, "o frasco de graça não sai da mochila")


func test_quests() -> void:
	_clean_save()
	check(TownProgress.quest_status("primeira_chama") == "available", "o Faroleiro já tem pedido")
	check(TownProgress.quest_status("sucata") == "locked", "sem o ferreiro, sem pedido dele")
	check(TownProgress.person_mark("guarda") == "!", "quem tem pedido ganha marca")
	check(TownProgress.quest_status("vigilia") == "locked", "a vigília vem depois da primeira chama")
	check(not TownProgress.complete_quest("primeira_chama"), "não entrega o que não aceitou")
	check(TownProgress.accept_quest("primeira_chama") and TownProgress.quest_status("primeira_chama") == "active", "aceita")
	check(TownProgress.person_mark("guarda") == "", "aceita, a marca some")
	var trip = Expedition.new(Data.DEFAULT_PARTY, 5, {}, TownProgress.expedition_setup())
	TownProgress.record(trip.result())
	check(TownProgress.quest_status("primeira_chama") == "active", "perder não acende o farol")
	var tally := {"beacons": 1, "kills": 5, "ruins": 1}
	var finished := TownProgress.record({"won": true, "brasas": 0, "rescued": ["ferreiro"], "memories": 0, "tally": tally})
	check(finished == ["primeira_chama"], "o fim da expedição avisa que a missão ficou pronta")
	check(TownProgress.last_note().contains("A Primeira Chama"), "a nota da cidade fala da missão")
	check(TownProgress.quest_status("primeira_chama") == "ready" and TownProgress.person_mark("guarda") == "?", "fica pronta")
	check(TownProgress.quest_status("sucata") == "available", "o resgate abre o pedido do ferreiro")
	check(TownProgress.accept_quest("sucata"), "aceita a sucata")
	TownProgress.record({"won": false, "brasas": 0, "rescued": [], "memories": 0, "tally": {"ruins": 2}})
	check(TownProgress.quest_progress("sucata") == 2, "o que veio antes de aceitar não conta")
	var before := TownProgress.brasas()
	check(TownProgress.complete_quest("primeira_chama"), "entrega")
	check(TownProgress.brasas() == before + 30 and TownProgress.item_count("pocao") == 1, "a recompensa chega")
	check(not TownProgress.complete_quest("primeira_chama"), "não recebe duas vezes")
	check(TownProgress.quest_status("vigilia") == "available", "abre a próxima missão")
	check(TownProgress.person_mark("guarda") == "", "sem mais nada, sem marca")


## O guia conta a história em capítulos, um por farol, e o objetivo acompanha.
func test_story() -> void:
	_clean_save()
	var guide: Array = Town.people().filter(func(p): return p["id"] == Content.GUIDE)
	check(guide.size() == 1 and Content.TALK.has(Content.GUIDE), "existe um guia com conversa")
	var state = _new()
	check(Hex.distance(guide[0]["cell"], Town.plaza()) <= Town.VISIT_RADIUS, "o guia está perto de onde a party começa")
	check(state.person_near(Town.plaza())["id"] == Content.GUIDE, "a primeira conversa à mão é com o guia")
	check(TownProgress.story_pending() and TownProgress.person_mark(Content.GUIDE) == "!", "no começo o guia tem história")
	check(TownProgress.objective() == Content.GOAL_TALK, "o objetivo manda falar com o guia")
	check(TownProgress.pending_pages() == Content.STORY[0]["pages"], "conta o primeiro capítulo")
	TownProgress.hear_story()
	check(not TownProgress.story_pending() and TownProgress.person_mark(Content.GUIDE) == "", "contada, a marca some")
	check(TownProgress.objective() == Content.GOAL_KEEPER, "depois, falar com o Faroleiro")
	TownProgress.set_met(Content.KEEPER)
	check(TownProgress.objective().ends_with("(0/%d)" % Content.BEACON_GOAL), "depois, acender um farol")
	TownProgress.record({"won": true, "guardian": "boss_cervo", "brasas": 0, "rescued": [], "memories": 0})
	TownProgress.record({"won": true, "guardian": "boss_cervo", "brasas": 0, "rescued": [], "memories": 0})
	check(TownProgress.guardians() == ["boss_cervo"], "o guardião vencido fica lembrado, sem repetir")
	check(TownProgress.pending_pages().size() == Content.STORY[1]["pages"].size() + Content.STORY[2]["pages"].size(), "quem pulou um capítulo ouve os dois")
	TownProgress.record({"won": false, "brasas": 0, "rescued": [], "memories": 0})
	check(not TownProgress.last_won(), "lembra que a última expedição foi perdida")
	for i in 5:
		TownProgress.record({"won": true, "brasas": 0, "rescued": [], "memories": 0})
	check(TownProgress.story_stage() == Content.STORY.size() - 2, "sem a batalha final, a história para no último farol")
	TownProgress.finish_story()
	check(TownProgress.story_stage() == Content.STORY.size() - 1 and TownProgress.story_pending(), "a batalha final abre o fim")
	for i in Content.STORY.size():
		check(not Content.STORY[i]["pages"].is_empty() and Content.STORY[i]["call"].all(func(line): return line.length() <= 40), "capítulo %d tem falas e balões curtos" % i)
		for page in Content.STORY[i]["pages"]:
			check(Town.people().any(func(p): return p["id"] == page[0]), "quem fala no capítulo %d existe" % i)
	for kind in Exp.BOSS_BY_BIOME.values():
		check(Exp.BOSS_LINES.has(kind) and Exp.BOSS_FAREWELL.has(kind), "%s tem falas" % kind)
		check(Content.TALK[Content.KEEPER]["guardians"].has(kind), "o Faroleiro conta quem era %s" % kind)


func test_growth() -> void:
	var empty = _new()
	var saved = _new(["ferreiro"])
	var forge: Vector2i = Town.buildings().filter(func(b): return b["art"] == "forja")[0]["cell"]
	check(empty.props[forge][0]["path"] == Town.RUBBLE, "sem o ferreiro a forja está em ruínas")
	check(saved.props[forge][0]["path"].ends_with("forja.png"), "o resgate reconstrói a forja")
	var smith: Vector2i = Town.people().filter(func(p): return p["id"] == "ferreiro")[0]["cell"]
	check(empty.tile_at(smith)["walkable"], "sem o ferreiro, o lugar dele fica livre")
	check(not saved.tile_at(smith)["walkable"], "o ferreiro ocupa uma casa")
	check(saved.person_near(smith + Vector2i(1, 0))["id"] == "ferreiro", "dá para falar com quem está perto")
	check(saved.person_near(Vector2i(200, 200)).is_empty(), "longe não há conversa")
	check(not saved.tile_at(Town.people().filter(func(p): return p["id"] == "mercadora")[0]["cell"])["walkable"], "a mercadora ocupa uma casa")
	# Cada morador resgatado traz de volta o prédio do seu ofício.
	var everyone = _new(Exp.RESIDENT_ORDER)
	for building in Town.buildings():
		if building.get("needs", "") == "":
			continue
		var cell: Vector2i = building["cell"]
		check(empty.props[cell][0]["path"] == Town.RUBBLE, "sem %s, %s em ruínas" % [building["needs"], building["art"]])
		check(everyone.props[cell][0]["path"] != Town.RUBBLE, "com %s, %s de pé" % [building["needs"], building["art"]])
	for id in Exp.RESIDENT_ORDER:
		var home: Array = Town.people().filter(func(p): return p["id"] == id)
		check(home.size() == 1 and home[0]["needs"] == id, "%s tem casa na cidade" % id)
		check(Town.buildings().any(func(b): return b.get("needs", "") == id), "%s reabre um prédio" % id)


## A cidade clareia com o progresso: lampiões acendem e o farol fica mais forte.
func test_lights() -> void:
	var lamps: Array = Town.lamps()
	check(lamps.size() >= 8, "a cidade tem lampiões nas ruas (%d)" % lamps.size())
	var fresh = TownState.new(Data.DEFAULT_PARTY, 5, {}, {"rescued": [], "beacons": 0})
	var grown = TownState.new(Data.DEFAULT_PARTY, 5, {}, {"rescued": ["ferreiro", "curandeira"], "beacons": 2})
	check(fresh.lit_lamps.size() == Town.LAMPS_BASE, "no começo, só os lampiões da praça acendem")
	check(grown.lit_lamps.size() > fresh.lit_lamps.size(), "resgates e faróis acendem mais lampiões")
	check(Hex.distance(lamps[0]["cell"], Town.plaza()) <= Hex.distance(lamps.back()["cell"], Town.plaza()), "a luz começa perto da praça")
	check(Town.beacon_power(3) > Town.beacon_power(0), "o farol da cidade cresce com os faróis acesos")
	check(Town.beam_length(0) == 0.0 and Town.beam_length(1) > 0.0, "o facho só gira depois do primeiro farol")
	for lamp in lamps:
		check(fresh.tile_at(lamp["cell"])["walkable"] or fresh.terrain_id_at(lamp["cell"]) != TownState.TERRAIN_WATER, "lampião em chão de verdade (%s)" % lamp["cell"])
	check(TownProgress.expedition_setup().has("beacons"), "a cidade sabe quantos faróis estão acesos")
