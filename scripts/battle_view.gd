extends Node2D
class_name BattleView

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
const TOWN_TINT := Color(0.6, 0.63, 0.82) # noite: as fogueiras e o farol iluminam a cidade
const EXPEDITION_META := "expedition"
const LOAD_META := "load_save" # save lido, à espera de main.tscn abrir
const SaveGame = preload("res://scripts/save_game.gd")
const AI = preload("res://scripts/ai.gd")
const UnitView = preload("res://scripts/unit_view.gd")
const Hud = preload("res://scripts/hud.gd")
const BattleCamera = preload("res://scripts/battle_camera.gd")
const BiomeArt = preload("res://scripts/biome_art.gd")
const Skills = preload("res://scripts/skill_data.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")
const HeroJuice = preload("res://scripts/hero_juice.gd")
const BattleJuice = preload("res://scripts/battle_juice.gd")

const BOARD_POS := Vector2(250, 142) # sem painel lateral: o tabuleiro fica no meio, a fila à esquerda
const BOARD_SCALE := 0.5
const TILE_WIDTH := 186
const ROW_STEP := 160
const SIDE_HEIGHT := 29 # altura da lateral do tile; empilhar tiles a cada 29 px forma o penhasco
const LAYERS_PER_LEVEL := 4 # 116 px por nível; a altura é projetada na vertical
# Na exploração os degraus são mais baixos: num mapa gerado, uma casa atrás de um
# degrau precisa continuar visível e clicável.
const WORLD_LAYERS_PER_LEVEL := 3
const TOWN_LAYERS_PER_LEVEL := 2 # a planta da cidade conta com degraus baixos
const TOWN_GROUND_EDGE := 0.35 # calçada e grama com a borda mais limpa que no mato das expedições
const FEET := Vector2(93, 125)
const NO_CELL := Vector2i(-999999, -999999) # coordenadas negativas existem na exploração
const HOLD_TIME := 0.45
const WORLD_META := "world_hero" # o menu guarda aqui o herói escolhido para explorar
const EXPLORE_ZOOM := 0.8 # a câmera fica mais longe fora da arena; o resto da lista acompanha
const FOG_START := 650.0
const FOG_END := 1100.0
const INSPECT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const TURN_SPEED := 1.9 # radianos por segundo com a tecla apertada
const TURN_EASE := 9.0 # quão rápido o giro acelera e freia
const MAP_REFRESH := 0.12 # segundos entre revisões do mapa enquanto gira
const DEPLOY_TIME := 0.45
const CAMERA_SPEED := 7.0
const WALK_STEP := 0.3 # tempo por casa na jornada, igual em chão plano e em degrau
const BUILD_BUDGET_USEC := 2000 # tempo por quadro para desenhar casas novas
const CHARGE_COLOR := Color(0.72, 0.3, 1.0, 0.42)
const ACTIVE_COLOR := Color(1.0, 0.84, 0.35)
const BEACON_COLOR := Color(1.0, 0.85, 0.35)
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
	"incinerar": {"impact": "fogo/fire", "impact_scale": 2.5, "ground": true, "sound": &"flame"},
	"rajada_calor": {"impact": "fogo/small_fire", "impact_scale": 5.0, "ground": true, "sound": &"fire_hit"},
	"toque_gelido": {"impact": "agua/ice_spike", "impact_scale": 1.6, "ground": true, "sound": &"ice"},
	"corrente": {"impact": "agua/splash", "impact_scale": 2.5, "ground": true, "sound": &"water"},
}
# Efeitos dos chefes dos faróis, feitos com as partículas do Kenney (assets/fx/kenney).
# "hit" sai no golpe básico, "skill" no especial. Cada camada:
#   burst: estouro de partículas (amount, speed [min, max], size, life, gravity, spread)
#   flash: uma imagem que cresce e some (size, life, spin)
#   ring: onda no chão que se abre (size, life)
const BOSS_FX := {
	"boss_cervo": {
		"hit": [
			{"kind": "flash", "tex": "slash_02", "color": Color(0.75, 0.55, 0.3), "size": 0.45, "life": 0.25},
			{"kind": "burst", "tex": "dirt_02", "color": Color(0.45, 0.32, 0.2), "amount": 8, "speed": [120, 260], "size": 0.08, "life": 0.5, "gravity": 500},
		],
		"skill": [
			{"kind": "ring", "tex": "circle_02", "color": Color(0.55, 0.3, 0.75), "size": 1.1, "life": 0.5},
			{"kind": "burst", "tex": "dirt_02", "color": Color(0.4, 0.3, 0.18), "amount": 22, "speed": [220, 480], "size": 0.12, "life": 0.8, "gravity": 700},
			{"kind": "burst", "tex": "twirl_02", "color": Color(0.6, 0.35, 0.85, 0.8), "amount": 6, "speed": [40, 120], "size": 0.3, "life": 0.9, "gravity": -60},
			{"kind": "burst", "tex": "smoke_04", "color": Color(0.25, 0.22, 0.2, 0.35), "amount": 10, "speed": [60, 160], "size": 0.35, "life": 1.0, "gravity": -40},
		],
	},
	"boss_serpente": {
		"hit": [
			{"kind": "flash", "tex": "slash_03", "color": Color(0.5, 0.95, 0.35), "size": 0.45, "life": 0.25},
			{"kind": "burst", "tex": "spark_04", "color": Color(0.6, 1.0, 0.4), "amount": 8, "speed": [150, 300], "size": 0.08, "life": 0.4},
		],
		"skill": [
			{"kind": "flash", "tex": "scratch_01", "color": Color(0.45, 1.0, 0.35), "size": 0.6, "life": 0.3},
			{"kind": "burst", "tex": "magic_03", "color": Color(0.55, 0.25, 0.8, 0.9), "amount": 12, "speed": [80, 220], "size": 0.18, "life": 0.9, "gravity": -80},
			{"kind": "burst", "tex": "smoke_07", "color": Color(0.35, 0.75, 0.25, 0.35), "amount": 10, "speed": [50, 140], "size": 0.4, "life": 1.1, "gravity": -30},
		],
	},
	"boss_jarl": {
		"hit": [
			{"kind": "flash", "tex": "slash_02", "color": Color(0.75, 0.9, 1.0), "size": 0.5, "life": 0.25},
			{"kind": "burst", "tex": "spark_04", "color": Color(0.7, 0.9, 1.0), "amount": 10, "speed": [150, 320], "size": 0.08, "life": 0.45},
		],
		"skill": [
			{"kind": "ring", "tex": "circle_02", "color": Color(0.6, 0.85, 1.0), "size": 1.3, "life": 0.55},
			{"kind": "burst", "tex": "star_06", "color": Color(0.8, 0.95, 1.0), "amount": 18, "speed": [200, 460], "size": 0.1, "life": 0.8, "gravity": 400},
			{"kind": "burst", "tex": "smoke_04", "color": Color(0.85, 0.92, 1.0, 0.35), "amount": 14, "speed": [80, 220], "size": 0.4, "life": 1.1, "gravity": -30},
		],
	},
	"boss_farao": {
		"hit": [
			{"kind": "flash", "tex": "slash_03", "color": Color(1.0, 0.82, 0.35), "size": 0.45, "life": 0.25},
			{"kind": "burst", "tex": "spark_04", "color": Color(1.0, 0.85, 0.4), "amount": 8, "speed": [150, 300], "size": 0.08, "life": 0.4},
		],
		"skill": [
			{"kind": "flash", "tex": "symbol_01", "color": Color(1.0, 0.8, 0.3), "size": 0.7, "life": 0.6, "spin": 1.5},
			{"kind": "flash", "tex": "light_02", "color": Color(1.0, 0.75, 0.3, 0.8), "size": 0.9, "life": 0.5},
			{"kind": "burst", "tex": "dirt_02", "color": Color(0.85, 0.7, 0.4), "amount": 18, "speed": [120, 320], "size": 0.1, "life": 0.9, "gravity": 300},
			{"kind": "burst", "tex": "star_06", "color": Color(1.0, 0.9, 0.5), "amount": 10, "speed": [80, 200], "size": 0.08, "life": 0.7, "gravity": -50},
		],
	},
}
const BoardArt = preload("res://scripts/battle/board_art.gd")
const BattleInput = preload("res://scripts/battle/battle_input.gd")
const BattleMarks = preload("res://scripts/battle/battle_marks.gd")
const EventPlayer = preload("res://scripts/battle/event_player.gd")
const HeroFx = preload("res://scripts/battle/hero_fx.gd")
const NetBridge = preload("res://scripts/battle/net_bridge.gd")
const RoamControl = preload("res://scripts/battle/roam_control.gd")
const TownMode = preload("res://scripts/battle/town_mode.gd")
const JourneyUi = preload("res://scripts/battle/journey_ui.gd")

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
var juice # tremor, hitstop e clarões dos heróis (battle_juice.gd)
var hit_ctx := {} # peso do golpe de herói em andamento: os eventos de dano seguintes usam
var hit_from := Vector2.ZERO # de onde veio o último golpe, para o tranco de quem apanha
var healers_animated := {} # quem já fez o gesto de cura nesta ação (Clareira cura vários)
var board_art := BoardArt.new(self) # chão, casas, paredes, enfeites e o mapa que carrega aos poucos
var input_ctl := BattleInput.new(self) # cliques, teclas, menu de ações e ficha
var marks_ctl := BattleMarks.new(self) # destaques no chão, dicas e marcadores da fila
var event_player := EventPlayer.new(self) # anima os eventos das regras: andar, atacar, magias
var hero_fx := HeroFx.new(self) # peso dos golpes dos heróis (juice)
var net_bridge := NetBridge.new(self) # comandos e pacotes do online
var roam_ctl := RoamControl.new(self) # caminhada livre e fila da party
var town_mode := TownMode.new(self) # Cidade-Farol
var journey_ui := JourneyUi.new(self) # objetivo, missão, poção e fim da expedição


