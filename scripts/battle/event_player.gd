extends RefCounted

## Anima os eventos que as regras devolvem: andar, atacar, dano, cura, morte, magias,
## início e fim de combate. Só apresentação: os eventos já aconteceram nas regras.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const UnitView = preload("res://scripts/unit_view.gd")
const HeroJuice = preload("res://scripts/hero_juice.gd")

const QUIET_DISTANCE := 11 # inimigo mais longe que isso age sem animação nem espera
const STEP_FLAT := 0.22
const STEP_CLIMB := 0.48
const DASH_TIME := 0.24 # salto da investida: rápido, numa tacada só
const PUSH_TIME := 0.18 # quem é empurrado desliza até onde parou
const STATUS_COLOR := {
	"burn": Color(1.0, 0.55, 0.2), "poison": Color(0.6, 1.0, 0.35), "slow": Color(0.6, 0.85, 1.0),
	"mark": Color(1.0, 0.85, 0.3), "might": Color(1.0, 0.7, 0.45),
	"blind": Color(0.62, 0.6, 0.68), "veil": Color(0.78, 0.76, 0.86),
}
const STEP_JUMP := 0.55 # pulo por cima de alguém (duas casas)
const JUMP_ARC := 150.0
const CAST_INK := Color(1.0, 0.62, 0.15)
const PROJECTILE_SCALE := 2.0
const FX_FPS := 16.0

var battle: BattleView # a tela dona deste módulo


func _init(host: Node) -> void:
	battle = host


## `roam`: exploração. Os passos não esperam a animação, porque cada herói anda no seu ritmo.
func _play(events: Array, roam := false) -> void:
	battle.online_session.publish(events, roam, roam)
	battle.hero_fx._mark_final_kill(events)
	for event in events:
		match event["type"]:
			"move":
				if event.get("dash", false):
					event["duration"] = DASH_TIME
					battle.sound_manager.play_sfx(&"swing")
				elif event.get("push", false):
					event["duration"] = PUSH_TIME
				if roam:
					_play_move(event)
				else:
					await _play_move(event)
			"deploy":
				event["silent"] = true
				event["duration"] = battle.DEPLOY_TIME
				_play_move(event) # todos abrem ao mesmo tempo, junto com o aviso de combate
			"attack":
				await _play_attack(event)
			"damage":
				if event.has("dot") or event.has("impact"):
					# Veneno, queimadura e batida do empurrão não vêm de um golpe: sem peso de ataque.
					battle.hit_ctx = {}
					battle.hit_from = battle.views[event["target"]].position + Vector2(0, 40)
				await _play_damage(event)
			"buff":
				await _play_buff(event)
			"status":
				_play_status(event)
			"heal":
				await _play_heal(event)
			"death":
				await _play_death(event)
			"guard":
				var id: String = event.get("ability", "")
				battle.hero_fx._play_hero_guard(event["unit"], id)
				if battle.SPELL_FX.has(id):
					await _play_spell_fx(id, Vector2.ZERO, [battle.views[event["unit"]].position])
				else:
					battle.sound_manager.play_sfx(&"guard")
				battle.views[event["unit"]].set_status("em guarda")
			"cast_start":
				await _play_cast_start(event)
			"cast_resolve":
				await _play_cast_resolve(event)
			"spawn":
				_play_spawn(event)
			"wander":
				event["silent"] = true
				event["duration"] = battle.WALK_STEP * 1.6
				_play_move(event) # sem esperar: o mundo anda junto com o herói
			"combat_start":
				await _play_combat_start(event)
			"combat_join":
				_mark_alerted(event["units"])
				if not battle.my_fight and not battle._free_roam(): # meu herói chegou perto e entrou na luta
					battle.my_fight = true
					battle.hud.show_banner("Combate!", Color(1.0, 0.42, 0.3))
			"ambush": # o resto do bando surge pelos flancos ou por trás
				_mark_alerted(event["units"])
				battle.hud.show_banner("Emboscada!", Color(1.0, 0.42, 0.3))
			"combat_end":
				await _play_combat_end(event)
			"despawn":
				_remove_view(event["unit"])
			"regen":
				_play_regen(event)
			"revive":
				_play_revive(event)
			"landmark":
				await _play_landmark(event)
			"level_up":
				_play_level_up(event)
	battle.hit_ctx = {}
	battle.healers_animated = {}
	for unit in battle.views:
		if unit.alive():
			_show_status(unit)


