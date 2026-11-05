extends RefCounted
## O que fica salvo entre as expedições: brasas, moradores, serviços e história.
## Sem autoload, para funcionar com o pacote de atualização e nos testes.

const Exp = preload("res://scripts/expedition_data.gd")

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
	var setup := {"hp": 0, "atk": 0, "rescued": rescued(), "memories": memories()}
	for id in setup["rescued"]:
		var data: Dictionary = Exp.RESIDENTS[id]
		setup[data["stat"]] += service_level(id) * data["per_level"]
	return setup


## Guarda o resultado de ExpeditionState.result().
static func record(result: Dictionary) -> void:
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
	config.set_value("town", "last_note", _note(result))
	_save(config)


static func _note(result: Dictionary) -> String:
	var text: String = "O farol foi aceso." if result["won"] else "A party voltou derrotada."
	text += " +%d brasas." % result["brasas"]
	for id in result["rescued"]:
		text += " %s" % Exp.RESIDENTS[id]["line"]
	return text


static func _save(config: ConfigFile) -> void:
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível salvar a cidade: %s" % error)
