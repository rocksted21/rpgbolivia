extends SceneTree
## Gera os assets do jogo a partir do kit (fica fora do projeto).
## Rodar com: godot --headless --path combate --script tools/build_assets.gd

const KIT := "res://../tactical-strategy-game-kit"
const SCALE := 0.58
const ANIMS := ["idle", "walk", "attack", "hurt"]
const FRAME_STEP := 2 # o kit tem 20 frames; usamos 10
const CHARACTERS := {
	"guardiao": ["people", "human", 2],
	"duelista": ["elf", "elves", 1],
	"besteiro": ["people", "human", 3],
	"mago_agua": ["people", "human", 5],
	# mago e druida vêm do PixelLab (tools/build_pixellab.gd)
	"esqueleto": ["undead", "undead", 1],
	"mumia": ["undead", "undead", 4],
	"diabrete": ["demon", "demons", 1],
	"feiticeira": ["demon", "demons", 4],
	"cerbero": ["demon", "demons", 7],
}
# Efeitos de magia (família de quadros soltos, fora do projeto como o kit).
# A chave é o caminho dentro de assets/fx: uma pasta por elemento.
const SPELL_PACKS := "res://../efeitos-pixelart"
const SPELL_FX := {
	"fogo/fireball": "fire-magic-effects-pixel-art/PNG/Fireball",
	"fogo/fire": "fire-magic-effects-pixel-art/PNG/Fire",
	"fogo/small_fire": "fire-magic-effects-pixel-art/PNG/Small_fire",
	"fogo/fire_flower": "fire-magic-effects-pixel-art/PNG/Fire_flower",
	"fogo/fire_hurricane": "fire-magic-effects-pixel-art/PNG/Fire_hurracane",
	"fogo/fire_pillar": "fire-magic-effects-pixel-art/PNG/Fire_pillar",
	"fogo/fire_shield": "fire-magic-effects-pixel-art/PNG/Fire_shield",
	"fogo/lava_drop": "fire-magic-effects-pixel-art/PNG/Lava_drop",
	"fogo/lava_puddle": "fire-magic-effects-pixel-art/PNG/Lava_paddle",
	"fogo/magma_geyser": "fire-magic-effects-pixel-art/PNG/Magma_geyser",
	"fogo/phoenix": "fire-magic-effects-pixel-art/PNG/Phoenix",
	"fogo/explosion": "magic-sprite-effects-and-icons-pack/PNG/Explosion",
	"fogo/sun_strike": "magic-sprite-effects-and-icons-pack/PNG/Sun_strike",
	"agua/water_drop": "water-effects-pixel-art-set/PNG/Water_drop",
	"agua/water_whip": "water-effects-pixel-art-set/PNG/Water_whip",
	"agua/waterball": "water-effects-pixel-art-set/PNG/Waterball",
	"agua/splash": "water-effects-pixel-art-set/PNG/Water_and_splash/Splash",
	"agua/ice_spike": "water-effects-pixel-art-set/PNG/Ice_spike",
	"agua/ice_crystal": "water-effects-pixel-art-set/PNG/Ice_crystal",
	"agua/snowflake": "water-effects-pixel-art-set/PNG/Snowflake",
	"agua/ice_burst": "magic-effects-pixel-art-pack/PNG/ice",
	"agua/geyser": "water-effects-pixel-art-set/PNG/Geyser",
	"agua/water_hurricane": "water-effects-pixel-art-set/PNG/Water_hurricane",
	"agua/kraken": "water-effects-pixel-art-set/PNG/Kraken",
}


