extends Node2D
## "Peso" do combate na tela: tremor, pausa no impacto (hitstop), câmera lenta,
## clarão, escurecer antes de magias grandes, vinheta e zoom rápido.
## Só apresentação: as regras não sabem que isso existe.
## Corre no tempo real (relógio do sistema), para seguir viva durante a pausa do impacto.

const FREEZE_SCALE := 0.03 # quase parado: Engine.time_scale durante o hitstop
const MAX_SHAKE := 22.0 # pixels de tela com trauma 1
const MAX_ROLL := 0.022 # radianos de giro com trauma 1
const SHAKE_DECAY := 1.7 # trauma que some por segundo
const SHAKE_SPEED := 38.0
const KICK_RETURN := 16.0 # quão rápido o tranco na direção do golpe volta
const SCREEN := Vector2(1280, 720)
const MARGIN := 500.0 # as camadas sobram da tela, para não aparecer borda no tremor
const DIM_Z := 850 # acima do tabuleiro e das unidades, abaixo dos efeitos (900)
const FLASH_Z := 960
const DIM_COLOR := Color(0.03, 0.02, 0.07)

var trauma := 0.0
var shake_clock := 0.0
var kick := Vector2.ZERO
var freeze_left := 0.0
var slow_left := 0.0
var slow_scale := 1.0
var zoom_peak := 0.0
var zoom_left := 0.0
var zoom_total := 0.0
var zoom_pivot := SCREEN / 2
var flash_left := 0.0
var flash_total := 0.0
var flash_peak := 0.0
var vignette_left := 0.0
var vignette_total := 0.0
var vignette_peak := 0.0
var dim_target := 0.0
var dim_speed := 1.0
var jitters := {} # nó -> {"left", "amount", "base"}
var noise := FastNoiseLite.new()
var transformed := false

var flash_rect: ColorRect
var dim_rect: ColorRect
var vignette: TextureRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 200 # depois de tudo que mexe nos nós; antes do desenho
	noise.frequency = 1.0
	noise.seed = randi()
	dim_rect = _cover(DIM_COLOR, DIM_Z)
	dim_rect.color.a = 0.0
	flash_rect = _cover(Color.WHITE, FLASH_Z)
	flash_rect.modulate.a = 0.0
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash_rect.material = add
	vignette = TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 1, 1, 1))
	gradient.add_point(0.55, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.05, 0.5)
	texture.width = 256
	texture.height = 144
	vignette.texture = texture
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.position = -Vector2.ONE * 60
	vignette.size = SCREEN + Vector2.ONE * 120
	vignette.z_index = FLASH_Z - 1
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	add_child(vignette)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if is_inside_tree():
		get_viewport().canvas_transform = Transform2D.IDENTITY


