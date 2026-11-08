extends SceneTree
## Regras do mapa fixo dos Subúrbios Apagados (scripts/suburbs_map.gd), sem tela: planta, locais
## sorteados entre os candidatos, rotas das lanternas, segredos, vau, forte e save.
## Rodar: godot --headless --path . --script tests/test_suburbs.gd

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const Plan = preload("res://scripts/suburbs_plan.gd")
const SuburbsGen = preload("res://scripts/suburbs_map.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")
const AI = preload("res://scripts/ai.gd")

const SEEDS := 30
var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	var progress = load("res://scripts/hero_progress.gd")
	progress.path = "user://test_progress_orbes.cfg" # Orbes achados não vão para o save de verdade
	test_default()
	test_landmarks()
	test_routes()
	test_secrets()
	test_ford()
	test_fort()
	test_art()
	test_save()
	test_danger()
	test_secret_events()
	print("regras: %d verificações, %d falhas" % [checks, failures])
	if not OS.has_environment("SKIP_SIM"):
		test_simulation()
	print("%d verificações, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _new(world_seed: int, town := {}):
	return ExpeditionState.new(Data.DEFAULT_PARTY, world_seed, {}, town)


## A pé a partir do início, com a regra de degrau do movimento. `skip`: casas proibidas.
func _walk(state, skip := {}) -> Dictionary:
	var seen := {state.start_cell: 0}
	var frontier := [state.start_cell]
	var i := 0
	while i < frontier.size():
		var current: Vector2i = frontier[i]
		i += 1
		for next in Hex.neighbors(current):
			if seen.has(next) or skip.has(next) or not state.tile_at(next)["walkable"]:
				continue
			if absi(state.elevation_at(next) - state.elevation_at(current)) > 1:
				continue
			seen[next] = seen[current] + 1
			frontier.append(next)
	return seen


func _reached(seen: Dictionary, cell: Vector2i) -> bool:
	return seen.has(cell) or Hex.neighbors(cell).any(func(next): return seen.has(next))


func _steps(seen: Dictionary, cell: Vector2i) -> int:
	var best := 999999
	for spot in [cell] + Hex.neighbors(cell):
		if seen.has(spot):
			best = mini(best, seen[spot])
	return best


func test_default() -> void:
	var state = _new(3)
	check(state.fixed_map and state.biome == "suburbios", "sem região escolhida, o mapa é o dos Subúrbios")
	check(state.start_cell == Plan.START, "a party começa na Praça do Portão")
	check(state.tile_at(state.start_cell)["walkable"], "o início é chão")
	for member in state.party:
		check(state.tile_at(member.pos)["walkable"], "cada herói começa em chão andável")
	var others := 0
	for cell in state.area_of(state.start_cell, 50):
		if state.biome_at(cell) != "suburbios":
			others += 1
	check(others == 0, "o mapa inteiro é dos Subúrbios (%d casas de outro bioma)" % others)
	var a = _new(11)
	var b = _new(11)
	check(a.landmarks.keys() == b.landmarks.keys(), "mesma semente, mesmos locais")
	var c = _new(12)
	check(a.gen.marks == c.gen.marks, "a planta é a mesma em toda expedição")
	check(state.district_at(Vector2i(-20, -15)) == "Cemitério da Colina", "o cemitério tem nome de bairro")
	check(state.tile_name_at(Vector2i(-9, -11)) == "Coreto", "o coreto tem nome ao passar o mouse")
	check(state.paved_at(state.start_cell), "a praça é calçada")
	check(state.gen.is_road(Vector2i(0, -10)), "a avenida é rua")
	check(state.terrain_id_at(Vector2i(0, 4)) == state.gen.HOUSE, "a muralha da cidade fecha o sul")
	var seen := _walk(state)
	var leak: bool = seen.keys().any(func(cell): return not state.gen.cells.has(cell))
	check(not leak, "a pé não se sai da planta")


func test_landmarks() -> void:
	var variety := {}
	for world_seed in SEEDS:
		var state = _new(world_seed * 13 + 1)
		var seen := _walk(state)
		var counts := {}
		var hidden := 0
		for cell in state.landmarks:
			var entry: Dictionary = state.landmarks[cell]
			counts[entry["kind"]] = counts.get(entry["kind"], 0) + 1
			hidden += 1 if entry.get("hidden", false) else 0
			check(_reached(seen, cell), "semente %d: %s em %s é alcançável" % [world_seed, entry["kind"], cell])
			if entry["kind"] in ["vila", "farol"]:
				check(not state.tile_at(cell)["walkable"], "semente %d: %s é construção" % [world_seed, entry["kind"]])
			else:
				check(state.tile_at(cell)["walkable"], "semente %d: %s em chão andável (%s)" % [world_seed, entry["kind"], cell])
			if entry["kind"] in ["vila", "ruina", "emboscada", "fonte", "memoria"] and not entry.get("hidden", false):
				variety[cell] = true
		check(counts.get("lanterna", 0) == 3, "semente %d: três lanternas" % world_seed)
		check(counts.get("farol", 0) == 1, "semente %d: um farol" % world_seed)
		check(counts.get("vila", 0) == Exp.FIXED_COUNTS["vila"], "semente %d: vilas (%d)" % [world_seed, counts.get("vila", 0)])
		check(counts.get("ruina", 0) == Exp.FIXED_COUNTS["ruina"], "semente %d: ruínas (%d)" % [world_seed, counts.get("ruina", 0)])
		check(counts.get("emboscada", 0) == Exp.FIXED_COUNTS["emboscada"], "semente %d: emboscadas" % world_seed)
		check(counts.get("fonte", 0) == Exp.FIXED_COUNTS["fonte"], "semente %d: fontes" % world_seed)
		check(counts.get("memoria", 0) == Exp.FIXED_COUNTS["memoria"] + 1, "semente %d: memórias (uma na cripta)" % world_seed)
		check(counts.get("bau", 0) == Exp.FIXED_COUNTS["bau"] + Plan.SECRETS.size(), "semente %d: baús (%d)" % [world_seed, counts.get("bau", 0)])
		check(hidden == Plan.SECRETS.size() + 1, "semente %d: segredos escondidos (%d)" % [world_seed, hidden])
		for cell in state.landmarks:
			if state.landmarks[cell]["kind"] == "vila":
				check(Hex.neighbors(cell).any(func(next): return seen.has(next)), "semente %d: dá para bater na porta da vila" % world_seed)
		var beacon_exits: int = Hex.neighbors(state.beacon_cell).filter(func(next): return seen.has(next)).size()
		check(beacon_exits >= Exp.BEACON_MIN_EXITS, "semente %d: espaço em volta do farol (%d)" % [world_seed, beacon_exits])
		check(Hex.distance(state.start_cell, state.beacon_cell) >= 30, "o farol fica longe do início")
	# Com 30 sementes, os candidatos se revezam: o mapa não repete sempre os mesmos locais.
	var candidates := 0
	for kind in ["vila", "ruina", "emboscada", "fonte", "memoria"]:
		candidates += Plan.SITES.get(kind, []).size()
	check(variety.size() >= candidates - 2, "os candidatos se revezam entre as expedições (%d de %d)" % [variety.size(), candidates])


func test_routes() -> void:
	var used := {}
	for world_seed in SEEDS:
		var state = _new(world_seed * 7 + 2)
		var cells: Array = state.lantern_cells()
		check(cells.size() == 3, "três lanternas em ordem")
		var route := Plan.LANTERN_ROUTES.find(cells)
		check(route >= 0, "semente %d: as lanternas seguem uma rota da planta" % world_seed)
		used[route] = true
		# zigue-zague: cada lanterna fica do lado oposto da avenida em relação à anterior
		for i in range(1, cells.size()):
			check(signi(cells[i].x) != signi(cells[i - 1].x), "semente %d: a lanterna %d troca de lado" % [world_seed, i + 1])
		check(not state.beacon_known(), "semente %d: o farol começa fora da bússola" % world_seed)
		var seen := _walk(state)
		var previous: Vector2i = state.start_cell
		for cell in cells:
			var free: int = Hex.neighbors(cell).filter(func(next): return seen.has(next)).size()
			check(free >= Exp.BEACON_MIN_EXITS, "semente %d: espaço para a luta da lanterna em %s (%d)" % [world_seed, cell, free])
			check(Hex.distance(cell, previous) >= 14, "semente %d: a lanterna fica longe da anterior" % world_seed)
			previous = cell
	check(used.size() == Plan.LANTERN_ROUTES.size(), "as duas rotas aparecem nas sementes")


func test_secrets() -> void:
	var state = _new(5)
	var seen := _walk(state)
	for secret in Plan.SECRETS:
		var cell: Vector2i = secret["cell"]
		var entry: Dictionary = state.landmarks.get(cell, {})
		check(entry.get("kind", "") == "bau" and entry.get("hidden", false), "%s guarda um baú escondido" % secret["name"])
		check(not state.open_landmarks(state.start_cell).has(cell), "%s não aparece na bússola" % secret["name"])
		check(seen.has(cell), "%s é alcançável a pé" % secret["name"])
		check(not state.gen.is_path(cell) and not Hex.neighbors(cell).any(func(next): return state.gen.is_road(next)), "%s fica longe das ruas" % secret["name"])
	var crypt: Vector2i = Plan.SITES["memoria_fixa"][0]
	check(state.landmarks.get(crypt, {}).get("kind", "") == "memoria", "a cripta guarda uma memória")
	# Os segredos só se abrem por uma passagem estreita: tirar a passagem fecha o acesso.
	var doors := {
		"Cripta dos Faroleiros": [Vector2i(-26, -17)],
		"Ilhota do lago": [Vector2i(-6, -14), Vector2i(-6, -13)],
		"Coração do labirinto": [Vector2i(13, -1)],
		"Arsenal esquecido": [Vector2i(29, -11)],
		"Passarela da usina": [Vector2i(24, -35), Vector2i(23, -35)],
	}
	for secret in Plan.SECRETS:
		if not doors.has(secret["name"]):
			continue
		var skip := {}
		for cell in doors[secret["name"]]:
			skip[cell] = true
		check(not _walk(state, skip).has(secret["cell"]), "%s tem uma entrada só" % secret["name"])
	# O labirinto não se atravessa em linha reta: o caminho até o baú é longo.
	var maze: Vector2i = Vector2i(10, 3)
	check(seen.get(maze, 0) - seen.get(Vector2i(13, -1), 0) >= 14, "o labirinto faz a party dar voltas")


## O vau escondido é um atalho de verdade: sem ele, a volta pelas pontes é bem maior.
func test_ford() -> void:
	var state = _new(5)
	var stones := {}
	for cell in state.gen.marks:
		if state.gen.marks[cell] == "o" and cell.y <= -22:
			stones[cell] = true
	check(stones.size() >= 3, "o canal tem pedras de vau")
	var with_ford := _walk(state)
	var without := _walk(state, stones)
	var target := Vector2i(-8, -25)
	check(with_ford.has(target) and without.has(target), "o cais norte é alcançável com ou sem o vau")
	var gain: int = without[target] - with_ford[target]
	check(gain >= 8, "o vau poupa caminho até o norte (%d passos)" % gain)
	var beacon_gain: int = _steps(without, state.beacon_cell) - _steps(with_ford, state.beacon_cell)
	check(beacon_gain >= 0, "o vau nunca deixa o farol mais longe")
	check(_steps(with_ford, state.beacon_cell) < 999999, "o farol é alcançável")
	check(not state.tile_at(Vector2i(0, -23))["walkable"], "a ponte do meio caiu: a avenida não atravessa o canal")


func test_fort() -> void:
	var first = _new(9, {"first_stage": true})
	check(first.landmarks.has(Plan.SITES["forte"][0]), "na primeira expedição, o quartel é o Forte da Vigília")
	check(first.fort.center == Plan.SITES["forte"][0], "o forte aponta para o pátio do quartel")
	first.hero.pos = first.fort.center + Vector2i(1, 0)
	for member in first.party:
		if member != first.hero:
			member.pos = first.hero.pos + Vector2i(0, 1 + first.party.find(member))
	var events: Array = first.tick()
	var captain = first.landmarks[first.fort.center]["guards"][0] if not first.landmarks[first.fort.center]["guards"].is_empty() else null
	check(captain != null and captain.alive(), "o comandante acorda no pátio")
	check(events.any(func(e): return e["type"] == "landmark"), "a luta do forte é anunciada")
	var later = _new(9, {"first_stage": false})
	check(not later.landmarks.values().any(func(e): return e["kind"] == "forte"), "depois, o quartel fica sem comandante")
	check(later.fort.cells.is_empty(), "sem forte, nada de cofre no pátio")


func test_art() -> void:
	var state = _new(4)
	var missing := []
	for cell in state.gen.art:
		for prop in state.gen.art[cell]:
			if not ResourceLoader.exists(prop["path"]) and not missing.has(prop["path"]):
				missing.append(prop["path"])
	check(missing.is_empty(), "toda peça da planta tem arte (%s)" % [missing])
	for id in [1, 2, 3, 5, 6, 7, 9, 10, 11, 16]:
		for prop in BiomeArt.props("suburbios", id, 0.7):
			check(ResourceLoader.exists(prop["path"]), "o terreno %d tem arte nos Subúrbios" % id)
	for kind in ["sombra", "agua", "trilha", "estrada"]:
		check(ResourceLoader.exists(BiomeArt.solo("suburbios", kind)), "chão %s dos Subúrbios" % kind)
	check(ResourceLoader.exists(BiomeArt.soil("suburbios")), "chão dos Subúrbios")
	check(ResourceLoader.exists(BiomeArt.wall("suburbios")), "muro de arrimo dos penhascos")
	check(BiomeArt.light_of("suburbios", "res://assets/biomes/suburbios/lampiao_aceso.png") == "lanterna", "o lampião aceso do portão brilha")
	check(Data.UNIT_TYPES.has(Exp.BOSS_BY_BIOME["suburbios"]), "o guardião dos Subúrbios existe")


func test_save() -> void:
	var state = _new(21)
	var lantern: Vector2i = state.lantern_cells()[0]
	state.landmarks[lantern]["state"] = "done"
	var restored = SaveGame.restore(SaveGame.capture(state))
	check(restored.fixed_map and restored.biome == "suburbios", "o save volta para os Subúrbios")
	check(restored.landmarks.keys() == state.landmarks.keys(), "o save mantém os locais e a ordem")
	check(restored.landmarks[lantern]["state"] == "done", "o save mantém a lanterna acesa")
	check(restored.lantern_cells() == state.lantern_cells(), "o save mantém a rota das lanternas")
	check(restored.terrain_override == state.terrain_override, "o save mantém as vilas")


func test_danger() -> void:
	var state = _new(2)
	check(state.danger() == 1, "o perigo começa baixo")
	state.farthest = Hex.distance(state.start_cell, state.beacon_cell)
	check(state.danger() >= 3, "perto do farol o perigo já liberou os inimigos fortes (%d)" % state.danger())


# --- Simulação: robôs jogam a expedição inteira (pula com SKIP_SIM=1) ----------------

var walk_maps := {}


func test_simulation() -> void:
	for town in [{}, {"hp": 18, "atk": 3}]:
		var wins := 0
		var reached := 0
		var lit := 0
		var brasas := 0
		var runs := 3
		for run in runs:
			var outcome := _play(run * 97 + 13, town)
			check(outcome["ended"], "expedição %d nos Subúrbios termina sem travar" % run)
			wins += 1 if outcome["won"] else 0
			reached += 1 if outcome["reached"] else 0
			lit += outcome["lit"]
			brasas += outcome["brasas"]
		print("Subúrbios, cidade %s: %d/%d vitórias · %d chegaram ao farol · %.1f lanternas · %d brasas" % [town, wins, runs, reached, float(lit) / runs, brasas / runs])


func _play(world_seed: int, town: Dictionary) -> Dictionary:
	var state = _new(world_seed, town)
	var actions := 0
	while state.winner() < 0 and actions < 14000:
		actions += 1
		state.tick()
		if state.winner() >= 0:
			break
		var unit = state.active_unit()
		if not unit.pending.is_empty():
			state.resolve_pending(unit)
		elif state.is_hero(unit) and not state.in_combat():
			_sim_walk(state, unit)
		else:
			var action: Dictionary = AI.decide(state, unit)
			if action.is_empty() or (state.is_hero(unit) and action["kind"] == "wait"):
				_sim_walk(state, unit)
			else:
				AI.apply(state, unit, action)
	return {"ended": state.winner() >= 0, "won": state.winner() == Data.Team.PLAYER, "reached": state.boss != null,
		"lit": state.lanterns_lit(), "brasas": state.brasas}


## Segue a corrente: a próxima lanterna, depois o farol. Os outros locais só se estiverem perto.
func _sim_walk(state, unit) -> void:
	var open: Array = state.open_landmarks(unit.pos)
	var lantern = state.next_lantern()
	var target: Vector2i = lantern if lantern != null else state.beacon_cell
	if not open.is_empty() and Hex.distance(open[0], unit.pos) <= 6:
		target = open[0]
	var distances := _map_to(state, target)
	var best: int = distances.get(unit.pos, 999999)
	var step = null
	for next in Hex.neighbors(unit.pos):
		if state.can_step(unit, next) and distances.get(next, 999999) < best:
			best = distances[next]
			step = next
	if step != null:
		state.do_step(unit, step)
		return
	var options: Array = Hex.neighbors(unit.pos).filter(func(cell): return state.can_step(unit, cell))
	if state.in_combat() or options.is_empty():
		state.do_wait(unit)
	else:
		state.do_step(unit, options[state.rng.randi_range(0, options.size() - 1)])


func _map_to(state, target: Vector2i) -> Dictionary:
	if walk_maps.get("state") != state:
		walk_maps = {"state": state}
	if walk_maps.has(target):
		return walk_maps[target]
	var distances := {target: 0}
	var frontier := [target]
	var head := 0
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		for next in Hex.neighbors(current):
			if distances.has(next) or not state.gen.cells.has(next) or not state.gen.walkable(next):
				continue
			if current != target and absi(state.elevation_at(next) - state.elevation_at(current)) > 1:
				continue
			distances[next] = distances[current] + 1
			frontier.append(next)
	walk_maps[target] = distances
	return distances


func test_secret_events() -> void:
	var state = _new(6)
	var secret: Dictionary = Plan.SECRETS[0]
	var cell: Vector2i = secret["cell"]
	check(state.secrets_found() == 0 and state.secrets_total() == Plan.SECRETS.size(), "nenhum segredo achado no começo")
	var near: Array = state.area_of(cell, 1).filter(func(p): return state.tile_at(p)["walkable"])
	for member in state.party:
		member.pos = near[0]
	var events: Array = state.tick()
	check(events.any(func(e): return e["type"] == "secret"), "chegar num segredo avisa")
	check(state.secrets_found() == 1, "o segredo conta como achado")
	check(not state.tick().any(func(e): return e["type"] == "secret"), "o aviso vem uma vez só")
	var restored = SaveGame.restore(SaveGame.capture(state))
	check(restored.secrets_found() == 1, "o save lembra os segredos achados")
