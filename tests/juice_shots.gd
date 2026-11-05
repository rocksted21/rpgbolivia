extends SceneTree
## Encena golpes e magias dos 6 heróis para ver o "peso" (juice): hitstop, tremor,
## clarões, números. Só a tela: os eventos são de mentira e as regras não mudam.
## Pranchas quadro a quadro (sem --headless, tempo fixo):
##   godot --path . --fixed-fps 30 --script tests/juice_shots.gd -- <pasta> [cena]
## Vídeo de tudo: acrescente --write-movie <pasta>/juice.avi e passe "video" como cena.

const Data = preload("res://scripts/game_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

const FPS := 30
const SHEET_COLS := 4
const CROP := Vector2i(560, 315)
const THUMB := Vector2i(560, 315)
## O vídeo mostra só os momentos mais fortes.
const VIDEO_SCENES := ["Guardião · Golpe Pesado", "Duelista · Corte Giratório", "Besteiro · Virote Pesado", "Druida · Chicote de Vinhas", "Druida · Cura", "Besteiro · Saraivada", "Mago de Fogo · Explosão", "Mago de Fogo · Fênix (carregando)", "Mago de Fogo · Fênix", "Mago de Água · Kraken", "Druida · Raízes", "Esqueleto bate no Guardião", "Abate final"]

var view
var dir := ""
var only := ""
var video := false
var caption: Label
var units := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	dir = args[0]
	only = args[1] if args.size() > 1 else ""
	video = only == "video"
	if video:
		only = ""
	HeroProgress.path = "user://test_progress_juice.cfg"
	view = load("res://main.tscn").instantiate()
	root.add_child(view)
	_run()


func _run() -> void:
	for i in 40:
		await process_frame
	for unit in view.state.units:
		units[unit.type_id] = unit
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 34)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 10)
	caption.position = Vector2(470, 120)
	layer.add_child(caption)
	view.hud.visible = false

	var skel = units["esqueleto"]
	var hit := func(target, amount: int, extra := {}) -> Dictionary:
		var event := {"type": "damage", "target": target, "amount": amount, "hp": maxi(1, target.hp - amount)}
		event.merge(extra)
		return event
	var attack := func(type_id: String, id: String) -> Dictionary:
		return {"type": "attack", "unit": units[type_id], "target": skel, "ability": id}

	# Corpo a corpo: herói em (3,2), esqueleto em (4,2).
	await _scene("Guardião · Golpe", {"guardiao": Vector2i(3, 2)}, [attack.call("guardiao", "golpe"), hit.call(skel, 8)])
	await _scene("Guardião · Golpe Pesado", {"guardiao": Vector2i(3, 2)}, [attack.call("guardiao", "golpe_pesado"), hit.call(skel, 15)])
	await _scene("Duelista · Golpe Rápido", {"duelista": Vector2i(3, 2)}, [attack.call("duelista", "rapido"), hit.call(skel, 6)])
	await _scene("Duelista · Corte Giratório", {"duelista": Vector2i(3, 2)}, [attack.call("duelista", "giro"), hit.call(skel, 15)])
	await _scene("Duelista · Estocada (flanco)", {"duelista": Vector2i(3, 2), "guardiao": Vector2i(5, 2)}, [attack.call("duelista", "estocada"), hit.call(skel, 17, {"flank": true})])
	# Distância.
	await _scene("Besteiro · Tiro", {"besteiro": Vector2i(1, 2)}, [attack.call("besteiro", "tiro"), hit.call(skel, 9)])
	await _scene("Besteiro · Virote Pesado", {"besteiro": Vector2i(1, 2)}, [attack.call("besteiro", "virote_pesado"), hit.call(skel, 16)])
	await _scene("Besteiro · Virote Perfurante", {"besteiro": Vector2i(1, 2)}, [attack.call("besteiro", "perfurante"), hit.call(skel, 13)])
	await _scene("Druida · Chicote de Vinhas", {"druida": Vector2i(2, 2)}, [attack.call("druida", "vinha"), hit.call(skel, 8)])
	await _scene("Druida · Espinho", {"druida": Vector2i(1, 2)}, [attack.call("druida", "espinho"), hit.call(skel, 7)])
	await _scene("Druida · Raízes", {"druida": Vector2i(2, 2)}, [attack.call("druida", "raizes"), hit.call(skel, 5)])
	await _scene("Mago de Fogo · Bola de Fogo", {"mago": Vector2i(1, 2)}, [attack.call("mago", "bola_fogo"), hit.call(skel, 11)])
	await _scene("Mago de Água · Estaca de Gelo", {"mago_agua": Vector2i(1, 2)}, [attack.call("mago_agua", "estaca_gelo"), hit.call(skel, 13)])
	# Magias carregadas, em área.
	await _cast("Besteiro · Saraivada", "besteiro", "saraivada", Vector2i(1, 2))
	await _cast("Mago de Fogo · Explosão", "mago", "explosao", Vector2i(1, 2))
	await _cast("Mago de Fogo · Fênix", "mago", "fenix", Vector2i(1, 1))
	await _cast("Mago de Água · Kraken", "mago_agua", "kraken", Vector2i(1, 1))
	# Suporte e guarda.
	await _scene("Druida · Cura", {"druida": Vector2i(2, 2), "guardiao": Vector2i(3, 2)},
		[{"type": "heal", "unit": units["druida"], "target": units["guardiao"], "amount": 12, "hp": units["guardiao"].hp}])
	await _scene("Guardião · Provocar", {"guardiao": Vector2i(3, 2)}, [{"type": "guard", "unit": units["guardiao"], "ability": "provocar"}])
	# Inimigo acertando herói, e o abate que fecha a luta.
	await _scene("Esqueleto bate no Guardião", {"guardiao": Vector2i(3, 2)},
		[{"type": "attack", "unit": skel, "target": units["guardiao"], "ability": "golpe"}, hit.call(units["guardiao"], 9)])
	await _scene("Abate final", {"guardiao": Vector2i(3, 2)},
		[attack.call("guardiao", "golpe_pesado"), {"type": "damage", "target": skel, "amount": 22, "hp": 0}, {"type": "death", "target": skel, "final": true}], 3.0)
	quit()


