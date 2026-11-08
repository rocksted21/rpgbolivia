extends RefCounted
## Save no meio do jogo: um espaço só, em user://. Guarda o estado das regras (unidades,
## locais, níveis) e refaz o mapa a partir da semente. Sem autoload, como game_settings.gd.

const BattleState = preload("res://scripts/battle_state.gd")
const WorldState = preload("res://scripts/world_state.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const TownState = preload("res://scripts/town_state.gd")
const Unit = preload("res://scripts/unit.gd")
const Data = preload("res://scripts/game_data.gd")

const VERSION := 2 # 2: expedição de um bioma só e com borda; o mapa de um save 1 seria outro

static var path := "user://savegame.dat"


static func exists() -> bool:
	return FileAccess.file_exists(path)


## Texto curto do que está salvo, para o botão de carregar; vazio sem save.
static func summary() -> String:
	var data := read()
	if data.is_empty():
		return ""
	var where: String = {"town": "Cidade-Farol", "expedition": "Expedição", "world": "Jornada", "battle": "Batalha"}.get(data.mode, "")
	return "%s · %s" % [where, data.get("when", "")]


static func mode_of(state) -> String:
	if "beacon_cell" in state:
		return "expedition"
	if "people" in state:
		return "town"
	if "party" in state:
		return "world"
	return "battle"


static func save(state) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível salvar o jogo: %s" % FileAccess.get_open_error())
		return false
	file.store_string(var_to_str(capture(state)))
	return true


static func read() -> Dictionary:
	if not exists():
		return {}
	var data: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("version", 0) != VERSION:
		return {}
	return data


# --- Gravar --------------------------------------------------------------------

static func capture(state) -> Dictionary:
	var mode := mode_of(state)
	var data := {version = VERSION, mode = mode, when = Time.get_datetime_string_from_system(false, true).substr(0, 16), next_uid = state.next_uid, builds = state.builds_used}
	var rows := []
	for unit in state.units:
		rows.append(_unit_row(unit, state))
	if mode != "battle":
		data.party = state.party.map(func(u): return u.type_id)
		data.party_uids = state.party.map(func(u): return u.uid)
		data.seed = state.gen.world_seed
		data.rng_state = state.rng.state
		data.start_cell = state.start_cell
		data.kills = state.kills
		data.farthest = state.farthest
		data.steps_until_spawn = state.steps_until_spawn
		data.heading = state.heading
		data.last_walker = state.last_walker.uid if state.last_walker != null else 0
		data.reinforce_left = state.reinforce_left # emboscada que ainda vai chegar nesta luta
		data.reinforce_at = state.reinforce_at
	if mode == "town":
		data.town = state.town_setup
	if mode == "expedition":
		data.town = state.town_setup
		var landmarks := {}
		for cell in state.landmarks:
			var entry: Dictionary = state.landmarks[cell].duplicate()
			entry.guards = entry.guards.map(func(u): return u.uid)
			for guard in state.landmarks[cell].guards:
				if not state.units.has(guard): # caiu e saiu do mapa, mas o local ainda conta com ele
					var row := _unit_row(guard, state)
					row.gone = true
					rows.append(row)
			landmarks[cell] = entry
		data.landmarks = landmarks
		# O arquivo grava as chaves em ordem alfabética; a ordem original dos locais decide jogadas.
		data.landmark_order = state.landmarks.keys()
		data.terrain_override = state.terrain_override.duplicate()
		data.beacon_cell = state.beacon_cell
		data.boss = state.boss.uid if state.boss != null else 0
		data.defeated_boss = state.defeated_boss
		data.brasas = state.brasas
		data.xp = state.xp
		data.level = state.level
		data.rescued = state.rescued.duplicate()
		data.memories = state.memories.duplicate()
		data.known_residents = state.known_residents.duplicate()
		data.known_memories = state.known_memories
		data.potions = state.potions
		data.free_potions = state.free_potions
		data.potions_used = state.potions_used
		data.far_compass = state.far_compass
		data.brasa_bonus = state.brasa_bonus
		data.items = state.items.duplicate()
		data.tally = state.tally.duplicate()
	data.units = rows
	return data


static func _unit_row(unit, state) -> Dictionary:
	return {
		uid = unit.uid, type = unit.type_id, team = unit.team, pos = unit.pos, name = unit.display_name,
		hp = unit.hp, max_hp = unit.max_hp, atk = unit.atk, def = unit.def, speed = unit.speed,
		abilities = unit.abilities.duplicate(), clock = unit.clock, moved = unit.moved, jumped = unit.jumped, guarding = unit.guarding,
		pending = unit.pending.duplicate(true), taunt_actions = unit.taunt_actions, statuses = unit.statuses.duplicate(true),
		taunted_by = unit.taunted_by.uid if unit.taunted_by != null else 0,
		engaged = "engaged" in state and state.engaged.has(unit), fighting = "fighting" in state and state.fighting.has(unit), gone = false,
	}


# --- Carregar ------------------------------------------------------------------

## Refaz o estado salvo; null se o save não serve.
static func restore(data: Dictionary):
	var state
	match data.get("mode", ""):
		"battle":
			state = BattleState.from_data(data.builds)
		"world":
			state = WorldState.new(data.party, data.seed, data.builds)
		"expedition":
			var setup: Dictionary = data.town.duplicate()
			setup["fort_layout"] = setup.get("fort_layout", 1)
			setup["first_stage"] = data.landmarks.values().any(func(entry): return entry["kind"] == "forte")
			state = ExpeditionState.new(data.party, data.seed, data.builds, setup)
			# As chaves acima só servem para refazer o mapa: o setup guardado volta como estava.
			state.town_setup = data.town.duplicate(true)
		"town":
			state = TownState.new(data.party, data.seed, data.builds, data.town)
		_:
			return null
	var by_uid := _restore_units(state, data)
	state.next_uid = data.next_uid
	if data.mode != "battle":
		state.rng.state = data.rng_state
		state.start_cell = data.start_cell
		state.kills = data.kills
		state.farthest = data.farthest
		state.steps_until_spawn = data.steps_until_spawn
		state.heading = data.heading
		state.last_walker = by_uid.get(data.last_walker, state.party[0])
		state.reinforce_left = data.get("reinforce_left", 0) # saves antigos não têm
		state.reinforce_at = data.get("reinforce_at", 0)
	if data.mode == "expedition":
		state.landmarks.clear()
		for cell in data.get("landmark_order", data.landmarks.keys()):
			var entry: Dictionary = data.landmarks[cell].duplicate()
			entry.guards = entry.guards.map(func(uid): return by_uid.get(uid)).filter(func(u): return u != null)
			state.landmarks[cell] = entry
		state.terrain_override = data.terrain_override.duplicate()
		state.beacon_cell = data.beacon_cell
		state.boss = by_uid.get(data.boss)
		state.defeated_boss = data.defeated_boss
		state.brasas = data.brasas
		state.xp = data.xp
		state.level = data.level
		state.rescued = data.rescued.duplicate()
		state.memories = data.memories.duplicate()
		state.known_residents = data.known_residents.duplicate()
		state.known_memories = data.known_memories
		state.potions = data.get("potions", state.potions)
		state.free_potions = data.get("free_potions", state.free_potions)
		state.potions_used = data.get("potions_used", state.potions_used)
		state.far_compass = data.get("far_compass", state.far_compass)
		state.brasa_bonus = data.get("brasa_bonus", state.brasa_bonus)
		state.items = data.get("items", state.items).duplicate()
		state.tally = data.get("tally", state.tally).duplicate()
	return state


## Heróis continuam os que o construtor fez (com as skills); o resto é recriado da linha salva.
static func _restore_units(state, data: Dictionary) -> Dictionary:
	var by_uid := {}
	var keep := {} # uid salvo -> unidade já criada pelo construtor
	if data.mode == "battle":
		for i in mini(state.units.size(), data.units.size()):
			keep[data.units[i].uid] = state.units[i]
	else:
		for i in state.party.size():
			keep[data.party_uids[i]] = state.party[i]
		if "engaged" in state:
			state.engaged.clear()
			state.fighting.clear()
		state.known.clear()
	state.units.clear()
	for row in data.units:
		var unit = keep.get(row.uid)
		if unit == null:
			unit = Unit.new(row.type, row.team, row.pos)
		unit.uid = row.uid
		unit.team = row.team
		unit.pos = row.pos
		unit.display_name = row.name
		unit.hp = row.hp
		unit.max_hp = row.max_hp
		unit.atk = row.atk
		unit.def = row.def
		unit.speed = row.speed
		unit.abilities = row.abilities.duplicate()
		# Saves de antes do Reerguer (2026-11-08): todo herói ganha a ação.
		if row.team == Data.Team.PLAYER and Data.WORLD_HEROES.has(row.type) and not unit.abilities.has("reerguer"):
			unit.abilities.append("reerguer")
		unit.clock = row.clock
		unit.moved = row.get("moved", 0)
		unit.jumped = row.get("jumped", false)
		unit.guarding = row.guarding
		unit.pending = row.pending.duplicate(true)
		unit.taunt_actions = row.taunt_actions
		var statuses: Variant = row.get("statuses", {})
		unit.statuses = statuses.duplicate(true) if statuses is Dictionary else {}
		by_uid[unit.uid] = unit
		if "known" in state:
			state.known[unit.uid] = unit
		if not row.gone:
			state.units.append(unit)
		if row.engaged:
			state.engaged[unit] = true
		if row.get("fighting", false):
			state.fighting[unit] = true
	for row in data.units:
		by_uid[row.uid].taunted_by = by_uid.get(row.taunted_by)
	return by_uid