func _initialize() -> void:
	var kit := ProjectSettings.globalize_path(KIT)
	var out := ProjectSettings.globalize_path("res://assets")
	for sub in ["units", "tiles", "fx/kit", "fx/fogo", "fx/agua"]:
		DirAccess.make_dir_recursive_absolute(out.path_join(sub))

	# Junta no meta.json existente: os personagens do PixelLab ficam como estão.
	var meta_path := out.path_join("units/meta.json")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path)) if FileAccess.file_exists(meta_path) else {}
	for key in CHARACTERS:
		meta[key] = _build_sheet(kit, out, key, CHARACTERS[key])
	var file := FileAccess.open(meta_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(meta, "\t"))
	file.close()

	for id in range(1, 12):
		var src := "%s/tactical-strategy-game-tileset/PNG/tail_1/%d.png" % [kit, id]
		DirAccess.copy_absolute(src, "%s/tiles/%d.png" % [out, id])

	var fx_dir := kit + "/2d-fantasy-people-warrior-character-sprites/PNG/human/effect"
	for fx in ["arrow", "magic", "heal"]:
		var img := Image.load_from_file("%s/1_animation_%s_010.png" % [fx_dir, fx])
		img.get_region(img.get_used_rect()).save_png("%s/fx/kit/%s.png" % [out, fx])

	var spell_meta := {}
	for key in SPELL_FX:
		spell_meta[key] = _build_strip(ProjectSettings.globalize_path(SPELL_PACKS).path_join(SPELL_FX[key]), "%s/fx/%s.png" % [out, key])
	file = FileAccess.open(out.path_join("fx/meta.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(spell_meta, "\t"))
	file.close()

	print("assets ok: ", meta.size(), " personagens, ", spell_meta.size(), " efeitos")
	quit()


# Os packs de efeito vêm um PNG por frame; juntamos numa tira horizontal.
func _build_strip(dir: String, dst: String) -> Dictionary:
	var names := Array(DirAccess.get_files_at(dir)).filter(func(n): return n.ends_with(".png"))
	names.sort_custom(func(a, b): return _frame_number(a) < _frame_number(b))
	var first := Image.load_from_file(dir.path_join(names[0]))
	var strip := Image.create(first.get_width() * names.size(), first.get_height(), false, Image.FORMAT_RGBA8)
	for i in names.size():
		var img := Image.load_from_file(dir.path_join(names[i]))
		img.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * first.get_width(), 0))
	strip.save_png(dst)
	return {"frames": names.size(), "w": first.get_width(), "h": first.get_height()}


func _frame_number(file_name: String) -> int:
	var regex := RegEx.create_from_string("(\\d+)\\.png$")
	return int(regex.search(file_name).get_string(1))


func _build_sheet(kit: String, out: String, key: String, info: Array) -> Dictionary:
	var n: int = info[2]
	var dir := "%s/2d-fantasy-%s-warrior-character-sprites/PNG/%s/%d" % [kit, info[0], info[1], n]

	# O canvas muda de uma animação para outra, mas o frame 0 é sempre a pose
	# de repouso: alinhar por ele mantém os pés no mesmo ponto em todas.
	var rows := []
	var half_w := 0
	var above := 0
	var below := 0
	var frame_count := 0
	var height := 0
	for anim in ANIMS:
		var frames := []
		for i in range(0, 20, FRAME_STEP):
			var img := Image.load_from_file("%s/%d_animation_%s_%03d.png" % [dir, n, anim, i])
			img.convert(Image.FORMAT_RGBA8)
			img.resize(int(img.get_width() * SCALE), int(img.get_height() * SCALE), Image.INTERPOLATE_LANCZOS)
			frames.append(img)
		frame_count = frames.size()
		var rest: Rect2i = frames[0].get_used_rect()
		var feet := Vector2i(rest.position.x + rest.size.x / 2, rest.end.y)
		height = maxi(height, rest.size.y)
		for img in frames:
			if img.get_size() != frames[0].get_size():
				push_warning("%s/%s: frames com tamanhos diferentes" % [key, anim])
			half_w = maxi(half_w, maxi(feet.x, img.get_width() - feet.x))
			above = maxi(above, feet.y)
			below = maxi(below, img.get_height() - feet.y)
		rows.append({"frames": frames, "feet": feet})

	var cell := Vector2i(half_w * 2, above + below)
	var sheet := Image.create(cell.x * frame_count, cell.y * ANIMS.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		var feet: Vector2i = rows[r]["feet"]
		for c in frame_count:
			var img: Image = rows[r]["frames"][c]
			var dst := Vector2i(c * cell.x + half_w - feet.x, r * cell.y + above - feet.y)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), dst)
	sheet.save_png("%s/units/%s.png" % [out, key])
	return {"cell_w": cell.x, "cell_h": cell.y, "feet_y": above, "height": height, "frames": frame_count}
