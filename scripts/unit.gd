extends RefCounted
## Estado de uma unidade em combate.

const Data = preload("res://scripts/game_data.gd")
const Skills = preload("res://scripts/skill_data.gd")

var type_id: String
var display_name: String
var role: String # classe: "Tanque · segura a linha"
var team: int
var pos: Vector2i
var hp: int
var max_hp: int
var atk: int
var def: int
var speed: int
var abilities: Array
var clock := 0
var moved := 0 # pontos de movimento gastos neste turno
var guarding := false
var pending := {} # magia carregando: {"ability": id, "tile": Vector2i}
var passives := {} # regras especiais das skills (ver skill_data.gd)
var ability_mods := {} # {habilidade: {campo: soma}}
var taunted_by = null # quem a IA é obrigada a perseguir
var taunt_actions := 0
var statuses := {} # efeitos com duração: {id: {"turns": n, "amount": x}} (ver Data.STATUS)
var uid := 0 # identifica a unidade na rede, mesmo com inimigos entrando e saindo


func _init(p_type_id: String, p_team: int, p_pos: Vector2i, build: Array = []) -> void:
	var data: Dictionary = Data.UNIT_TYPES[p_type_id]
	type_id = p_type_id
	display_name = data["name"]
	role = data.get("role", "")
	team = p_team
	pos = p_pos
	hp = data["hp"]
	max_hp = data["hp"]
	atk = data["atk"]
	def = data["def"]
	speed = data["speed"]
	abilities = data["abilities"].duplicate()
	for node_id in build:
		var found: Dictionary = Skills.locate(p_type_id, node_id)
		if not found.is_empty():
			_apply_node(found["node"])


func _apply_node(node: Dictionary) -> void:
	if node.has("unlock") and node["unlock"] not in abilities:
		abilities.append(node["unlock"])
	var stats: Dictionary = node.get("stats", {})
	hp += stats.get("hp", 0)
	max_hp += stats.get("hp", 0)
	atk += stats.get("atk", 0)
	def += stats.get("def", 0)
	speed += stats.get("speed", 0)
	passives.merge(node.get("passive", {}), true)
	for ability_id in node.get("mods", {}):
		var mods: Dictionary = ability_mods.get_or_add(ability_id, {})
		for key in node["mods"][ability_id]:
			mods[key] = mods.get(key, 0) + node["mods"][ability_id][key]


## Dados da habilidade para esta unidade, já com as skills aplicadas.
func ability(ability_id: String) -> Dictionary:
	var base: Dictionary = Data.ABILITIES[ability_id]
	var has_cast_mult: bool = passives.has("cast_mult") and base.has("cast_time")
	if not ability_mods.has(ability_id) and not has_cast_mult:
		return base
	var out := base.duplicate()
	var mods: Dictionary = ability_mods.get(ability_id, {})
	for key in mods:
		out[key] = out.get(key, 0) + mods[key]
	if has_cast_mult:
		out["cast_time"] = roundi(out["cast_time"] * passives["cast_mult"])
	return out


func passive(key: String, fallback: Variant = null) -> Variant:
	return passives.get(key, fallback)


func has_status(id: String) -> bool:
	return statuses.has(id)


## Nomes dos efeitos ativos, para o texto embaixo da unidade.
func status_names() -> Array:
	var out := []
	for id in statuses:
		out.append(Data.STATUS[id]["name"])
	return out


func alive() -> bool:
	return hp > 0
