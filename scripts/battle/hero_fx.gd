extends RefCounted

## Peso dos golpes dos heróis (juice): golpes, magias, dano, morte, chuva de flechas,
## rastros e números que saltam. Os pesos ficam em hero_juice.gd.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const UnitView = preload("res://scripts/unit_view.gd")
const HeroJuice = preload("res://scripts/hero_juice.gd")
const BattleJuice = preload("res://scripts/battle_juice.gd")

# Só apresentação: os eventos e as regras são os mesmos. Muda quando o golpe acerta
# (no frame do impacto, não no fim da animação) e o peso dele na tela: hitstop,
# tremor, clarão, tranco, números que saltam. Pesos em hero_juice.gd.
const RAIN_FALL := 0.24 # tempo de queda de cada virote da chuva
const RAIN_HEIGHT := 520.0
const RAIN_DRIFT := 160.0

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


## Ponto da tela de algo desenhado no tabuleiro.
func _screen_point(board_point: Vector2, elevation := 0.0) -> Vector2:
	return battle.battle_camera.project(battle.board.global_transform * board_point, elevation)


func _view_screen(view) -> Vector2:
	return _screen_point(view.position, battle.battle_camera.elevation_of(view)) + Vector2(0, -45)


## Direção na tela de `from` até `to` (pontos do tabuleiro).
func _screen_dir(from: Vector2, to: Vector2) -> Vector2:
	var delta := _screen_point(to, battle._height_at_point(to)) - _screen_point(from, battle._height_at_point(from))
	return delta.normalized() if delta.length() > 1.0 else Vector2.ZERO


func _impact_fraction(unit, anim: UnitView.Anim) -> float:
	if anim == UnitView.Anim.STRONG:
		return HeroJuice.STRONG_HIT.get(unit.type_id, 0.5)
	return HeroJuice.ATTACK_HIT


## Espera a animação que está tocando chegar em `fraction` dos frames dela.
func _wait_anim_frame(view, fraction: float) -> void:
	var target := int(round(view.anim_frame_count() * fraction))
	var guard := 0
	while is_instance_valid(view) and not view.looping and int(view.frame_pos) < target and guard < 300:
		guard += 1
		await battle.get_tree().process_frame


## A luta acaba com este golpe: o último abate ganha câmera lenta.
func _mark_final_kill(events: Array) -> void:
	var last := -1
	var ends := false
	for i in events.size():
		match events[i]["type"]:
			"death":
				last = i
			"combat_end":
				ends = true
	if last < 0:
		return
	var decided: bool = ends or battle.state.winner() >= 0
	if not decided and battle.exploring and battle.state.in_combat():
		decided = battle.state.engaged.keys().all(func(u): return not u.alive())
	if decided:
		events[last]["final"] = true


func _play_hero_attack(event: Dictionary, weight: Dictionary) -> void:
	var unit = event["unit"]
	var view = battle.views[unit]
	var target_view = battle.views[event["target"]]
	var id: String = event.get("ability", "")
	var magic := battle.SPELL_FX.has(id)
	var shot: String = Data.ABILITIES[id].get("shot", "") if Data.ABILITIES.has(id) else ""
	var anim := battle.event_player._attack_anim(unit, id)
	var dir := _screen_dir(view.position, target_view.position)
	weight["dir"] = dir
	if not magic:
		battle.sound_manager.play_sfx(&"swing")
	view.play_once(anim)
	var fraction := _impact_fraction(unit, anim)
	var reach: float = view.anim_frame_count() * fraction / UnitView.FPS
	if shot == "" and not magic:
		view.lunge(dir * weight.get("lunge", 34), reach, 0.12, 0.3)
		var ghosts: int = weight.get("ghosts", 0)
		for i in ghosts:
			battle.get_tree().create_timer(reach * (0.45 + 0.55 * i / maxf(ghosts, 1))).timeout.connect(_ghost.bind(view, weight["color"]))
	await _wait_anim_frame(view, fraction)
	battle.hit_ctx = weight
	battle.hit_ctx["attacker"] = unit
	battle.hit_ctx["hits"] = 0
	battle.hit_ctx["screen_done"] = magic
	if shot != "":
		if weight.has("recoil"):
			view.knock(-dir * weight["recoil"], 0.22)
		_play_fx_layers(HeroJuice.muzzle_fx(weight["color"]), view.position + dir * 50.0, dir)
		await battle.event_player._fly_projectile(shot, view.position + Vector2(0, -90), target_view.position + Vector2(0, -90), weight.get("trail", Color(0, 0, 0, 0)))
		battle.sound_manager.play_sfx(&"arrow_hit")
	elif magic:
		await battle.event_player._play_spell_fx(id, view.position + Vector2(0, -90), [target_view.position], weight)
	else:
		battle.sound_manager.play_sfx(&"melee_hit")
		if weight.get("heavy", false):
			battle.sound_manager.play_sfx(&"explosion")


