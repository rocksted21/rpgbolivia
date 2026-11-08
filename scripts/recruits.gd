extends RefCounted
## Heróis que ainda não estão no roster esperam pela party na expedição (ver hero_roster.gd):
##   fumaca    · a Névoa Densa do Parque do Coreto (Subúrbios): luta contra o Andarilho, que se
##               rende quando perde a luta (smoke_duel.gd).
##   besteiro  · preso na vila mais longe do início: salvar a vila o liberta.
##   mago_agua · o Duelo do Mago de Sangue, no Desafio de Arena mais longe do início: ele se rende
##               quando perde a luta (arena_data.gd "duelo_sangue", regra "blood" em arena_state.gd).
## Quem já foi recrutado vem em town_setup["recruited"] (TownProgress.expedition_setup) e não aparece mais.
## A marca fica no próprio local ("recruit"), então volta com o save sem nada a mais.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")

const SMOKE_HERO := "fumaca"
const SMOKE_CELL := Vector2i(-11, -12) # Parque do Coreto, à beira do lago; longe das duas rotas de lanternas
const SMOKE_SPACING := 3 # se a planta mudar e um local cair em cima, o Andarilho fica para outra vez
const PRISONER := "besteiro"
const FREED_COLOR := Color("7fb6ff")


static func known(state) -> Array:
	return state.town_setup.get("recruited", [])


## Chamado no fim da montagem do mapa, depois dos outros locais. Não usa a semente:
## o resto do mapa sai igual com ou sem os heróis por recrutar.
static func place(state) -> void:
	var have := known(state)
	if SMOKE_HERO not in have and state.fixed_map:
		if state.landmarks.keys().all(func(cell): return Hex.distance(cell, SMOKE_CELL) >= SMOKE_SPACING):
			state.landmarks[SMOKE_CELL] = {"kind": "andarilho", "state": "idle", "guards": [], "hidden": false, "recruit": SMOKE_HERO}
	if PRISONER not in have:
		var villages: Array = state.landmarks.keys().filter(func(cell): return state.landmarks[cell]["kind"] == "vila")
		villages.sort_custom(func(a, b):
			var gap_a: int = Hex.distance(a, state.start_cell)
			var gap_b: int = Hex.distance(b, state.start_cell)
			return gap_a > gap_b or (gap_a == gap_b and a < b))
		if not villages.is_empty():
			state.landmarks[villages[0]]["recruit"] = PRISONER


## Depois de um local concluído: a vila que guardava o prisioneiro avisa que ele está livre.
static func on_complete(state, cell: Vector2i, events: Array) -> void:
	var entry: Dictionary = state.landmarks[cell]
	var hero: String = entry.get("recruit", "")
	if hero == "" or entry["kind"] != "vila":
		return
	var hero_name: String = Data.UNIT_TYPES[hero]["name"]
	events.append({"type": "landmark", "cell": cell, "title": "%s libertado!" % hero_name,
		"detail": "Ele estava preso na vila. Agora pode entrar na party, na Cidade-Farol.", "done": true, "color": FREED_COLOR})


## Heróis que esta expedição trouxe para o roster (entra em ExpeditionState.result()).
static func recruited(state) -> Array:
	var have := known(state)
	var out := []
	for cell in state.landmarks:
		var entry: Dictionary = state.landmarks[cell]
		var hero: String = entry.get("recruit", "")
		if hero != "" and entry["state"] == "done" and hero not in have and hero not in out:
			out.append(hero)
	return out
