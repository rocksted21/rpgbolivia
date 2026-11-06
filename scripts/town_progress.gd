extends RefCounted
## O que fica salvo entre as expedições: brasas, moradores, serviços e história.
## Sem autoload, para funcionar com o pacote de atualização e nos testes.

const Exp = preload("res://scripts/expedition_data.gd")
const Content = preload("res://scripts/town_content.gd")

static var path := "user://town.cfg"


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path) # sem arquivo, começa vazio
	return config


static func brasas() -> int:
	return maxi(0, int(_load().get_value("town", "brasas", 0)))


static func beacons() -> int:
	return maxi(0, int(_load().get_value("town", "beacons", 0)))


static func expeditions() -> int:
	return maxi(0, int(_load().get_value("town", "expeditions", 0)))


static func memories() -> int:
	return clampi(int(_load().get_value("town", "memories", 0)), 0, Exp.MEMORIES.size())


static func last_note() -> String:
	return str(_load().get_value("town", "last_note", ""))


## Só moradores que existem nos dados, mesmo que o arquivo tenha sido mexido.
static func rescued() -> Array:
	var saved: Variant = _load().get_value("town", "rescued", [])
	if not saved is Array:
		return []
	return Exp.RESIDENT_ORDER.filter(func(id): return id in saved)


static func service_level(resident: String) -> int:
	var costs: Array = Exp.RESIDENTS[resident]["costs"]
	return clampi(int(_load().get_value("services", resident, 0)), 0, costs.size())


## Custo da próxima melhoria; -1 se o morador não está na cidade ou já chegou ao máximo.
static func next_cost(resident: String) -> int:
	var costs: Array = Exp.RESIDENTS[resident]["costs"]
	var level := service_level(resident)
	return costs[level] if resident in rescued() and level < costs.size() else -1


static func buy(resident: String) -> bool:
	var cost := next_cost(resident)
	if cost < 0 or cost > brasas():
		return false
	var config := _load()
	config.set_value("town", "brasas", brasas() - cost)
	config.set_value("services", resident, service_level(resident) + 1)
	_save(config)
	return true


## Dados para ExpeditionState.new().
static func expedition_setup() -> Dictionary:
	var setup := {"hp": 0, "atk": 0, "def": 0, "potions": 0, "free_potions": 0, "far_compass": 0, "brasa_bonus": 0,
		"rest_heal": 0, "maps": 0, "xp_pct": 0, "potion_pct": 0, "brasa_pct": 0,
		"rescued": rescued(), "memories": memories(), "items": []}
	for id in setup["rescued"]:
		var data: Dictionary = Exp.RESIDENTS[id]
		setup[data["stat"]] += service_level(id) * data["per_level"]
	for id in Content.UPGRADE_ORDER:
		var upgrade: Dictionary = Content.UPGRADES[id]
		if upgrade["resident"] in setup["rescued"]:
			setup[upgrade["stat"]] += upgrade_level(id) * upgrade["per_level"]
	setup["free_potions"] = setup["potions"]
	setup["potions"] += item_count(Content.POTION)
	for id in Content.ITEM_ORDER:
		var item: Dictionary = Content.ITEMS[id]
		if item.has("setup") and item_count(id) > 0:
			setup["items"].append(id)
			for stat in item["setup"]:
				setup[stat] += item["setup"][stat]
	return setup


# --- Melhorias extras -----------------------------------------------------------

static func upgrade_level(id: String) -> int:
	return clampi(int(_load().get_value("upgrades", id, 0)), 0, Content.UPGRADES[id]["costs"].size())


## Custo da próxima melhoria; -1 se quem a oferece não voltou ou se já chegou ao máximo.
static func upgrade_cost(id: String) -> int:
	var costs: Array = Content.UPGRADES[id]["costs"]
	var level := upgrade_level(id)
	return costs[level] if Content.UPGRADES[id]["resident"] in rescued() and level < costs.size() else -1


static func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or cost > brasas():
		return false
	var config := _load()
	config.set_value("town", "brasas", brasas() - cost)
	config.set_value("upgrades", id, upgrade_level(id) + 1)
	_save(config)
	return true


# --- Mochila --------------------------------------------------------------------

static func item_count(id: String) -> int:
	return clampi(int(_load().get_value("bag", id, 0)), 0, Content.ITEMS[id]["max"])


static func can_buy_item(id: String) -> bool:
	return item_count(id) < Content.ITEMS[id]["max"] and Content.ITEMS[id]["price"] <= brasas()


static func buy_item(id: String) -> bool:
	if not can_buy_item(id):
		return false
	var config := _load()
	config.set_value("town", "brasas", brasas() - Content.ITEMS[id]["price"])
	config.set_value("bag", id, item_count(id) + 1)
	_save(config)
	return true