## Texto embaixo da unidade. Quem carrega magia mostra a contagem regressiva
## de ações até ela sair, a mesma do menu e da fila.
func _show_status(unit) -> void:
	if not unit.pending.is_empty():
		battle.views[unit].set_status("magia em %d" % battle.state.actions_until(unit), CAST_INK)
		if HeroJuice.is_hero(unit.type_id):
			battle.views[unit].set_aura(HeroJuice.color_of(unit.type_id))
	else:
		var words: Array = unit.status_names()
		if unit.guarding:
			words.push_front("em guarda")
		battle.views[unit].set_status(" · ".join(words))
		battle.views[unit].clear_aura(false)


## Habilidade em aliado (Interpor, Corrente, Bênção): o gesto de quem usa e o brilho em quem recebe.
func _play_buff(event: Dictionary) -> void:
	var unit = event["unit"]
	var target = event["target"]
	var view = battle.views[unit]
	var id: String = event.get("ability", "")
	if target != unit:
		view.face_toward((battle.views[target].position - view.position).rotated(battle.view_angle))
	view.play_once(UnitView.Anim.ATTACK)
	await battle.get_tree().create_timer(HeroJuice.ATTACK_HIT * view.anim_frame_count() / UnitView.FPS).timeout
	var target_view = battle.views[target]
	var weight := HeroJuice.for_guard(unit.type_id, id)
	if not weight.is_empty():
		var color: Color = weight["color"]
		battle.hero_fx._play_fx_layers(weight["fx"], target_view.position, Vector2.UP)
		target_view.flash(Color(color.r * 2.5 + 0.6, color.g * 2.5 + 0.6, color.b * 2.5 + 0.6), 0.35)
		target_view.squash(-0.12, 0.45)
		battle.juice.shake(weight.get("shake", 0.1))
	if battle.SPELL_FX.has(id):
		await _play_spell_fx(id, Vector2.ZERO, [target_view.position])
	else:
		battle.sound_manager.play_sfx(&"guard" if Data.ABILITIES[id].get("guard_ally", false) else &"heal")
		await battle.get_tree().create_timer(0.25).timeout
	if target.alive():
		_show_status(target)


## Efeito novo numa unidade: o nome sobe em cima dela e entra no texto de baixo.
func _play_status(event: Dictionary) -> void:
	var target = event["target"]
	if not target.alive() or not battle.views.has(target):
		return
	var id: String = event["status"]
	_float_text(battle.views[target].position + Vector2(-50, -250), Data.STATUS[id]["name"], STATUS_COLOR.get(id, Color.WHITE))
	_show_status(target)


## Quem ainda não tem desenho ganha um; quem saiu do mapa perde o seu.
func _match_views() -> void:
	for unit in battle.state.units:
		if not battle.views.has(unit):
			battle.board_art._add_unit_view(unit)
	for unit in battle.views.keys():
		if not battle.state.units.has(unit):
			_remove_view(unit)


func _mark_alerted(units: Array) -> void:
	for unit in units:
		if battle.views.has(unit):
			_float_text(battle.views[unit].position + Vector2(-12, -210), "!", Color(1.0, 0.3, 0.2))


## Foi visto: aviso, e a câmera mostra quem apareceu antes de voltar para a party.
func _play_combat_start(event: Dictionary) -> void:
	if not battle.online_session.playing and battle._free_roam(): # solo: a luta começa com um herói dela
		battle.selected = battle._first_mine()
	battle.my_fight = not battle._free_roam()
	if not battle.my_fight: # a luta é de outro jogador, longe daqui: só um aviso
		battle.hud.show_banner("Aliado em combate", Color(1.0, 0.7, 0.4))
		battle.hud.refresh(battle.state)
		return
	battle.sound_manager.play_sfx(&"charge")
	battle.hud.show_banner("Combate!" , Color(1.0, 0.42, 0.3))
	_mark_alerted(event["units"])
	battle.hud.refresh(battle.state)
	if not event["surprised"]:
		return
	battle.camera_look = battle._camera_target(battle.camera_cell).lerp(battle._camera_target(event["units"][0].pos), 0.45)
	await battle.get_tree().create_timer(0.75).timeout
	battle.camera_look = null


