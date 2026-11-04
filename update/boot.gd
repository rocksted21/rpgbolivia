extends Control
## Checks each exported launch before opening the menu. Editor runs stay local.

const Updater := preload("res://update/pck_updater.gd")
var status: Label
var detail: Label
var bar: ProgressBar


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("191e2a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 480
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)
	var title := Label.new()
	title.text = "COMBATE TÁTICO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("f2ca76"))
	column.add_child(title)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status)
	bar = ProgressBar.new()
	bar.custom_minimum_size.y = 16
	column.add_child(bar)
	detail = Label.new()
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	_start.call_deferred()


func update_status(label: String, fraction: float, message: String) -> void:
	status.text = label
	bar.value = clampf(fraction, 0.0, 1.0) * 100.0
	detail.text = message


func _start() -> void:
	update_status("CARREGANDO", 0.0, "")
	await get_tree().process_frame
	if await Updater.run(self):
		return
	if get_tree().change_scene_to_file("res://scenes/main_menu.tscn") != OK:
		update_status("NÃO FOI POSSÍVEL ABRIR O JOGO", 0.0, "Feche e abra novamente para recuperar a versão anterior.")
