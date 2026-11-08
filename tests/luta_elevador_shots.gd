extends SceneTree
## Capturas da luta do elevador. Rodar sem --headless:
## godot --path . --script tests/luta_elevador_shots.gd -- <pasta>
## Tira fotos da chegada pela ponte, do elevador subindo, do começo da luta e da grade.

const SHOTS := [
	{"nome": "1_ponte", "tempo": 2.2},
	{"nome": "2_elevador_subindo", "tempo": 6.6},
	{"nome": "3_vez_do_jogador", "tempo": 15.0},
	{"nome": "4_grade", "tempo": 15.2, "grade": true},
	{"nome": "5_luta_andando", "tempo": 28.0, "auto": true},
]


func _initialize() -> void:
	var scene: Node2D = load("res://scenes/luta_elevador.tscn").instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node2D) -> void:
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://luta_elevador_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	var start := Time.get_ticks_msec()
	for shot in SHOTS:
		if shot.get("auto", false) and not scene.auto_heroes:
			scene.auto_heroes = true
			if not scene.busy:
				scene._clear_buttons()
				scene._run_battle()
		while (Time.get_ticks_msec() - start) / 1000.0 < shot["tempo"]:
			await process_frame
		scene.show_all = shot.get("grade", false)
		scene.marks.queue_redraw()
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, shot["nome"]])
	quit()