func _play_hero_cast(event: Dictionary, weight: Dictionary) -> void:
	var unit = event["unit"]
	var view = battle.views[unit]
	var id: String = event["id"]
	var center: Vector2 = battle.feet_of(event["tile"])
	battle.hit_from = center
	battle.marks_ctl._refresh_overlays()
	var ult: bool = weight.get("ult", false)
	var color: Color = weight["color"]
	if ult:
		# Magia máxima: o mundo escurece e só o mago e a magia brilham.
		battle.juice.dim(0.6, 0.35)
		view.z_index = BattleJuice.DIM_Z + 10
		battle.juice.shake(0.18)
		_play_fx_layers(HeroJuice.cast_fx(color), view.position, Vector2.UP)
		battle.sound_manager.play_sfx(&"charge")
	view.clear_aura(true)
	view.set_status("") # a magia saiu: some o "magia em N"
	view.flash(Color(color.r * 3.0 + 0.6, color.g * 3.0 + 0.6, color.b * 3.0 + 0.6), 0.25)
	view.play_once(UnitView.Anim.STRONG)
	await _wait_anim_frame(view, _impact_fraction(unit, UnitView.Anim.STRONG))
	weight["dir"] = _screen_dir(view.position, center)
	weight["center"] = center
	battle.hit_ctx = weight
	battle.hit_ctx["attacker"] = unit
	battle.hit_ctx["area"] = true
	battle.hit_ctx["hits"] = 0
	battle.hit_ctx["screen_done"] = true
	if battle.SPELL_FX.has(id):
		var spots := [center]
		if battle.SPELL_FX[id].get("per_cell", false):
			var cells: Array = event["cells"].duplicate()
			cells.sort_custom(func(a, b): return Hex.distance(a, event["tile"]) < Hex.distance(b, event["tile"]))
			spots = cells.map(func(cell): return battle.feet_of(cell))
		await battle.event_player._play_spell_fx(id, view.position + Vector2(0, -90), spots, weight)
	elif weight.has("rain"):
		await _arrow_rain(event["cells"], weight)
	else:
		await battle.event_player._fly_projectile(Data.ABILITIES[id].get("shot", "kit/magic"), view.position + Vector2(0, -90), center + Vector2(0, -20), weight.get("trail", Color(0, 0, 0, 0)))
		_hero_impact(weight, center)
	# A área acende na cor do herói, sem segurar o dano.
	var tween := battle.create_tween().set_parallel()
	var flashes := []
	for cell in event["cells"]:
		var flash := Polygon2D.new()
		flash.polygon = battle.hex_poly
		battle._place_ground_marker(flash, cell)
		flash.color = Color(color.r * 0.5 + 0.5, color.g * 0.5 + 0.5, color.b * 0.5 + 0.5, 0.6)
		flash.position = battle.cell_origin(cell)
		flash.z_index = 880
		battle.board.add_child(flash)
		flashes.append(flash)
		tween.tween_property(flash, "modulate:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		for flash in flashes:
			flash.queue_free())
	if ult:
		battle.get_tree().create_timer(0.7).timeout.connect(func():
			if is_instance_valid(view):
				view.z_index = battle._z(battle._row(unit.pos)) + 5)


## O impacto na tela: tremor, tranco, clarão, zoom e as camadas no centro.
func _hero_impact(weight: Dictionary, center: Vector2) -> void:
	var trauma: float = weight.get("shake", 0.2)
	battle.juice.shake(trauma)
	battle.juice.push(weight.get("dir", Vector2.ZERO), 14.0 * trauma)
	if weight.has("flash"):
		battle.juice.flash(weight["flash"], 0.3)
	if weight.has("zoom"):
		battle.juice.punch_zoom(_screen_point(center, battle._height_at_point(center)) + Vector2(0, -40), weight["zoom"], 0.55)
	if weight.has("impact"):
		_play_fx_layers(weight["impact"], center, weight.get("dir", Vector2.RIGHT))
	if weight.get("ult", false):
		battle.juice.dim(0.0, 0.6)