func _ready() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units/meta.json"))
	fx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/meta.json"))
	_start_battle()
	if online_session.playing:
		online_session.command_received.connect(net_bridge._network_command)
		online_session.packet_received.connect(net_bridge._network_packet)
		online_session.connection_lost.connect(net_bridge._network_lost)
		online_session.changed.connect(net_bridge._room_status)
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
		leave_button.pressed.connect(net_bridge._leave_online)
		row.add_child(leave_button)
		net_bridge._room_status()
		net_bridge._network_packet({})


func _exit_tree() -> void:
	get_tree().paused = false
	music_manager.play_menu()


func _start_battle() -> void:
	var root := get_tree().root
	var loaded: Dictionary = {}
	if root.has_meta(LOAD_META):
		loaded = root.get_meta(LOAD_META)
		root.remove_meta(LOAD_META)
	if online_session.playing:
		loaded = {}
	if not loaded.is_empty(): # o save decide o modo, como se a party tivesse vindo do menu
		root.set_meta(WORLD_META, loaded.get("party", []))
		root.set_meta(TOWN_META, loaded.mode == "town")
		root.set_meta(EXPEDITION_META, loaded.mode == "expedition")
		root.set_meta("skills_back", "res://main.tscn")
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
	elif not loaded.is_empty():
		state = SaveGame.restore(loaded)
		expedition = loaded.mode == "expedition"
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
	if juice != null:
		juice.queue_free()
	juice = BattleJuice.new()
	add_child(juice)
	hit_ctx = {}
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
	board_art._show_facing_walls()
	board_art._build_tiles()
	for unit in state.units:
		board_art._add_unit_view(unit)
	active_outline = board_art._new_hex_line(ACTIVE_COLOR, 7)
	inspect_outline = board_art._new_hex_line(INSPECT_COLOR, 7)
	inspect_outline.visible = false
	pinned = null
	marks_ctl._build_focus_marker()

	hud = Hud.new()
	add_child(hud)
	hud.setup(meta)
	hud.unit_picked.connect(input_ctl._on_timeline_pick)
	hud.option_pressed.connect(input_ctl._on_option_pressed)
	hud.order_toggled.connect(marks_ctl._on_order_toggled)
	hud.end_turn_pressed.connect(input_ctl._end_turn)
	hud.restart_pressed.connect(net_bridge._leave_online if online_session.playing else (_back_to_menu if expedition else _start_battle))
	hud.skills_pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	hud.save_allowed = not online_session.playing
	hud.load_allowed = not online_session.playing
	hud.options_toggled.connect(func(open): get_tree().paused = open and not online_session.playing)
	hud.save_pressed.connect(_save_game)
	hud.load_pressed.connect(_load_game)
	hud.quit_pressed.connect(_quit_to_title)
	if exploring:
		hud.setup_exploration()
		hud.menu_pressed.connect(_back_to_menu)
		if expedition:
			hud.use_town_exit()
			hud.set_potions(state.potions)
			hud.potion_pressed.connect(journey_ui._use_potion)
		if town:
			town_mode._setup_town()
		hud.setup_party(state.party, _owner_names())
		hud.party_pressed.connect(input_ctl._on_party_pick)
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


