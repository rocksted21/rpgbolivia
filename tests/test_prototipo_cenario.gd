extends SceneTree
## Protótipo do cenário pintado: dá para ir a todos os andares pelas escadas,
## os obstáculos bloqueiam e a cena abre e anda sem erro.
## Rodar: godot --headless --path . --script tests/test_prototipo_cenario.gd

const ChaoPintado = preload("res://scripts/prototipo/chao_pintado.gd")

var checks := 0
var failures := 0


func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FALHOU: ", text)


func _initialize() -> void:
	var floor_map := ChaoPintado.new()
	var start := floor_map.start_spot()
	check(floor_map.walkable(start), "o começo fica no chão")
	# Um lugar de cada área, todos alcançáveis a partir da praça
	var places := {
		"calcada_alta": Vector2(600, 600), "terraco_alto": Vector2(1100, 440),
		"ponte": Vector2(1320, 525), "terraco_direito": Vector2(1580, 680),
		"rua_baixa": Vector2(950, 800), "rua_frente": Vector2(700, 960),
		"rua_direita": Vector2(1500, 840),
	}
	for place in places:
		var spot := floor_map.nearest_walkable(places[place], 4)
		check(spot.x >= 0, "%s tem chão" % place)
		check(not floor_map.path(start, spot).is_empty(), "dá para chegar em %s" % place)
	# Muros e escadas: a rua baixa não fica colada na calçada alta (só pela escada)
	check(not floor_map.walkable(Vector2(800, 640)), "a parede entre a calçada e a rua não é chão")
	check(not floor_map.walkable(Vector2(1290, 715)), "a carruagem da direita bloqueia")
	check(not floor_map.walkable(Vector2(1350, 845)), "o muro quebrado bloqueia")
	var long_way := floor_map.path(Vector2(600, 600), floor_map.nearest_walkable(Vector2(950, 800), 4))
	check(long_way.size() > 40, "da calçada para a rua o caminho dá a volta pela escada")

	var scene: Node2D = load("res://scenes/prototipo_cenario.tscn").instantiate()
	root.add_child(scene)
	_walk(scene)


func _walk(scene: Node2D) -> void:
	await process_frame
	check(scene.walk_to(Vector2(1580, 680)), "o líder aceita andar até o terraço direito")
	for i in 900:
		scene._process(1.0 / 30.0)
	var leader: Node2D = scene.heroes[0]["node"]
	check(leader.position.distance_to(Vector2(1580, 680)) < 20, "o líder chegou ao terraço direito (%s)" % leader.position)
	var follower: Node2D = scene.heroes[3]["node"]
	check(scene.floor_map.walkable(follower.position) or follower.position.distance_to(leader.position) < 200, "o último da fila veio junto")
	print("prototipo_cenario: %d checagens, %d falhas" % [checks, failures])
	quit(1 if failures > 0 else 0)
