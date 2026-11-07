extends RefCounted

## Estilo "latão e vinho" do HUD e do Diário: o mesmo da tela inicial. Painéis vinho com
## moldura de latão e um contorno escuro por fora; texto creme em Libre Baskerville.

const WINE := Color("2a1319")
const WINE_DEEP := Color("16090c") # contorno de fora e fundo das fichas
const WINE_LIFT := Color("3a1a22") # botão com o mouse em cima
const BRASS := Color("c9a36a")
const BRASS_DIM := Color("8a6d4a")
const GOLD := Color("f2ca76")
const FLAME := Color("f5a00a")
const TEXT := Color("f4dcb8")
const TEXT_LIT := Color("fff1cf")
const MUTED := Color("cdb596")
const DIM := Color("a8927a")
const HP := Color(0.35, 0.65, 1.0)
const FONT := preload("res://assets/fonts/LibreBaskerville.ttf")

static var _fonts := {}


## Libre Baskerville no peso pedido (400 texto, 700 títulos e números).
static func font(weight := 400) -> Font:
	if not _fonts.has(weight):
		var variation := FontVariation.new()
		variation.base_font = FONT
		variation.variation_opentype = {"wght": weight}
		_fonts[weight] = variation
	return _fonts[weight]


## Placa vinho com moldura de latão; `ring` é o contorno escuro por fora da moldura.
static func panel(fill := WINE, edge := BRASS, width := 2, radius := 4, margin := 10, ring := 3) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	box.anti_aliasing = true
	if ring > 0:
		box.shadow_color = WINE_DEEP
		box.shadow_size = ring
	return box


## Medalhão redondo (botões do canto, retratos).
static func medal(fill := WINE, edge := BRASS, width := 2) -> StyleBoxFlat:
	return panel(fill, edge, width, 999, 0, 3)


static func label(text: String, size: int, color := TEXT, weight := 400) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font", font(weight))
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	return item


## Botão do Diário. `primary`: dourado cheio (Voltar ao jogo). `round_shape`: medalhão.
static func style_button(button: Button, primary := false, round_shape := false) -> void:
	var fill := GOLD if primary else Color(WINE, 0.0)
	var edge := BRASS if primary else Color(BRASS, 0.55)
	var make := func(f: Color, e: Color) -> StyleBoxFlat:
		return medal(f, e, 2) if round_shape else panel(f, e, 2 if primary else 1, 4, 8, 0)
	if round_shape:
		fill = WINE
		edge = BRASS
	button.add_theme_stylebox_override("normal", make.call(fill, edge))
	button.add_theme_stylebox_override("hover", make.call(fill.lightened(0.15) if primary else WINE_LIFT, BRASS))
	button.add_theme_stylebox_override("pressed", make.call(fill.darkened(0.12) if primary else WINE_DEEP, GOLD))
	button.add_theme_stylebox_override("disabled", make.call(Color(fill, 0.35) if primary else Color(WINE, 0.0), Color(BRASS, 0.2)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := WINE_DEEP if primary else TEXT
	button.add_theme_font_override("font", font(700 if primary else 400))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(key, ink)
	button.add_theme_color_override("font_disabled_color", Color(ink, 0.4))
