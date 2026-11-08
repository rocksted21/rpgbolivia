extends SceneTree
const Data = preload("res://scripts/game_data.gd")
const Expedition = preload("res://scripts/expedition_state.gd")
const Save = preload("res://scripts/save_game.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var seen := {}
	for world_seed in [9, 77, 93, 207]:
		var state = Expedition.new(Data.DEFAULT_PARTY, world_seed, {}, {"biome": legacy_biome(world_seed)})
		var sites: Dictionary = state.camps.sites
		print("Semente ", world_seed, ": ", sites)
		var reachable: Dictionary = state.layout.walk_area()
		for center in sites:
			seen[sites[center]] = true
			check(reachable.has(center), "centro acessível: %s" % sites[center])
			check(state.tile_at(center)["walkable"], "centro caminhável")
			if sites[center] == "crossing":
				check(state.terrain_id_at(center) == state.gen.BRIDGE, "travessia preserva ponte real")
				check(state.floor_id_at(center) == state.gen.BRIDGE, "travessia não aterra o rio")
		for cell in state.camps.cells:
			var info: Dictionary = state.camps.cells[cell]
			check(state.tile_at(cell)["walkable"] != info["solid"], "colisão acompanha o cenário")
			check(not info["solid"] or not state.gen.is_path(cell), "trilha preservada")
			for prop in state.camps.art_at(cell):
				check(ResourceLoader.exists(prop["path"]), "arte existe: " + prop["path"])
		var restored = Save.restore(Save.capture(state))
		check(restored.camps.cells == state.camps.cells, "save preserva piso e objetos")
		check(restored.camps.sites == state.camps.sites, "save preserva os temas")
	for theme in ["camp", "garden", "shrine", "crossing"]:
		check(seen.has(theme), "tema aparece nas sementes de teste: " + theme)
	print("Cenários: %d verificações, %d falhas" % [checks, failures])
	quit(1 if failures else 0)


## Bioma que a semente sorteava antes do mapa fixo dos Subúrbios: assim os testes do mapa
## sorteado continuam olhando os mesmos mapas de antes.
static func legacy_biome(world_seed: int) -> String:
	var dice := RandomNumberGenerator.new()
	dice.seed = world_seed + 17
	var keys := ["deserto", "floresta", "neve", "selva"]
	return keys[dice.randi_range(0, keys.size() - 1)]

