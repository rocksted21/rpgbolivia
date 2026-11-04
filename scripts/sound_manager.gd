extends "res://scripts/audio_group.gd"
## Autoload da cena SoundManager.tscn. Os players e os sons ficam na cena,
## editáveis pelo Inspector. Menu tem os sons de interface; Combate tem os de
## ataques, magias e personagens (gerado por tools/build_audio.gd).
## Exemplo: SoundManager.play_ui(&"click1") ou SoundManager.play_sfx(&"swing").


func play_ui(sound_name: StringName) -> void:
	_play("Menu", sound_name)


func play_sfx(sound_name: StringName) -> void:
	_play("Combate", sound_name)


func _play(group: String, sound_name: StringName) -> void:
	var player := get_node_or_null(NodePath(group + "/" + str(sound_name))) as AudioStreamPlayer
	if player == null:
		push_warning("Som inexistente: %s/%s" % [group, sound_name])
		return
	player.play()


## Conectar antes da ação do botão, que pode destruir ou trocar a interface.
func bind_button(button: BaseButton, click_sound: StringName = &"click1") -> void:
	var click_callback := play_ui.bind(click_sound)
	var hover_callback := _on_button_hovered.bind(button)
	if not button.pressed.is_connected(click_callback):
		button.pressed.connect(click_callback)
	if not button.mouse_entered.is_connected(hover_callback):
		button.mouse_entered.connect(hover_callback)


func _on_button_hovered(button: BaseButton) -> void:
	if not button.disabled:
		play_ui(&"rollover1")


## Volume linear entre 0 (silêncio) e 1 (volume configurado nos players).
func set_menu_volume(volume: float) -> void:
	$Menu.volume = clampf(volume, 0.0, 1.0) * 100.0


func set_menu_muted(muted: bool) -> void:
	$Menu.muted = muted


func set_combat_volume(volume: float) -> void:
	$Combate.volume = clampf(volume, 0.0, 1.0) * 100.0


func set_combat_muted(muted: bool) -> void:
	$Combate.muted = muted
