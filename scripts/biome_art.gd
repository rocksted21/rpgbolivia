extends RefCounted
## Qual arte de assets/biomes cada terreno usa. As regras ficam em game_data.gd e os
## arquivos são gerados por tools/build_biomes.py.

const ROOT := "res://assets/biomes/%s/%s.png"
const GROUND := {1: "campo_a", 9: "campo_b", 2: "campo_a", 3: "sombra", 5: "agua_a", 6: "sombra", 7: "campo_a", 10: "sombra", 11: "sombra", 13: "trilha"}
const DECOR_CHANCE := 0.1 # abaixo disso a casa de campo ganha um enfeite; world_gen.gd escolhe quais
const MOUNTAIN_LANDMARK := 0.08
# Altura da base de cada objeto dentro do hexágono: fundo atrás do personagem, frente diante dele.
const BACK_Y := 92
const MIDDLE_Y := 118
const FRONT_Y := 172
const BEHIND_UNIT := 3
const BEFORE_UNIT := 6


static func wall(biome: String) -> String:
	return ROOT % [biome, "parede"]


static func ground(biome: String, terrain_id: int, detail := 0.0) -> String:
	if terrain_id == 12: # calçada: só a Cidade-Farol tem
		return "res://assets/town/calcada.png"
	if terrain_id == 5 and detail >= 0.5: # a água tem duas versões: repetida, ela vira padrão
		return ROOT % [biome, "agua_b"]
	return ROOT % [biome, GROUND[terrain_id]]


## Objetos em pé de uma casa: [{path, ground_y, depth, layer}]. detail varia o desenho.
static func props(biome: String, terrain_id: int, detail: float) -> Array:
	var variant := "a" if detail < 0.5 else "b"
	match terrain_id:
		3:
			return [
				_prop(biome, "floresta_fundo_" + variant, BACK_Y, BEHIND_UNIT, "back"),
				_prop(biome, "floresta_frente_" + variant, FRONT_Y, BEFORE_UNIT, "front"),
			]
		2:
			return [_prop(biome, "pedras_" + variant, MIDDLE_Y, BEHIND_UNIT)]
		6:
			# As serras são de pedra; um monumento aparece de vez em quando.
			return [_prop(biome, "montanha_b" if detail < MOUNTAIN_LANDMARK else "montanha_a", MIDDLE_Y + 20, BEHIND_UNIT)]
		7:
			return [_prop(biome, "colinas_" + variant, MIDDLE_Y, BEHIND_UNIT)]
		10:
			return [_prop(biome, "casa", MIDDLE_Y + 20, BEHIND_UNIT)]
		11:
			return [_prop(biome, "torre", MIDDLE_Y + 20, BEHIND_UNIT)]
		1, 9:
			if detail < DECOR_CHANCE:
				var decor := "abc"[int(detail / DECOR_CHANCE * 3.0)]
				return [_prop(biome, "enfeite_" + decor, BACK_Y, BEHIND_UNIT)]
	return []


## O farol da região: aceso depois de derrotar o guardião.
static func beacon(biome: String, lit: bool) -> Dictionary:
	return _prop(biome, "farol_aceso" if lit else "farol_apagado", MIDDLE_Y + 20, BEHIND_UNIT)


static func _prop(biome: String, file: String, ground_y: int, depth: int, layer := "main") -> Dictionary:
	return {"path": ROOT % [biome, file], "ground_y": ground_y, "depth": depth, "layer": layer}
