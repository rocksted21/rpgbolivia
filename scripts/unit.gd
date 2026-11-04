extends RefCounted
## Estado de uma unidade em combate.

const Data = preload("res://scripts/game_data.gd")

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
var guarding := false
var pending := {} # magia carregando: {"ability": id, "tile": Vector2i}


func _init(p_type_id: String, p_team: int, p_pos: Vector2i) -> void:
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
	abilities = data["abilities"]


func alive() -> bool:
	return hp > 0