## Nome do jogador de cada herói, para a barra da party no online.
func _owner_names() -> Dictionary:
	var names := {}
	if online_session.playing:
		for unit in state.party:
			names[unit] = str(online_session.players.get(online_session.owner_of(unit), ""))
	return names


## Profundidade de desenho de uma linha. A conta é relativa porque o Godot limita o
## z_index, e numa caminhada longa o número da linha passaria desse limite.
func _z(row: int) -> int:
	return (row - z_origin) * 10


# --- Mapa infinito -----------------------------------------------------------

func _camera_target(cell: Vector2i) -> Vector2:
	var feet := Vector2(_column_x(cell), cell.y * ROW_STEP) + FEET
	return BattleCamera.FOCUS - feet * BOARD_SCALE


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


func _add_effect_billboard(item: CanvasItem, offset: Vector2, additive := false) -> void:
	battle_camera.add_billboard(item, offset, _height_at_point(item.position + offset), additive)


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
	input_ctl._refresh_end_turn()
	pinned = null
	input_ctl._close_menu()
	marks_ctl._refresh_overlays()
	while true:
		var result: int = state.winner()
		if result >= 0:
			online_session.publish([], true)
			sound_manager.play_sfx(&"victory" if result == Data.Team.PLAYER else &"defeat")
			journey_ui._show_result(result)
			return
		if exploring:
			var changes: Array = state.tick()
			if not changes.is_empty():
				await event_player._play(changes)
			journey_ui._update_journey()
		var unit = state.active_unit()
		_place_ground_marker(active_outline, unit.pos)
		active_outline.visible = not _free_roam()
		active_outline.z_index = _z(_row(unit.pos)) + 3
		if exploring and state.in_combat():
			_focus_turn(unit)
		marks_ctl._refresh_turn_markers()
		hud.refresh(state)
		hud.set_hint("")
		if not unit.pending.is_empty():
			await event_player._play(state.resolve_pending(unit))
			continue
		if unit.team == Data.Team.ENEMY:
			if not event_player._is_quiet(unit) and unit.moved == 0:
				await get_tree().create_timer(0.2).timeout
			await event_player._play(AI.apply(state, unit, AI.decide(state, unit)))
			continue
		break
	busy = false
	if exploring:
		journey_ui._update_journey()
		marks_ctl._refresh_hover()
	hud.refresh(state)
	marks_ctl._refresh_turn_markers()
	marks_ctl._refresh_overlays()
	marks_ctl._update_hint()
	online_session.publish([], true)


