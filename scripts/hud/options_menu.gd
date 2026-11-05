extends RefCounted

## Menu de opções do canto: volume, salvar, carregar e sair.

const GameSettings = preload("res://scripts/game_settings.gd")
const SaveGame = preload("res://scripts/save_game.gd")

const OPTIONS_PANEL_WIDTH := 400
const OPTIONS_CONFIRM_WIDTH := 460
const OPTIONS_Y := 74

var hud: BattleHud # a tela dona deste módulo


func _init(host: Node) -> void:
	hud = host


## Botão "Opções", no canto: abre por cima de tudo o volume, salvar, carregar e sair.
func _build_options() -> void:
	GameSettings.apply()
	hud.options_button = hud.party_ui._corner_button("Opções", Vector2(hud.SCREEN.x - hud.OPTIONS_WIDTH - hud.MARGIN, OPTIONS_Y), hud.OPTIONS_WIDTH)
	hud.options_button.pressed.connect(open_options)
	var layer := CanvasLayer.new()
	layer.layer = hud.layer + 10 # acima de tudo que o HUD cria depois (party, cidade, cartão)
	layer.process_mode = Node.PROCESS_MODE_ALWAYS # o jogo fica pausado com o menu aberto
	hud.add_child(layer)
	hud.options_overlay = ColorRect.new()
	hud.options_overlay.color = Color(0, 0, 0, 0.6)
	hud.options_overlay.size = hud.SCREEN
	hud.options_overlay.visible = false
	layer.add_child(hud.options_overlay)
	hud.options_panel = _options_box(OPTIONS_PANEL_WIDTH)
	hud.options_overlay.add_child(hud.options_panel)
	var column: VBoxContainer = hud.options_panel.get_child(0)
	column.add_child(_options_title("Opções"))
	hud.volume_label = hud._label("", 20, Color(1.0, 0.95, 0.8))
	column.add_child(hud.volume_label)
	hud.volume_slider = HSlider.new()
	hud.volume_slider.min_value = 0
	hud.volume_slider.max_value = 100
	hud.volume_slider.step = 5
	hud.volume_slider.value = GameSettings.volume()
	hud.volume_slider.focus_mode = Control.FOCUS_NONE
	hud.volume_slider.custom_minimum_size.y = 36
	column.add_child(hud.volume_slider)
	hud.volume_mute = _options_button(column, "Silenciar")
	hud.volume_mute.toggle_mode = true
	hud.volume_mute.button_pressed = GameSettings.muted()
	hud.volume_slider.value_changed.connect(func(value: float):
		GameSettings.set_volume(int(value))
		if hud.volume_mute.button_pressed and value > 0.0: # mexer no volume tira do mudo
			hud.volume_mute.set_pressed_no_signal(false)
			GameSettings.set_muted(false)
		_show_volume())
	hud.volume_mute.toggled.connect(func(on: bool):
		GameSettings.set_muted(on)
		_show_volume())
	_show_volume()
	column.add_child(HSeparator.new())
	hud.save_button = _options_button(column, "Salvar jogo")
	hud.save_button.pressed.connect(func(): hud.save_pressed.emit())
	hud.load_button = _options_button(column, "Carregar jogo")
	hud.load_button.pressed.connect(func(): hud.load_pressed.emit())
	hud.options_note = hud._label("", 16, Color(1.0, 0.85, 0.4))
	hud.options_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.options_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.options_note.custom_minimum_size.x = OPTIONS_PANEL_WIDTH - 36
	column.add_child(hud.options_note)
	column.add_child(HSeparator.new())
	var quit := _options_button(column, "Sair do jogo")
	quit.pressed.connect(func():
		hud.options_panel.visible = false
		hud.quit_panel.visible = true
		_center(hud.quit_panel))
	var back := _options_button(column, "Voltar ao jogo")
	back.pressed.connect(close_options)

	hud.quit_panel = _options_box(OPTIONS_CONFIRM_WIDTH)
	hud.quit_panel.visible = false
	hud.options_overlay.add_child(hud.quit_panel)
	var confirm: VBoxContainer = hud.quit_panel.get_child(0)
	confirm.add_child(_options_title("Sair do jogo?"))
	var warning := hud._label("Você volta para a tela inicial. O que não foi salvo será perdido.", 18, Color(0.9, 0.9, 0.92))
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.custom_minimum_size.x = OPTIONS_CONFIRM_WIDTH - 36
	confirm.add_child(warning)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	confirm.add_child(row)
	var ok := _options_button(row, "OK")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func(): hud.quit_pressed.emit())
	var cancel := _options_button(row, "Cancelar")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func():
		hud.quit_panel.visible = false
		hud.options_panel.visible = true
		_center(hud.options_panel))


func _options_box(width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", hud._box(Color(0.1, 0.11, 0.14, 0.97), Color(1.0, 0.85, 0.4), 2, 10, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return panel


func _options_title(text: String) -> Label:
	var title := hud._label(text, 30, Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return title


func _options_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size.y = 50
	hud.sound_manager.bind_button(button, &"click3")
	parent.add_child(button)
	return button


## Salvar só com `save_allowed` (fora do online, partida em andamento); carregar, com `load_allowed`.
func open_options() -> void:
	var can_load := SaveGame.exists()
	hud.card_ui.hide_card()
	hud.save_button.disabled = not hud.save_allowed
	hud.load_button.disabled = not can_load or not hud.load_allowed
	hud.load_button.text = "Carregar jogo" if not can_load else "Carregar jogo (%s)" % SaveGame.summary()
	hud.options_note.text = ""
	hud.options_panel.visible = true
	hud.quit_panel.visible = false
	hud.options_overlay.visible = true
	_center(hud.options_panel)
	_center(hud.quit_panel)
	hud.options_toggled.emit(true)


func close_options() -> void:
	hud.options_overlay.visible = false
	hud.options_toggled.emit(false)


func options_open() -> bool:
	return hud.options_overlay.visible


func show_options_note(text: String) -> void:
	hud.options_note.text = text


func _center(panel: Control) -> void:
	panel.reset_size()
	panel.position = (hud.SCREEN - panel.get_combined_minimum_size()) / 2


func _show_volume() -> void:
	hud.volume_label.text = "Volume: sem som" if GameSettings.muted() or GameSettings.volume() == 0 else "Volume: %d%%" % GameSettings.volume()