func _play_combat_end(event: Dictionary) -> void:
	if battle.state.split_fights and not battle.my_fight:
		battle.hud.show_banner("Combate do aliado acabou", Color(0.6, 1.0, 0.6))
		battle.hud.refresh(battle.state)
		battle.marks_ctl._refresh_turn_markers()
		if battle.online_session.playing and battle.online_session.relay.is_master:
			await battle._reward_fight() # o mundo é do dono: a experiência de toda luta vai para o save dele
		return
	battle.my_fight = false
	battle.sound_manager.play_sfx(&"victory")
	battle.hud.show_banner("Você escapou" if event["fled"] else "Combate vencido", Color(0.6, 1.0, 0.6))
	battle.hud.refresh(battle.state)
	battle.marks_ctl._refresh_turn_markers()
	await battle.get_tree().create_timer(0.4).timeout
	await battle._reward_fight()


func _is_quiet(unit) -> bool:
	return battle.exploring and Hex.distance(unit.pos, battle.camera_cell) > QUIET_DISTANCE


func _play_spawn(event: Dictionary) -> void:
	battle.board_art._add_unit_view(event["unit"])
	var view = battle.views[event["unit"]]
	view.modulate.a = 0.0
	battle.create_tween().tween_property(view, "modulate:a", 1.0, 0.4)


func _remove_view(unit) -> void:
	if battle.views.has(unit):
		battle.views[unit].queue_free()
		battle.views.erase(unit)


func _play_regen(event: Dictionary) -> void:
	var view = battle.views[event["unit"]]
	view.set_hp(event["hp"])
	if event.get("quiet", false): # descansar andando não merece um número subindo a cada passo
		return
	_float_text(view.position + Vector2(-20, -200), "+%d" % event["amount"], Color(0.4, 1.0, 0.5))


## A câmera andou: o que está sob o mouse mudou. Toque não tem hover, então fica como está.
func _play_revive(event: Dictionary) -> void:
	var view = battle.views[event["unit"]]
	view.visible = true
	view.rotation = 0.0
	view.modulate.a = 1.0
	view.set_hp(event["hp"])
	battle.sound_manager.play_sfx(&"heal")
	_float_text(view.position + Vector2(-60, -200), "de pé!", Color(0.4, 1.0, 0.5))


func _play_landmark(event: Dictionary) -> void:
	battle.sound_manager.play_sfx(&"victory" if event["done"] else &"defeat")
	battle.hud.show_banner(event["title"], event["color"])
	if event["detail"] != "":
		battle.hud.show_detail(event["detail"])
	if battle.state.landmarks[event["cell"]]["kind"] == "bau":
		battle.hud.set_potions(battle.state.potions)
	if event["done"] and battle.landmark_nodes.has(event["cell"]):
		for node in battle.landmark_nodes[event["cell"]]:
			if battle.cell_nodes.has(event["cell"]):
				battle.cell_nodes[event["cell"]].erase(node)
			node.queue_free()
		battle.landmark_nodes.erase(event["cell"])
	if event["done"] and battle.state.landmarks[event["cell"]]["kind"] in ["bau", "forte"]:
		battle.board_art._rebuild_cell(event["cell"]) # o baú fica aberto
	battle.journey_ui._update_journey()
	await battle.get_tree().create_timer(0.5).timeout


func _play_level_up(event: Dictionary) -> void:
	battle.sound_manager.play_sfx(&"heal")
	battle.hud.show_banner("Nível %d!" % event["level"], Color(0.6, 0.9, 1.0))
	for member in battle.state.party:
		if battle.views.has(member):
			battle.views[member].set_hp(member.hp)