# --- Conversas e missões --------------------------------------------------------

static func met(person: String) -> bool:
	return bool(_load().get_value("met", person, false))


static func set_met(person: String) -> void:
	var config := _load()
	config.set_value("met", person, true)
	_save(config)


## "locked", "available", "active", "ready" ou "done".
static func quest_status(id: String) -> String:
	var saved := str(_load().get_value("quests", id, ""))
	if saved == "done":
		return "done"
	if saved == "active":
		return "ready" if quest_progress(id) >= Content.QUESTS[id]["target"] else "active"
	var quest: Dictionary = Content.QUESTS[id]
	if quest.has("needs_resident") and quest["needs_resident"] not in rescued():
		return "locked"
	if quest.has("needs_quest") and quest_status(quest["needs_quest"]) != "done":
		return "locked"
	return "available"


static func quest_progress(id: String) -> int:
	return clampi(int(_load().get_value("quest_progress", id, 0)), 0, Content.QUESTS[id]["target"])


static func accept_quest(id: String) -> bool:
	if quest_status(id) != "available":
		return false
	var config := _load()
	config.set_value("quests", id, "active")
	config.set_value("quest_progress", id, 0)
	_save(config)
	return true


## Entrega a missão pronta e guarda a recompensa. Item além do limite da mochila vira nada.
static func complete_quest(id: String) -> bool:
	if quest_status(id) != "ready":
		return false
	var reward: Dictionary = Content.QUESTS[id]["reward"]
	var config := _load()
	config.set_value("quests", id, "done")
	config.set_value("town", "brasas", brasas() + reward["brasas"])
	for item in reward["items"]:
		config.set_value("bag", item, mini(item_count(item) + reward["items"][item], Content.ITEMS[item]["max"]))
	_save(config)
	return true


static func quests_with(status: String) -> Array:
	return Content.QUEST_ORDER.filter(func(id): return quest_status(id) == status)


static func quests_of(person: String) -> Array:
	return Content.QUEST_ORDER.filter(func(id): return Content.QUESTS[id]["giver"] == person)


## "?" tem missão para entregar, "!" tem missão nova, "" não tem nada.
static func person_mark(person: String) -> String:
	var statuses: Array = quests_of(person).map(func(id): return quest_status(id))
	if "ready" in statuses:
		return "?"
	return "!" if "available" in statuses else ""


## Guarda o resultado de ExpeditionState.result(). Devolve as missões que ficaram prontas.
static func record(result: Dictionary) -> Array:
	var config := _load()
	var saved := rescued()
	for id in result["rescued"]:
		if id not in saved and Exp.RESIDENTS.has(id):
			saved.append(id)
	config.set_value("town", "brasas", brasas() + result["brasas"])
	config.set_value("town", "rescued", saved)
	config.set_value("town", "memories", memories() + result["memories"])
	config.set_value("town", "expeditions", expeditions() + 1)
	if result["won"]:
		config.set_value("town", "beacons", beacons() + 1)
	_spend_items(config, result)
	var finished := _advance_quests(config, result)
	config.set_value("town", "last_note", _note(result, finished))
	_save(config)
	return finished


## A expedição gasta os itens que levou e as poções usadas que não eram de graça.
static func _spend_items(config: ConfigFile, result: Dictionary) -> void:
	for id in result.get("items", []):
		config.set_value("bag", id, 0)
	var left: int = item_count(Content.POTION) - int(result.get("bag_potions_used", 0))
	config.set_value("bag", Content.POTION, maxi(left, 0))


## Soma o que a expedição fez nas missões aceitas. Devolve as que ficaram prontas agora.
static func _advance_quests(config: ConfigFile, result: Dictionary) -> Array:
	var finished := []
	var tally: Dictionary = result.get("tally", {})
	for id in Content.QUEST_ORDER:
		if str(config.get_value("quests", id, "")) != "active":
			continue
		var quest: Dictionary = Content.QUESTS[id]
		var before: int = int(config.get_value("quest_progress", id, 0))
		var now: int = mini(before + int(tally.get(quest["count"], 0)), quest["target"])
		config.set_value("quest_progress", id, now)
		if before < quest["target"] and now >= quest["target"]:
			finished.append(id)
	return finished


static func _note(result: Dictionary, finished: Array) -> String:
	var text: String = "O farol foi aceso." if result["won"] else "A party voltou derrotada."
	text += " +%d brasas." % result["brasas"]
	for id in result["rescued"]:
		text += " %s" % Exp.RESIDENTS[id]["line"]
	for id in finished:
		text += " " + Content.QUEST_READY % Content.QUESTS[id]["title"]
	return text


static func _save(config: ConfigFile) -> void:
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível salvar a cidade: %s" % error)
