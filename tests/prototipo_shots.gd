extends SceneTree
## Capturas do protótipo do cenário pintado. Rodar sem --headless:
## godot --path . --script tests/prototipo_shots.gd -- <pasta>

const SHOTS := [
	{"nome": "1_inteiro", "zoom": 0.64, "destino": Vector2(470, 560), "passos": 0, "chao": false},
	{"nome": "2_escada", "zoom": 1.2, "destino": Vector2(950, 800), "passos": 150, "chao": false},
	{"nome": "3_atras_da_cerca", "zoom": 1.4, "destino": Vector2(860, 905), "passos": 400, "chao": false},
	{"nome": "4_ponte", "zoom": 1.2, "destino": Vector2(1580, 680), "passos": 330, "chao": false},
	{"nome": "5_chao", "zoom": 0.64, "destino": Vector2(1580, 680), "passos": 0, "chao": true},
]


func _initialize() -> void:
	var scene: Node2D = load("res://scenes/prototipo_cenario.tscn").instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node2D) -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://prototipo_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await process_frame
	for shot in SHOTS:
		scene.walk_to(shot["destino"])
		for i in shot["passos"]:
			scene._process(1.0 / 30.0)
		scene.mask_layer.visible = shot["chao"]
		scene._set_zoom(shot["zoom"])
		scene.camera.reset_smoothing()
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, shot["nome"]])
	quit()
