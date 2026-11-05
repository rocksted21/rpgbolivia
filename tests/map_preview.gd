extends SceneTree
## Desenha o mapa visto de cima, para comparar o gerador sem abrir o jogo. Rodar:
## godot --headless --path . --script tests/map_preview.gd -- <arquivo.png> [semente] [raio]

const WorldGen = preload("res://scripts/world_gen.gd")

const CELL := 4
const BIOME_COLOR := {
	"floresta": Color("7d8446"), "selva": Color("3c5038"), "neve": Color("dfe6ee"), "deserto": Color("d9ab5e"),
}
const TERRAIN_COLOR := {
	WorldGen.WATER: Color("2c5f7f"), WorldGen.MOUNTAIN: Color("35343a"), WorldGen.FOREST: Color("1f3d26"),
	WorldGen.HILLS: Color("8a7a58"), WorldGen.ROCKS: Color("85858a"), WorldGen.HOUSE: Color("e0402a"), WorldGen.TOWER: Color("e040d0"),
	WorldGen.PATH: Color("d98c4a"),
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var world_seed := int(args[1]) if args.size() > 1 else 42
	var radius := int(args[2]) if args.size() > 2 else 100
	var gen = WorldGen.new(world_seed)
	var start: Vector2i = gen.find_start()
	var size := radius * 2 * CELL
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for row in range(-radius, radius):
		for col in range(-radius, radius):
			var cell := start + Vector2i(col, row)
			var spot: Dictionary = gen.sample(cell)
			var color: Color = TERRAIN_COLOR.get(spot["terrain"], BIOME_COLOR[spot["biome"]])
			color = color.darkened(0.16 * (WorldGen.MAX_LEVEL - spot["elevation"]) / WorldGen.MAX_LEVEL)
			if spot.get("decor", false):
				color = Color("ffb070")
			var x := (col + radius) * CELL + (cell.y & 1) * CELL / 2
			image.fill_rect(Rect2i(x, (row + radius) * CELL, CELL, CELL), color)
	image.fill_rect(Rect2i(radius * CELL - 4, radius * CELL - 4, 8, 8), Color.RED)
	image.save_png(args[0])
	quit()