func _cover(color: Color, z: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = -Vector2.ONE * MARGIN
	rect.size = SCREEN + Vector2.ONE * MARGIN * 2
	rect.z_index = z
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


# --- Pedidos ---------------------------------------------------------------------

## Tremor que soma e vai sumindo. 0,2 é leve; 0,6 é golpe pesado; 1 é magia máxima.
func shake(amount: float) -> void:
	trauma = clampf(maxf(trauma, amount) + amount * 0.25, 0.0, 1.0)


## Tranco curto na direção do golpe (em pixels de tela), que volta como mola.
func push(direction: Vector2, pixels: float) -> void:
	kick += direction.normalized() * pixels


## Para tudo por alguns centésimos de segundo no impacto.
func hitstop(seconds: float) -> void:
	freeze_left = maxf(freeze_left, seconds)


## Câmera lenta depois do hitstop (abates, último inimigo).
func slowmo(scale: float, seconds: float) -> void:
	slow_scale = scale if slow_left <= 0.0 else minf(slow_scale, scale)
	slow_left = maxf(slow_left, seconds)


## Clarão que soma luz na tela inteira; a cor diz o elemento e o alpha, a força.
func flash(color: Color, seconds := 0.22) -> void:
	if color.a <= flash_peak * (flash_left / maxf(flash_total, 0.001)):
		return
	flash_rect.color = Color(color, 1.0)
	flash_peak = color.a
	flash_left = seconds
	flash_total = seconds


## Escurece tudo menos os efeitos, para a magia grande brilhar.
func dim(alpha: float, seconds := 0.25) -> void:
	dim_target = alpha
	dim_speed = absf(alpha - dim_rect.color.a) / maxf(seconds, 0.01)


## Borda da tela na cor pedida (vermelho quando um herói apanha).
func pulse_vignette(color: Color, seconds := 0.45) -> void:
	vignette.self_modulate = Color(color, 1.0)
	vignette_peak = maxf(color.a, vignette_peak * vignette_left / maxf(vignette_total, 0.001))
	vignette_left = seconds
	vignette_total = seconds


## Aproxima rápido em volta de um ponto da tela e volta devagar.
func punch_zoom(screen_point: Vector2, amount: float, seconds := 0.45) -> void:
	if amount < zoom_peak * _zoom_envelope():
		return
	zoom_pivot = screen_point.clamp(SCREEN * 0.2, SCREEN * 0.8)
	zoom_peak = amount
	zoom_left = seconds
	zoom_total = seconds


## Faz um nó tremer no lugar (quem apanha, durante o hitstop).
func jitter(item: Node2D, pixels: float, seconds: float) -> void:
	if not is_instance_valid(item):
		return
	var base: Vector2 = jitters[item]["base"] if jitters.has(item) else item.position
	jitters[item] = {"left": seconds, "amount": pixels, "base": base}


func frozen() -> bool:
	return freeze_left > 0.0


# --- Quadro a quadro -------------------------------------------------------------

func _process(delta: float) -> void:
	# O delta vem multiplicado pelo time_scale que este nó mesmo pôs; desfaz para ter o tempo real.
	var dt := clampf(delta / maxf(Engine.time_scale, 0.001), 0.0, 0.1)
	_update_time(dt)
	_update_overlays(dt)
	_update_jitters(dt)
	_update_view(dt)


func _update_time(dt: float) -> void:
	var scale := 1.0
	if freeze_left > 0.0:
		freeze_left -= dt
		scale = FREEZE_SCALE
	elif slow_left > 0.0:
		slow_left -= dt
		# Volta suave ao normal nos últimos instantes.
		scale = lerpf(1.0, slow_scale, clampf(slow_left / 0.15, 0.0, 1.0))
	Engine.time_scale = scale


func _update_overlays(dt: float) -> void:
	if flash_left > 0.0:
		flash_left = maxf(0.0, flash_left - dt)
		flash_rect.modulate.a = flash_peak * pow(flash_left / flash_total, 1.6)
	elif flash_rect.modulate.a != 0.0:
		flash_rect.modulate.a = 0.0
		flash_peak = 0.0
	dim_rect.color.a = move_toward(dim_rect.color.a, dim_target, dim_speed * dt)
	dim_rect.visible = dim_rect.color.a > 0.001
	if vignette_left > 0.0:
		vignette_left = maxf(0.0, vignette_left - dt)
		vignette.modulate.a = vignette_peak * pow(vignette_left / vignette_total, 1.3)
	elif vignette.modulate.a != 0.0:
		vignette.modulate.a = 0.0
		vignette_peak = 0.0


func _update_jitters(dt: float) -> void:
	for item in jitters.keys():
		var entry: Dictionary = jitters[item]
		if not is_instance_valid(item):
			jitters.erase(item)
			continue
		entry.left -= dt
		if entry.left <= 0.0:
			item.position = entry.base
			jitters.erase(item)
		else:
			var strength: float = entry.amount * clampf(entry.left / 0.06, 0.35, 1.0)
			item.position = entry.base + Vector2(randf_range(-1, 1), randf_range(-0.6, 0.6)) * strength


func _zoom_envelope() -> float:
	if zoom_left <= 0.0:
		return 0.0
	var progress := 1.0 - zoom_left / zoom_total
	return progress / 0.18 if progress < 0.18 else pow(1.0 - (progress - 0.18) / 0.82, 2.0)


func _update_view(dt: float) -> void:
	trauma = maxf(0.0, trauma - SHAKE_DECAY * dt)
	kick = kick.lerp(Vector2.ZERO, 1.0 - exp(-dt * KICK_RETURN))
	if kick.length() < 0.2:
		kick = Vector2.ZERO
	var zoom := 0.0
	if zoom_left > 0.0:
		zoom = zoom_peak * _zoom_envelope()
		zoom_left = maxf(0.0, zoom_left - dt)
		if zoom_left == 0.0:
			zoom_peak = 0.0
	if trauma <= 0.0 and kick == Vector2.ZERO and zoom == 0.0:
		if transformed:
			transformed = false
			get_viewport().canvas_transform = Transform2D.IDENTITY
		return
	transformed = true
	shake_clock += dt * SHAKE_SPEED
	var strength := trauma * trauma
	var offset := Vector2(noise.get_noise_2d(shake_clock, 0.0), noise.get_noise_2d(0.0, shake_clock + 50.0)) * MAX_SHAKE * 1.6 * strength
	offset += kick
	var roll := noise.get_noise_2d(shake_clock * 0.7, 100.0) * MAX_ROLL * strength
	var z := 1.0 + zoom
	var scaled := Transform2D(0.0, Vector2(z, z), 0.0, zoom_pivot - zoom_pivot * z)
	var center := SCREEN / 2
	var rolled := Transform2D(roll, center - center.rotated(roll))
	get_viewport().canvas_transform = Transform2D(0.0, offset) * rolled * scaled