func _play_move(event: Dictionary) -> void:
	var view = battle.views[event["unit"]]
	var from: Vector2 = battle.feet_of(event["from"])
	var to: Vector2 = battle.feet_of(event["to"])
	var unit = event["unit"]
	if battle.exploring and unit == battle.camera_unit:
		battle._set_camera(event["to"])
	if battle.exploring and Hex.distance(event["to"], battle.camera_cell) > QUIET_DISTANCE:
		if battle.walks.has(unit):
			battle.roam_ctl._finish_walk(unit)
		view.position = to
		view.z_index = battle._z(battle._row(event["to"])) + 5
		battle.battle_camera.set_elevation(battle._cell_elevation(event["to"]), view)
		return
	if not event.get("silent", false) and HeroJuice.is_hero(unit.type_id) and (not battle.exploring or battle.state.in_combat()):
		battle.hero_fx._step_dust(event["from"], battle.state.elevation_at(event["to"]) != battle.state.elevation_at(event["from"]))
	if battle.exploring:
		var time: float = event.get("duration", battle.WALK_STEP)
		if not event.get("silent", false):
			battle.sound_manager.play_sfx(&"step")
		battle.roam_ctl._begin_walk(unit, event["from"], event["to"], time)
		await battle.get_tree().create_timer(time).timeout
		return
	view.face_toward(to - from)
	view.z_index = battle._z(maxi(battle._row(event["from"]), battle._row(event["to"]))) + 5
	view.set_walking(true)
	battle.moving[unit] = battle.moving.get(unit, 0) + 1
	if not event.get("silent", false):
		battle.sound_manager.play_sfx(&"step")
	var height_delta: int = battle.state.elevation_at(event["to"]) - battle.state.elevation_at(event["from"])
	var leap: bool = event.get("jump", false)
	var duration: float = event.get("duration", STEP_JUMP if leap else (STEP_FLAT if height_delta == 0 else STEP_CLIMB))
	var tween := battle.create_tween()
	tween.tween_method(_move_frame.bind(view, event["from"], event["to"], battle._cell_elevation(event["from"]), battle._cell_elevation(event["to"]), height_delta, leap), 0.0, 1.0, duration)
	await tween.finished
	battle.moving[unit] -= 1
	if battle.moving[unit] <= 0:
		battle.moving.erase(unit)
	if not is_instance_valid(view) or battle.moving.has(unit):
		return
	view.set_walking(false)
	view.set_jump_height(0.0)
	view.position = battle.feet_of(unit.pos)
	view.z_index = battle._z(battle._row(unit.pos)) + 5
	battle.battle_camera.set_elevation(battle._cell_elevation(unit.pos), view)
	battle.marks_ctl._refresh_overlays()


## As casas, e não pontos prontos: girar a câmera no meio do passo não deixa o herói fora do lugar.
func _move_frame(progress: float, view, from: Vector2i, to: Vector2i, from_height: float, to_height: float, height_delta: int, leap := false) -> void:
	if not is_instance_valid(view):
		return
	view.position = battle.feet_of(from).lerp(battle.feet_of(to), progress)
	battle.battle_camera.set_elevation(lerpf(from_height, to_height, progress), view)
	var jump := 0.0
	if leap: # pulo por cima de alguém: arco alto
		jump = sin(progress * PI) * JUMP_ARC
	elif height_delta != 0:
		jump = sin(progress * PI) * (110.0 if height_delta > 0 else 65.0)
	view.set_jump_height(jump)


func _play_attack(event: Dictionary) -> void:
	var unit = event["unit"]
	var target = event["target"]
	var view = battle.views[unit]
	view.face_toward((battle.feet_of(target.pos) - view.position).rotated(battle.view_angle))
	# Quem apanha olha para quem bateu, para o tranco do dano sair na direção certa.
	battle.views[target].face_toward((view.position - battle.views[target].position).rotated(battle.view_angle))
	var id: String = event.get("ability", "")
	var magic := battle.SPELL_FX.has(id)
	battle.hit_from = view.position
	battle.hit_ctx = {}
	var weight := HeroJuice.for_ability(unit.type_id, id)
	if not weight.is_empty():
		await battle.hero_fx._play_hero_attack(event, weight)
		return
	if not magic:
		battle.sound_manager.play_sfx(&"swing") # golpe corpo a corpo ou disparo da flecha
	await view.play_once(_attack_anim(unit, id))
	var shot: String = Data.ABILITIES[id].get("shot", "") if Data.ABILITIES.has(id) else ""
	if shot != "":
		await _fly_projectile(shot, view.position + Vector2(0, -90), battle.views[target].position + Vector2(0, -90))
		battle.sound_manager.play_sfx(&"arrow_hit")
	elif magic:
		await _play_spell_fx(id, view.position + Vector2(0, -90), [battle.views[target].position])
	else:
		battle.sound_manager.play_sfx(&"melee_hit")
	if battle.BOSS_FX.has(unit.type_id):
		var strong := _attack_anim(unit, id) == UnitView.Anim.STRONG
		_play_boss_fx(battle.BOSS_FX[unit.type_id]["skill" if strong else "hit"], battle.views[target].position)


