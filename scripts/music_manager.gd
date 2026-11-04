extends "res://scripts/audio_group.gd"
## Digital Hope acompanha as telas fora da batalha, sem reiniciar entre elas.
## Músicas e volumes editáveis em Musicmanager.tscn.

var _current: AudioStreamPlayer
var _combat_active := false


func _ready() -> void:
	super._ready()
	for child in $Combate.get_children():
		if child is AudioStreamPlayer:
			child.finished.connect(_on_track_finished)
	play_menu()


func play_menu() -> void:
	if _current == $Menu/DigitalHope and _current.playing:
		return
	stop()
	_current = $Menu/DigitalHope
	_current.play()


func play_combat() -> void:
	if _combat_active:
		return
	stop()
	_combat_active = true
	_play_next_combat_track()


func stop() -> void:
	_combat_active = false
	if is_instance_valid(_current):
		_current.stop()
	_current = null


func _play_next_combat_track() -> void:
	var tracks: Array[AudioStreamPlayer] = []
	for child in $Combate.get_children():
		if child is AudioStreamPlayer and child.stream != null:
			tracks.append(child)
	if tracks.is_empty():
		return
	if tracks.size() > 1:
		tracks.erase(_current)
	if is_instance_valid(_current):
		_current.stop()
	_current = tracks.pick_random()
	_current.play()


func _on_track_finished() -> void:
	if _combat_active:
		_play_next_combat_track()
