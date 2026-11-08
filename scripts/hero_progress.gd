extends RefCounted
## Progressão salva dos heróis: pontos ganhos e nós comprados, em user://.
## Sem autoload, para funcionar com o pacote de atualização e nos testes.

const Skills = preload("res://scripts/skill_data.gd")

const OWN_PATH := "user://progress.cfg"
## Online, quem entra na sala de outro joga com o progresso do mundo dele: uma cópia à parte,
## para o save próprio não mudar.
const GUEST_PATH := "user://progress_sala.cfg"

## Ramos da árvore abertos desde o começo (a partir da esquerda). Os outros pedem um Orbe de Talento.
const START_BRANCHES := 1

static var path := OWN_PATH
static var own_path := OWN_PATH # o save de antes de entrar na sala (os testes usam outro)


## Partida nova, solo ou online: não herda experiência nem habilidades da anterior.
static func new_game() -> Error:
	use_own()
	var config := ConfigFile.new()
	for type_id in Skills.hero_types():
		config.set_value(type_id, "xp", 0)
		config.set_value(type_id, "earned", Skills.START_POINTS)
		config.set_value(type_id, "unlocked", [])
	return config.save(path)


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path) # sem arquivo, começa vazio
	return config


static func earned(type_id: String) -> int:
	var value: Variant = _load().get_value(type_id, "earned", Skills.START_POINTS)
	return clampi(int(value) if value is int else Skills.START_POINTS, 0, Skills.MAX_POINTS)


## Nós comprados, só dos ramos abertos (um ramo trancado não vale, mesmo vindo de fora).
static func unlocked(type_id: String) -> Array:
	var open := open_branches(type_id)
	return _raw_unlocked(type_id).filter(func(node_id): return Skills.locate(type_id, node_id)["branch"] in open)


static func _raw_unlocked(type_id: String) -> Array:
	return Skills.sanitize(type_id, _load().get_value(type_id, "unlocked", []), earned(type_id))


# --- Ramos trancados (Orbe de Talento) ------------------------------------------

## Ramos da árvore abertos (índices). Os primeiros START_BRANCHES nascem abertos; os outros
## abrem com um Orbe de Talento, para sempre. Save antigo sem a chave: todo ramo que já tem
## nó comprado conta como aberto, e isso fica gravado (redistribuir não tranca de novo).
static func open_branches(type_id: String) -> Array:
	var saved := _load()
	if saved.has_section_key(type_id, "branches"): # get_value sem padrão reclama da chave que falta
		return _clean_branches(type_id, saved.get_value(type_id, "branches", []))
	var open := _legacy_branches(type_id, _raw_unlocked(type_id))
	if Skills.has_tree(type_id):
		var config := _load()
		config.set_value(type_id, "branches", open)
		config.save(path)
	return open


static func locked_branches(type_id: String) -> Array:
	var open := open_branches(type_id)
	var out := []
	for branch in Skills.tree(type_id).size():
		if branch not in open:
			out.append(branch)
	return out


static func is_branch_open(type_id: String, branch: int) -> bool:
	return branch in open_branches(type_id)


## O nó fica num ramo aberto (a tela usa para mostrar o cadeado).
static func can_reach(type_id: String, node_id: String) -> bool:
	var found := Skills.locate(type_id, node_id)
	return not found.is_empty() and found["branch"] in open_branches(type_id)


## Abre um ramo trancado. Quem gasta o orbe é hero_bag.gd; aqui só se grava.
static func open_branch(type_id: String, branch: int) -> bool:
	var open := open_branches(type_id)
	if branch in open or branch < 0 or branch >= Skills.tree(type_id).size():
		return false
	open.append(branch)
	open.sort()
	var config := _load()
	config.set_value(type_id, "branches", open)
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível salvar o ramo aberto: %s" % error)
	return true


static func _legacy_branches(type_id: String, nodes: Array) -> Array:
	var open := []
	for branch in mini(START_BRANCHES, Skills.tree(type_id).size()):
		open.append(branch)
	for node_id in nodes:
		var found := Skills.locate(type_id, node_id)
		if not found.is_empty() and found["branch"] not in open:
			open.append(found["branch"])
	open.sort()
	return open


static func _clean_branches(type_id: String, value: Variant) -> Array:
	var open := []
	for branch in mini(START_BRANCHES, Skills.tree(type_id).size()):
		open.append(branch)
	if value is Array:
		for entry in value:
			if (entry is int or entry is float) and int(entry) >= 0 and int(entry) < Skills.tree(type_id).size() and int(entry) not in open:
				open.append(int(entry))
	open.sort()
	return open


# --- Bolsa do herói (itens únicos, como o Orbe; regras em hero_bag.gd) ----------

static func bag(type_id: String) -> Array:
	var value: Variant = _load().get_value(type_id, "bag", [])
	var out := []
	if value is Array:
		for item in value:
			if item is String or item is StringName:
				out.append(str(item))
	return out


static func set_bag(type_id: String, items: Array) -> void:
	var config := _load()
	config.set_value(type_id, "bag", items)
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível salvar a bolsa: %s" % error)


static func available(type_id: String) -> int:
	return earned(type_id) - Skills.spent(type_id, unlocked(type_id))


static func unlock(type_id: String, node_id: String) -> bool:
	var current := unlocked(type_id)
	if not Skills.can_unlock(type_id, current, node_id, earned(type_id)) or not can_reach(type_id, node_id):
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


## Todo o progresso, como o dono da sala manda: {tipo do herói: {xp, earned, unlocked, branches, bag}}.
static func export_all() -> Dictionary:
	var out := {}
	for type_id in Skills.hero_types():
		out[type_id] = {xp = xp(type_id), earned = earned(type_id), unlocked = unlocked(type_id), branches = open_branches(type_id), bag = bag(type_id)}
	return out


## Quem entrou na sala passa a usar o progresso do dono (em GUEST_PATH, não no save próprio).
static func use_host(data: Variant) -> void:
	if path != GUEST_PATH:
		own_path = path
	path = GUEST_PATH
	var config := ConfigFile.new()
	if data is Dictionary:
		for type_id in Skills.hero_types():
			var entry: Variant = data.get(type_id)
			if not entry is Dictionary:
				continue
			var points: int = clampi(int(entry.get("earned", Skills.START_POINTS)) if entry.get("earned") is int else Skills.START_POINTS, 0, Skills.MAX_POINTS)
			config.set_value(type_id, "xp", maxi(0, int(entry.get("xp", 0)) if entry.get("xp") is int else 0))
			config.set_value(type_id, "earned", points)
			var nodes := Skills.sanitize(type_id, entry.get("unlocked", []), points)
			config.set_value(type_id, "unlocked", nodes)
			# Dono numa versão sem ramos trancados: o que ele já comprou conta como aberto.
			var branches: Variant = entry.get("branches")
			config.set_value(type_id, "branches", _clean_branches(type_id, branches) if branches is Array else _legacy_branches(type_id, nodes))
			var items: Variant = entry.get("bag", [])
			config.set_value(type_id, "bag", (items as Array).filter(func(item): return item is String).slice(0, 4) if items is Array else [])
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível guardar o progresso da sala: %s" % error)


## Saiu da sala: volta para o save próprio.
static func use_own() -> void:
	if path == GUEST_PATH:
		path = own_path


static func _write(type_id: String, points: int, nodes: Array) -> void:
	var config := _load()
	config.set_value(type_id, "earned", points)
	config.set_value(type_id, "unlocked", nodes)
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível salvar o progresso: %s" % error)
