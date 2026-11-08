extends RefCounted
## Bolsa de cada herói: poucos espaços, guardada por tipo de herói junto do progresso
## (hero_progress.gd, chave "bag"). Guarda itens únicos, como a Chama Viva.
## A mochila da cidade (poções da loja, town_progress "bag") é outra coisa e continua igual.
##
## Chama Viva: quem a carrega usa e escolhe um ramo trancado da própria árvore,
## que fica aberto para sempre. Fora de combate, um herói pode passar um item para outro.

const HeroProgress = preload("res://scripts/hero_progress.gd")
const Skills = preload("res://scripts/skill_data.gd")
const Data = preload("res://scripts/game_data.gd")

const SIZE := 4
const ORB := "orbe_talento"
const ORB_COLOR := Color("c79bff")
const ITEMS := {
	# Sprite do PixelLab (assets/items); sem ele, o ícone desenhado "orb" de icon.gd.
	# "anim": folha com os quadros lado a lado (PixelLab animate_image), tocada em loop no mapa.
	ORB: {"name": "Chama Viva", "icon": "orb", "color": ORB_COLOR, "sprite": "res://assets/items/chama_viva.png",
		"anim": "res://assets/items/chama_viva_anim.png", "frames": 9, "fps": 10.0,
		"desc": "Abre um ramo trancado da árvore de quem a usa. Para sempre."},
}
# Onde a Chama Viva aparece no mapa. Forte da Vigília e Guardião do Farol: sempre (expedition_state).
const ORB_CHANCE := {
	"lanterna": 0.35, # Sentinela da Lanterna derrotada
	"segredo": 0.5, # baú de um segredo da planta
}


static func items(type_id: String) -> Array:
	return HeroProgress.bag(type_id)


static func count(type_id: String, item_id: String) -> int:
	return items(type_id).count(item_id)


static func free_slots(type_id: String) -> int:
	return maxi(0, SIZE - items(type_id).size())


static func item_info(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {"name": item_id, "icon": "star", "color": Color.WHITE, "desc": ""})


## Ícone do item para a interface: o sprite (pixel nítido) ou, sem ele, o ícone desenhado.
static func item_icon(item_id: String, size: float) -> Control:
	var info := item_info(item_id)
	var texture := _sprite(info.get("sprite", ""))
	if texture == null:
		var icon = preload("res://scripts/icon.gd").new()
		icon.setup(info["icon"], info["color"], size)
		return icon
	var rect := TextureRect.new()
	rect.texture = texture
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Chama Viva animada (Sprite2D com os quadros da folha). Sem a folha, o quadro parado.
## Coloque na árvore e chame `play_flame` para ela dançar. null = sem sprite nenhum.
static func flame_sprite() -> Sprite2D:
	var info := item_info(ORB)
	var sheet := _sprite(info.get("anim", ""))
	var sprite := Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sheet != null:
		sprite.texture = sheet
		sprite.hframes = int(info.get("frames", 1))
		return sprite
	sprite.texture = _sprite(info.get("sprite", ""))
	return sprite if sprite.texture != null else null


## Toca os quadros em loop (o sprite já precisa estar na árvore).
static func play_flame(sprite: Sprite2D) -> void:
	if sprite == null or sprite.hframes <= 1 or not sprite.is_inside_tree():
		return
	var frames := sprite.hframes
	var loop := sprite.create_tween().set_loops()
	loop.tween_method(func(at: float): sprite.frame = int(at) % frames, 0.0, float(frames), frames / float(item_info(ORB).get("fps", 10.0)))


## Textura do item (null sem sprite): o mapa usa para a Chama Viva flutuando nos locais.
static func sprite(item_id: String) -> Texture2D:
	return _sprite(item_info(item_id).get("sprite", ""))


## Importado pelo editor, ou lido direto do PNG (antes do editor importar o arquivo novo).
static func _sprite(path: String) -> Texture2D:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return load(path)
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


## Online, quem entrou na sala de outro vê a bolsa do dono, mas não mexe nela.
static func editable() -> bool:
	return HeroProgress.path != HeroProgress.GUEST_PATH


static func add(type_id: String, item_id: String) -> bool:
	var bag := items(type_id)
	if bag.size() >= SIZE or not Skills.has_tree(type_id):
		return false
	bag.append(item_id)
	HeroProgress.set_bag(type_id, bag)
	return true


static func remove_at(type_id: String, index: int) -> String:
	var bag := items(type_id)
	if index < 0 or index >= bag.size():
		return ""
	var item: String = bag[index]
	bag.remove_at(index)
	HeroProgress.set_bag(type_id, bag)
	return item


## Passa o item da posição `index` de um herói para outro. Quem chama confere se é fora de combate.
static func give(from_type: String, index: int, to_type: String) -> bool:
	if from_type == to_type or not editable() or free_slots(to_type) <= 0:
		return false
	if index < 0 or index >= items(from_type).size():
		return false
	var item := remove_at(from_type, index)
	return add(to_type, item)


## O herói ainda tem ramo trancado (uma Chama Viva serviria para ele).
static func wants_orb(type_id: String) -> bool:
	return Skills.has_tree(type_id) and not HeroProgress.locked_branches(type_id).is_empty()


## Usa a Chama Viva da posição `index` para abrir o ramo `branch` do próprio herói.
static func use_orb(type_id: String, index: int, branch: int) -> bool:
	if not editable() or index < 0 or index >= items(type_id).size() or items(type_id)[index] != ORB:
		return false
	if branch not in HeroProgress.locked_branches(type_id):
		return false
	if not HeroProgress.open_branch(type_id, branch):
		return false
	remove_at(type_id, index)
	return true


## Usa a primeira Chama Viva da bolsa (a árvore de skills chama assim).
static func use_first_orb(type_id: String, branch: int) -> bool:
	return use_orb(type_id, items(type_id).find(ORB), branch)


## Quem fica com uma Chama Viva achada: sorteado entre os vivos que ainda têm ramo trancado e espaço
## na bolsa; sem nenhum, entre os vivos com espaço; depois, qualquer um da party com espaço.
## "" = todas as bolsas cheias.
static func pick_holder(alive_types: Array, party_types: Array, rng: RandomNumberGenerator) -> String:
	var pools := [
		alive_types.filter(func(type_id): return free_slots(type_id) > 0 and wants_orb(type_id)),
		alive_types.filter(func(type_id): return free_slots(type_id) > 0 and Skills.has_tree(type_id)),
		party_types.filter(func(type_id): return free_slots(type_id) > 0 and Skills.has_tree(type_id)),
	]
	for pool in pools:
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]
	return ""


static func hero_name(type_id: String) -> String:
	return Data.UNIT_TYPES[type_id]["name"] if Data.UNIT_TYPES.has(type_id) else type_id