func _cast(title: String, type_id: String, id: String, from: Vector2i) -> void:
	var caster = units[type_id]
	var ability: Dictionary = Data.ABILITIES[id]
	var tile := Vector2i(4, 2)
	var spots := {type_id: from, "esqueleto": Vector2i(4, 2), "diabrete": Vector2i(5, 2), "mumia": Vector2i(4, 3), "guardiao": Vector2i(2, 2)}
	if ability["radius"] >= 2:
		spots["cerbero"] = Vector2i(5, 3)
	var cells: Array = view.state.area_of(tile, ability["radius"])
	var events := [{"type": "cast_resolve", "unit": caster, "ability": ability, "id": id, "tile": tile, "cells": cells}]
	for unit in view.state.units:
		if unit.team != caster.team and cells.has(spots.get(unit.type_id, unit.pos)):
			events.append({"type": "damage", "target": unit, "amount": 8 + randi() % 8, "hp": maxi(1, unit.hp - 8)})
	caster.pending = {"ability": id, "tile": tile}
	await _scene(title + " (carregando)", spots, [{"type": "cast_start", "unit": caster, "ability": id, "tile": tile}], 1.4)
	caster.pending = {}
	await _scene(title, spots, events, 3.0)


## Põe as unidades nas casas pedidas, toca os eventos e salva a prancha.
func _scene(title: String, spots: Dictionary, events: Array, seconds := 2.2) -> void:
	if only != "" and not title.to_lower().begins_with(only.to_lower()):
		return
	if video and not VIDEO_SCENES.has(title):
		return
	# Volta todos para a formação inicial (com o esqueleto em (4,2)) antes de arrumar a cena.
	for entry in Data.BATTLE_UNITS:
		units[entry[0]].pos = Vector2i(4, 2) if entry[0] == "esqueleto" else entry[2]
	for type_id in spots:
		_place(units[type_id], spots[type_id])
	for unit in view.state.units:
		_sync(unit)
		var unit_view = view.views[unit]
		unit_view.visible = unit.alive()
		unit_view.modulate.a = 1.0
		unit_view.rotation = 0.0
		unit_view.set_hp(unit.hp)
	view._refresh_overlays()
	caption.text = title
	print("cena: ", title)
	for i in 6:
		await process_frame
	var done := [false]
	var play := func():
		await view._play(events)
		done[0] = true
	play.call()
	var focus: Vector2 = view.cell_to_screen(Vector2i(4, 2))
	var shots := []
	for i in int(seconds * FPS):
		await process_frame
		if not video and i % 3 == 1 and shots.size() < 20:
			shots.append(_crop(root.get_texture().get_image(), focus))
	while not done[0]:
		await process_frame
	for i in 10:
		await process_frame
	if not video:
		_sheet(shots, title)
	if only != "" and not video:
		root.get_texture().get_image().save_png("%s/%s_fim.png" % [dir, title.to_lower().replace(" ", "_")])


func _place(unit, cell: Vector2i) -> void:
	var other = view.state.unit_at(cell)
	if other != null and other != unit:
		other.pos = unit.pos
		_sync(other)
	unit.pos = cell
	_sync(unit)


func _sync(unit) -> void:
	var unit_view = view.views[unit]
	unit_view.position = view.feet_of(unit.pos)
	unit_view.z_index = view._z(view._row(unit.pos)) + 5
	view.battle_camera.set_elevation(view._cell_elevation(unit.pos), unit_view)
	unit_view.face_right(unit.team == Data.Team.PLAYER)


func _crop(image: Image, focus: Vector2) -> Image:
	var size := image.get_size()
	var corner := (Vector2i(focus) - CROP / 2).clamp(Vector2i.ZERO, size - CROP)
	var part := image.get_region(Rect2i(corner, CROP))
	part.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
	return part


func _sheet(shots: Array, title: String) -> void:
	if shots.is_empty():
		return
	var rows := ceili(shots.size() / float(SHEET_COLS))
	var sheet := Image.create(THUMB.x * SHEET_COLS, THUMB.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for i in shots.size():
		var shot: Image = shots[i]
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, THUMB), Vector2i((i % SHEET_COLS) * THUMB.x, (i / SHEET_COLS) * THUMB.y))
	var file := title.to_lower().replace(" · ", "_").replace(" ", "_").replace("(", "").replace(")", "")
	sheet.save_png("%s/%s.png" % [dir, file])