func _play_hero_damage(event: Dictionary) -> void:
	var target = event["target"]
	var view = battle.views[target]
	view.set_hp(event["hp"])
	var weight := battle.hit_ctx
	var hero_target := HeroJuice.is_hero(target.type_id)
	var lethal: bool = event["hp"] <= 0
	var flank: bool = event.get("flank", false)
	var amount: int = event["amount"]
	var share := clampf(float(amount) / maxf(target.max_hp, 1), 0.0, 1.0)
	var area: bool = weight.get("area", false)
	var from: Vector2 = weight.get("center", battle.hit_from) if area else battle.hit_from
	var dir := _screen_dir(from, view.position)
	if dir == Vector2.ZERO:
		dir = Vector2(randf_range(-1.0, 1.0), -0.4).normalized()
	battle.sound_manager.play_sfx(&"hurt")
	view.play_once(UnitView.Anim.HURT)
	if hero_target:
		battle.juice.pulse_vignette(Color(0.85, 0.04, 0.04, 0.3 + 0.6 * clampf(share * 2.5, 0.0, 1.0)), 0.55)
	if weight.is_empty():
		# Um inimigo acertou um herói: leve, mas dá para sentir.
		view.flash(Color(4.0, 1.3, 1.2))
		view.knock(dir * (24.0 + 40.0 * share))
		view.squash(0.12)
		battle.juice.jitter(view.sprite, 5.0, 0.08)
		battle.juice.hitstop(0.035 + 0.05 * share)
		battle.juice.shake(0.14 + 0.35 * share)
		_pop_number(view.position, str(amount), Color(1.0, 0.32, 0.28), 1.0 + share, "FLANCO!" if flank else "")
		await battle.get_tree().create_timer(0.25).timeout
		return
	var first: bool = weight["hits"] == 0
	weight["hits"] += 1
	var power := 1.0 + (0.4 if flank else 0.0) + (0.5 if lethal else 0.0)
	view.flash()
	view.squash(minf(0.18 * power, 0.32))
	view.knock(dir * weight.get("knock", 30) * power)
	var stop: float = weight.get("stop", 0.05) * power
	battle.juice.jitter(view.sprite, 8.0, stop + 0.06)
	if weight.has("fx") and weight["hits"] <= 5:
		_play_fx_layers(weight["fx"], view.position, dir)
	if first:
		battle.juice.hitstop(stop)
		if not weight.get("screen_done", false):
			var trauma: float = weight.get("shake", 0.2) * power
			battle.juice.shake(trauma)
			battle.juice.push(dir, 14.0 * trauma)
			if weight.has("flash"):
				battle.juice.flash(weight["flash"])
			if weight.has("zoom"):
				battle.juice.punch_zoom(_view_screen(view), weight["zoom"], 0.45)
	else:
		battle.juice.shake(0.12)
	if lethal:
		battle.juice.slowmo(0.4, 0.28)
		battle.juice.punch_zoom(_view_screen(view), maxf(weight.get("zoom", 0.0), 0.035), 0.5)
	var heavy: bool = weight.get("stop", 0.0) >= 0.1 or lethal or flank
	var ink := Color(1.0, 0.82, 0.25) if heavy else Color(1.0, 0.97, 0.9)
	if hero_target:
		ink = Color(1.0, 0.32, 0.28) # fogo amigo
	var big := clampf(0.95 + amount / 22.0 + (0.25 if heavy else 0.0), 1.0, 1.8)
	_pop_number(view.position, str(amount), ink, big, "FLANCO!" if flank else "")
	await battle.get_tree().create_timer(0.07 if area else 0.25).timeout


