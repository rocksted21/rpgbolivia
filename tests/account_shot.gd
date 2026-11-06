extends SceneTree
func _init() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	for i in 20: await process_frame
	menu.account_button.grab_focus()
	for i in 20: await process_frame
	root.get_texture().get_image().save_png("user://shot_menu.png")
	quit()
