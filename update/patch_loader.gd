extends Node
## Mounts a previously downloaded update before the other autoloads initialize.


func _init() -> void:
	preload("res://update/pck_updater.gd").apply_saved_pack()
