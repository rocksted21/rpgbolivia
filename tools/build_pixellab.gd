extends SceneTree
## Converte personagens exportados do PixelLab (ZIP "all frames", extraído em
## pixellab/<id>) para o formato de folha do jogo e junta no meta.json.
## Rodar com: godot --headless --path combate --script tools/build_pixellab.gd

const SRC := "res://../pixellab"
# O tabuleiro é desenhado com escala 0.5: ampliar 2x dá 1 pixel de tela por
# pixel do sprite (tamanho original).
const PIXEL_SCALE := 2
# Linhas da folha. As 4 primeiras seguem UnitView.Anim (o HUD só usa essas);
# as outras são as variantes de frente e de costas. Lado = "east" espelhado,
# porque os sprites do jogo olham para a esquerda.
const ROWS := [
	["idle", "south"], ["walk", "side"], ["attack", "side"], ["hurt", "side"],
	["walk", "south"], ["walk", "north"],
	["attack", "south"], ["attack", "north"],
	["hurt", "south"], ["hurt", "north"],
	# Ataque forte: só entra na folha quando o personagem tem a animação.
	["strong", "side"], ["strong", "south"], ["strong", "north"],
]
# Começo do nome da animação no export (o PixelLab troca maiúsculas e às vezes
# reescreve o nome das custom). O ataque é a animação que sobra.
const NAMES := {"idle": "idle", "walk": "walking", "hurt": "jerk_backward", "strong": "strong"}
# Todo herói tem um ataque normal e um forte, usados por várias habilidades.
# Nomes que não dizem o que são ficam aqui (a Druida: cura é o normal, atack é o forte).
const RENAMES := {"druida": {"cura": "attack", "atack": "strong"}}
# Chefes dos faróis: canvas grande, então a folha fica em 1x e o jogo amplia 2x.
const BOSSES := ["boss_cervo", "boss_serpente", "boss_jarl", "boss_farao"]
# Pasta do export quando não é a própria chave (versões dark de 2026-11-06; as antigas ficam
# intactas em pixellab/guardiao, mago_agua e druida).
const SOURCES := {"guardiao": "guardiao_dark", "mago_agua": "mago_sangue", "druida": "curandeira_dark"}
# fumaca = Heroi Smoke 3 do PixelLab (389e7df3-09d9-475b-98b4-da5ce98ee454).
const CHARACTERS := ["boss_cervo", "boss_serpente", "boss_jarl", "boss_farao", "guardiao", "duelista", "besteiro", "mago", "druida", "mago_agua", "esqueleto", "mumia", "diabrete", "feiticeira", "cerbero", "fumaca"]


var pixel_scale := PIXEL_SCALE
var renames := {}


func _initialize() -> void:
	var src := ProjectSettings.globalize_path(SRC)
	var out := ProjectSettings.globalize_path("res://assets/units")
	var meta_path := out.path_join("meta.json")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	var only := Array(OS.get_cmdline_user_args()) # "-- fumaca mago": gera só esses
	for key in CHARACTERS:
		if not only.is_empty() and key not in only:
			continue
		pixel_scale = 1 if key in BOSSES else PIXEL_SCALE
		renames = RENAMES.get(key, {})
		meta[key] = _build_sheet(key, src.path_join(SOURCES.get(key, key)), "%s/%s.png" % [out, key])
	var file := FileAccess.open(meta_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(meta, "\t"))
	file.close()
	print("pixellab ok: ", CHARACTERS)
	quit()


func _build_sheet(key: String, dir: String, dst: String) -> Dictionary:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("metadata.json")))
	var frames: Dictionary = info["states"][0]["frames"]
	var anims: Dictionary = frames["animations"]
	var rest := _load(dir, frames["rotations"]["south"], false)

	var rows := []
	var cell := rest.get_size()
	var has_strong := not _frames(dir, anims, "strong", "south").is_empty()
	for spec in ROWS:
		if spec[0] == "strong" and not has_strong:
			continue
		var row := _frames(dir, anims, spec[0], spec[1])
		if row.is_empty() and spec[0] == "strong":
			row = _frames(dir, anims, "attack", spec[1])
		if row.is_empty() and spec[0] == "walk":
			# Sem o andar nessa direção, as pernas de frente servem: parado, parece que desliza.
			row = _frames(dir, anims, "walk", "south")
		if row.is_empty():
			push_warning("%s: sem %s/%s, usando a pose parada" % [key, spec[0], spec[1]])
			row = [rest]
		for img in row:
			cell = Vector2i(maxi(cell.x, img.get_width()), maxi(cell.y, img.get_height()))
		rows.append(row)

	# Morte (só de frente): última linha, quando existe. O jogo segura o último frame (o corpo).
	var death_row := -1
	var death := _frames(dir, anims, "death", "south")
	if not death.is_empty():
		death_row = rows.size()
		for img in death:
			cell = Vector2i(maxi(cell.x, img.get_width()), maxi(cell.y, img.get_height()))
		rows.append(death)

	# Os canvases das animações crescem igual para os dois lados: centralizar
	# mantém os pés no mesmo ponto em todas as linhas.
	var columns: int = rows.map(func(r): return r.size()).max()
	var sheet := Image.create(cell.x * columns, cell.y * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in rows[r].size():
			var img: Image = rows[r][c]
			var dst_pos := Vector2i(c * cell.x, r * cell.y) + (cell - img.get_size()) / 2
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), dst_pos)
	sheet.save_png(dst)

	var used := rest.get_used_rect()
	return {
		"cell_w": cell.x, "cell_h": cell.y,
		"feet_y": used.end.y + (cell.y - rest.get_height()) / 2,
		"height": used.size.y,
		"frames": columns,
		"row_frames": rows.map(func(r): return r.size()),
		"pixel": true, "directions": true,
		"texture_scale": PIXEL_SCALE / pixel_scale,
		"death_row": death_row,
	}


func _frames(dir: String, anims: Dictionary, kind: String, direction: String) -> Array:
	var source := "east" if direction == "side" else direction
	# Prefere a versão com as três direções: sobras de testes no PixelLab
	# costumam ter só uma.
	for complete in [true, false]:
		for anim in anims:
			var dirs: Dictionary = anims[anim]
			if _kind_of(anim) != kind or not dirs.has(source):
				continue
			if complete and not (dirs.has("south") and dirs.has("east") and dirs.has("north")) and kind != "idle" and kind != "death":
				continue
			return dirs[source].map(func(path): return _load(dir, path, direction == "side"))
	return []


func _kind_of(anim: String) -> String:
	if renames.has(anim.to_lower()):
		return renames[anim.to_lower()]
	if anim.to_lower().contains("strong"): # "attack_strong", "2_attack_strong"...
		return "strong"
	# Morte dos heróis (2026-11-08): o PixelLab nomeia pelo começo do prompt ("Recoil_violently…",
	# "Jolt_backward…"). Se o prompt mudar, ponha o começo novo aqui.
	for prefix in ["recoil", "jolt", "death"]:
		if anim.to_lower().begins_with(prefix):
			return "death"
	for kind in NAMES:
		if anim.to_lower().begins_with(NAMES[kind]):
			return kind
	return "attack"


func _load(dir: String, path: String, mirror: bool) -> Image:
	var img := Image.load_from_file(dir.path_join(path))
	img.convert(Image.FORMAT_RGBA8)
	img.resize(img.get_width() * pixel_scale, img.get_height() * pixel_scale, Image.INTERPOLATE_NEAREST)
	if mirror:
		img.flip_x()
	return img
