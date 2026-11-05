extends Node2D

# Resolve services after the content pack is mounted by the thin installer.
var music_manager:
	get: return get_node("/root/MusicManager")

var online_session:
	get: return get_node("/root/OnlineSession")

var sound_manager:
	get: return get_node("/root/SoundManager")

## Tela do combate: desenha o tabuleiro, recebe o input e anima os eventos das regras.

const Hex = preload("res://scripts/hex.gd")
const Data = preload("res://scripts/game_data.gd")
const BattleState = preload("res://scripts/battle_state.gd")
const WorldState = preload("res://scripts/world_state.gd")
const WorldGen = preload("res://scripts/world_gen.gd")
const ExpeditionState = preload("res://scripts/expedition_state.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const Exp = preload("res://scripts/expedition_data.gd")
const TownState = preload("res://scripts/town_state.gd")
const TownPanels = preload("res://scripts/town_panels.gd")
const TownLife = preload("res://scripts/town_life.gd")
const TownContent = preload("res://scripts/town_content.gd")
const TownData = preload("res://scripts/town_data.gd")
const WorldLight = preload("res://scripts/world_light.gd")
const TOWN_META := "town"
const BLOOM_INTENSITY := 1.3
const BLOOM_THRESHOLD := 0.72
const TOWN_PANELS_LAYER := 50
const TOWN_TINT := Color(0.6, 0.63, 0.82) # noite: as fogueiras e o farol iluminam a cidade
const EXPEDITION_META := "expedition"
const BOSS_SCALE := 1.35
const COMPASS_ARROWS := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
const AI = preload("res://scripts/ai.gd")
const UnitView = preload("res://scripts/unit_view.gd")
const Hud = preload("res://scripts/hud.gd")
const BattleCamera = preload("res://scripts/battle_camera.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")
const Skills = preload("res://scripts/skill_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

const BOARD_POS := Vector2(250, 142) # sem painel lateral: o tabuleiro fica no meio, a fila à esquerda
const BOARD_SCALE := 0.5
const TILE_WIDTH := 186
const ROW_STEP := 160
const TILE_FRONT := 213.0 # ponta da frente do topo do hexágono, na textura (igual ao shader)
const TILE_SLOPE := 53.0 # quanto as bordas inclinadas descem do centro até o lado
const TILE_WALL := 31.0 # altura da parede abaixo da borda da frente
# Cantos do topo do hexágono; o lado i dá para a vizinha na direção i de Hex.neighbor.
const HEX_CORNERS := [Vector2(185, 53), Vector2(185, 160), Vector2(93, 213), Vector2(0, 160), Vector2(0, 53), Vector2(93, 0)]
const HEX_MIDDLE := Vector2(93, 107)
const WALL_SIDE_MARGIN := 0.4
const SIDE_HEIGHT := 29 # altura da lateral do tile; empilhar tiles a cada 29 px forma o penhasco
const LAYERS_PER_LEVEL := 4 # 116 px por nível; a altura é projetada na vertical
# Na exploração os degraus são mais baixos: num mapa gerado, uma casa atrás de um
# degrau precisa continuar visível e clicável.
const WORLD_LAYERS_PER_LEVEL := 3
const TOWN_LAYERS_PER_LEVEL := 2 # a planta da cidade conta com degraus baixos
const MODEL_META := "res://assets/town/modelos/meta.json"
const MODEL_SCALE := 2.0 # como os personagens: 1 pixel de arte vale 2 no tabuleiro
const MODEL_NIGHT_LIFT := Color(1.3, 1.26, 1.05) # desfaz parte do tom de noite: janelas acesas continuam vivas
const TOWN_GROUND_EDGE := 0.35 # calçada e grama com a borda mais limpa que no mato das expedições
# Chão natural das expedições: as casas continuam nas regras, mas não aparecem no desenho.
const CORNER_WOBBLE := Vector2(38, 26) # quanto cada canto sai do lugar: some o desenho da colmeia
const PROP_WOBBLE := Vector2(74, 50) # árvores e pedras fora do centro da casa
const RING_RADIUS := Vector2(78, 62)
const TOWN_WOBBLE := 0.55
const TRAIL_STRENGTH := 0.86 # abaixo de 1 estreita o traço; a estrada é mais larga
const ROAD_CORNER := 0.22
const FOREST_HEIGHT := 1.65
const TREE_SEE_THROUGH := 0.45
const FEET := Vector2(93, 125)
const NO_CELL := Vector2i(-999999, -999999) # coordenadas negativas existem na exploração
const HOLD_TIME := 0.45
const SCENERY_BASE := {3: 1, 6: 7, 10: 9, 11: 9}
const TILE_PATH := "res://assets/tiles/%d.png"
const WORLD_META := "world_hero" # o menu guarda aqui o herói escolhido para explorar
const EXPLORE_ZOOM := 0.8 # a câmera fica mais longe fora da arena; o resto da lista acompanha
const FOG_START := 650.0
const FOG_END := 1100.0
const FOG_SIDE_SQUEEZE := 0.6 # igual ao peso lateral da névoa no shader
const VIEW_ROWS_FRONT := 7
const VIEW_ROWS_BACK := 14
const UNLOAD_MARGIN := 2
const Z_REBASE_ROWS := 12 # em meias linhas: a ordem de desenho fica longe do limite do Godot
const QUIET_DISTANCE := 11 # inimigo mais longe que isso age sem animação nem espera

const STEP_COLOR := Color(0.27, 0.67, 1.0, 0.35)
const PATH_COLOR := Color(0.27, 0.67, 1.0, 0.7)
const REACH_FILL := Color(1.0, 0.55, 0.1, 0.3)
const REACH_LINE := Color(1.0, 0.6, 0.15, 0.95)
const TARGET_COLOR := Color(0.92, 0.24, 0.24, 0.55)
const INSPECT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const NEXT_ENEMY_ARROW := Color(0.95, 0.3, 0.25)
const ROAM_HINT := "Clique para andar  ·  Segure Q/E para girar  ·  Tab troca de herói  ·  G alterna fila e separados"
const TURN_SPEED := 1.9 # radianos por segundo com a tecla apertada
const TURN_EASE := 9.0 # quão rápido o giro acelera e freia
const TURN_DRAG := 0.007 # radianos por pixel ao arrastar com o botão do meio
const MAP_REFRESH := 0.12 # segundos entre revisões do mapa enquanto gira
const DEPLOY_TIME := 0.45
const CAMERA_SPEED := 7.0
const STEP_FLAT := 0.22
const STEP_CLIMB := 0.48
const WALK_STEP := 0.3 # tempo por casa na jornada, igual em chão plano e em degrau
const WALK_SMOOTH := 8.0 # arredonda as curvas: o desenho persegue o caminho, sem quinas
const MAX_WALK_FRAME := 0.05
const WALK_SETTLE := 1.5 # distância em que o herói já é considerado parado
const FACE_HOLD := 0.4 # tempo mínimo olhando para um lado, para não ficar virando
const FACE_FOLLOW := 2.5 # quão rápido o olhar acompanha a direção da caminhada
const FACE_TURN := 1.3 # precisa ser bem mais vertical que horizontal para virar de frente ou de costas
const FACE_KEEP := 0.75 # e bem menos para voltar a olhar de lado
const FACE_SIDE_FLIP := 0.3 # andando quase na vertical, não troca de lado à toa
const CATCH_UP := 0.7 # quanto o seguidor acelera por casa de atraso
const BUILD_BUDGET_USEC := 2000 # tempo por quadro para desenhar casas novas
const FILE_RETRY := 0.05
const FILE_PATIENCE := 1.5
const SIGHT_COLOR := Color(0.95, 0.25, 0.2, 0.28)
const DEFAULT_HINT := "Toque numa casa azul para andar ou num personagem para agir. Segure para ver detalhes."
const END_TURN_KEY_HINT := "Espaço encerra o turno."
# Magia é roxa para não se confundir com o laranja do alcance.
const AREA_COLOR := Color(0.72, 0.3, 1.0, 0.6)
const CHARGE_COLOR := Color(0.72, 0.3, 1.0, 0.42)
const ACTIVE_COLOR := Color(1.0, 0.84, 0.35)
const BEACON_COLOR := Color(1.0, 0.85, 0.35)
const CAST_INK := Color(1.0, 0.62, 0.15)
# Animação de cada magia (tiras em assets/fx/<elemento>, geradas pelo build_assets).
# projectile voa do mago até o alvo; impact toca no alvo, ou em cada casa da área se per_cell.
# Posição do impacto: ground põe a base do efeito no chão; senão o centro fica `lift` acima dos pés.
# ring_delay: o anel em volta do centro começa depois. Escalas são no tabuleiro, que está a 0.5:
# escala 2 dá 1 pixel do efeito por pixel de tela.
# sound: som do impacto, do grupo Combate do SoundManager; cast_sound: o do projétil (fire_cast).
const SPELL_FX := {
	"faisca": {"impact": "fogo/small_fire", "impact_scale": 4.0, "ground": true, "sound": &"fire_hit"},
	"labareda": {"impact": "fogo/fire", "impact_scale": 3.0, "ground": true, "sound": &"flame"},
	"bola_fogo": {"projectile": "fogo/fireball", "impact": "fogo/explosion", "impact_scale": 2.0, "lift": 90, "sound": &"fire_hit"},
	"pilar_fogo": {"impact": "fogo/fire_pillar", "impact_scale": 2.0, "ground": true, "sound": &"flame"},
	"golpe_solar": {"impact": "fogo/sun_strike", "impact_scale": 2.0, "lift": 90, "sound": &"explosion"},
	"flor_fogo": {"impact": "fogo/fire_flower", "impact_scale": 2.0, "lift": 40, "sound": &"fire_hit"},
	"explosao": {"projectile": "fogo/fireball", "impact": "fogo/explosion", "impact_scale": 2.0, "per_cell": true, "lift": 40, "ring_delay": 0.12, "sound": &"explosion"},
	"poca_lava": {"impact": "fogo/lava_puddle", "impact_scale": 2.0, "per_cell": true, "lift": 0, "sound": &"flame"},
	"chuva_lava": {"impact": "fogo/lava_drop", "impact_scale": 3.0, "per_cell": true, "ground": true, "ring_delay": 0.1, "sound": &"fire_hit"},
	"geiser_magma": {"impact": "fogo/magma_geyser", "impact_scale": 2.0, "ground": true, "sound": &"explosion"},
	"furacao_fogo": {"impact": "fogo/fire_hurricane", "impact_scale": 3.0, "lift": 60, "sound": &"flame"},
	"fenix": {"impact": "fogo/phoenix", "impact_scale": 4.0, "lift": 120, "sound": &"explosion"},
	"escudo_fogo": {"impact": "fogo/fire_shield", "impact_scale": 2.0, "lift": 90, "sound": &"flame"},
	"gota": {"impact": "agua/water_drop", "impact_scale": 4.0, "ground": true, "sound": &"water"},
	"chicote_agua": {"impact": "agua/water_whip", "impact_scale": 2.0, "lift": 90, "sound": &"water"},
	"bola_agua": {"projectile": "agua/waterball", "projectile_turn": PI, "cast_sound": &"water", "impact": "agua/splash", "impact_scale": 3.0, "ground": true, "sound": &"water"},
	"estaca_gelo": {"impact": "agua/ice_spike", "impact_scale": 2.0, "ground": true, "sound": &"ice"},
	"cristal_gelo": {"impact": "agua/ice_crystal", "impact_scale": 4.0, "ground": true, "sound": &"ice"},
	"floco_neve": {"impact": "agua/snowflake", "impact_scale": 3.0, "lift": 60, "sound": &"ice"},
	"estilhaco_gelo": {"impact": "agua/ice_burst", "impact_scale": 2.0, "per_cell": true, "lift": 40, "ring_delay": 0.12, "sound": &"ice"},
	"onda": {"impact": "agua/splash", "impact_scale": 3.0, "per_cell": true, "ground": true, "ring_delay": 0.1, "sound": &"water"},
	"geiser": {"impact": "agua/geyser", "impact_scale": 2.0, "ground": true, "sound": &"water"},
	"redemoinho": {"impact": "agua/water_hurricane", "impact_scale": 3.0, "lift": 60, "sound": &"water"},
	"kraken": {"impact": "agua/kraken", "impact_scale": 5.0, "lift": 120, "sound": &"water"},
	"chama": {"impact": "fogo/fire_pillar", "impact_scale": 2.0, "per_cell": true, "ground": true, "sound": &"flame"},
	"manto_agua": {"impact": "agua/splash", "impact_scale": 3.0, "ground": true, "sound": &"water"},
}
const PROJECTILE_SCALE := 2.0
const FX_FPS := 16.0

var hex_poly := PackedVector2Array([Vector2(93, 0), Vector2(185, 53), Vector2(185, 160), Vector2(93, 213), Vector2(0, 160), Vector2(0, 53)])
var state
var hud
var board: Node2D
var battle_camera: Node
var meta := {}
var fx_meta := {}
var views := {}
var overlays := {}
var reach_lines := {}
var forests := {}
var trees := {} # árvores soltas do mapa: ficam transparentes quando escondem alguém
var active_outline: Line2D
var inspect_outline: Line2D
var busy := true
var hover := NO_CELL
var menu_cell := NO_CELL # casa com o menu aberto
var menu_options := []
var show_order := false
var pressing := false
var press_cell := NO_CELL
var press_token := 0 # cada toque novo invalida o "segurar" do toque anterior
var pinned = null # unidade escolhida tocando na fila de turnos
var focus_ring: Line2D
var focus_tween: Tween
var remote_playing := false
var room_label: Label
var rewarded := false # os pontos da luta já foram dados
var exploring := false
var expedition := false # solo: cidade, locais especiais e chefe (ver expedition_state.gd)
var town := false # a Cidade-Farol: mapa fixo, moradores e nada de inimigos
var town_panels
var town_life
var models := {} # construções em 3D à vista: {sprite: {views, turn}}
var model_meta := {}
var natural := false # chão contínuo: expedições e jornada, sem a cidade
var world_light # luz e partículas das expedições e da jornada
var cell_tint := Color.WHITE # tom da casa em construção
var person_labels := {}
var quests_finished := []
var landmark_nodes := {} # casa: marcas no mapa de um local especial
var selected # o herói que recebe os cliques fora de combate
var together := true # fora de combate, os heróis do jogador andam em fila atrás do selecionado
var file_next := {} # herói -> quem anda logo atrás dele
var file_blocked := {} # seguidor -> tempo esperando alguém sair da frente
var walk_paths := {} # herói -> casas que faltam; cada um caminha no próprio ritmo (só o dono da sala)
var walk_goals := {} # herói -> casa escolhida, para refazer a rota se alguém entrar na frente
var step_wait := {} # herói -> tempo até o próximo passo
var moving := {} # unidades em movimento na tela
var walks := {} # unidade -> caminhada em andamento (posição contínua, independente dos passos)
var overlays_dirty := false
var cells_to_build := []
var cells_to_unload := []
var camera_unit # quem a câmera acompanha
var camera_cell := NO_CELL
var camera_look = null # enquanto mostra quem apareceu, a câmera olha para este ponto
var view_angle := 0.0 # giro da câmera; as regras não sabem dele
var turn_speed := 0.0
var turn_hold := 0 # botão da tela apertado: -1, 1 ou 0
var map_refresh := 0.0
var cell_rows := {} # casa -> linha de desenho atual, para só mexer no que mudou de ordem
var roam_search := {} # busca de caminho a partir de roam_from, para desenhar a rota sob o mouse
var roam_from := NO_CELL
var roam_for = null
var cell_nodes := {} # nós desenhados de cada casa, para descarregar o que ficou para trás
var building: Array # casa em construção
var z_origin := 0
var level_layers := LAYERS_PER_LEVEL
var tile_meshes := {}
var wall_meshes := {}
var wall_groups := [] # paredes por lado do hexágono: as de costas para a câmera ficam escondidas


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	fx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/meta.json"))
	_start_battle()
	if online_session.playing:
		online_session.command_received.connect(_network_command)
		online_session.packet_received.connect(_network_packet)
		online_session.connection_lost.connect(_network_lost)
		online_session.changed.connect(_room_status)
		var layer := CanvasLayer.new()
		add_child(layer)
		var row := HBoxContainer.new()
		row.position = Vector2(860, 74)
		layer.add_child(row)
		room_label = Label.new()
		room_label.add_theme_font_size_override("font_size", 18)
		row.add_child(room_label)
		var leave_button := Button.new()
		leave_button.text = "Sair da sala"
		sound_manager.bind_button(leave_button)
		leave_button.pressed.connect(_leave_online)
		row.add_child(leave_button)
		_room_status()
		_network_packet({})


func _exit_tree() -> void:
	music_manager.play_menu()


func _start_battle() -> void:
	var chosen: Variant = get_tree().root.get_meta(WORLD_META, [])
	var party_types: Array = chosen if chosen is Array else ([chosen] if str(chosen) != "" else [])
	exploring = online_session.playing or not party_types.is_empty()
	town = not online_session.playing and get_tree().root.get_meta(TOWN_META, false)
	expedition = false
	if town:
		music_manager.play_menu()
	else:
		music_manager.play_combat()
	level_layers = LAYERS_PER_LEVEL
	if exploring:
		level_layers = TOWN_LAYERS_PER_LEVEL if town else WORLD_LAYERS_PER_LEVEL
	if online_session.playing:
		state = online_session.state
	elif exploring:
		var builds := {}
		for i in party_types.size():
			builds[i] = HeroProgress.unlocked(party_types[i])
		expedition = not town and get_tree().root.get_meta(EXPEDITION_META, false)
		if town:
			state = TownState.new(party_types, randi(), builds, TownProgress.expedition_setup())
		elif expedition:
			state = ExpeditionState.new(party_types, randi(), builds, TownProgress.expedition_setup())
		else:
			state = WorldState.new(party_types, randi(), builds)
	else:
		state = BattleState.from_data(_saved_builds())
	rewarded = false
	walk_paths.clear()
	walk_goals.clear()
	file_next.clear()
	file_blocked.clear()
	step_wait.clear()
	moving.clear()
	walks.clear()
	cell_rows.clear()
	landmark_nodes.clear()
	cells_to_build.clear()
	cells_to_unload.clear()
	camera_look = null
	roam_from = NO_CELL
	selected = _first_mine() if exploring else null
	camera_unit = selected
	views.clear()
	cell_nodes.clear()
	z_origin = 0
	overlays.clear()
	reach_lines.clear()
	forests.clear()
	trees.clear()
	hover = NO_CELL
	menu_cell = NO_CELL
	menu_options = []
	show_order = false
	if board != null:
		board.queue_free()
	if battle_camera != null:
		battle_camera.queue_free()
	if hud != null:
		hud.queue_free()
	if town_life != null:
		town_life.queue_free()
		town_life = null
	person_labels.clear()

	board = Node2D.new()
	board.position = BOARD_POS
	board.scale = Vector2.ONE * BOARD_SCALE
	if town:
		board.modulate = TOWN_TINT
	add_child(board)
	battle_camera = BattleCamera.new()
	add_child(battle_camera)
	if exploring:
		battle_camera.set_zoom(EXPLORE_ZOOM)
	if world_light != null:
		world_light.queue_free()
		world_light = null
	natural = exploring
	if natural:
		battle_camera.ground_noise = load(BiomeArt.EDGE_NOISE)
		if town:
			battle_camera.soil_edge = TOWN_GROUND_EDGE
	if exploring:
		_add_bloom()
		if not town:
			world_light = WorldLight.new()
			add_child(world_light)
			world_light.setup(self)
		battle_camera.set_fog(FOG_START, FOG_END)
		camera_cell = selected.pos
		board.position = _camera_target(camera_cell)
		z_origin = _row(camera_cell)
	wall_groups = []
	for dir in 6:
		var group := Node2D.new()
		board.add_child(group)
		wall_groups.append(group)
	_show_facing_walls()
	_build_tiles()
	for unit in state.units:
		_add_unit_view(unit)
	active_outline = _new_hex_line(ACTIVE_COLOR, 7)
	inspect_outline = _new_hex_line(INSPECT_COLOR, 7)
	inspect_outline.visible = false
	pinned = null
	_build_focus_marker()

	hud = Hud.new()
	add_child(hud)
	hud.setup(meta)
	hud.unit_picked.connect(_on_timeline_pick)
	hud.option_pressed.connect(_on_option_pressed)
	hud.order_toggled.connect(_on_order_toggled)
	hud.end_turn_pressed.connect(_end_turn)
	hud.restart_pressed.connect(_leave_online if online_session.playing else (_back_to_menu if expedition else _start_battle))
	hud.skills_pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	if exploring:
		hud.setup_exploration()
		hud.menu_pressed.connect(_back_to_menu)
		if expedition:
			hud.use_town_exit()
			hud.set_potions(state.potions)
			hud.potion_pressed.connect(_use_potion)
		if town:
			_setup_town()
		hud.setup_party(state.party, _owner_names())
		hud.party_pressed.connect(_on_party_pick)
		hud.rotate_held.connect(func(direction): turn_hold = direction)
		hud.together_toggled.connect(func(on): together = on)
	if online_session.playing:
		hud.skills_button.visible = false
		for child in hud.end_label.get_parent().get_children():
			if child is Button and child != hud.skills_button: child.text = "Voltar ao Online"
	_advance()


## Bloom no mapa: só o que já é muito claro brilha. A interface fica em outra camada, de fora.
func _add_bloom() -> void:
	if has_node("Bloom"):
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = 0
	env.glow_enabled = true
	env.glow_intensity = BLOOM_INTENSITY
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = BLOOM_THRESHOLD
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var world_env := WorldEnvironment.new()
	world_env.name = "Bloom"
	world_env.environment = env
	add_child(world_env)


## Builds salvas dos heróis, por índice em Data.BATTLE_UNITS.
func _saved_builds() -> Dictionary:
	var builds := {}
	for i in Data.BATTLE_UNITS.size():
		var type_id: String = Data.BATTLE_UNITS[i][0]
		if Skills.has_tree(type_id):
			builds[i] = HeroProgress.unlocked(type_id)
	return builds


func _update_journey() -> void:
	if town:
		_update_town()
		return
	hud.set_journey(state.alive_party().size(), state.party.size(), state.farthest, state.kills, state.danger(), Data.BIOMES[state.biome_at(camera_cell)]["name"])
	if expedition:
		hud.set_objective(_objective_text())
		hud.set_tracker(_quest_tracker())
	hud.update_party(selected if _free_roam() else state.active_unit())


## Nome do jogador de cada herói, para a barra da party no online.
func _owner_names() -> Dictionary:
	var names := {}
	if online_session.playing:
		for unit in state.party:
			names[unit] = str(online_session.players.get(online_session.owner_of(unit), ""))
	return names


## Fim de luta: dá os pontos e mostra o resultado. Online, só dos heróis deste jogador;
## na exploração, que só acaba com a queda, o ganho vem da distância e dos abates.
func _show_result(result: int) -> void:
	var won := result == Data.Team.PLAYER
	var note := ""
	if exploring: # a vida no topo da tela precisa mostrar a queda
		_update_journey()
	if not rewarded:
		rewarded = true
		var gain: int = Skills.WIN_POINTS if won else Skills.LOSS_POINTS
		if exploring:
			gain = Skills.journey_points(state.kills, state.farthest)
		if expedition:
			quests_finished = TownProgress.record(state.result())
			_set_return_to_town()
			if won:
				_rebuild_cell(state.beacon_cell) # o farol acende
		var types := []
		for unit in state.units:
			if unit.team == Data.Team.PLAYER and (not online_session.playing or online_session.can_control(unit)):
				types.append(unit.type_id)
		var before := 0
		for type_id in types:
			before += HeroProgress.earned(type_id)
		var count := HeroProgress.award(types, gain)
		if count == 1: # perto do teto, o herói pode ganhar menos que o previsto
			var after := 0
			for type_id in types:
				after += HeroProgress.earned(type_id)
			gain = after - before
		if count > 0:
			note = "+%d %s de skill%s" % [gain, "pontos" if gain > 1 else "ponto", " para %d heróis" % count if count > 1 else ""]
	for id in quests_finished:
		note += "%sMissão cumprida: %s" % ["\n" if note != "" else "", TownContent.QUESTS[id]["title"]]
	quests_finished = []
	hud.show_end(_end_text() if exploring else ("Vitória!" if won else "Derrota"), note)


# Anel grosso que pulsa na casa do personagem em foco, com o nome em cima dele.
func _build_focus_marker() -> void:
	focus_ring = _new_hex_line(Color(1.0, 0.95, 0.3), 12)
	focus_ring.visible = false
	if focus_tween != null:
		focus_tween.kill()
	focus_tween = create_tween().set_loops()
	focus_tween.tween_property(focus_ring, "modulate:a", 0.35, 0.45)
	focus_tween.tween_property(focus_ring, "modulate:a", 1.0, 0.45)


## Marca no mapa e na fila o mesmo personagem, seja ele vindo do toque no mapa ou na fila.
func _sync_focus() -> void:
	var shown = _shown_unit() if not busy else null
	hud.highlight(shown)
	if shown == null or not shown.alive():
		focus_ring.visible = false
		return
	_place_ground_marker(focus_ring, shown.pos)
	focus_ring.z_index = _z(_row(shown.pos)) + 4 # abaixo do personagem (+5)
	focus_ring.visible = true


func _on_timeline_pick(unit) -> void:
	if busy or not unit.alive():
		return
	_close_menu()
	pinned = null if pinned == unit else unit
	_refresh_overlays()
	_update_hint()
	sound_manager.play_ui(&"switch3")


func _build_tiles() -> void:
	if exploring:
		_sync_world(camera_cell)
		return
	for row in state.rows():
		for col in state.cols():
			_build_cell(Vector2i(col, row))


func _build_cell(cell: Vector2i) -> void:
	building = []
	var row := _row(cell)
	var base := Vector2(_column_x(cell), cell.y * ROW_STEP)
	var layers: int = state.elevation_at(cell) * level_layers
	# Só a parede que aparece: o que as casas da frente cobrem não precisa ser desenhado.
	var terrain_id: int = state.terrain_id_at(cell)
	# Só a exploração tem biomas; o Online continua com os tiles do mapa fixo.
	var biome: String = state.biome_at(cell) if exploring else ""
	var wall := BiomeArt.wall(biome) if exploring else TILE_PATH % 9
	var ground := BiomeArt.ground(biome, state.floor_id_at(cell), state.detail_at(cell)) if exploring else TILE_PATH % SCENERY_BASE.get(terrain_id, terrain_id)
	cell_tint = BiomeArt.NIGHT_TINT.get(biome, Color.WHITE) if world_light != null else Color.WHITE
	if exploring:
		_add_walls(cell, wall, ground, row, layers)
	else:
		for layer in range(_hidden_layers(cell, layers), layers):
			_add_tile(wall, base - Vector2(0, layer * SIDE_HEIGHT), row, layer * SIDE_HEIGHT)
	if natural:
		_add_natural_ground(cell, row, layers, biome)
	else:
		_add_tile(ground, cell_origin(cell), row, layers * SIDE_HEIGHT)
	if exploring:
		if not natural:
			for overlay_path in state.ground_overlays(cell):
				_add_tile(overlay_path, cell_origin(cell), row, layers * SIDE_HEIGHT)
		_add_biome_props(biome, terrain_id, cell)
	elif SCENERY_BASE.has(terrain_id):
		_add_scenery(terrain_id, cell)
	if expedition:
		_add_landmark(cell, row)
	if town:
		_add_person_name(cell, row)
	var overlay := Polygon2D.new()
	overlay.polygon = hex_poly
	_place_ground_marker(overlay, cell)
	overlay.z_index = _z(row) + 1
	overlay.visible = false
	board.add_child(overlay)
	building.append(overlay)
	overlays[cell] = overlay
	var line := _new_hex_line(REACH_LINE, 5)
	_place_ground_marker(line, cell)
	line.z_index = _z(row) + 2
	line.visible = false
	building.append(line)
	reach_lines[cell] = line
	cell_nodes[cell] = building
	cell_rows[cell] = row


## Com a câmera livre, qualquer lado pode ficar de frente: cada lado com desnível ganha a sua
## parede, degrau por degrau. Os lados de trás ficam cobertos pelo topo da própria casa.
func _add_walls(cell: Vector2i, wall: String, ground: String, row: int, layers: int) -> void:
	for dir in 6:
		var side: int = state.elevation_at(Hex.neighbor(cell, dir)) * level_layers
		for layer in range(side + 1, layers + 1):
			var height := layer * SIDE_HEIGHT
			var path := ground if layer == layers else wall
			var strip := Polygon2D.new()
			strip.texture = load(path)
			var mesh: Dictionary = _natural_wall_mesh(cell, dir) if natural else _wall_mesh(dir)
			strip.polygon = mesh["vertices"]
			strip.uv = mesh["uv"]
			strip.polygons = mesh["faces"]
			strip.material = battle_camera.tile_material(height * BOARD_SCALE, BOARD_SCALE)
			strip.position = Vector2(_column_x(cell), cell.y * ROW_STEP - height)
			strip.z_index = _z(row)
			strip.modulate = cell_tint
			wall_groups[dir].add_child(strip)
			battle_camera.keep_drawn(strip)
			building.append(strip)


## A mesma parede, com os cantos fora do lugar como no chão: o penhasco não sai em zigue-zague.
func _natural_wall_mesh(cell: Vector2i, dir: int) -> Dictionary:
	var base: Dictionary = _wall_mesh(dir)
	var origin := Vector2(_column_x(cell), cell.y * ROW_STEP)
	var a := _natural_corner(cell, dir) - origin
	var b := _natural_corner(cell, (dir + 1) % 6) - origin
	var drop := Vector2(signf(a.x - HEX_MIDDLE.x) if is_equal_approx(a.x, b.x) else 0.0, TILE_WALL)
	return {"vertices": PackedVector2Array([a, b, b + drop, a + drop]), "uv": base["uv"], "faces": base["faces"]}


# --- Chão natural --------------------------------------------------------------

## Canto de uma casa, no plano do mundo. Casas vizinhas calculam o mesmo canto, então nunca abre fresta.
func _natural_corner(cell: Vector2i, index: int) -> Vector2:
	var corner: Vector2 = HEX_CORNERS[index]
	var key := Vector2i(_column_x(cell) + (TILE_WIDTH if corner.x > HEX_MIDDLE.x else int(corner.x)) , cell.y * ROW_STEP + int(corner.y))
	var mixed := (key.x * 73856093) ^ (key.y * 19349663)
	mixed = (mixed ^ (mixed >> 13)) * 1274126177
	mixed = mixed ^ (mixed >> 16)
	var wobble := Vector2(float(mixed & 0xFFF) / 4095.0 - 0.5, float((mixed >> 12) & 0xFFF) / 4095.0 - 0.5)
	# A planta da cidade alinha escadas e prédios com os degraus: lá os cantos saem menos do lugar.
	return Vector2(key) + wobble * CORNER_WOBBLE * 2.0 * (TOWN_WOBBLE if town else 1.0)


## Malha da casa: centro, 6 cantos e 6 meios de lado. A cobertura de cada mancha é dada nesses pontos.
func _natural_mesh(cell: Vector2i) -> Dictionary:
	var vertices := PackedVector2Array()
	vertices.resize(13)
	var middle := Vector2.ZERO
	for i in 6:
		vertices[1 + i] = _natural_corner(cell, i)
		middle += vertices[1 + i]
	vertices[0] = middle / 6.0
	for i in 6:
		vertices[7 + i] = (vertices[1 + i] + vertices[1 + (i + 1) % 6]) / 2.0
	var faces: Array[PackedInt32Array] = []
	for i in 6:
		faces.append(PackedInt32Array([0, 1 + i, 7 + i]))
		faces.append(PackedInt32Array([0, 7 + i, 1 + (i + 1) % 6]))
	return {"vertices": vertices, "faces": faces}


## Desenha o chão em camadas. Cada camada é uma mancha: cobre as casas do seu tipo e avança até
## o meio do caminho nas vizinhas, com a borda recortada pelo ruído do shader.
func _add_natural_ground(cell: Vector2i, row: int, layers: int, biome: String) -> void:
	var mesh := _natural_mesh(cell)
	var around := []
	for dir in 6:
		var next: Vector2i = Hex.neighbor(cell, dir)
		# Um penhasco separa os terrenos: a mancha não atravessa o desnível.
		around.append(next if state.elevation_at(next) == state.elevation_at(cell) else cell)
	var order: Array = BiomeArt.BIOME_ORDER
	var ranks := {}
	for spot in [cell] + around:
		ranks[spot] = order.find(state.biome_at(spot))
	var lowest: int = ranks.values().min()
	var highest: int = ranks.values().max()
	_natural_layer(mesh, BiomeArt.soil(order[lowest]), _full_cover(), order[lowest], row, layers)
	for level in range(lowest + 1, highest + 1):
		if ranks.values().has(level) or level <= ranks[cell]:
			var cover := _cover(around, cell, func(spot): return ranks[spot] >= level)
			_natural_layer(mesh, BiomeArt.soil(order[level]), cover, order[level], row, layers)
	var shaded := _cover(around, cell, func(spot): return state.floor_id_at(spot) in BiomeArt.SHADED)
	_natural_layer(mesh, BiomeArt.solo(biome, "sombra"), shaded, biome, row, layers)
	var wet := _cover(around, cell, func(spot): return state.floor_id_at(spot) in BiomeArt.WET)
	_natural_layer(mesh, BiomeArt.solo(biome, "agua"), wet, biome, row, layers)
	if town: # as ruas da cidade são desenhadas pela planta
		var paved := _cover(around, cell, func(spot): return state.floor_id_at(spot) == TownState.TERRAIN_STONE)
		_natural_layer(mesh, BiomeArt.COBBLES, paved, biome, row, layers)
		return
	var links: Array = state.gen.path_links(cell)
	if links.is_empty():
		return
	if state.terrain_id_at(cell) == WorldGen.BRIDGE:
		for dir in links:
			_add_tile(BiomeArt.COMMON % ("ponte_%d" % dir), cell_origin(cell), row, layers * SIDE_HEIGHT)
		_add_tile(BiomeArt.COMMON % "ponte", cell_origin(cell), row, layers * SIDE_HEIGHT)
		return
	_natural_layer(mesh, BiomeArt.solo(biome, "trilha"), _path_cover(links, TRAIL_STRENGTH, 0.0), biome, row, layers)
	var roads: Array = state.gen.road_links(cell)
	if not roads.is_empty():
		_natural_layer(mesh, BiomeArt.solo(biome, "estrada"), _path_cover(roads, 1.0, ROAD_CORNER), biome, row, layers)


func _full_cover() -> PackedFloat32Array:
	var cover := PackedFloat32Array()
	cover.resize(13)
	cover.fill(1.0)
	return cover


## Cobertura nos 13 pontos: a média das casas que se encontram em cada ponto.
func _cover(around: Array, cell: Vector2i, member: Callable) -> PackedFloat32Array:
	var cover := PackedFloat32Array()
	cover.resize(13)
	var own := 1.0 if member.call(cell) else 0.0
	var sides := []
	for dir in 6:
		sides.append(1.0 if member.call(around[dir]) else 0.0)
	cover[0] = own
	for i in 6:
		# O canto i fica entre os lados i e i - 1; o meio i fica só no lado i.
		cover[1 + i] = (own + sides[i] + sides[(i + 5) % 6]) / 3.0
		cover[7 + i] = (own + sides[i]) / 2.0
	return cover


## Caminho: sai do centro para os meios dos lados por onde continua.
func _path_cover(links: Array, strength: float, corner: float) -> PackedFloat32Array:
	var cover := PackedFloat32Array()
	cover.resize(13)
	cover.fill(corner)
	cover[0] = strength
	for dir in links:
		cover[7 + dir] = strength
	return cover


func _natural_layer(mesh: Dictionary, path: String, cover: PackedFloat32Array, biome: String, row: int, layers: int) -> void:
	var seen := false
	for value in cover:
		if value > 0.2:
			seen = true
			break
	if not seen:
		return
	var tint: Color = cell_tint if world_light != null else Color.WHITE
	tint = BiomeArt.NIGHT_TINT.get(biome, tint) if world_light != null else tint
	var colors := PackedColorArray()
	colors.resize(13)
	for i in 13:
		colors[i] = Color(tint, cover[i])
	var height := layers * SIDE_HEIGHT
	var tile := Polygon2D.new()
	tile.texture = load(path)
	tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tile.polygon = mesh["vertices"]
	tile.uv = mesh["vertices"]
	tile.polygons = mesh["faces"]
	tile.vertex_colors = colors
	tile.material = battle_camera.soil_material(height * BOARD_SCALE)
	tile.position = Vector2(0, -height)
	tile.z_index = _z(row)
	board.add_child(tile)
	battle_camera.keep_drawn(tile)
	building.append(tile)


## Parede de um lado do hexágono, com o mesmo truque da faixa da frente dos tiles: a base fica
## mais abaixo na malha e o shader a converte em altura, de volta à mesma borda do chão.
func _wall_mesh(dir: int) -> Dictionary:
	if wall_meshes.has(dir):
		return wall_meshes[dir]
	var a: Vector2 = HEX_CORNERS[dir]
	var b: Vector2 = HEX_CORNERS[(dir + 1) % 6]
	# Nos lados verticais, 1 pixel para fora: o Godot não desenha malha sem área.
	var drop := Vector2(signf(a.x - HEX_MIDDLE.x) if a.x == b.x else 0.0, TILE_WALL)
	# A arte da parede é a faixa inclinada da frente do tile.
	var ua := Vector2(0, TILE_FRONT - TILE_SLOPE)
	var ub := Vector2(TILE_WIDTH / 2.0, TILE_FRONT)
	wall_meshes[dir] = {
		"vertices": PackedVector2Array([a, b, b + drop, a + drop]),
		"uv": PackedVector2Array([ua, ub, ub + Vector2(0, TILE_WALL), ua + Vector2(0, TILE_WALL)]),
		"faces": [PackedInt32Array([0, 1, 2, 3])] as Array[PackedInt32Array],
	}
	return wall_meshes[dir]


func _hidden_layers(cell: Vector2i, layers: int) -> int:
	var hidden := layers
	for dir in [1, 2]: # as duas vizinhas de baixo, as únicas na frente da parede
		var front: Vector2i = Hex.neighbor(cell, dir)
		hidden = mini(hidden, state.elevation_at(front) * level_layers if state.exists(front) else 0)
	return hidden


## Profundidade de desenho de uma linha. A conta é relativa porque o Godot limita o
## z_index, e numa caminhada longa o número da linha passaria desse limite.
func _z(row: int) -> int:
	return (row - z_origin) * 10


func _rebase_depth(row: int) -> void:
	if absi(row - z_origin) < Z_REBASE_ROWS:
		return
	var shift := (row - z_origin) * 10
	z_origin = row
	for child in board.get_children():
		if wall_groups.has(child):
			for strip in child.get_children():
				strip.z_index = clampi(strip.z_index - shift, -RenderingServer.CANVAS_ITEM_Z_MAX, RenderingServer.CANVAS_ITEM_Z_MAX)
		elif child.z_index < 800: # marcadores e efeitos ficam sempre por cima
			child.z_index = clampi(child.z_index - shift, -RenderingServer.CANVAS_ITEM_Z_MAX, RenderingServer.CANVAS_ITEM_Z_MAX)


# --- Mapa infinito -----------------------------------------------------------

func _camera_target(cell: Vector2i) -> Vector2:
	var feet := Vector2(_column_x(cell), cell.y * ROW_STEP) + FEET
	return BattleCamera.FOCUS - feet * BOARD_SCALE


## Desenha as casas que cabem na tela em volta de `center` e descarrega as distantes. Durante a
## caminhada isso é dividido entre vários quadros (`all_now` falso), para o movimento não engasgar.
func _sync_world(center: Vector2i, all_now := true) -> void:
	var wanted := {}
	var reach := VIEW_ROWS_BACK + 8
	var middle := _flat_point(center)
	for row in range(center.y - reach, center.y + reach + 1):
		for col in range(center.x - reach - 6, center.x + reach + 7):
			var cell := Vector2i(col, row)
			var spot := (_flat_point(cell) - middle).rotated(view_angle)
			var gap := roundi(spot.y / ROW_STEP)
			if gap >= -VIEW_ROWS_BACK and gap <= VIEW_ROWS_FRONT and absf(spot.x) / TILE_WIDTH <= _visible_columns(gap):
				wanted[cell] = true
	cells_to_build = wanted.keys().filter(func(cell): return not cell_nodes.has(cell))
	cells_to_build.sort_custom(func(a, b): return Hex.distance(a, center) > Hex.distance(b, center)) # o fim sai primeiro
	cells_to_unload = []
	for cell in cell_nodes:
		var spot := (_flat_point(cell) - middle).rotated(view_angle)
		var gap := roundi(spot.y / ROW_STEP)
		if gap < -VIEW_ROWS_BACK - UNLOAD_MARGIN or gap > VIEW_ROWS_FRONT + UNLOAD_MARGIN or absf(spot.x) / TILE_WIDTH > _visible_columns(gap) + UNLOAD_MARGIN:
			cells_to_unload.append(cell)
	if all_now:
		_work_on_map(-1)


func _flat_point(cell: Vector2i) -> Vector2:
	return Vector2(_column_x(cell), cell.y * ROW_STEP)


## Constrói e descarrega casas até o tempo acabar; `budget` negativo termina tudo.
func _work_on_map(budget: int) -> void:
	var begin := Time.get_ticks_usec()
	while not cells_to_build.is_empty() or not cells_to_unload.is_empty():
		if not cells_to_build.is_empty():
			var cell: Vector2i = cells_to_build.pop_back() # as mais próximas primeiro
			if not cell_nodes.has(cell):
				_build_cell(cell)
		elif cell_nodes.has(cells_to_unload[-1]):
			_unload_cell(cells_to_unload.pop_back())
		else:
			cells_to_unload.pop_back()
		if budget >= 0 and Time.get_ticks_usec() - begin > budget:
			return


## Quantas colunas para cada lado cabem na tela nessa linha: mais ao fundo, mais colunas.
func _visible_columns(row_gap: int) -> int:
	var depth := 1.0 / maxf(0.25, 1.0 - row_gap * ROW_STEP * BOARD_SCALE * BattleCamera.PERSPECTIVE)
	var on_screen: float = 760.0 / (depth * battle_camera.zoom) / (TILE_WIDTH * BOARD_SCALE)
	var row_distance := row_gap * ROW_STEP * BOARD_SCALE
	var in_fog := sqrt(maxf(0.0, FOG_END * FOG_END - row_distance * row_distance)) / FOG_SIDE_SQUEEZE / (TILE_WIDTH * BOARD_SCALE)
	return ceili(minf(on_screen, in_fog)) + 1


func _unload_cell(cell: Vector2i) -> void:
	if not cell_nodes.has(cell):
		return
	for node in cell_nodes[cell]:
		node.queue_free()
	cell_nodes.erase(cell)
	cell_rows.erase(cell)
	if world_light != null:
		world_light.forget_cell(cell)
	overlays.erase(cell)
	reach_lines.erase(cell)
	forests.erase(cell)
	trees.erase(cell)


## Marca de um local no chão natural: um círculo, porque não há casas à vista.
func _new_place_ring(color: Color) -> Line2D:
	var ring := _new_hex_line(color, 6)
	var points := PackedVector2Array()
	for i in 24:
		points.append(HEX_MIDDLE + Vector2.from_angle(TAU * i / 24.0) * RING_RADIUS)
	ring.points = points
	return ring


func _new_hex_line(color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.closed = true
	line.points = hex_poly
	line.material = battle_camera.ground_material
	board.add_child(line)
	return line


func _add_tile(path: String, pos: Vector2, row: int, height := 0.0) -> void:
	# Malha subdividida: a perspectiva acompanha a textura até nas bordas dos hexes.
	# Um Sprite2D teria só quatro vértices e abriria frestas entre casas vizinhas.
	var tile := Polygon2D.new()
	var texture: Texture2D = load(path)
	tile.texture = texture
	var mesh: Dictionary = _tile_mesh(texture)
	tile.polygon = mesh["vertices"]
	tile.uv = mesh["vertices"]
	tile.polygons = mesh["faces"]
	tile.material = battle_camera.tile_material(height * BOARD_SCALE, BOARD_SCALE)
	tile.position = pos
	tile.z_index = _z(row)
	tile.modulate = cell_tint
	board.add_child(tile)
	battle_camera.keep_drawn(tile)
	building.append(tile)


func _tile_mesh(texture: Texture2D) -> Dictionary:
	var key := [texture.get_size(), exploring]
	if tile_meshes.has(key):
		return tile_meshes[key]
	# As fileiras seguem as bordas do hexágono. Com a dobra entre o topo e a parede bem
	# em cima de um vértice, o shader não entorta a borda nem abre frestas nas junções.
	var vertices := PackedVector2Array()
	var faces: Array[PackedInt32Array] = []
	const COLUMNS := 6
	const TOP_ROWS := 8
	var rows := TOP_ROWS if exploring else TOP_ROWS + 1 # a jornada desenha as paredes à parte
	var width: float = texture.get_width()
	var slope := TILE_SLOPE / (TILE_WIDTH / 2.0)
	for x in COLUMNS + 1:
		var px := x * width / float(COLUMNS)
		var off_center := absf(px - TILE_WIDTH / 2.0)
		var back := off_center * slope
		var front := TILE_FRONT - off_center * slope
		for y in TOP_ROWS + 1:
			vertices.append(Vector2(px, lerpf(back, front, y / float(TOP_ROWS))))
		if not exploring:
			vertices.append(Vector2(px, minf(front + TILE_WALL, texture.get_height())))
	for x in COLUMNS:
		for y in rows:
			var i := x * (rows + 1) + y
			faces.append(PackedInt32Array([i, i + rows + 1, i + rows + 2, i + 1]))
	tile_meshes[key] = {"vertices": vertices, "faces": faces}
	return tile_meshes[key]


func _add_biome_props(biome: String, terrain_id: int, cell: Vector2i) -> void:
	var detail: float = state.detail_at(cell)
	var made := {}
	var art: Array
	if town:
		art = state.art_at(cell)
	elif expedition and cell == state.beacon_cell:
		art = [BiomeArt.beacon(biome, state.defeated_boss)]
	else:
		art = BiomeArt.props(biome, terrain_id, detail)
		if expedition and state.landmarks.has(cell):
			var entry: Dictionary = state.landmarks[cell]
			var special: Array = BiomeArt.landmark(biome, entry["kind"], entry["state"] == "done", detail)
			art = art if special.is_empty() else special
	for prop in art:
		made[prop["layer"]] = _biome_prop(prop, cell, detail)
		if prop["layer"] == "tree":
			trees[cell] = made["tree"]
		if world_light != null:
			world_light.add_prop(cell, made[prop["layer"]], BiomeArt.prop_tint(biome, prop["path"]))
			var light := BiomeArt.light_of(biome, prop["path"])
			if light != "":
				world_light.add_spot(cell, light)
	if made.has("back") and made.has("front"):
		forests[cell] = made


## Construção de todos os lados: uma folha com um quadro por ângulo, trocado conforme o giro.
func _model_prop(prop: Dictionary, cell: Vector2i) -> Sprite2D:
	if model_meta.is_empty():
		model_meta = JSON.parse_string(FileAccess.get_file_as_string(MODEL_META))
	var info: Dictionary = model_meta[prop["model"]]
	var sprite := Sprite2D.new()
	sprite.texture = load(prop["path"])
	sprite.centered = false
	sprite.hframes = int(info["columns"])
	sprite.vframes = int(info["views"]) / int(info["columns"])
	sprite.scale = Vector2.ONE * MODEL_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var foot := Vector2(info["foot_x"], info["foot_y"]) * MODEL_SCALE
	sprite.position = cell_origin(cell) + Vector2(93, prop["ground_y"]) - foot
	sprite.z_index = _z(_row(cell)) + prop["depth"]
	board.add_child(sprite)
	building.append(sprite)
	battle_camera.add_billboard(sprite, foot, _cell_elevation(cell))
	sprite.self_modulate = MODEL_NIGHT_LIFT
	models[sprite] = {"views": int(info["views"]), "turn": float(prop.get("turn", 0.0))}
	_set_model_frame(sprite)
	return sprite


func _set_model_frame(sprite: Sprite2D) -> void:
	var views_count: int = models[sprite]["views"]
	sprite.frame = posmod(roundi((view_angle + models[sprite]["turn"]) / TAU * views_count), views_count)


func _update_model_frames() -> void:
	for sprite in models.keys():
		if is_instance_valid(sprite):
			_set_model_frame(sprite)
		else:
			models.erase(sprite)


func _biome_prop(prop: Dictionary, cell: Vector2i, detail: float) -> Sprite2D:
	if prop.has("model"):
		return _model_prop(prop, cell)
	var sprite := Sprite2D.new()
	sprite.texture = load(prop["path"])
	sprite.centered = false
	# O ponto de apoio de cada arte é o centro da imagem.
	var foot: Vector2 = sprite.texture.get_size() / 2.0
	sprite.position = cell_origin(cell) + Vector2(93 + prop.get("offset_x", 0), prop["ground_y"]) - foot
	if natural and not town and not _is_marked_place(cell):
		sprite.position += Vector2(fmod(detail * 53.0, 1.0) - 0.5, fmod(detail * 71.0, 1.0) - 0.5) * PROP_WOBBLE * (1.0 if prop["layer"] != "front" else 0.6)
	sprite.flip_h = prop.get("flip", false) or (not prop.get("fixed", false) and fmod(detail * 13.0, 1.0) < 0.5)
	sprite.z_index = _z(_row(cell)) + prop["depth"]
	board.add_child(sprite)
	building.append(sprite)
	battle_camera.add_billboard(sprite, foot, _cell_elevation(cell))
	return sprite


## Farol e locais especiais ficam no centro da casa: é onde o jogador espera clicar.
func _is_marked_place(cell: Vector2i) -> bool:
	return expedition and (cell == state.beacon_cell or state.landmarks.has(cell))


func _add_scenery(id: int, cell: Vector2i) -> void:
	if id == 3:
		var back := _scenery_layer(id, cell, 3, FOREST_HEIGHT, 1)
		var front := _scenery_layer(id, cell, 6, FOREST_HEIGHT, 2)
		forests[cell] = {"back": back, "front": front}
	else:
		_scenery_layer(id, cell, 3)


func _scenery_layer(id: int, cell: Vector2i, depth: int, height := 1.0, slice := 0) -> Sprite2D:
	var prop := Sprite2D.new()
	prop.texture = load("res://assets/tiles/%d.png" % id)
	prop.centered = false
	prop.scale.y = height
	prop.position = cell_origin(cell) + Vector2(0, 160 * (1.0 - height))
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.z_index = _z(_row(cell)) + depth
	board.add_child(prop)
	building.append(prop)
	battle_camera.add_billboard(prop, Vector2(93, 160 * height), _cell_elevation(cell))
	prop.material.set_shader_parameter("scenery", true)
	prop.material.set_shader_parameter("scenery_base", load("res://assets/tiles/%d.png" % SCENERY_BASE[id]))
	prop.material.set_shader_parameter("scenery_slice", slice)
	return prop


func _add_unit_view(unit) -> void:
	var view := UnitView.new()
	board.add_child(view)
	view.setup(unit, Hud.PLAYER_COLOR if unit.team == Data.Team.PLAYER else Hud.ENEMY_COLOR, meta[unit.type_id])
	view.position = feet_of(unit.pos)
	view.z_index = _z(_row(unit.pos)) + 5
	views[unit] = view
	if expedition and state.is_boss(unit):
		view.scale *= BOSS_SCALE
		view.self_modulate = Color(0.75, 0.6, 1.0)
	battle_camera.add_billboard(view, Vector2.ZERO, _cell_elevation(unit.pos))


## Altura em unidades da tela lógica; a grade e os custos continuam iguais.
func _cell_elevation(cell: Vector2i) -> float:
	return state.elevation_at(cell) * level_layers * SIDE_HEIGHT * BOARD_SCALE


func _place_ground_marker(item: CanvasItem, cell: Vector2i) -> void:
	item.position = cell_origin(cell)
	item.material = battle_camera.surface_material(_cell_elevation(cell))
	battle_camera.keep_drawn(item)


func _height_at_point(point: Vector2) -> float:
	var nearest := INF
	var height := 0.0
	for cell in overlays:
		var distance: float = point.distance_squared_to(feet_of(cell))
		if distance < nearest:
			nearest = distance
			height = _cell_elevation(cell)
	return height


func _add_effect_billboard(item: CanvasItem, offset: Vector2) -> void:
	battle_camera.add_billboard(item, offset, _height_at_point(item.position + offset))


func _column_x(cell: Vector2i) -> int:
	return cell.x * TILE_WIDTH + (cell.y & 1) * TILE_WIDTH / 2


func cell_origin(cell: Vector2i) -> Vector2:
	var level: int = state.elevation_at(cell) * level_layers
	return Vector2(_column_x(cell), cell.y * ROW_STEP - level * SIDE_HEIGHT)


func feet_of(cell: Vector2i) -> Vector2:
	return cell_origin(cell) + FEET


## Centro da casa em coordenadas de tela (usado também pelo teste de jogo).
func cell_to_screen(cell: Vector2i) -> Vector2:
	return battle_camera.project(board.global_transform * (cell_origin(cell) + Vector2(93, 107)), _cell_elevation(cell))


func _cell_at(screen: Vector2) -> Vector2i:
	var found := NO_CELL
	var front_row := -999999
	for cell in overlays: # as linhas da frente cobrem as de trás
		var row := _row(cell)
		if row <= front_row or screen.distance_squared_to(cell_to_screen(cell)) > 67600.0:
			continue
		var projected := PackedVector2Array()
		for point in hex_poly:
			projected.append(battle_camera.project(board.global_transform * (cell_origin(cell) + point), _cell_elevation(cell)))
		if Geometry2D.is_point_in_polygon(screen, projected):
			found = cell
			front_row = row
	return found


## Com a câmera baixa, a cabeça pode estar sobre outra casa. Seleciona o
## personagem visível por seus pixels opacos, respeitando a ordem do desenho.
func _pick_cell(screen: Vector2) -> Vector2i:
	# Num mapa gerado, um degrau pode cobrir o centro da casa vizinha: o passo continua possível.
	if exploring and not busy:
		for cell in Hex.neighbors(_actor().pos):
			if overlays.has(cell) and state.can_step(_actor(), cell) and screen.distance_to(cell_to_screen(cell)) <= 14.0:
				return cell
	var ground_cell := _cell_at(screen)
	# Mantém o centro de cada hex acessível para movimento e mira no chão,
	# mesmo quando o corpo de alguém na fileira da frente passa por cima dele.
	if ground_cell != NO_CELL and screen.distance_to(cell_to_screen(ground_cell)) <= 14.0:
		return ground_cell
	var candidates: Array = views.values()
	candidates.sort_custom(func(a, b): return a.z_index > b.z_index)
	for view in candidates:
		if not view.visible or not view.unit.alive():
			continue
		var anchor: Vector2 = view.global_position
		var height: float = battle_camera.elevation_of(view)
		var original: Vector2 = anchor + (screen - battle_camera.project(anchor, height)) / battle_camera.depth_at(anchor, height)
		if view.sprite.is_pixel_opaque(view.sprite.to_local(original)):
			return view.unit.pos
	return ground_cell


# --- Laço de turnos ----------------------------------------------------------

func _advance() -> void:
	if online_session.playing and not online_session.relay.is_master:
		busy = true
		return
	busy = true
	_refresh_end_turn()
	pinned = null
	_close_menu()
	_refresh_overlays()
	while true:
		var result: int = state.winner()
		if result >= 0:
			online_session.publish([], true)
			sound_manager.play_sfx(&"victory" if result == Data.Team.PLAYER else &"defeat")
			_show_result(result)
			return
		if exploring:
			var changes: Array = state.tick()
			if not changes.is_empty():
				await _play(changes)
			_update_journey()
		var unit = state.active_unit()
		_place_ground_marker(active_outline, unit.pos)
		active_outline.visible = not _free_roam()
		active_outline.z_index = _z(_row(unit.pos)) + 3
		if exploring and state.in_combat():
			_focus_turn(unit)
		_refresh_turn_markers()
		hud.refresh(state)
		hud.set_hint("")
		if not unit.pending.is_empty():
			await _play(state.resolve_pending(unit))
			continue
		if unit.team == Data.Team.ENEMY:
			if not _is_quiet(unit) and unit.moved == 0:
				await get_tree().create_timer(0.2).timeout
			await _play(AI.apply(state, unit, AI.decide(state, unit)))
			continue
		break
	busy = false
	if exploring:
		_update_journey()
		_refresh_hover()
	hud.refresh(state)
	_refresh_turn_markers()
	_refresh_overlays()
	_update_hint()
	online_session.publish([], true)


func _perform(events: Array) -> void:
	busy = true
	_refresh_end_turn()
	_close_menu()
	hud.set_hint("")
	_refresh_overlays()
	await _play(events)
	_advance()


## Seta amarela em quem joga e vermelha no próximo inimigo; os números ficam prontos
## para quando forem pedidos.
func _refresh_turn_markers() -> void:
	var order: Array = state.turn_order()
	for unit in views:
		if not order.has(unit) or _free_roam():
			views[unit].hide_arrow()
	if _free_roam():
		if selected != null and views.has(selected):
			views[selected].show_arrow(ACTIVE_COLOR)
		return
	var next_enemy = null
	for unit in order.slice(1):
		if unit.team == Data.Team.ENEMY:
			next_enemy = unit
			break
	for i in order.size():
		var view = views[order[i]]
		view.set_order(i + 1, i == 0)
		if i == 0:
			view.show_arrow(ACTIVE_COLOR)
		elif order[i] == next_enemy:
			view.show_arrow(NEXT_ENEMY_ARROW)
		else:
			view.hide_arrow()


# Os números mudam a quase toda ação, então só aparecem quando pedidos: todos pelo
# botão de ordem, ou só o da unidade inspecionada.
func _refresh_order_badges() -> void:
	var shown = _shown_unit() if not busy else null
	for unit in views:
		views[unit].set_order_visible(show_order or unit == shown)


func _on_order_toggled(on: bool) -> void:
	show_order = on
	_refresh_order_badges()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Arrastar com o botão do meio gira a câmera, inclusive na vez dos inimigos.
	if exploring and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_set_view_angle(view_angle + event.relative.x * TURN_DRAG)
		return
	if event is InputEventMouseButton:
		_handle_button(event)
		return
	if busy:
		return
	if event is InputEventMouseMotion:
		# Toque vira mouse emulado; sem este filtro ele deixaria um "hover" preso.
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var cell := _pick_cell(event.position)
		if cell != hover:
			hover = cell
			if state.unit_at(cell) != null:
				pinned = null # passar o mouse por outro personagem troca o foco
			_refresh_overlays()
			_update_hint()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if menu_cell != NO_CELL or not _free_roam():
				_close_menu()
			else:
				_stop_selected()
		elif _free_roam() and event.keycode == KEY_TAB:
			_select_next()
		elif _free_roam() and event.keycode == KEY_G:
			hud.set_together(not together)
		elif event.keycode == KEY_SPACE:
			_end_turn()
		elif event.keycode >= KEY_1 and event.keycode < KEY_1 + menu_options.size():
			_on_option_pressed(event.keycode - KEY_1)


func _end_turn() -> void:
	if busy or _free_roam():
		return
	if online_session.playing:
		_submit_online("wait", NO_CELL)
	else:
		_perform(state.do_wait(state.active_unit()))


## O botão só aparece quando é a vez de alguém que este jogador controla.
func _refresh_end_turn() -> void:
	var unit = state.active_unit()
	hud.show_end_turn(not busy and state.winner() < 0 and not _free_roam() and unit != null and unit.team == Data.Team.PLAYER and online_session.can_control(unit))


# O toque vira clique ao soltar, para dar tempo de saber se a pessoa está segurando.
# Segurar num personagem (ou o botão direito) abre o cartão dele, até no turno inimigo.
func _handle_button(event: InputEventMouseButton) -> void:
	var cell := _pick_cell(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if state.unit_at(cell) != null:
			_show_card(state.unit_at(cell))
		elif not busy:
			_close_menu()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		press_token += 1
		if event.pressed:
			pressing = true
			press_cell = cell
			if state.unit_at(cell) != null:
				var token := press_token
				get_tree().create_timer(HOLD_TIME).timeout.connect(func(): _on_hold(token))
		elif pressing:
			pressing = false
			if not busy:
				_click(press_cell)


func _on_hold(token: int) -> void:
	if token != press_token or not pressing:
		return
	pressing = false # o soltar depois do cartão não vale como toque
	var unit = state.unit_at(press_cell)
	if unit != null:
		_show_card(unit)


func _show_card(unit) -> void:
	var order: int = state.turn_order().find(unit) + 1
	var info := {
		"title": unit.display_name,
		"team": unit.team,
		"type_id": unit.type_id,
		"hp": unit.hp,
		"max_hp": unit.max_hp,
		"order": order,
		"atk": unit.atk,
		"def": unit.def,
		"speed": unit.speed,
		"abilities": unit.abilities.map(func(id): return _card_ability(unit, id)),
	}
	if not unit.pending.is_empty():
		var ability: Dictionary = unit.ability(unit.pending["ability"])
		var radius: int = ability["radius"]
		info["spell"] = {
			"name": ability["name"],
			"radius": radius,
			"cells": 1 + 3 * radius * (radius + 1),
			"power": roundi(unit.atk * ability["power"]),
			"actions": state.actions_until(unit),
			"secret": unit.team != Data.Team.PLAYER,
		}
	hud.show_card(info)


const ABILITY_ICONS := {
	"golpe": "sword", "rapido": "sword", "golpe_pesado": "sword", "estocada": "sword", "adaga": "sword", "coronhada": "sword",
	"tiro": "arrow", "tiro_longo": "arrow", "perfurante": "arrow", "tiro_rapido": "arrow", "saraivada": "arrow", "chuva_virotes": "arrow",
	"cura": "heart", "clareira": "heart", "agua_vital": "heart",
	"guarda": "shield", "escudo_fogo": "shield", "provocar": "shield", "aparar": "shield", "casca": "shield", "manto_agua": "shield",
} # o resto das magias usa o ícone do elemento


# Magias sem ícone próprio usam o do elemento: a pasta do efeito (fogo/, agua/).
func _spell_icon(id: String) -> String:
	if not SPELL_FX.has(id):
		return "star"
	return "drop" if SPELL_FX[id]["impact"].begins_with("agua/") else "flame"


## Dados de uma habilidade para a ficha: alcance, efeito, tempo e quanto tiraria do herói da vez.
func _card_ability(unit, id: String) -> Dictionary:
	var ability: Dictionary = unit.ability(id)
	var out := {"name": ability["name"], "icon": ABILITY_ICONS.get(id, _spell_icon(id)), "time": state.time_for(ability["time"], unit)}
	if ability["kind"] == "charge":
		out["time"] = "%d + %d" % [state.cast_time_for(unit, id), state.recovery_time_for(unit, id)]
		out["time_hint"] = "Conjuração + recuperação após o impacto"
	if ability["kind"] == "guard":
		out["range"] = ""
	elif ability["min_range"] > 1:
		out["range"] = "%d-%d" % [ability["min_range"], ability["range"]]
	else:
		out["range"] = str(ability["range"])
	match ability["kind"]:
		"heal":
			out["amount"] = "+%d" % ability["heal"]
			out["amount_icon"] = "heart"
		"guard":
			out["amount"] = "½ dano" if not unit.passives.has("guard_mult") else "%d%% dano" % roundi(unit.passives["guard_mult"] * 100)
			out["amount_icon"] = "shield"
		_:
			out["amount"] = str(roundi(unit.atk * ability["power"]))
			out["amount_icon"] = "star"
	var hero = _actor()
	if ability["kind"] == "attack" and hero.team == Data.Team.PLAYER and unit.team != Data.Team.PLAYER:
		out["hero_type"] = hero.type_id
		out["hero_amount"] = state.preview_attack(unit, id, hero)["amount"]
	return out


# Mesmas regras para mouse e toque: casa vizinha livre anda na hora; qualquer outra
# casa abre o menu com o que dá para fazer nela. Nada acontece sem tocar numa opção.
func _click(cell: Vector2i) -> void:
	if pinned != null:
		pinned = null
		_refresh_overlays()
		_update_hint()
	if menu_cell != NO_CELL:
		var other_unit: bool = cell != menu_cell and cell != NO_CELL and state.unit_at(cell) != null
		_close_menu() # tocar fora só fecha, para não andar sem querer
		if not other_unit:
			return
	if cell == NO_CELL:
		return
	if _free_roam():
		var occupant = state.unit_at(cell)
		if occupant == null:
			_travel(cell)
		elif state.is_hero(occupant) and online_session.can_control(occupant) and occupant != selected:
			_select(occupant)
		else:
			_open_menu(cell)
		return
	var unit = _actor()
	# Se alguma ação mira essa casa, o menu pergunta: assim dá para mirar no chão
	# onde o inimigo ainda vai pisar sem o herói sair andando.
	var aimable := _cell_options(cell).any(func(option): return option["kind"] == "ability")
	# Casa do alcance anda na hora, pelo caminho inteiro.
	if _can_walk_to(unit, cell) and not aimable:
		if online_session.playing:
			_submit_online("step", cell)
		else:
			_perform(state.do_move(unit, cell))
		return
	_open_menu(cell)


func _can_walk_to(unit, cell: Vector2i) -> bool:
	return state.unit_at(cell) == null and state.move_cells(unit).has(cell)


## O que muda para o herói se ele for para essa casa, em frases curtas.
func _terrain_notes(unit, cell: Vector2i) -> Array:
	var notes := []
	var tile: Dictionary = state.tile_at(cell)
	if tile["damage"] < 1.0:
		notes.append("Aqui você leva %d%% menos dano" % roundi((1.0 - tile["damage"]) * 100))
	var climb: int = state.elevation_at(cell) - state.elevation_at(unit.pos)
	var percent := roundi(Data.HEIGHT_MULT_PER_LEVEL * 100)
	if climb > 0:
		notes.append("Mais alto: +%d%% de dano em quem está abaixo" % (percent * climb))
	elif climb < 0:
		notes.append("Mais baixo: −%d%% de dano em quem está acima" % (percent * -climb))
	return notes


func _open_menu(cell: Vector2i) -> void:
	var occupant = state.unit_at(cell)
	var options := _cell_options(cell)
	if options.is_empty() and occupant == null:
		return
	menu_cell = cell
	menu_options = options
	# Sem ações, um menu só cobriria o alcance que a pessoa quer ver: a informação vai na dica.
	if not options.is_empty():
		var title: String = occupant.display_name if occupant != null else state.tile_name_at(cell)
		var info: String = _menu_info(occupant) if occupant != null else "\n".join(_terrain_notes(_actor(), cell))
		hud.show_menu(cell_to_screen(cell), title, occupant.team if occupant != null else -1, info, options)
	# A fila mostra onde a magia seria solta, antes de confirmar.
	var spell := _menu_spell()
	if spell != "":
		var unit = _actor()
		hud.preview_cast(state, unit, state.cast_time_for(unit, spell))
	_refresh_overlays()
	_update_hint()


func _close_menu() -> void:
	if menu_cell == NO_CELL:
		return
	menu_cell = NO_CELL
	menu_options = []
	hud.hide_menu()
	hud.preview_cast(state, null, 0)
	_refresh_overlays()
	_update_hint()


func _cell_options(cell: Vector2i) -> Array:
	var unit = _actor()
	var options := []
	for id in unit.abilities:
		if state.valid_targets(unit, id).has(cell):
			var option := _ability_option(unit, id, cell)
			option["kind"] = "ability"
			option["id"] = id
			option["label"] = Data.ABILITIES[id]["name"]
			options.append(option)
	if state.unit_at(cell) != null:
		options.append_array(_blocked_options(unit, state.unit_at(cell)))
		if not _free_roam() and state.unit_at(cell).team != unit.team and options.all(func(option): return option["kind"] == "blocked"):
			var spot: Vector2i = state.approach_cell(unit, state.unit_at(cell))
			if spot != state.NO_MOVE:
				options.push_front({"kind": "approach", "cell": spot, "label": "Aproximar", "detail": "fica ao alcance"})
	if _free_roam():
		if cell != unit.pos:
			options.append({"kind": "travel", "label": "Ir até lá", "detail": "para ao ser visto"})
		options.append({"kind": "cancel", "label": "Cancelar", "detail": ""})
	elif cell == unit.pos:
		options.append({"kind": "wait", "label": "Encerrar turno", "detail": "passa a vez"})
	elif state.unit_at(cell) == null:
		if _can_walk_to(unit, cell):
			options.append({"kind": "step", "label": "Andar", "detail": "até aqui"})
		if not options.is_empty():
			options.append({"kind": "cancel", "label": "Cancelar", "detail": ""})
	return options


func _ability_option(unit, id: String, cell: Vector2i) -> Dictionary:
	var ability: Dictionary = unit.ability(id)
	var target = state.unit_at(cell)
	match ability["kind"]:
		"attack":
			return {"detail": _preview_text(unit, id, target), "tone": "damage"}
		"heal":
			var detail := "+%d" % mini(ability["heal"], target.max_hp - target.hp)
			return {"detail": detail + " e vizinhos" if ability.has("radius") else detail, "tone": "heal"}
		"guard":
			return {"detail": "atrai inimigos" if ability.has("taunt") else "reduz o dano"}
		_:
			return {"detail": _area_text(unit, state.area_of(cell, ability["radius"])), "note": _cast_wait_text(state.cast_wait(unit, id))}


## Magia carregada não sai na hora: diz quantas ações dos outros passam antes
## e quanto isso dá em rodadas (todo mundo agindo uma vez).
func _cast_wait_text(actions: int) -> String:
	if actions == 0:
		return "solta já na sua próxima vez"
	var others: int = state.turn_order().size() - 1
	var rounds := ceili(float(actions) / maxi(1, others))
	return "solta após %d aç%s (~%d rodada%s)" % [actions, "ão" if actions == 1 else "ões", rounds, "" if rounds == 1 else "s"]


# A magia acerta todo mundo na área, então o menu avisa quantos aliados vão junto.
func _area_text(unit, cells: Array) -> String:
	var enemies := 0
	var allies := 0
	for cell in cells:
		var occupant = state.unit_at(cell)
		if occupant != null:
			if occupant.team == unit.team:
				allies += 1
			else:
				enemies += 1
	var text := "%d inimigo%s" % [enemies, "" if enemies == 1 else "s"]
	if allies > 0:
		text += ", %d aliado%s" % [allies, "" if allies == 1 else "s"]
	return text


func _menu_info(occupant) -> String:
	if occupant == null:
		return ""
	if not state.takes_turns(occupant):
		return "Vida %d/%d, ainda não viu você" % [occupant.hp, occupant.max_hp]
	return "Vida %d/%d, age em %dº" % [occupant.hp, occupant.max_hp, state.turn_order().find(occupant) + 1]


func _on_option_pressed(index: int) -> void:
	if busy or index < 0 or index >= menu_options.size():
		return
	var option: Dictionary = menu_options[index]
	if option.get("disabled", false):
		return
	var cell := menu_cell
	var unit = _actor()
	if option["kind"] == "approach":
		cell = option["cell"]
		option = {"kind": "step"}
	if online_session.playing and option["kind"] != "cancel" and option["kind"] != "travel":
		_submit_online(option["kind"], cell, option.get("id", ""))
		return
	match option["kind"]:
		"ability":
			_perform(state.do_ability(unit, option["id"], cell))
		"wait":
			_perform(state.do_wait(unit))
		"step":
			_perform(state.do_move(unit, cell))
		"travel":
			_travel(cell)
		"cancel":
			_close_menu()


# --- Destaques e dica --------------------------------------------------------

func _refresh_overlays() -> void:
	for cell in trees:
		trees[cell].modulate.a = TREE_SEE_THROUGH if _covers_a_unit(cell) else 1.0
	for cell in forests:
		# A frente ainda encobre as pernas, mas deixa uma pista do ocupante.
		var occupant = state.unit_at(cell)
		var clear := _covers_a_unit(cell)
		forests[cell].back.modulate.a = TREE_SEE_THROUGH if clear else 1.0
		forests[cell].front.modulate.a = TREE_SEE_THROUGH if clear else (0.82 if occupant != null and occupant.alive() else 1.0)
	_refresh_order_badges()
	for cell in overlays:
		overlays[cell].visible = false
		reach_lines[cell].visible = false
	inspect_outline.visible = false
	if not busy:
		_mark_free_look()
	# Só a mira dos heróis aparece: ver onde a magia inimiga cai tornaria o mago dela inútil.
	# A IA também não olha a mira dos heróis, então os dois lados jogam no escuro.
	for unit in state.units:
		if unit.alive() and unit.team == Data.Team.PLAYER and not unit.pending.is_empty():
			var ability: Dictionary = unit.ability(unit.pending["ability"])
			for cell in state.area_of(unit.pending["tile"], ability["radius"]):
				_mark(cell, CHARGE_COLOR)
	_sync_focus()


func _mark_free_look() -> void:
	var unit = _actor()
	var shown = _shown_unit()
	var focus: Vector2i = menu_cell if menu_cell != NO_CELL else (shown.pos if shown != null else NO_CELL)
	if focus != NO_CELL:
		_place_ground_marker(inspect_outline, focus)
		inspect_outline.z_index = _z(_row(focus)) + 4
		inspect_outline.visible = true
	var spell := _menu_spell()
	if spell != "":
		for cell in state.area_of(menu_cell, unit.ability(spell)["radius"]):
			_mark(cell, AREA_COLOR)
		return
	if _free_roam():
		if shown != null and shown != unit:
			for cell in state.sight_cells(shown):
				_mark(cell, SIGHT_COLOR)
		elif hover != NO_CELL:
			for cell in _roam_path(hover):
				_mark(cell, STEP_COLOR)
		return
	if exploring and shown != null and not state.takes_turns(shown):
		for cell in state.sight_cells(shown):
			_mark(cell, SIGHT_COLOR)
		return
	if shown != null and shown != unit:
		_mark_reach(shown)
		return
	var reach: Dictionary = state.move_cells(unit)
	for cell in reach:
		_mark(cell, STEP_COLOR)
	if reach.has(hover):
		for cell in state.straight_path(state.search(unit, state.move_left(unit)), unit.pos, hover):
			_mark(cell, PATH_COLOR)
	_mark_aim(unit)


## Magia carregada que o menu aberto oferece; a área dela fica pintada.
func _menu_spell() -> String:
	for option in menu_options:
		if option["kind"] == "ability" and _actor().ability(option["id"])["kind"] == "charge":
			return option["id"]
	return ""


## Quem está sendo inspecionado: o do menu aberto ou, no mouse, o que está sob o cursor.
func _shown_unit():
	if menu_cell != NO_CELL:
		return state.unit_at(menu_cell)
	if pinned != null:
		return pinned
	return state.unit_at(hover) if hover != NO_CELL else null


func _mark_reach(unit) -> void:
	for cell in state.attack_reach(unit):
		_mark_reach_cell(cell)
		var occupant = state.unit_at(cell)
		if occupant != null and occupant.team != unit.team:
			_mark(cell, TARGET_COLOR)


## Para o herói da vez, o laranja é onde ele consegue mirar: no arqueiro e no mago a
## casa colada fica sem cor, e dá para ver na hora que ali ele não acerta.
func _mark_aim(unit) -> void:
	for id in unit.abilities:
		var kind: String = unit.ability(id)["kind"]
		if kind != "attack" and kind != "charge":
			continue
		for cell in state.cells_in_range(unit, id):
			_mark_reach_cell(cell)
			var occupant = state.unit_at(cell)
			if occupant != null and occupant.team != unit.team:
				_mark(cell, TARGET_COLOR)


func _mark_reach_cell(cell: Vector2i) -> void:
	if not reach_lines.has(cell):
		return
	reach_lines[cell].visible = true
	if not overlays[cell].visible:
		_mark(cell, REACH_FILL)


## As árvores são altas: as das duas fileiras da frente podem esconder quem está atrás.
func _covers_a_unit(cell: Vector2i) -> bool:
	if not exploring:
		return false
	for unit in state.units:
		if unit.alive() and _row(cell) > _row(unit.pos) and Hex.distance(cell, unit.pos) <= 2:
			return true
	return false


func _mark(cell: Vector2i, color: Color) -> void:
	if overlays.has(cell):
		overlays[cell].color = color
		overlays[cell].visible = true


func _preview_text(unit, id: String, target) -> String:
	var result: Dictionary = state.preview_attack(unit, id, target)
	return "−%d flanco" % result["amount"] if result["flank"] else "−%d" % result["amount"]


func _update_hint() -> void:
	_refresh_end_turn()
	if busy:
		return
	var unit = _actor()
	if online_session.playing and not _free_roam():
		var owner: int = online_session.owner_of(unit)
		hud.set_hint("Vez de %s · %s%s" % [unit.display_name, online_session.players.get(owner, "Dono"), " · você joga" if online_session.can_control(unit) else " · aguardando"])
		return
	if hud.menu_open():
		hud.set_hint("")
		return
	var shown = _shown_unit()
	if _free_roam() and (shown == null or shown == unit):
		hud.set_hint(ROAM_HINT)
		return
	if shown != null:
		var text := "%s: %s" % [shown.display_name, _menu_info(shown).to_lower()]
		if not shown.pending.is_empty():
			text += ". Preparando magia: segure para ver"
		if menu_cell != NO_CELL and shown.team != unit.team:
			text += ". Fora do seu alcance, toque de novo para fechar."
		hud.set_hint(text)
	elif hover != NO_CELL and _can_walk_to(unit, hover):
		var notes := _terrain_notes(unit, hover)
		hud.set_hint("%s%s" % [state.tile_name_at(hover), ": " + ". ".join(notes) if not notes.is_empty() else ""])
	elif _free_roam():
		hud.set_hint(DEFAULT_HINT)
	else:
		hud.set_hint(_turn_hint(unit))


## Quanto resta do turno, em palavras.
func _turn_hint(unit) -> String:
	var steps: int = state.steps_left(unit)
	var walk: String = "%d %s" % [steps, "casa" if steps == 1 else "casas"] if steps > 0 else "sem passos"
	return "%s · Atacar encerra o turno · %s" % [walk, END_TURN_KEY_HINT]


# --- Animação dos eventos ----------------------------------------------------

## `roam`: exploração. Os passos não esperam a animação, porque cada herói anda no seu ritmo.
func _play(events: Array, roam := false) -> void:
	online_session.publish(events, roam, roam)
	for event in events:
		match event["type"]:
			"move":
				if roam:
					_play_move(event)
				else:
					await _play_move(event)
			"deploy":
				event["silent"] = true
				event["duration"] = DEPLOY_TIME
				_play_move(event) # todos abrem ao mesmo tempo, junto com o aviso de combate
			"attack":
				await _play_attack(event)
			"damage":
				await _play_damage(event)
			"heal":
				await _play_heal(event)
			"death":
				await _play_death(event)
			"guard":
				var id: String = event.get("ability", "")
				if SPELL_FX.has(id):
					await _play_spell_fx(id, Vector2.ZERO, [views[event["unit"]].position])
				else:
					sound_manager.play_sfx(&"guard")
				views[event["unit"]].set_status("em guarda")
			"cast_start":
				await _play_cast_start(event)
			"cast_resolve":
				await _play_cast_resolve(event)
			"spawn":
				_play_spawn(event)
			"wander":
				event["silent"] = true
				event["duration"] = WALK_STEP * 1.6
				_play_move(event) # sem esperar: o mundo anda junto com o herói
			"combat_start":
				await _play_combat_start(event)
			"combat_join":
				_mark_alerted(event["units"])
			"combat_end":
				await _play_combat_end(event)
			"despawn":
				_remove_view(event["unit"])
			"regen":
				_play_regen(event)
			"revive":
				_play_revive(event)
			"landmark":
				await _play_landmark(event)
			"level_up":
				_play_level_up(event)
	for unit in views:
		if unit.alive():
			_show_status(unit)


func _submit_online(kind: String, cell: Vector2i, ability := "", hero = null, followers := []) -> void:
	var actor = hero if hero != null else _actor()
	if not online_session.can_control(actor): return
	if not _free_roam():
		if busy: return
		_close_menu()
	elif busy and kind != "travel" and kind != "stop": return
	else:
		_close_menu()
	online_session.submit({kind = kind, cell = cell, ability = ability, hero = actor.uid, followers = followers.map(func(u): return u.uid)})


func _network_command(sender: int, command: Dictionary) -> void:
	if not online_session.playing or not online_session.relay.is_master or state.winner() >= 0: return
	var cell: Variant = command.get("cell", NO_CELL)
	if not cell is Vector2i: return
	var kind := str(command.get("kind", ""))
	if _free_roam():
		var hero = state.unit_by_uid(int(command.get("hero", 0))) if command.get("hero") is int else null
		if hero == null or not state.is_hero(hero) or not hero.alive() or online_session.owner_of(hero) != sender: return
		match kind:
			"travel":
				var followers := []
				if command.get("followers") is Array:
					for uid in command["followers"]:
						var member = state.unit_by_uid(int(uid)) if uid is int else null
						if member != null and member != hero and state.is_hero(member) and member.alive() and online_session.owner_of(member) == sender and not member in followers:
							followers.append(member)
				_start_file(hero, followers, cell)
			"stop": _end_chain(hero)
			"ability":
				var id: String = str(command.get("ability", ""))
				if not busy and id in hero.abilities and cell in state.valid_targets(hero, id):
					_perform(state.do_ability(hero, id, cell))
		return
	if busy or command.get("revision", -1) != online_session.revision: return
	var unit = state.active_unit()
	if online_session.owner_of(unit) != sender or not unit.pending.is_empty(): return
	match kind:
		"wait": _perform(state.do_wait(unit))
		"step":
			if state.unit_at(cell) == null and state.move_cells(unit).has(cell): _perform(state.do_move(unit, cell))
		"ability":
			var id: String = str(command.get("ability", ""))
			if id in unit.abilities and cell in state.valid_targets(unit, id):
				_perform(state.do_ability(unit, id, cell))


func _network_packet(_packet: Dictionary) -> void:
	if remote_playing or not online_session.playing or online_session.relay.is_master: return
	remote_playing = true
	while not online_session.packets.is_empty():
		var packet: Dictionary = online_session.packets.pop_front()
		if int(packet.revision) <= online_session.revision: continue
		online_session.revision = int(packet.revision)
		var roam: bool = packet.get("roam", false)
		if not roam:
			busy = true
			_close_menu()
		online_session.apply_snapshot(packet.snapshot)
		var events: Array = packet.events
		for event in events:
			for key in ["unit", "target"]:
				if event.has(key): event[key] = state.unit_by_uid(int(event[key]))
			if event.has("units"):
				event["units"] = event["units"].map(func(uid): return state.unit_by_uid(int(uid)))
		await _play(events, roam)
		_match_views()
		for unit in views:
			if not moving.has(unit):
				views[unit].position = feet_of(unit.pos)
				views[unit].z_index = _z(_row(unit.pos)) + 5
				battle_camera.set_elevation(_cell_elevation(unit.pos), views[unit])
			views[unit].set_hp(unit.hp)
			views[unit].visible = unit.alive()
			if unit.alive():
				views[unit].rotation = 0.0
				views[unit].modulate.a = 1.0
		busy = not bool(packet.ready)
		hud.refresh(state)
		if state.winner() < 0:
			_place_ground_marker(active_outline, state.active_unit().pos)
			active_outline.visible = not _free_roam()
			if state.in_combat():
				_focus_turn(state.active_unit())
			elif camera_unit != selected:
				_select(_actor())
			_update_journey()
		_refresh_turn_markers()
		_refresh_overlays()
		_update_hint()
		if state.winner() >= 0:
			busy = true
			_show_result(state.winner())
	remote_playing = false


func _room_status() -> void:
	if room_label == null: return
	room_label.text = "SALA DE %s · %d/4  " % [online_session.players.get(online_session.original_host, "Jogador"), online_session.players.size()]
	_update_hint()


func _leave_online() -> void:
	online_session.leave()
	get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")


func _network_lost(_reason: String) -> void:
	get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")


## Texto embaixo da unidade. Quem carrega magia mostra a contagem regressiva
## de ações até ela sair, a mesma do menu e da fila.
func _show_status(unit) -> void:
	if not unit.pending.is_empty():
		views[unit].set_status("magia em %d" % state.actions_until(unit), CAST_INK)
	else:
		views[unit].set_status("em guarda" if unit.guarding else "")


# --- Exploração --------------------------------------------------------------

## Fora de combate: o herói anda livre, sem fila de turnos.
func _free_roam() -> bool:
	return exploring and not state.in_combat()


## O herói que recebe as ordens agora: o selecionado fora de combate, o da vez em combate.
func _actor():
	if not _free_roam():
		return state.active_unit()
	if selected == null or not selected.alive():
		selected = _first_mine()
	return selected


func _first_mine():
	var living: Array = state.alive_party()
	for member in living:
		if online_session.can_control(member):
			return member
	return living[0] if not living.is_empty() else state.hero


func _select(unit) -> void:
	selected = unit
	roam_from = NO_CELL
	_follow(unit)
	_refresh_turn_markers()
	_refresh_overlays()
	_update_hint()
	_update_journey()


func _select_next() -> void:
	var mine: Array = state.alive_party().filter(func(u): return online_session.can_control(u))
	if mine.size() > 1:
		_select(mine[(mine.find(selected) + 1) % mine.size()])


func _on_party_pick(unit) -> void:
	if _free_roam() and unit.alive() and online_session.can_control(unit):
		sound_manager.play_ui(&"switch3")
		_select(unit)
	else:
		_on_timeline_pick(unit)


# --- Câmera --------------------------------------------------------------------

func _process(delta: float) -> void:
	if not exploring or board == null:
		return
	_update_turn(delta)
	_update_walks(delta)
	if town and selected != null:
		town_panels.set_nearby(state.person_near(selected.pos))
	var goal: Vector2 = camera_look if camera_look != null else BattleCamera.FOCUS - _camera_point() * BOARD_SCALE
	board.position = board.position.lerp(goal, 1.0 - exp(-delta * CAMERA_SPEED))
	_work_on_map(BUILD_BUDGET_USEC)
	_roam_tick(delta)
	if overlays_dirty:
		overlays_dirty = false
		_refresh_overlays()


## O ponto que a câmera segue: a posição contínua de quem está andando, sem contar a altura.
func _camera_point() -> Vector2:
	if walks.has(camera_unit):
		return walks[camera_unit].ground
	return _ground(camera_cell)


func _ground(cell: Vector2i) -> Vector2:
	return Vector2(_column_x(cell), cell.y * ROW_STEP) + FEET


func _level_height(cell: Vector2i) -> float:
	return state.elevation_at(cell) * level_layers * SIDE_HEIGHT


# --- Movimento contínuo --------------------------------------------------------
# As regras movem de casa em casa; a tela não. Cada unidade percorre as casas numa linha só,
# sem parar entre elas, e o desenho persegue essa linha: as curvas ficam redondas e os
# degraus viram rampas. Passos que chegam adiantados (fila, rede) só apressam um pouco.

func _begin_walk(unit, from: Vector2i, to: Vector2i, duration: float) -> void:
	var view = views[unit]
	if not walks.has(unit):
		walks[unit] = {
			"from": from, "to": to, "progress": 0.0, "duration": duration, "queue": [],
			"ground": view.position + Vector2(0, _level_height(from)), "level": _level_height(from),
			"heading": Vector2.ZERO, "face_wait": 0.0,
		}
		moving[unit] = true
		view.set_walking(true)
		view.set_jump_height(0.0)
		view.face_toward((_ground(to) - _ground(from)).rotated(view_angle))
	else:
		walks[unit]["queue"].append({"to": to, "duration": duration})


func _update_walks(frame_time: float) -> void:
	var delta := minf(frame_time, MAX_WALK_FRAME) # um quadro lento não vira um salto na tela
	for unit in walks.keys():
		var view = views.get(unit)
		var walk: Dictionary = walks[unit]
		if view == null or not is_instance_valid(view):
			walks.erase(unit)
			moving.erase(unit)
			continue
		var queue: Array = walk["queue"]
		walk["progress"] += delta * (1.0 + queue.size() * 0.5) / walk["duration"]
		while walk["progress"] >= 1.0 and not queue.is_empty():
			var next: Dictionary = queue.pop_front()
			walk["progress"] -= 1.0
			walk["from"] = walk["to"]
			walk["to"] = next["to"]
			walk["duration"] = next["duration"]
		# Esperando o próximo passo, o avanço não acumula: senão ele pularia casas ao chegar.
		walk["progress"] = minf(walk["progress"], 1.0)
		var progress: float = walk["progress"]
		var goal: Vector2 = _ground(walk["from"]).lerp(_ground(walk["to"]), progress)
		var goal_level: float = lerpf(_level_height(walk["from"]), _level_height(walk["to"]), progress)
		var blend := 1.0 - exp(-delta * WALK_SMOOTH)
		var previous: Vector2 = walk["ground"]
		walk["ground"] = previous.lerp(goal, blend)
		walk["level"] = lerpf(walk["level"], goal_level, blend)
		view.position = walk["ground"] - Vector2(0, walk["level"])
		battle_camera.set_elevation(walk["level"] * BOARD_SCALE, view)
		view.z_index = _z(maxi(_row(walk["from"]), _row(walk["to"]))) + 5
		_steer(view, walk, walk["ground"] - previous, delta)
		if progress >= 1.0 and queue.is_empty() and walk["ground"].distance_to(goal) < WALK_SETTLE:
			_finish_walk(unit)


## Olha para a direção geral da caminhada: o zigue-zague das casas não faz o herói virar.
func _steer(view, walk: Dictionary, moved: Vector2, delta: float) -> void:
	walk["heading"] = walk["heading"].lerp(moved, 1.0 - exp(-delta * FACE_FOLLOW))
	walk["face_wait"] -= delta
	if walk["face_wait"] > 0.0 or walk["heading"].length() < 0.01:
		return
	var seen: Vector2 = walk["heading"].rotated(view_angle)
	var was: Array = [view.sprite.flip_h, view.facing]
	var vertical: bool = absf(seen.y) > absf(seen.x) * (FACE_KEEP if view.facing != view.Facing.SIDE else FACE_TURN)
	var sideways: bool = absf(seen.x) > absf(seen.y) * FACE_SIDE_FLIP
	if vertical:
		view.facing = view.Facing.SOUTH if seen.y > 0 else view.Facing.NORTH
	else:
		view.facing = view.Facing.SIDE
	if sideways or not vertical:
		view.face_right(seen.x > 0)
	if [view.sprite.flip_h, view.facing] != was:
		walk["face_wait"] = FACE_HOLD


func _finish_walk(unit) -> void:
	walks.erase(unit)
	moving.erase(unit)
	var view = views[unit]
	view.set_walking(false)
	view.position = feet_of(unit.pos)
	view.z_index = _z(_row(unit.pos)) + 5
	battle_camera.set_elevation(_cell_elevation(unit.pos), view)
	overlays_dirty = true


func _follow(unit) -> void:
	camera_unit = unit
	_set_camera(unit.pos)


func _set_camera(cell: Vector2i) -> void:
	camera_cell = cell
	_sync_world(cell, false)
	_rebase_depth(_row(cell))


## Em combate a câmera vai até cada herói da vez, e até o inimigo que estiver fora de vista.
func _focus_turn(unit) -> void:
	if state.is_hero(unit) or Hex.distance(unit.pos, camera_cell) > 6:
		_follow(unit)


## Gira enquanto Q/E ou o botão da tela estão apertados: acelera e freia suave, e para onde soltar.
func _update_turn(delta: float) -> void:
	var direction := turn_hold
	if Input.is_key_pressed(KEY_Q):
		direction -= 1
	if Input.is_key_pressed(KEY_E):
		direction += 1
	turn_speed = lerpf(turn_speed, clampi(direction, -1, 1) * TURN_SPEED, 1.0 - exp(-delta * TURN_EASE))
	if direction == 0 and absf(turn_speed) < 0.01:
		turn_speed = 0.0
	if turn_speed != 0.0:
		_set_view_angle(view_angle + turn_speed * delta)
	map_refresh -= delta


func _set_view_angle(angle: float) -> void:
	view_angle = fposmod(angle, TAU)
	battle_camera.set_view_angle(view_angle)
	_show_facing_walls()
	_refresh_depths()
	_update_model_frames()
	if map_refresh <= 0.0:
		map_refresh = MAP_REFRESH
		_sync_world(camera_cell, false)


func _show_facing_walls() -> void:
	for dir in wall_groups.size():
		var outward: Vector2 = HEX_CORNERS[dir] + HEX_CORNERS[(dir + 1) % 6] - HEX_MIDDLE * 2.0
		# Folga: com a perspectiva, paredes quase de lado ainda aparecem nas pontas da tela.
		wall_groups[dir].visible = outward.rotated(view_angle).y > -outward.length() * WALL_SIDE_MARGIN


## Com o giro, a ordem de desenho muda: quem está mais perto da tela vai por cima.
func _refresh_depths() -> void:
	for cell in cell_nodes:
		var row := _row(cell)
		var shift: int = (row - cell_rows[cell]) * 10
		if shift != 0:
			cell_rows[cell] = row
			for node in cell_nodes[cell]:
				node.z_index += shift
	for unit in views:
		if not walks.has(unit):
			views[unit].z_index = _z(_row(unit.pos)) + 5
	if state.winner() < 0 and active_outline != null:
		active_outline.z_index = _z(_row(state.active_unit().pos)) + 3
	_rebase_depth(_row(camera_cell))


## Linha de desenho da casa, em meias linhas: nos ângulos livres as casas não ficam alinhadas.
func _row(cell: Vector2i) -> int:
	if not exploring:
		return cell.y
	var flat := Vector2(_column_x(cell), cell.y * ROW_STEP).rotated(view_angle)
	return roundi(flat.y * 2.0 / ROW_STEP)


# --- Caminhada livre -----------------------------------------------------------

## Rota do herói até a casa; se não dá para chegar nela, até a casa alcançável mais próxima.
func _route(hero, target: Vector2i, found: Dictionary) -> Array:
	var goal := target
	if not found["cost"].has(goal):
		var nearest := Hex.distance(hero.pos, target)
		goal = hero.pos
		for cell in found["cost"]:
			var distance := Hex.distance(cell, target)
			if distance < nearest:
				nearest = distance
				goal = cell
	return state.straight_path(found, hero.pos, goal)


func _roam_path(target: Vector2i) -> Array:
	var hero = _actor()
	if roam_from != hero.pos or roam_for != hero:
		roam_search = state.search(hero)
		roam_from = hero.pos
		roam_for = hero
	return _route(hero, target, roam_search)


## Manda o herói selecionado até a casa; em fila, os outros heróis do jogador vão atrás dele.
func _travel(target: Vector2i) -> void:
	var hero = _actor()
	_close_menu()
	if not online_session.can_control(hero):
		return
	var followers := []
	if together:
		followers = state.alive_party().filter(func(u): return u != hero and online_session.can_control(u))
		followers.sort_custom(func(a, b): return Hex.distance(a.pos, hero.pos) < Hex.distance(b.pos, hero.pos))
	if online_session.playing:
		_submit_online("travel", target, "", hero, followers)
	else:
		_start_file(hero, followers, target)
	hover = NO_CELL
	_refresh_overlays()


func _stop_selected() -> void:
	if online_session.playing:
		_submit_online("stop", _actor().pos, "", _actor())
	else:
		_end_chain(_actor())


## Cada seguidor primeiro alcança quem está à frente; depois, pisa nas casas que ele deixa.
func _start_file(leader, followers: Array, target: Vector2i) -> void:
	for member in [leader] + followers:
		_end_walk(member)
		file_next.erase(member)
		for ahead in file_next.keys():
			if file_next[ahead] == member:
				file_next.erase(ahead)
	var path := _route(leader, target, state.search(leader))
	if path.is_empty():
		return
	walk_paths[leader] = path
	walk_goals[leader] = target
	var ahead = leader
	for member in followers:
		file_next[ahead] = member
		var trail := _route(member, ahead.pos, state.search(member))
		if not trail.is_empty():
			walk_paths[member] = trail
		ahead = member


func _end_walk(hero) -> void:
	walk_paths.erase(hero)
	walk_goals.erase(hero)
	file_blocked.erase(hero)


## Para o herói e quem vem atrás dele.
func _end_chain(hero) -> void:
	var member = hero
	while member != null:
		_end_walk(member)
		member = file_next.get(member)


## Cada herói dá o próximo passo quando termina o anterior. Só quem simula anda aqui.
func _roam_tick(delta: float) -> void:
	if online_session.playing and not online_session.relay.is_master:
		return
	for hero in step_wait.keys():
		step_wait[hero] -= delta
	if walk_paths.is_empty() or busy:
		return
	if not _free_roam():
		_clear_walks()
		return
	for hero in walk_paths.keys():
		if walk_paths.has(hero) and step_wait.get(hero, 0.0) <= 0.0:
			_roam_step(hero)
			if busy:
				return


func _clear_walks() -> void:
	walk_paths.clear()
	walk_goals.clear()
	file_next.clear()
	file_blocked.clear()


func _roam_step(hero) -> void:
	var path: Array = walk_paths[hero]
	if not hero.alive() or path.is_empty():
		_end_walk(hero)
		return
	var cell: Vector2i = path[0]
	if walk_goals.has(hero):
		# Quem puxa a fila não fica preso aos que vêm atrás; sozinho, respeita o limite da party.
		if not file_next.has(hero) and not state.may_roam(hero, cell):
			_end_walk(hero)
			return
		if not state.can_step(hero, cell): # alguém entrou na frente: tenta outra rota, uma vez
			var detour := _route(hero, walk_goals[hero], state.search(hero))
			if detour.is_empty() or not state.can_step(hero, detour[0]):
				_end_walk(hero)
				return
			path = detour
			walk_paths[hero] = path
			cell = path[0]
	elif not state.can_step(hero, cell):
		# Seguidor: quem está na frente logo sai. Se não sair, ele para e espera a próxima ordem.
		file_blocked[hero] = file_blocked.get(hero, 0.0) + FILE_RETRY
		step_wait[hero] = FILE_RETRY
		if file_blocked[hero] > FILE_PATIENCE:
			_end_walk(hero)
		return
	file_blocked.erase(hero)
	path.pop_front()
	if path.is_empty():
		_end_walk(hero)
	var from: Vector2i = hero.pos
	# Atrasado na fila, o seguidor acelera até colar em quem está à frente.
	var late: int = path.size() if not walk_goals.has(hero) else 0
	var wait: float = WALK_STEP / (1.0 + CATCH_UP * late)
	step_wait[hero] = wait
	var events: Array = state.do_step(hero, cell)
	for event in events:
		if event["type"] == "move":
			event["duration"] = wait
	var behind = null
	if file_next.has(hero) and file_next[hero].alive():
		behind = file_next[hero]
		if not walk_paths.has(behind):
			walk_paths[behind] = []
		walk_paths[behind].append(from)
	events.append_array(state.tick())
	var fight := events.any(func(e): return e["type"] == "combat_start")
	if fight:
		_clear_walks()
		busy = true
		_close_menu()
		hud.set_hint("")
	await _play(events, true)
	_update_journey()
	if fight:
		_refresh_overlays()
		await get_tree().create_timer(DEPLOY_TIME).timeout
		_advance()
	elif behind != null and walk_paths.has(behind) and step_wait.get(behind, 0.0) <= 0.0:
		_roam_step(behind) # quem está na fila pisa junto: a distância entre eles não muda


## Quem ainda não tem desenho ganha um; quem saiu do mapa perde o seu.
func _match_views() -> void:
	for unit in state.units:
		if not views.has(unit):
			_add_unit_view(unit)
	for unit in views.keys():
		if not state.units.has(unit):
			_remove_view(unit)


func _mark_alerted(units: Array) -> void:
	for unit in units:
		if views.has(unit):
			_float_text(views[unit].position + Vector2(-12, -210), "!", Color(1.0, 0.3, 0.2))


## Foi visto: aviso, e a câmera mostra quem apareceu antes de voltar para a party.
func _play_combat_start(event: Dictionary) -> void:
	sound_manager.play_sfx(&"charge")
	hud.show_banner("Combate!" , Color(1.0, 0.42, 0.3))
	_mark_alerted(event["units"])
	hud.refresh(state)
	if not event["surprised"]:
		return
	camera_look = _camera_target(camera_cell).lerp(_camera_target(event["units"][0].pos), 0.45)
	await get_tree().create_timer(0.75).timeout
	camera_look = null


func _play_combat_end(event: Dictionary) -> void:
	sound_manager.play_sfx(&"victory")
	hud.show_banner("Você escapou" if event["fled"] else "Combate vencido", Color(0.6, 1.0, 0.6))
	hud.refresh(state)
	_refresh_turn_markers()
	await get_tree().create_timer(0.4).timeout


func _is_quiet(unit) -> bool:
	return exploring and Hex.distance(unit.pos, camera_cell) > QUIET_DISTANCE


func _play_spawn(event: Dictionary) -> void:
	_add_unit_view(event["unit"])
	var view = views[event["unit"]]
	view.modulate.a = 0.0
	create_tween().tween_property(view, "modulate:a", 1.0, 0.4)


func _remove_view(unit) -> void:
	if views.has(unit):
		views[unit].queue_free()
		views.erase(unit)


func _play_regen(event: Dictionary) -> void:
	var view = views[event["unit"]]
	view.set_hp(event["hp"])
	if event.get("quiet", false): # descansar andando não merece um número subindo a cada passo
		return
	_float_text(view.position + Vector2(-20, -200), "+%d" % event["amount"], Color(0.4, 1.0, 0.5))


## A câmera andou: o que está sob o mouse mudou. Toque não tem hover, então fica como está.
func _play_revive(event: Dictionary) -> void:
	var view = views[event["unit"]]
	view.visible = true
	view.rotation = 0.0
	view.modulate.a = 1.0
	view.set_hp(event["hp"])
	sound_manager.play_sfx(&"heal")
	_float_text(view.position + Vector2(-60, -200), "de pé!", Color(0.4, 1.0, 0.5))


func _refresh_hover() -> void:
	if hover == NO_CELL:
		return
	hover = _pick_cell(get_viewport().get_mouse_position())
	_refresh_overlays()
	_update_hint()


func _rebuild_cell(cell: Vector2i) -> void:
	landmark_nodes.erase(cell)
	if cell_nodes.has(cell):
		_unload_cell(cell)
		_build_cell(cell)


## Marca de um local especial no chão, com o nome em cima. Some quando o local é usado.
func _add_landmark(cell: Vector2i, row: int) -> void:
	if not state.landmarks.has(cell) or state.landmarks[cell]["state"] == "done":
		return
	var is_beacon: bool = cell == state.beacon_cell
	var color: Color = BEACON_COLOR if is_beacon else Exp.LANDMARKS[state.landmarks[cell]["kind"]]["color"]
	var ring := _new_place_ring(color) if natural else _new_hex_line(color, 9)
	_place_ground_marker(ring, cell)
	ring.z_index = _z(row) + 2
	building.append(ring)
	var name_label := Label.new()
	name_label.text = state.landmark_label(cell)
	var lift := 130 if state.landmarks[cell]["kind"] == "bau" else 210 # o baú é baixo: o nome fica perto dele
	name_label.position = feet_of(cell) + Vector2(-110, -lift)
	name_label.custom_minimum_size = Vector2(220, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.z_index = _z(row) + 7
	name_label.add_theme_font_size_override("font_size", 34)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 8)
	board.add_child(name_label)
	building.append(name_label)
	battle_camera.add_billboard(name_label, Vector2(110, lift), _cell_elevation(cell))
	landmark_nodes[cell] = [ring, name_label]


func _play_landmark(event: Dictionary) -> void:
	sound_manager.play_sfx(&"victory" if event["done"] else &"defeat")
	hud.show_banner(event["title"], event["color"])
	if event["detail"] != "":
		hud.show_detail(event["detail"])
	if state.landmarks[event["cell"]]["kind"] == "bau":
		hud.set_potions(state.potions)
	if event["done"] and landmark_nodes.has(event["cell"]):
		for node in landmark_nodes[event["cell"]]:
			if cell_nodes.has(event["cell"]):
				cell_nodes[event["cell"]].erase(node)
			node.queue_free()
		landmark_nodes.erase(event["cell"])
	if event["done"] and state.landmarks[event["cell"]]["kind"] == "bau":
		_rebuild_cell(event["cell"]) # o baú fica aberto
	_update_journey()
	await get_tree().create_timer(0.5).timeout


func _play_level_up(event: Dictionary) -> void:
	sound_manager.play_sfx(&"heal")
	hud.show_banner("Nível %d!" % event["level"], Color(0.6, 0.9, 1.0))
	for member in state.party:
		if views.has(member):
			views[member].set_hp(member.hp)


## Nível, brasas e para onde ir, com a seta já girada conforme a câmera.
func _objective_text() -> String:
	var growth := "máx." if state.xp_to_next() < 0 else "%d XP" % state.xp_to_next()
	var text := "Nível %d (%s)   ·   Brasas %d   ·   Farol %s" % [state.level, growth, state.brasas, _direction_to(state.beacon_cell)]
	var open: Array = state.open_landmarks(camera_cell)
	if not open.is_empty() and (state.far_compass or Hex.distance(open[0], camera_cell) <= Exp.COMPASS_RADIUS):
		text += "   ·   %s %s" % [state.landmark_label(open[0]), _direction_to(open[0])]
	return text


## A primeira missão aceita, somando o que a expedição já fez por ela.
func _quest_tracker() -> String:
	var result: Dictionary = state.result()
	for id in TownProgress.quests_with("active"):
		var quest: Dictionary = TownContent.QUESTS[id]
		var done: int = mini(TownProgress.quest_progress(id) + int(result["tally"].get(quest["count"], 0)), quest["target"])
		return "Missão: %s (%d/%d)" % [quest["title"], done, quest["target"]]
	return ""


func _use_potion() -> void:
	if state.winner() >= 0:
		return
	var events: Array = state.use_potion()
	if events.is_empty():
		hud.set_hint("A party está com a vida cheia.")
		return
	sound_manager.play_sfx(&"heal")
	for event in events:
		_play_regen(event)
	hud.set_potions(state.potions)
	_update_journey()


func _direction_to(cell: Vector2i) -> String:
	var away: Vector2 = (_flat_point(cell) - _flat_point(camera_cell)).rotated(view_angle)
	var sector := posmod(roundi(away.angle() / (TAU / COMPASS_ARROWS.size())), COMPASS_ARROWS.size())
	return "%s %d" % [COMPASS_ARROWS[sector], Hex.distance(cell, camera_cell)]


func _end_text() -> String:
	if expedition:
		var saved: Dictionary = state.result()
		var title: String = "O farol voltou a brilhar!" if saved["won"] else "A party caiu na escuridão"
		var kept := "%d brasas levadas" % saved["brasas"]
		return "%s\n%s · %d resgate%s · nível %d" % [title, kept, saved["rescued"].size(), "" if saved["rescued"].size() == 1 else "s", state.level]
	return "Fim da jornada\n%d casas de distância · %d inimigos derrotados" % [state.farthest, state.kills]


func _back_to_menu() -> void:
	if expedition:
		_start_battle() # o fim da expedição já deixou a volta para a cidade marcada
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Cidade-Farol --------------------------------------------------------------

func _set_return_to_town() -> void:
	var root := get_tree().root
	root.set_meta(TOWN_META, true)
	root.set_meta(EXPEDITION_META, false)


func _setup_town() -> void:
	town_panels = TownPanels.new()
	town_panels.z_index = TOWN_PANELS_LAYER # por cima das linhas do topo, criadas depois
	hud.add_child(town_panels)
	town_panels.setup(_party_types())
	town_panels.depart.connect(_depart)
	town_panels.skills_requested.connect(func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	town_panels.menu_requested.connect(_back_to_menu)
	town_panels.changed.connect(_town_changed)
	town_life = TownLife.new()
	add_child(town_life)
	town_life.setup(self)


func _town_changed() -> void:
	town_panels.refresh()
	_update_town()
	for cell in person_labels:
		_show_person_mark(cell)


func _party_types() -> Array:
	return state.party.map(func(unit): return unit.type_id)


func _depart(party_types: Array) -> void:
	var root := get_tree().root
	root.set_meta("world_hero", party_types)
	root.set_meta(TOWN_META, false)
	root.set_meta(EXPEDITION_META, true)
	online_session.leave()
	_start_battle()


func _update_town() -> void:
	var saved: Array = TownProgress.rescued()
	var people: int = TownData.BASE_PEOPLE + saved.size() * TownData.PEOPLE_PER_RESCUE + TownProgress.beacons() * TownData.PEOPLE_PER_BEACON
	var city_level: int = 1 + saved.size() + TownProgress.beacons()
	hud.set_status("Cidade-Farol   ·   Heróis %d/%d   ·   Habitantes %d" % [state.alive_party().size(), state.party.size(), people])
	hud.set_objective("Nível da Cidade %d   ·   Brasas %d   ·   Faróis acesos %d" % [city_level, TownProgress.brasas(), TownProgress.beacons()])
	hud.update_party(selected)


## Nome de quem mora aqui, com o aviso de que dá para conversar.
func _add_person_name(cell: Vector2i, row: int) -> void:
	if not state.people.has(cell) or not state.is_present(state.people[cell]):
		return
	var name_label := Label.new()
	name_label.position = feet_of(cell) + Vector2(-140, -176)
	name_label.custom_minimum_size = Vector2(280, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.z_index = _z(row) + 7
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 8)
	board.add_child(name_label)
	building.append(name_label)
	battle_camera.add_billboard(name_label, Vector2(140, 176), _cell_elevation(cell))
	person_labels[cell] = name_label
	_show_person_mark(cell)


## "!" tem pedido novo, "?" tem missão para entregar. Sem nada, só o nome.
func _show_person_mark(cell: Vector2i) -> void:
	var name_label = person_labels[cell]
	if not is_instance_valid(name_label): # a casa saiu de perto e será refeita ao voltar
		return
	var person: Dictionary = state.people[cell]
	var mark: String = TownProgress.person_mark(person["id"])
	name_label.text = "%s %s" % [mark, person["name"]] if mark != "" else person["name"]
	var color: Color = Color("9fe39a") if mark == "?" else (BEACON_COLOR if mark == "!" else Color(0.92, 0.9, 0.82))
	name_label.add_theme_color_override("font_color", color)


func _play_move(event: Dictionary) -> void:
	var view = views[event["unit"]]
	var from: Vector2 = feet_of(event["from"])
	var to: Vector2 = feet_of(event["to"])
	var unit = event["unit"]
	if exploring and unit == camera_unit:
		_set_camera(event["to"])
	if exploring and Hex.distance(event["to"], camera_cell) > QUIET_DISTANCE:
		if walks.has(unit):
			_finish_walk(unit)
		view.position = to
		view.z_index = _z(_row(event["to"])) + 5
		battle_camera.set_elevation(_cell_elevation(event["to"]), view)
		return
	if exploring:
		var time: float = event.get("duration", WALK_STEP)
		if not event.get("silent", false):
			sound_manager.play_sfx(&"step")
		_begin_walk(unit, event["from"], event["to"], time)
		await get_tree().create_timer(time).timeout
		return
	view.face_toward(to - from)
	view.z_index = _z(maxi(_row(event["from"]), _row(event["to"]))) + 5
	view.set_walking(true)
	moving[unit] = moving.get(unit, 0) + 1
	if not event.get("silent", false):
		sound_manager.play_sfx(&"step")
	var height_delta: int = state.elevation_at(event["to"]) - state.elevation_at(event["from"])
	var duration: float = event.get("duration", STEP_FLAT if height_delta == 0 else STEP_CLIMB)
	var tween := create_tween()
	tween.tween_method(_move_frame.bind(view, event["from"], event["to"], _cell_elevation(event["from"]), _cell_elevation(event["to"]), height_delta), 0.0, 1.0, duration)
	await tween.finished
	moving[unit] -= 1
	if moving[unit] <= 0:
		moving.erase(unit)
	if not is_instance_valid(view) or moving.has(unit):
		return
	view.set_walking(false)
	view.set_jump_height(0.0)
	view.position = feet_of(unit.pos)
	view.z_index = _z(_row(unit.pos)) + 5
	battle_camera.set_elevation(_cell_elevation(unit.pos), view)
	_refresh_overlays()


## As casas, e não pontos prontos: girar a câmera no meio do passo não deixa o herói fora do lugar.
func _move_frame(progress: float, view, from: Vector2i, to: Vector2i, from_height: float, to_height: float, height_delta: int) -> void:
	if not is_instance_valid(view):
		return
	view.position = feet_of(from).lerp(feet_of(to), progress)
	battle_camera.set_elevation(lerpf(from_height, to_height, progress), view)
	var jump := 0.0
	if height_delta != 0:
		jump = sin(progress * PI) * (110.0 if height_delta > 0 else 65.0)
	view.set_jump_height(jump)


func _play_attack(event: Dictionary) -> void:
	var unit = event["unit"]
	var target = event["target"]
	var view = views[unit]
	view.face_toward((feet_of(target.pos) - view.position).rotated(view_angle))
	# Quem apanha olha para quem bateu, para o tranco do dano sair na direção certa.
	views[target].face_toward((view.position - views[target].position).rotated(view_angle))
	var id: String = event.get("ability", "")
	var magic := SPELL_FX.has(id)
	if not magic:
		sound_manager.play_sfx(&"swing") # golpe corpo a corpo ou disparo da flecha
	await view.play_once(_attack_anim(unit, id))
	var shot: String = Data.ABILITIES[id].get("shot", "") if Data.ABILITIES.has(id) else ""
	if shot != "":
		await _fly_projectile(shot, view.position + Vector2(0, -90), views[target].position + Vector2(0, -90))
		sound_manager.play_sfx(&"arrow_hit")
	elif magic:
		await _play_spell_fx(id, view.position + Vector2(0, -90), [views[target].position])
	else:
		sound_manager.play_sfx(&"melee_hit")


# A primeira habilidade da unidade é o ataque básico; as outras usam o ataque forte.
func _attack_anim(unit, ability_id: String) -> UnitView.Anim:
	var abilities: Array = Data.UNIT_TYPES.get(unit.type_id, {}).get("abilities", [])
	if abilities.is_empty() or ability_id == "" or ability_id == abilities[0]:
		return UnitView.Anim.ATTACK
	return UnitView.Anim.STRONG


func _play_damage(event: Dictionary) -> void:
	var view = views[event["target"]]
	view.set_hp(event["hp"])
	var text := str(event["amount"])
	if event.get("flank", false):
		text += " flanco!"
	_float_text(view.position + Vector2(-20, -200), text, Color(1.0, 0.4, 0.3))
	sound_manager.play_sfx(&"hurt")
	view.play_once(UnitView.Anim.HURT)
	await get_tree().create_timer(0.25).timeout


func _play_heal(event: Dictionary) -> void:
	var view = views[event["target"]]
	view.set_hp(event["hp"])
	sound_manager.play_sfx(&"heal")
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/kit/heal.png")
	fx.scale = Vector2.ONE * 0.5
	fx.position = view.position + Vector2(0, -90)
	fx.z_index = 900
	board.add_child(fx)
	_add_effect_billboard(fx, Vector2(0, 90))
	var tween := create_tween()
	tween.tween_property(fx, "modulate:a", 0.0, 0.6)
	tween.tween_callback(fx.queue_free)
	_float_text(view.position + Vector2(-20, -200), "+%d" % event["amount"], Color(0.4, 1.0, 0.5))
	await tween.finished


# O kit não tem animação de morte: a unidade tomba e some.
func _play_death(event: Dictionary) -> void:
	var view = views[event["target"]]
	sound_manager.play_sfx(&"death_hero" if event["target"].team == Data.Team.PLAYER else &"death_monster")
	var tween := create_tween().set_parallel()
	tween.tween_property(view, "rotation", deg_to_rad(80 if view.sprite.flip_h else -80), 0.35)
	tween.tween_property(view, "modulate:a", 0.0, 0.5)
	await tween.finished
	view.visible = false


func _play_cast_start(event: Dictionary) -> void:
	var view = views[event["unit"]]
	view.face_toward((feet_of(event["tile"]) - view.position).rotated(view_angle))
	_show_status(event["unit"])
	_refresh_overlays()
	sound_manager.play_sfx(&"charge")
	await view.play_once(UnitView.Anim.ATTACK)


func _play_cast_resolve(event: Dictionary) -> void:
	var view = views[event["unit"]]
	_refresh_overlays()
	await view.play_once(UnitView.Anim.STRONG)
	var id: String = event["id"]
	var center: Vector2 = feet_of(event["tile"]) + Vector2(0, -20)
	if SPELL_FX.has(id):
		var spots := [feet_of(event["tile"])]
		if SPELL_FX[id].get("per_cell", false):
			var cells: Array = event["cells"].duplicate()
			cells.sort_custom(func(a, b): return Hex.distance(a, event["tile"]) < Hex.distance(b, event["tile"]))
			spots = cells.map(func(cell): return feet_of(cell))
		await _play_spell_fx(id, view.position + Vector2(0, -90), spots)
	else:
		await _fly_projectile(Data.ABILITIES[id].get("shot", "kit/magic"), view.position + Vector2(0, -90), center)
	var flashes := []
	for cell in event["cells"]:
		var flash := Polygon2D.new()
		flash.polygon = hex_poly
		_place_ground_marker(flash, cell)
		flash.color = Color(1.0, 0.75, 0.3, 0.85)
		flash.position = cell_origin(cell)
		flash.z_index = 900
		board.add_child(flash)
		flashes.append(flash)
	var tween := create_tween().set_parallel()
	for flash in flashes:
		tween.tween_property(flash, "modulate:a", 0.0, 0.35)
	await tween.finished
	for flash in flashes:
		flash.queue_free()


## Projétil (se a magia tiver) do mago até o primeiro ponto, depois o impacto em todos os pontos.
## Os pontos são pés de casas (com per_cell, uma por casa, começando pelo centro da área).
func _play_spell_fx(id: String, from: Vector2, spots: Array) -> void:
	var spell: Dictionary = SPELL_FX[id]
	var ground: bool = spell.get("ground", false)
	var lift: float = spell.get("lift", 90)
	if spell.has("projectile"):
		var to: Vector2 = spots[0] - Vector2(0, 90 if ground else lift)
		var ball := _fx_sprite(spell["projectile"], PROJECTILE_SCALE)
		ball.position = from
		_add_effect_billboard(ball, Vector2(0, 90))
		# Os projéteis do pack voam para a direita; projectile_turn corrige os que não.
		ball.rotation = (to - from).angle() + spell.get("projectile_turn", 0.0)
		var duration := clampf(from.distance_to(to) / 1400.0, 0.15, 0.5)
		sound_manager.play_sfx(spell.get("cast_sound", &"fire_cast"))
		var flight := create_tween().set_parallel()
		flight.tween_property(ball, "position", to, duration)
		flight.tween_method(battle_camera.set_elevation.bind(ball), _height_at_point(from + Vector2(0, 90)), _height_at_point(spots[0]), duration)
		flight.tween_method(_loop_frames.bind(ball), 0.0, duration, duration)
		await flight.finished
		ball.queue_free()
	sound_manager.play_sfx(spell["sound"])
	var size: float = spell["impact_scale"]
	var frames: int = fx_meta[spell["impact"]]["frames"]
	var hits := []
	var burst := create_tween().set_parallel()
	for i in spots.size():
		var hit := _fx_sprite(spell["impact"], size)
		hit.position = spots[i]
		hit.position.y -= fx_meta[spell["impact"]]["h"] * size / 2.0 if ground else lift
		_add_effect_billboard(hit, Vector2(0, fx_meta[spell["impact"]]["h"] * size / 2.0 if ground else lift))
		var delay: float = spell.get("ring_delay", 0.0) if i > 0 else 0.0
		hit.visible = delay == 0.0
		burst.tween_callback(hit.show).set_delay(delay)
		burst.tween_property(hit, "frame", frames - 1, frames / FX_FPS).from(0).set_delay(delay)
		hits.append(hit)
	if world_light != null:
		world_light.flash(spots[0], spell["impact"].begins_with("agua/"), 1.0 + 0.2 * (spots.size() - 1))
	await burst.finished
	for hit in hits:
		hit.queue_free()


func _fx_sprite(fx_name: String, size: float) -> Sprite2D:
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/%s.png" % fx_name)
	fx.hframes = fx_meta[fx_name]["frames"]
	fx.scale = Vector2.ONE * size
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_index = 900
	board.add_child(fx)
	return fx


func _loop_frames(elapsed: float, fx: Sprite2D) -> void:
	fx.frame = int(elapsed * FX_FPS) % fx.hframes


func _fly_projectile(texture: String, from: Vector2, to: Vector2) -> void:
	var fx := Sprite2D.new()
	fx.texture = load("res://assets/fx/%s.png" % texture)
	fx.position = from
	fx.z_index = 900
	if texture == "kit/arrow":
		fx.rotation = (to - from).angle() - Vector2(-22, 12).angle() # inclinação da flecha no PNG
	else:
		fx.scale = Vector2.ONE * 1.6
	board.add_child(fx)
	var tween := create_tween()
	_add_effect_billboard(fx, Vector2(0, 90))
	var duration := clampf(from.distance_to(to) / 1800.0, 0.1, 0.4)
	tween.set_parallel()
	tween.tween_property(fx, "position", to, duration)
	tween.tween_method(battle_camera.set_elevation.bind(fx), _height_at_point(from + Vector2(0, 90)), _height_at_point(to + Vector2(0, 90)), duration)
	await tween.finished
	fx.queue_free()


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.z_index = 1000
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	board.add_child(label)
	_add_effect_billboard(label, Vector2(0, 200))
	var tween := create_tween().set_parallel()
	tween.tween_property(label, "position:y", pos.y - 70, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)


# Toda habilidade que serviria nesse alvo aparece; as que não dá para usar agora
# ficam apagadas dizendo o alcance que precisa (ou que a vida já está cheia).
func _blocked_options(unit, target) -> Array:
	var options := []
	var enemy: bool = target.team != unit.team
	for id in unit.abilities:
		var ability: Dictionary = unit.ability(id)
		var kind: String = ability["kind"]
		var fits: bool = (kind == "attack" and enemy) or kind == "charge" or (kind == "heal" and not enemy) or (kind == "guard" and target == unit)
		if not fits or state.valid_targets(unit, id).has(target.pos):
			continue
		var detail := _range_short(ability)
		if kind == "heal" and target.hp >= target.max_hp and Hex.distance(unit.pos, target.pos) <= ability["range"]:
			detail = "vida cheia"
		options.append({"kind": "blocked", "id": id, "label": ability["name"], "detail": detail, "disabled": true})
	return options


func _range_short(ability: Dictionary) -> String:
	if ability["min_range"] > 1:
		return "de %d a %d casas" % [ability["min_range"], ability["range"]]
	return "só colado" if ability["range"] == 1 else "até %d casas" % ability["range"]
