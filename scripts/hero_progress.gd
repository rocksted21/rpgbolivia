extends RefCounted
## Progressão salva dos heróis: pontos ganhos e nós comprados, em user://.
## Sem autoload, para funcionar com o pacote de atualização e nos testes.

const Skills = preload("res://scripts/skill_data.gd")

static var path := "user://progress.cfg"


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path) # sem arquivo, começa vazio
	return config


static func earned(type_id: String) -> int:
	var value: Variant = _load().get_value(type_id, "earned", Skills.START_POINTS)
	return clampi(int(value) if value is int else Skills.START_POINTS, 0, Skills.MAX_POINTS)


static func unlocked(type_id: String) -> Array:
	return Skills.sanitize(type_id, _load().get_value(type_id, "unlocked", []), earned(type_id))


static func available(type_id: String) -> int:
	return earned(type_id) - Skills.spent(type_id, unlocked(type_id))


static func unlock(type_id: String, node_id: String) -> bool:
	var current := unlocked(type_id)
	if not Skills.can_unlock(type_id, current, node_id, earned(type_id)):
		return false
	current.append(node_id)
	_write(type_id, earned(type_id), current)
	return true


## Devolve todos os pontos do herói; redistribuir é de graça.
static func reset(type_id: String) -> void:
	_write(type_id, earned(type_id), [])


## Soma os pontos da luta. Devolve quantos heróis ganharam algo (no teto, não ganham).
static func award(type_ids: Array, gain: int) -> int:
	var rewarded := 0
	for type_id in type_ids:
		var before := earned(type_id)
		if Skills.has_tree(type_id) and before < Skills.MAX_POINTS:
			_write(type_id, mini(before + gain, Skills.MAX_POINTS), unlocked(type_id))
			rewarded += 1
	return rewarded


static func xp(type_id: String) -> int:
	var value: Variant = _load().get_value(type_id, "xp", 0)
	return maxi(0, int(value) if value is int else 0)


## Nível do herói pela experiência guardada: começa no 1.
static func level(type_id: String) -> int:
	var total := xp(type_id)
	var found := 1
	while found < Skills.HERO_LEVEL_XP.size() and total >= Skills.HERO_LEVEL_XP[found]:
		found += 1
	return found


## {level, fraction (barra até o próximo nível), max (já no último)}.
static func level_info(type_id: String) -> Dictionary:
	var current := level(type_id)
	if current >= Skills.HERO_LEVEL_XP.size():
		return {"level": current, "fraction": 1.0, "max": true}
	var floor_xp: int = Skills.HERO_LEVEL_XP[current - 1]
	var span: int = maxi(1, Skills.HERO_LEVEL_XP[current] - floor_xp)
	return {"level": current, "fraction": float(xp(type_id) - floor_xp) / span, "max": false}


## Soma experiência. Cada nível novo dá 1 ponto de skill (até o teto). Devolve quem subiu.
static func add_xp(type_ids: Array, amount: int) -> Array:
	var raised := []
	for type_id in type_ids:
		if not Skills.has_tree(type_id) or amount <= 0:
			continue
		var before := level(type_id)
		var config := _load()
		config.set_value(type_id, "xp", xp(type_id) + amount)
		var error := config.save(path)
		if error != OK:
			push_error("Não foi possível salvar a experiência: %s" % error)
		var gained := level(type_id) - before
		if gained > 0:
			_write(type_id, mini(earned(type_id) + gained, Skills.MAX_POINTS), unlocked(type_id))
			raised.append(type_id)
	return raised


## {tipo do herói: [nós]}, como vai para a sala online.
static func all_builds() -> Dictionary:
	var out := {}
	for type_id in Skills.hero_types():
		out[type_id] = unlocked(type_id)
	return out


static func _write(type_id: String, points: int, nodes: Array) -> void:
	var config := _load()
	config.set_value(type_id, "earned", points)
	config.set_value(type_id, "unlocked", nodes)
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível salvar o progresso: %s" % error)