## Toca as camadas de um efeito de chefe em volta dos pés de `feet`.
func _play_boss_fx(layers: Array, feet: Vector2) -> void:
	for layer in layers:
		var tex: Texture2D = load("res://assets/fx/kenney/%s.png" % layer["tex"])
		var color: Color = layer["color"]
		var life: float = layer["life"]
		var size: float = layer["size"]
		var item: Node2D
		match layer["kind"]:
			"burst":
				var parts := CPUParticles2D.new()
				parts.texture = tex
				parts.one_shot = true
				parts.explosiveness = 1.0
				parts.amount = layer["amount"]
				parts.lifetime = life
				parts.direction = Vector2.UP
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
				parts.position = feet + Vector2(0, -70)
				parts.emitting = true
				item = parts
			"flash":
				var flash := Sprite2D.new()
				flash.texture = tex
				flash.modulate = Color(color * 1.7, color.a) # aditivo some no chão claro
				flash.position = feet + Vector2(0, -80)
				flash.scale = Vector2.ONE * size * 0.5
				flash.rotation = randf() * TAU
				item = flash
				var tween := battle.create_tween().set_parallel()
				tween.tween_property(flash, "scale", Vector2.ONE * size, life)
				tween.tween_property(flash, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
				tween.tween_property(flash, "rotation", flash.rotation + layer.get("spin", 0.4), life)
			"ring":
				var ring := Sprite2D.new()
				ring.texture = tex
				ring.modulate = Color(color * 1.7, color.a)
				ring.position = feet
				ring.scale = Vector2(0.15, 0.06)
				item = ring
				var tween := battle.create_tween().set_parallel()
				tween.tween_property(ring, "scale", Vector2(size, size * 0.4), life).set_ease(Tween.EASE_OUT)
				tween.tween_property(ring, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD if layer["kind"] != "burst" or layer["tex"].begins_with("spark") or layer["tex"].begins_with("star") or layer["tex"].begins_with("magic") or layer["tex"].begins_with("twirl") else CanvasItemMaterial.BLEND_MODE_MIX
		item.material = material
		item.z_index = 900
		battle.board.add_child(item)
		battle._add_effect_billboard(item, feet - item.position)
		battle.get_tree().create_timer(life + 0.3).timeout.connect(item.queue_free)


# Heróis: hero_juice.gd diz quais habilidades usam o golpe forte. Os outros:
# a primeira habilidade é o ataque básico; as outras usam o ataque forte.
func _attack_anim(unit, ability_id: String) -> UnitView.Anim:
	if HeroJuice.is_hero(unit.type_id):
		return UnitView.Anim.STRONG if HeroJuice.strong_anim(unit.type_id, ability_id) else UnitView.Anim.ATTACK
	var abilities: Array = Data.UNIT_TYPES.get(unit.type_id, {}).get("abilities", [])
	if abilities.is_empty() or ability_id == "" or ability_id == abilities[0]:
		return UnitView.Anim.ATTACK
	return UnitView.Anim.STRONG


func _play_damage(event: Dictionary) -> void:
	if not battle.hit_ctx.is_empty() or HeroJuice.is_hero(event["target"].type_id):
		await battle.hero_fx._play_hero_damage(event)
		return
	var view = battle.views[event["target"]]
	view.set_hp(event["hp"])
	var text := str(event["amount"])
	if event.get("flank", false):
		text += " flanco!"
	_float_text(view.position + Vector2(-20, -200), text, Color(1.0, 0.4, 0.3))
	battle.sound_manager.play_sfx(&"hurt")
	view.play_once(UnitView.Anim.HURT)
	await battle.get_tree().create_timer(0.25).timeout


func _play_heal(event: Dictionary) -> void:
	var view = battle.views[event["target"]]
	var healer = event["unit"]
	# Quem cura faz o gesto normal (na Druida, a animação de cura), uma vez por ação.
	# Curas passivas (Sede de Sangue) não têm gesto.
	var caster: bool = healer.type_id in ["druida", "mago_agua"] or healer != event["target"]
	if HeroJuice.is_hero(healer.type_id) and caster and not battle.healers_animated.has(healer):
		battle.healers_animated[healer] = true
		if healer != event["target"]:
			battle.views[healer].face_toward((view.position - battle.views[healer].position).rotated(battle.view_angle))
		battle.views[healer].play_once(UnitView.Anim.ATTACK)
		await battle.get_tree().create_timer(HeroJuice.ATTACK_HIT * battle.views[healer].anim_frame_count() / UnitView.FPS).timeout
	view.set_hp(event["hp"])
	battle.sound_manager.play_sfx(&"heal")
	if HeroJuice.is_hero(event["unit"].type_id):
		var color := HeroJuice.color_of(event["unit"].type_id)
		if event["unit"].type_id != "druida" and event["unit"].type_id != "mago_agua":
			color = Color(0.5, 1.0, 0.55) # quem se cura com Sede de Sangue
		battle.hero_fx._play_fx_layers(HeroJuice.heal_fx(color), view.position, Vector2.UP)
		view.flash(Color(color.r * 2.2 + 0.4, color.g * 2.2 + 0.4, color.b * 2.2 + 0.4), 0.35)
		view.squash(-0.1, 0.4)
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/kit/heal.png")
	fx.scale = Vector2.ONE * 0.5
	fx.position = view.position + Vector2(0, -90)
	fx.z_index = 900
	battle.board.add_child(fx)
	battle._add_effect_billboard(fx, Vector2(0, 90))
	var tween := battle.create_tween()
	tween.tween_property(fx, "modulate:a", 0.0, 0.6)
	tween.tween_callback(fx.queue_free)
	_float_text(view.position + Vector2(-20, -200), "+%d" % event["amount"], Color(0.4, 1.0, 0.5))
	await tween.finished


# O kit não tem animação de morte: a unidade tomba e some.
func _play_death(event: Dictionary) -> void:
	if event["target"].team == Data.Team.ENEMY:
		battle.fight_kills += 1
		if battle.expedition and battle.state.is_boss(event["target"]):
			battle.fight_boss = true
	if not battle.hit_ctx.is_empty() or HeroJuice.is_hero(event["target"].type_id):
		await battle.hero_fx._play_hero_death(event)
		return
	var view = battle.views[event["target"]]
	battle.sound_manager.play_sfx(&"death_hero" if event["target"].team == Data.Team.PLAYER else &"death_monster")
	var tween := battle.create_tween().set_parallel()
	tween.tween_property(view, "rotation", deg_to_rad(80 if view.sprite.flip_h else -80), 0.35)
	tween.tween_property(view, "modulate:a", 0.0, 0.5)
	await tween.finished
	view.visible = false


func _play_cast_start(event: Dictionary) -> void:
	var view = battle.views[event["unit"]]
	view.face_toward((battle.feet_of(event["tile"]) - view.position).rotated(battle.view_angle))
	_show_status(event["unit"])
	battle.marks_ctl._refresh_overlays()
	battle.sound_manager.play_sfx(&"charge")
	if HeroJuice.is_hero(event["unit"].type_id):
		var color := HeroJuice.color_of(event["unit"].type_id)
		battle.hero_fx._play_fx_layers(HeroJuice.cast_fx(color), view.position, Vector2.UP)
		view.flash(Color(color.r * 3.0 + 0.5, color.g * 3.0 + 0.5, color.b * 3.0 + 0.5), 0.3)
		view.squash(-0.12, 0.4)
		battle.juice.shake(0.08)
	await view.play_once(UnitView.Anim.ATTACK)


func _play_cast_resolve(event: Dictionary) -> void:
	var view = battle.views[event["unit"]]
	battle.hit_ctx = {}
	battle.hit_from = battle.feet_of(event["tile"])
	var weight := HeroJuice.for_ability(event["unit"].type_id, event["id"])
	if not weight.is_empty():
		await battle.hero_fx._play_hero_cast(event, weight)
		return
	battle.marks_ctl._refresh_overlays()
	await view.play_once(UnitView.Anim.STRONG)
	var id: String = event["id"]
	var center: Vector2 = battle.feet_of(event["tile"]) + Vector2(0, -20)
	if battle.SPELL_FX.has(id):
		var spots := [battle.feet_of(event["tile"])]
		if battle.SPELL_FX[id].get("per_cell", false):
			var cells: Array = event["cells"].duplicate()
			cells.sort_custom(func(a, b): return Hex.distance(a, event["tile"]) < Hex.distance(b, event["tile"]))
			spots = cells.map(func(cell): return battle.feet_of(cell))
		await _play_spell_fx(id, view.position + Vector2(0, -90), spots)
	else:
		await _fly_projectile(Data.ABILITIES[id].get("shot", "kit/magic"), view.position + Vector2(0, -90), center)
	var flashes := []
	for cell in event["cells"]:
		var flash := Polygon2D.new()
		flash.polygon = battle.hex_poly
		battle._place_ground_marker(flash, cell)
		flash.color = Color(1.0, 0.75, 0.3, 0.85)
		flash.position = battle.cell_origin(cell)
		flash.z_index = 900
		battle.board.add_child(flash)
		flashes.append(flash)
	var tween := battle.create_tween().set_parallel()
	for flash in flashes:
		tween.tween_property(flash, "modulate:a", 0.0, 0.35)
	await tween.finished
	for flash in flashes:
		flash.queue_free()


## Projétil (se a magia tiver) do mago até o primeiro ponto, depois o impacto em todos os pontos.
## Os pontos são pés de casas (com per_cell, uma por casa, começando pelo centro da área).
## Com `weight` (magia de herói), acende o impacto na tela e volta no auge da explosão,
## para o dano aparecer junto com ela; a animação termina sozinha.
func _play_spell_fx(id: String, from: Vector2, spots: Array, weight := {}) -> void:
	var spell: Dictionary = battle.SPELL_FX[id]
	var ground: bool = spell.get("ground", false)
	var lift: float = spell.get("lift", 90)
	if spell.has("projectile"):
		var to: Vector2 = spots[0] - Vector2(0, 90 if ground else lift)
		var ball := _fx_sprite(spell["projectile"], PROJECTILE_SCALE)
		ball.position = from
		battle._add_effect_billboard(ball, Vector2(0, 90))
		# Os projéteis do pack voam para a direita; projectile_turn corrige os que não.
		ball.rotation = (to - from).angle() + spell.get("projectile_turn", 0.0)
		var duration := clampf(from.distance_to(to) / 1400.0, 0.15, 0.5)
		battle.sound_manager.play_sfx(spell.get("cast_sound", &"fire_cast"))
		var flight := battle.create_tween().set_parallel()
		flight.tween_property(ball, "position", to, duration)
		flight.tween_method(battle.battle_camera.set_elevation.bind(ball), battle._height_at_point(from + Vector2(0, 90)), battle._height_at_point(spots[0]), duration)
		flight.tween_method(_loop_frames.bind(ball), 0.0, duration, duration)
		var glow: Sprite2D = null
		if weight.has("trail"):
			glow = battle.hero_fx._glow_sprite("circle_05", weight["trail"], 0.32)
			glow.position = from
			battle._add_effect_billboard(glow, Vector2(0, 90), true)
			flight.tween_property(glow, "position", to, duration)
			flight.tween_method(battle.battle_camera.set_elevation.bind(glow), battle._height_at_point(from + Vector2(0, 90)), battle._height_at_point(spots[0]), duration)
			battle.hero_fx._trail_embers(from, to, weight["trail"], duration)
		await flight.finished
		ball.queue_free()
		if glow != null:
			glow.queue_free()
	battle.sound_manager.play_sfx(spell["sound"])
	var size: float = spell["impact_scale"]
	var frames: int = battle.fx_meta[spell["impact"]]["frames"]
	var hits := []
	var burst := battle.create_tween().set_parallel()
	for i in spots.size():
		var hit := _fx_sprite(spell["impact"], size)
		hit.position = spots[i]
		hit.position.y -= battle.fx_meta[spell["impact"]]["h"] * size / 2.0 if ground else lift
		battle._add_effect_billboard(hit, Vector2(0, battle.fx_meta[spell["impact"]]["h"] * size / 2.0 if ground else lift))
		var delay: float = spell.get("ring_delay", 0.0) if i > 0 else 0.0
		hit.visible = delay == 0.0
		burst.tween_callback(hit.show).set_delay(delay)
		burst.tween_property(hit, "frame", frames - 1, frames / FX_FPS).from(0).set_delay(delay)
		hits.append(hit)
	if battle.world_light != null and not spell["impact"].begins_with("fumaca/"): # fumaça não acende
		battle.world_light.flash(spots[0], spell["impact"], 1.0 + 0.2 * (spots.size() - 1))
	if not weight.is_empty():
		burst.finished.connect(func():
			for hit in hits:
				if is_instance_valid(hit):
					hit.queue_free())
		# O tremor e o dano saem no auge da animação (peak), não no primeiro quadro.
		await battle.get_tree().create_timer(weight.get("peak", minf(frames / FX_FPS * 0.3, 0.35))).timeout
		battle.hero_fx._hero_impact(weight, spots[0])
		return
	await burst.finished
	for hit in hits:
		hit.queue_free()


func _fx_sprite(fx_name: String, size: float) -> Sprite2D:
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/%s.png" % fx_name)
	fx.hframes = battle.fx_meta[fx_name]["frames"]
	fx.scale = Vector2.ONE * size
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_index = 900
	battle.board.add_child(fx)
	return fx


func _loop_frames(elapsed: float, fx: Sprite2D) -> void:
	fx.frame = int(elapsed * FX_FPS) % fx.hframes


## trail (herói): rastro de luz atrás do projétil, na cor pedida.
func _fly_projectile(texture: String, from: Vector2, to: Vector2, trail := Color(0, 0, 0, 0)) -> void:
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/%s.png" % texture)
	fx.position = from
	fx.z_index = 900
	if texture == "kit/arrow":
		fx.rotation = (to - from).angle() - Vector2(-22, 12).angle() # inclinação da flecha no PNG
	else:
		fx.scale = Vector2.ONE * 1.6
	battle.board.add_child(fx)
	var tween := battle.create_tween()
	battle._add_effect_billboard(fx, Vector2(0, 90))
	var duration := clampf(from.distance_to(to) / 1800.0, 0.1, 0.4)
	tween.set_parallel()
	tween.tween_property(fx, "position", to, duration)
	tween.tween_method(battle.battle_camera.set_elevation.bind(fx), battle._height_at_point(from + Vector2(0, 90)), battle._height_at_point(to + Vector2(0, 90)), duration)
	var streak: Sprite2D = null
	if trail.a > 0.0:
		streak = battle.hero_fx._glow_sprite("trace_07", trail, 0.3)
		streak.scale = Vector2(0.22, 0.5)
		streak.rotation = (to - from).angle() + PI / 2
		streak.offset = Vector2(0, 230) # fica atrás da ponta
		streak.position = from
		streak.z_index = 899
		battle._add_effect_billboard(streak, Vector2(0, 90), true)
		tween.tween_property(streak, "position", to, duration)
		tween.tween_method(battle.battle_camera.set_elevation.bind(streak), battle._height_at_point(from + Vector2(0, 90)), battle._height_at_point(to + Vector2(0, 90)), duration)
		if texture != "kit/arrow":
			fx.modulate = Color.WHITE.lerp(trail, 0.6) # a bolha do kit ganha a cor do herói
			battle.hero_fx._trail_embers(from, to, trail, duration)
	await tween.finished
	fx.queue_free()
	if streak != null:
		var fade := battle.create_tween()
		fade.tween_property(streak, "modulate:a", 0.0, 0.08)
		fade.tween_callback(streak.queue_free)


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.z_index = 1000
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	battle.board.add_child(label)
	battle._add_effect_billboard(label, Vector2(0, 200))
	var tween := battle.create_tween().set_parallel()
	tween.tween_property(label, "position:y", pos.y - 70, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