func _play_hero_death(event: Dictionary) -> void:
	var target = event["target"]
	var view = battle.views[target]
	var hero_died := HeroJuice.is_hero(target.type_id)
	view.clear_aura(false)
	battle.sound_manager.play_sfx(&"death_hero" if target.team == Data.Team.PLAYER else &"death_monster")
	view.flash(Color(5.0, 1.4, 1.3) if hero_died else Color(8, 8, 8), 0.35)
	if event.get("final", false):
		# O golpe que decide a luta.
		battle.juice.slowmo(0.22, 0.85)
		battle.juice.punch_zoom(_view_screen(view), 0.1, 1.2)
		battle.juice.flash(Color(1.0, 0.25, 0.2, 0.3) if hero_died else Color(1.0, 0.95, 0.85, 0.28), 0.45)
		battle.juice.shake(0.5)
	elif hero_died:
		battle.juice.slowmo(0.35, 0.5)
		battle.juice.pulse_vignette(Color(0.9, 0.05, 0.05, 0.85), 1.0)
		battle.juice.shake(0.45)
	else:
		battle.juice.shake(0.22)
	_play_fx_layers(HeroJuice.death_fx(hero_died), view.position, Vector2.UP)
	if hero_died and target.team == Data.Team.PLAYER:
		# O corpo fica no chão: um aliado colado pode reerguer (Reerguer), e o fim da luta levanta.
		view.set_status("caído", Color(1.0, 0.45, 0.45))
		await view.lie_down()
		return
	var tween := battle.create_tween()
	tween.tween_method(view.set_jump_height, 0.0, 36.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(view.set_jump_height, 36.0, 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(view, "rotation", deg_to_rad(80 if view.sprite.flip_h else -80), 0.3)
	tween.tween_callback(view.squash.bind(0.25, 0.3))
	tween.tween_property(view, "modulate:a", 0.0, 0.35)
	await tween.finished
	if is_instance_valid(view): # a exploração pode ter tirado o corpo do mapa no meio
		view.visible = false


func _play_hero_guard(unit, id: String) -> void:
	var weight := HeroJuice.for_guard(unit.type_id, id)
	if weight.is_empty():
		return
	var view = battle.views[unit]
	var color: Color = weight["color"]
	_play_fx_layers(weight["fx"], view.position, Vector2.UP)
	view.flash(Color(color.r * 2.5 + 0.6, color.g * 2.5 + 0.6, color.b * 2.5 + 0.6), 0.35)
	view.squash(-0.12, 0.45)
	battle.juice.shake(weight.get("shake", 0.1))


## Saraivada e Chuva de Virotes: virotes caem do céu em cada casa da área.
func _arrow_rain(cells: Array, weight: Dictionary) -> void:
	var drops := []
	for cell in cells:
		for i in int(weight.get("rain", 2)):
			drops.append(cell)
	drops.shuffle()
	battle.sound_manager.play_sfx(&"swing")
	var spread := 0.3 + 0.03 * drops.size()
	var last := 0.0
	for i in drops.size():
		var delay := 0.0 if i == 0 else randf() * spread
		last = maxf(last, delay)
		_rain_arrow(drops[i], delay, weight, i == 0)
	await battle.get_tree().create_timer(RAIN_FALL + minf(last, 0.25)).timeout


func _rain_arrow(cell: Vector2i, delay: float, weight: Dictionary, first: bool) -> void:
	if delay > 0.0:
		await battle.get_tree().create_timer(delay).timeout
	if battle.board == null or not is_instance_valid(battle.board):
		return
	var feet := battle.feet_of(cell) + Vector2(randf_range(-40, 40), randf_range(-20, 20))
	var base := battle._cell_elevation(cell)
	var arrow := Sprite2D.new()
	arrow.texture = load("res://assets/fx/kit/arrow.png")
	arrow.rotation = Vector2(RAIN_DRIFT, RAIN_HEIGHT).angle() - Vector2(-22, 12).angle()
	arrow.scale = Vector2.ONE * 0.6
	arrow.offset = Vector2(22, -12).normalized() * 80.0 # a ponta fica no chão, não o meio
	arrow.z_index = 900
	battle.board.add_child(arrow)
	battle.battle_camera.add_billboard(arrow, Vector2.ZERO, base)
	_rain_frame(0.0, arrow, feet, base)
	var fall := battle.create_tween()
	fall.tween_method(_rain_frame.bind(arrow, feet, base), 0.0, 1.0, RAIN_FALL).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	if not is_instance_valid(arrow):
		return
	if first or randf() < 0.3:
		battle.sound_manager.play_sfx(&"arrow_hit")
	_play_fx_layers(HeroJuice.landing_fx(weight["color"]), feet, Vector2.UP)
	if first:
		_hero_impact(weight, weight.get("center", feet))
	else:
		battle.juice.shake(0.07)
	var fade := battle.create_tween()
	fade.tween_interval(0.2)
	fade.tween_property(arrow, "modulate:a", 0.0, 0.2)
	fade.tween_callback(arrow.queue_free)


## A altura vira elevação (como os degraus), para o virote cair sem mudar de casa.
func _rain_frame(progress: float, arrow: Sprite2D, feet: Vector2, base: float) -> void:
	if not is_instance_valid(arrow):
		return
	var height := (1.0 - progress) * RAIN_HEIGHT
	arrow.position = feet + Vector2(-RAIN_DRIFT * (1.0 - progress), -height)
	battle.battle_camera.set_elevation(base + height * battle.BOARD_SCALE, arrow)


## Rastro do corpo no avanço (Duelista).
func _ghost(view, color: Color) -> void:
	if not is_instance_valid(view) or not view.visible:
		return
	var source: Sprite2D = view.sprite
	var ghost := Sprite2D.new()
	ghost.texture = source.texture
	ghost.hframes = source.hframes
	ghost.vframes = source.vframes
	ghost.frame = source.frame
	ghost.flip_h = source.flip_h
	ghost.offset = source.offset
	ghost.texture_filter = source.texture_filter
	ghost.scale = source.scale * view.scale
	ghost.position = view.position + view.visual_root.position * view.scale
	ghost.modulate = Color(color.r, color.g, color.b, 0.5)
	ghost.z_index = view.z_index - 1
	battle.board.add_child(ghost)
	battle.battle_camera.add_billboard(ghost, view.position - ghost.position, battle.battle_camera.elevation_of(view), true)
	var tween := battle.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.28)
	tween.tween_callback(ghost.queue_free)


func _glow_sprite(tex: String, color: Color, size: float) -> Sprite2D:
	var glow := Sprite2D.new()
	glow.texture = load("res://assets/fx/kenney/%s.png" % tex)
	glow.modulate = color
	glow.scale = Vector2.ONE * size
	glow.z_index = 899
	battle.board.add_child(glow)
	return glow


## Brasas soltas pelo caminho de um projétil.
func _trail_embers(from: Vector2, to: Vector2, color: Color, duration: float) -> void:
	var parts := CPUParticles2D.new()
	parts.texture = load("res://assets/fx/kenney/star_04.png")
	parts.amount = 28
	parts.lifetime = 0.35
	parts.local_coords = false
	parts.direction = Vector2.UP
	parts.spread = 180.0
	parts.initial_velocity_min = 15.0
	parts.initial_velocity_max = 60.0
	parts.gravity = Vector2(0, -80)
	parts.scale_amount_min = 0.05
	parts.scale_amount_max = 0.1
	var fade := Gradient.new()
	fade.set_color(0, Color(color * 1.6, 1.0))
	fade.set_color(1, Color(color, 0.0))
	parts.color_ramp = fade
	parts.position = from
	parts.z_index = 898
	battle.board.add_child(parts)
	battle._add_effect_billboard(parts, Vector2(0, 90), true)
	var tween := battle.create_tween().set_parallel()
	tween.tween_property(parts, "position", to, duration)
	tween.tween_method(battle.battle_camera.set_elevation.bind(parts), battle._height_at_point(from + Vector2(0, 90)), battle._height_at_point(to + Vector2(0, 90)), duration)
	tween.chain().tween_callback(func(): parts.emitting = false)
	tween.chain().tween_interval(0.5)
	tween.chain().tween_callback(parts.queue_free)


func _step_dust(cell: Vector2i, big: bool) -> void:
	_play_fx_layers(HeroJuice.dust_fx(big), battle.feet_of(cell), Vector2.UP)


## Camadas de efeito (formato de hero_juice.gd) em volta dos pés `feet`.
func _play_fx_layers(layers: Array, feet: Vector2, dir := Vector2.RIGHT) -> void:
	for layer in layers:
		var delay: float = layer.get("delay", 0.0)
		if delay > 0.0:
			battle.get_tree().create_timer(delay).timeout.connect(_play_fx_layer.bind(layer, feet, dir))
		else:
			_play_fx_layer(layer, feet, dir)


func _play_fx_layer(layer: Dictionary, feet: Vector2, dir: Vector2) -> void:
	if battle.board == null or not is_instance_valid(battle.board):
		return
	var tex: Texture2D = load("res://assets/fx/kenney/%s.png" % layer["tex"])
	var color: Color = layer["color"]
	var life: float = layer["life"]
	var size: float = layer["size"]
	var height: float = layer.get("height", 80.0)
	var item: Node2D
	match layer["kind"]:
		"burst":
			var parts := CPUParticles2D.new()
			parts.texture = tex
			parts.one_shot = true
			parts.explosiveness = 1.0
			parts.amount = layer["amount"]
			parts.lifetime = life
			parts.direction = dir if layer.get("along", false) and dir != Vector2.ZERO else Vector2.UP
			parts.spread = layer.get("spread", 180.0)
			parts.initial_velocity_min = layer["speed"][0]
			parts.initial_velocity_max = layer["speed"][1]
			parts.gravity = Vector2(0, layer.get("gravity", 0.0))
			parts.damping_min = 80.0
			parts.damping_max = 160.0
			parts.angle_min = -180.0
			parts.angle_max = 180.0
			parts.scale_amount_min = size * 0.6
			parts.scale_amount_max = size * 1.2
			var fade := Gradient.new()
			fade.set_color(0, color)
			fade.set_color(1, Color(color, 0.0))
			parts.color_ramp = fade
			parts.position = feet + Vector2(0, -height)
			parts.emitting = true
			item = parts
		"flash":
			var flash := Sprite2D.new()
			flash.texture = tex
			flash.modulate = color
			flash.position = feet + Vector2(0, -height)
			var stretch: Vector2 = layer.get("stretch", Vector2.ONE)
			flash.scale = stretch * size * layer.get("grow", 0.5)
			flash.rotation = dir.angle() + layer.get("turn", 0.0) if layer.get("align", false) else randf() * TAU
			item = flash
			var tween := battle.create_tween().set_parallel()
			tween.tween_property(flash, "scale", stretch * size, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(flash, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
			tween.tween_property(flash, "rotation", flash.rotation + layer.get("spin", 0.3), life)
		"ring":
			var ring := Sprite2D.new()
			ring.texture = tex
			ring.modulate = color
			ring.position = feet + Vector2(0, -4)
			ring.scale = Vector2(0.15, 0.06)
			item = ring
			var tween := battle.create_tween().set_parallel()
			tween.tween_property(ring, "scale", Vector2(size, size * 0.4), life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(ring, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
	item.z_index = 900
	battle.board.add_child(item)
	battle._add_effect_billboard(item, feet - item.position, layer.get("add", false))
	battle.get_tree().create_timer(life + 0.5).timeout.connect(item.queue_free)


## Número de dano que salta, cresce e cai de lado; não para no hitstop.
func _pop_number(feet: Vector2, text: String, color: Color, big := 1.0, tag := "") -> void:
	var drift := randf_range(-55.0, 55.0)
	_number_label(feet, text, color, int(48 * big), drift, -215.0, 0.0)
	if tag != "":
		_number_label(feet, tag, Color(1.0, 0.85, 0.3), 30, drift, -215.0 - 48.0 * big, 0.05)


func _number_label(feet: Vector2, text: String, color: Color, font_size: int, drift: float, lift: float, delay: float) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 1000
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.02, 0.02))
	label.add_theme_constant_override("outline_size", maxi(10, font_size / 4))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 5)
	battle.board.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size / 2
	label.position = feet + Vector2(drift * 0.3, lift) - label.size / 2
	label.scale = Vector2.ONE * 0.25
	battle._add_effect_billboard(label, feet - label.position)
	var pop := battle.create_tween().set_ignore_time_scale(true)
	pop.tween_interval(delay)
	pop.tween_property(label, "scale", Vector2.ONE * 1.35, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var rise := battle.create_tween().set_ignore_time_scale(true).set_parallel()
	rise.tween_property(label, "position:y", label.position.y - 90.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(delay)
	rise.tween_property(label, "position:x", label.position.x + drift, 0.8).set_delay(delay)
	rise.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(delay + 0.6)
	rise.chain().tween_callback(label.queue_free)