func _perform(events: Array) -> void:
	busy = true
	input_ctl._refresh_end_turn()
	input_ctl._close_menu()
	hud.set_hint("")
	marks_ctl._refresh_overlays()
	await event_player._play(events)
	_advance()


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


# --- Câmera --------------------------------------------------------------------

func _process(delta: float) -> void:
	if not exploring or board == null:
		return
	_update_turn(delta)
	roam_ctl._update_walks(delta)
	if town and selected != null:
		town_panels.set_nearby(state.person_near(selected.pos))
	var goal: Vector2 = camera_look if camera_look != null else BattleCamera.FOCUS - _camera_point() * BOARD_SCALE
	board.position = board.position.lerp(goal, 1.0 - exp(-delta * CAMERA_SPEED))
	board_art._work_on_map(BUILD_BUDGET_USEC)
	roam_ctl._roam_tick(delta)
	if overlays_dirty:
		overlays_dirty = false
		marks_ctl._refresh_overlays()


## O ponto que a câmera segue: a posição contínua de quem está andando, sem contar a altura.
func _camera_point() -> Vector2:
	if walks.has(camera_unit):
		return walks[camera_unit].ground
	return roam_ctl._ground(camera_cell)


func _follow(unit) -> void:
	camera_unit = unit
	_set_camera(unit.pos)


