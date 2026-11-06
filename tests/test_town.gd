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
	DirAccess.remove_absolute(TownProgress.path)
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _new(rescued := []):
	return TownState.new(Data.DEFAULT_PARTY, 5, {}, {"rescued": rescued})


func _reachable(state) -> Dictionary:
	for member in state.party:
		member.pos = Vector2i(999, 999)
	var seen := {Town.PLAZA: true}
	var frontier := [Town.PLAZA]
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
	check(state.tile_at(Town.PLAZA)["walkable"], "a praça é caminhável")
	for member in state.party:
		check(state.tile_at(member.pos)["walkable"], "%s começa em casa livre" % member.type_id)
	check(state.foes().is_empty() and state.tick().is_empty(), "a cidade não tem inimigos")
	check(state.winner() < 0, "a cidade não acaba")
	var seen := _reachable(state)
	check(seen.size() > 120, "a cidade é grande (%d casas)" % seen.size())
	for spot in [Vector2i(17, 8), Vector2i(12, 12), Vector2i(18, 24), Vector2i(27, 13)]:
		check(seen.has(spot), "as ruas sobem aos platôs e descem às docas: %s" % spot)
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
	var width: int = Town.MAP[0].length()
	for line in Town.MAP:
		check(line.length() == width, "a planta é retangular")
	check(ResourceLoader.exists("res://assets/town/calcada.png"), "calçada existe")
	var cells := {}
	for building in Town.BUILDINGS:
		for cell in state._disc(building["cell"], building["radius"]):
			check(not cells.has(cell), "prédios não se sobrepõem em %s" % cell)
			cells[cell] = true
	for person in Town.PEOPLE:
		check(not cells.has(person["cell"]), "%s fica fora dos prédios" % person["name"])


## Nenhum enfeite pode fechar uma rua ou o caminho de quem anda pela cidade.
func test_roads() -> void:
	var state = _new(["ferreiro", "curandeira"])
	var seen := _reachable(state)
	for road in Town.ROADS:
		for cell in state._line(road[0], road[1]):
			if state.levels.has(cell):
				check(seen.has(cell), "a rua continua aberta em %s" % cell)
	for cell in Town.WALK_ROUTE:
		check(seen.has(cell), "quem passeia chega a %s" % cell)
	for art in Town.WALKER_ART:
		check(ResourceLoader.exists(Town.TOWN_ROOT % art), "arte de quem passeia: %s" % art)


func test_content() -> void:
	for person in Town.PEOPLE:
		check(ResourceLoader.exists(Town.TOWN_ROOT % person["art"]), "%s tem arte" % person["name"])
		if person["service"] != "board":
			check(Content.TALK.has(person["id"]), "%s tem conversa" % person["name"])
	var ids: Array = Town.PEOPLE.map(func(person): return person["id"])
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


func test_growth() -> void:
	var empty = _new()
	var saved = _new(["ferreiro"])
	var forge: Vector2i = Town.BUILDINGS[1]["cell"]
	check(empty.props[forge][0]["path"] == Town.RUBBLE, "sem o ferreiro a forja está em ruínas")
	check(saved.props[forge][0]["path"].ends_with("forja.png"), "o resgate reconstrói a forja")
	var smith: Vector2i = Town.PEOPLE[0]["cell"]
	check(empty.tile_at(smith)["walkable"], "sem o ferreiro, o lugar dele fica livre")
	check(not saved.tile_at(smith)["walkable"], "o ferreiro ocupa uma casa")
	check(saved.person_near(smith + Vector2i(1, 0))["id"] == "ferreiro", "dá para falar com quem está perto")
	check(saved.person_near(Vector2i(200, 200)).is_empty(), "longe não há conversa")
	check(not saved.tile_at(Town.PEOPLE.filter(func(p): return p["id"] == "mercadora")[0]["cell"])["walkable"], "a mercadora ocupa uma casa")
	# Cada morador resgatado traz de volta o prédio do seu ofício.
	var everyone = _new(Exp.RESIDENT_ORDER)
	for building in Town.BUILDINGS:
		if building.get("needs", "") == "":
			continue
		var cell: Vector2i = building["cell"]
		check(empty.props[cell][0]["path"] == Town.RUBBLE, "sem %s, %s em ruínas" % [building["needs"], building["art"]])
		check(everyone.props[cell][0]["path"] != Town.RUBBLE, "com %s, %s de pé" % [building["needs"], building["art"]])
	for id in Exp.RESIDENT_ORDER:
		var home: Array = Town.PEOPLE.filter(func(p): return p["id"] == id)
		check(home.size() == 1 and home[0]["needs"] == id, "%s tem casa na cidade" % id)
		check(Town.BUILDINGS.any(func(b): return b.get("needs", "") == id), "%s reabre um prédio" % id)
