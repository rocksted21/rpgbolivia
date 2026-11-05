extends SceneTree
## Regras da Cidade-Farol, sem tela. Rodar: godot --headless --path . --script tests/test_town.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Town = preload("res://scripts/town_data.gd")
const TownState = preload("res://scripts/town_state.gd")

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
	check(seen.size() > 150, "a cidade é grande (%d casas)" % seen.size())
	for spot in state.people:
		var near: Array = Hex.neighbors(spot).filter(func(cell): return seen.has(cell))
		check(not near.is_empty(), "dá para chegar até %s" % state.people[spot]["name"])
	for cell in seen:
		check(state.levels.has(cell), "o caminho não sai da ilha")
	check(not state.tile_at(Vector2i(200, 200))["walkable"], "em volta da cidade é água")


func test_art() -> void:
	var state = _new(["ferreiro", "curandeira"])
	for cell in state.props:
		check(ResourceLoader.exists(state.props[cell]["path"]), "arte existe: %s" % state.props[cell]["path"])
	check(ResourceLoader.exists("res://assets/town/calcada.png"), "calçada existe")
	var cells := {}
	for building in Town.BUILDINGS:
		for cell in state._disc(building["cell"], building["radius"]):
			check(not cells.has(cell), "prédios não se sobrepõem em %s" % cell)
			cells[cell] = true
	for person in Town.PEOPLE:
		check(not cells.has(person["cell"]), "%s fica fora dos prédios" % person["name"])


func test_growth() -> void:
	var empty = _new()
	var saved = _new(["ferreiro"])
	var forge: Vector2i = Town.BUILDINGS[1]["cell"]
	check(empty.props[forge]["path"] == Town.RUBBLE, "sem o ferreiro a forja está em ruínas")
	check(saved.props[forge]["path"].ends_with("forja.png"), "o resgate reconstrói a forja")
	var smith: Vector2i = Town.PEOPLE[0]["cell"]
	check(empty.tile_at(smith)["walkable"], "sem o ferreiro, o lugar dele fica livre")
	check(not saved.tile_at(smith)["walkable"], "o ferreiro ocupa uma casa")
	check(saved.person_near(smith + Vector2i(1, 0))["id"] == "ferreiro", "dá para falar com quem está perto")
	check(saved.person_near(Vector2i(200, 200)).is_empty(), "longe não há conversa")