func _set_camera(cell: Vector2i) -> void:
	camera_cell = cell
	board_art._sync_world(cell, false)
	board_art._rebase_depth(_row(cell))


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
	board_art._show_facing_walls()
	board_art._refresh_depths()
	board_art._update_model_frames()
	if map_refresh <= 0.0:
		map_refresh = MAP_REFRESH
		board_art._sync_world(camera_cell, false)


## Linha de desenho da casa, em meias linhas: nos ângulos livres as casas não ficam alinhadas.
func _row(cell: Vector2i) -> int:
	if not exploring:
		return cell.y
	var flat := Vector2(_column_x(cell), cell.y * ROW_STEP).rotated(view_angle)
	return roundi(flat.y * 2.0 / ROW_STEP)


func _back_to_menu() -> void:
	if expedition:
		_start_battle() # o fim da expedição já deixou a volta para a cidade marcada
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Menu de opções ------------------------------------------------------------

func _save_game() -> void:
	if online_session.playing or state.winner() >= 0:
		return
	if SaveGame.save(state):
		hud.show_options_note("Jogo salvo!")
		hud.load_button.disabled = false
		hud.load_button.text = "Carregar jogo (%s)" % SaveGame.summary()
	else:
		hud.show_options_note("Não foi possível salvar.")


## Recarrega a cena com o save: o que estava animando para junto com a cena antiga.
func _load_game() -> void:
	var data := SaveGame.read()
	if data.is_empty():
		hud.show_options_note("Save não encontrado ou de outra versão.")
		return
	get_tree().paused = false
	get_tree().root.set_meta(LOAD_META, data)
	get_tree().change_scene_to_file("res://main.tscn")


func _quit_to_title() -> void:
	get_tree().paused = false
	if online_session.playing:
		online_session.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Repasses ---------------------------------------------------------------
# Outros scripts e os testes chamam estas funções na tela; o código mora nos módulos.

func _update_journey() -> void:
	journey_ui._update_journey()


func _sync_world(center: Vector2i, all_now := true) -> void:
	board_art._sync_world(center, all_now)


func _add_unit_view(unit) -> void:
	board_art._add_unit_view(unit)


func _unhandled_input(event: InputEvent) -> void:
	input_ctl._unhandled_input(event)


func _end_turn() -> void:
	input_ctl._end_turn()


func _card_ability(unit, id: String) -> Dictionary:
	return input_ctl._card_ability(unit, id)


func _click(cell: Vector2i) -> void:
	input_ctl._click(cell)


func _cell_options(cell: Vector2i) -> Array:
	return input_ctl._cell_options(cell)


func _on_option_pressed(index: int) -> void:
	input_ctl._on_option_pressed(index)


func _refresh_overlays() -> void:
	marks_ctl._refresh_overlays()


func _shown_unit():
	return marks_ctl._shown_unit()


func _update_hint() -> void:
	marks_ctl._update_hint()


func _play(events: Array, roam := false) -> void:
	await event_player._play(events, roam)


func _submit_online(kind: String, cell: Vector2i, ability := "", hero = null, followers := []) -> void:
	net_bridge._submit_online(kind, cell, ability, hero, followers)


func _network_command(sender: int, command: Dictionary) -> void:
	net_bridge._network_command(sender, command)


func _select(unit) -> void:
	input_ctl._select(unit)


func _select_next() -> void:
	input_ctl._select_next()


func _on_party_pick(unit) -> void:
	input_ctl._on_party_pick(unit)


func _refresh_depths() -> void:
	board_art._refresh_depths()


func _travel(target: Vector2i) -> void:
	roam_ctl._travel(target)


func _stop_selected() -> void:
	roam_ctl._stop_selected()


func _remove_view(unit) -> void:
	event_player._remove_view(unit)


func _rebuild_cell(cell: Vector2i) -> void:
	board_art._rebuild_cell(cell)


func _play_move(event: Dictionary) -> void:
	await event_player._play_move(event)


func _play_boss_fx(layers: Array, feet: Vector2) -> void:
	event_player._play_boss_fx(layers, feet)
