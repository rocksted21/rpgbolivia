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
const TOWN_PANELS_LAYER := 50
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
# Nas expedições, o chão são os tiles hex novos (assets/2 tiles topo) no lugar do chão contínuo.
# false volta ao chão de antes.
const TILES_2 := true
const ROW_STEP := 160
const HEX_MIDDLE := Vector2(93, 107)
const SIDE_HEIGHT := 29 # altura da lateral do tile; empilhar tiles a cada 29 px forma o penhasco
const LAYERS_PER_LEVEL := 4 # 116 px por nível; a altura é projetada na vertical
# Na exploração os degraus são mais baixos: num mapa gerado, uma casa atrás de um
# degrau precisa continuar visível e clicável.
const WORLD_LAYERS_PER_LEVEL := 3
const TOWN_LAYERS_PER_LEVEL := 2 # a planta da cidade conta com degraus baixos
const TOWN_GROUND_EDGE := 0.35 # calçada e grama com a borda mais limpa que no mato das expedições
const FOREST_HEIGHT := 1.65
const FEET := Vector2(93, 125)
const NO_CELL := Vector2i(-999999, -999999) # coordenadas negativas existem na exploração
const HOLD_TIME := 0.45
const WORLD_META := "world_hero" # o menu guarda aqui o herói escolhido para explorar
const EXPLORE_ZOOM := 0.8 # a câmera fica mais longe fora da arena; o resto da lista acompanha
const FOG_START := 650.0
const FOG_END := 1100.0
const PATH_COLOR := Color(0.27, 0.67, 1.0, 0.7)
const INSPECT_COLOR := Color(1.0, 1.0, 1.0, 0.95)
const ZOOM_IN := 1.25 # botão de zoom: aproximado; solto, volta ao padrão (1.0 na arena)
const PAN_LIMIT := 380.0 # quanto a câmera solta pode se afastar do foco
const XP_INK := Color(0.55, 0.9, 1.0)
const LEVEL_INK := Color(1.0, 0.85, 0.3)
const SkillTreeScene = preload("res://scenes/skill_tree.tscn")
# Giro em passos fixos (estilo FFT): parada a câmera está sempre num ângulo "bonito".
# 90° casa com as folhas de 16 vistas (4 quadros por passo) e com a arte chapada de frente.
const TURN_STEP := TAU / 4.0
const TURN_SNAP := 11.0 # quão rápido a câmera chega no próximo ângulo (~0,3 s)
const TURN_REPEAT := 0.45 # segurando Q/E: segundos entre um passo e outro
const TURN_DRAG_STEP := 0.35 # fração de um passo que o arrasto/torção precisa para girar
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
	"gota": {"impact": "sangue/water_drop", "impact_scale": 4.0, "ground": true, "sound": &"water"},
	"chicote_agua": {"impact": "sangue/water_whip", "impact_scale": 2.0, "lift": 90, "sound": &"water"},
	"bola_agua": {"projectile": "sangue/waterball", "projectile_turn": PI, "cast_sound": &"water", "impact": "sangue/splash", "impact_scale": 3.0, "ground": true, "sound": &"water"},
	"estaca_gelo": {"impact": "sangue/ice_spike", "impact_scale": 2.0, "ground": true, "sound": &"ice"},
	"cristal_gelo": {"impact": "sangue/ice_crystal", "impact_scale": 4.0, "ground": true, "sound": &"ice"},
	"floco_neve": {"impact": "sangue/snowflake", "impact_scale": 3.0, "lift": 60, "sound": &"ice"},
	"estilhaco_gelo": {"impact": "sangue/ice_burst", "impact_scale": 2.0, "per_cell": true, "lift": 40, "ring_delay": 0.12, "sound": &"ice"},
	"onda": {"impact": "sangue/splash", "impact_scale": 3.0, "per_cell": true, "ground": true, "ring_delay": 0.1, "sound": &"water"},
	"geiser": {"impact": "sangue/geyser", "impact_scale": 2.0, "ground": true, "sound": &"water"},
	"redemoinho": {"impact": "sangue/water_hurricane", "impact_scale": 3.0, "lift": 60, "sound": &"water"},
	"kraken": {"impact": "sangue/kraken", "impact_scale": 5.0, "lift": 120, "sound": &"water"},
	"chama": {"impact": "fogo/fire_pillar", "impact_scale": 2.0, "per_cell": true, "ground": true, "sound": &"flame"},
	"manto_agua": {"impact": "agua/splash", "impact_scale": 3.0, "ground": true, "sound": &"water"},
	"incinerar": {"impact": "fogo/fire", "impact_scale": 2.5, "ground": true, "sound": &"flame"},
	"rajada_calor": {"impact": "fogo/small_fire", "impact_scale": 5.0, "ground": true, "sound": &"fire_hit"},
	"toque_gelido": {"impact": "agua/ice_spike", "impact_scale": 1.6, "ground": true, "sound": &"ice"},
	"corrente": {"impact": "sangue/splash", "impact_scale": 2.5, "ground": true, "sound": &"water"},
	# Andarilho da Fumaça (pack de fumaça).
	"baforada": {"impact": "fumaca/horizontal_smoke", "impact_scale": 2.0, "lift": 70, "sound": &"swing"},
	"sufocar": {"impact": "fumaca/rising_smoke", "impact_scale": 3.0, "lift": 100, "sound": &"swing"},
	"nuvem_cega": {"impact": "fumaca/circle_smoke", "impact_scale": 3.0, "lift": 40, "ring_delay": 0.1, "sound": &"swing"},
	"veu_fumaca": {"impact": "fumaca/smoke_ring", "impact_scale": 3.0, "ground": true, "sound": &"swing"},
	"passo_fumaca": {"impact": "fumaca/falling_smoke", "impact_scale": 2.5, "ground": true, "sound": &"swing"},
	"cranio_fumaca": {"impact": "fumaca/smoke_skull", "impact_scale": 4.0, "lift": 120, "sound": &"explosion"},
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
var move_tiles := {} # casa -> [preenchimento, borda], criados só quando aparecem
var move_shown: Array[Vector2i] = []
var move_pulse := 0.0
var forests := {}
var trees := {} # árvores soltas do mapa: ficam transparentes quando escondem alguém
var active_outline: Line2D
var inspect_outline: Line2D
var busy := true
var hover := NO_CELL
var menu_cell := NO_CELL # casa com o menu aberto
var jump_mode := false # J (ou "Pular" no menu do herói): o próximo clique numa casa verde pula
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
var town_crew # na cidade (solo): os heróis que não são o líder cuidam da vida (ver battle/town_crew.gd)
var models := {} # construções em 3D à vista: {sprite: {views, turn}}
var model_meta := {}
var natural := false # chão contínuo: expedições e jornada, sem a cidade
var world_light # luz e partículas das expedições e da jornada
var cell_tint := Color.WHITE # tom da casa em construção
var person_labels := {}
var quests_finished := []
var landmark_nodes := {} # casa: marcas no mapa de um local especial
var selected # o herói que recebe os cliques fora de combate
var my_fight := false # online: algum herói meu está na luta atual (as lutas dos outros não me prendem)
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
var view_target := 0.0 # ângulo fixo para onde a câmera está indo (múltiplo de TURN_STEP)
var turn_last := 0 # direção apertada no quadro anterior: o passo sai ao apertar, não a cada quadro
var turn_repeat := 0.0 # segurando, outro passo sai quando zera
var turn_drag := 0.0 # arrasto/torção acumulado até valer um passo
var tall_props := {} # construções grandes: {sprite: pé no tabuleiro}; ficam transparentes quando cobrem alguém
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
var zoomed := false
var pan := Vector2.ZERO # deslocamento da câmera arrastada, em coordenadas do tabuleiro
var press_pos := Vector2.ZERO
var drag_ok := false # o toque começou numa casa sem inimigo, com zoom
var dragging := false
var touches := {} # dedo -> posição na tela
var gesture := {} # dois dedos: ângulo e distância de partida
var hit_from := Vector2.ZERO
var fight_kills := 0 # inimigos derrotados na luta atual: viram experiência no fim dela
var fight_boss := false
var tree_layer: CanvasLayer # árvore de talentos aberta por cima do jogo # de onde veio o último golpe, para o tranco de quem apanha
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
	for type_id in Data.UNIT_TYPES: # variações usam a folha de outro tipo
		if not meta.has(type_id) and meta.has(Data.art(type_id)):
			meta[type_id] = meta[Data.art(type_id)]
	fx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/meta.json"))
	_start_battle()
	online_session.match_started.connect(_on_room_opened)
	online_session.relocated.connect(_on_relocated)
	if online_session.playing:
		_go_online()
		net_bridge._network_packet({})


## Liga a cena à sala: comandos, pacotes e quem joga com cada herói.
func _go_online() -> void:
	if not online_session.command_received.is_connected(net_bridge._network_command):
		online_session.command_received.connect(net_bridge._network_command)
		online_session.packet_received.connect(net_bridge._network_packet)
		online_session.connection_lost.connect(net_bridge._network_lost)
		online_session.changed.connect(net_bridge._room_status)
		online_session.player_arrived.connect(_on_player_arrived)
		online_session.progress_received.connect(_on_progress_received)
		online_session.hero_learned.connect(_on_hero_learned)
		online_session.world_progress.connect(_update_party_progress)
	hud.save_allowed = online_session.relay.is_master
	hud.load_allowed = false
	net_bridge._room_status()


## A jornada que estava rolando virou sala (botão Grupo): o dono segue jogando com todos.
func _on_room_opened() -> void:
	if online_session.state != state:
		return
	_go_online()
	hud.show_banner("Sala aberta: %s" % online_session.relay.room_code, LEVEL_INK)
	_open_group()


## Alguém entrou no meio: recebe a partida e o dono já vê a janela para dar um herói a ele.
func _on_player_arrived(id: int) -> void:
	online_session.publish([], not busy, _free_roam())
	hud.show_banner("%s entrou na sala" % online_session.players.get(id, "Jogador"), Color(0.6, 1.0, 0.6))
	sound_manager.play_ui(&"switch3")
	_open_group()


func _open_group() -> void:
	var heroes := []
	for unit in state.party:
		heroes.append({"unit": unit, "type_id": unit.type_id, "owner": online_session.owner_of(unit) if online_session.playing else 0})
	hud.show_group({
		"online": online_session.playing, "is_host": online_session.playing and online_session.relay.is_master,
		"code": online_session.relay.room_code, "players": online_session.players if online_session.playing else {}, "heroes": heroes,
	})


func _open_room() -> void:
	if online_session.playing or expedition or town or state.winner() >= 0:
		return
	hud.show_banner("Abrindo sala…", Color(0.8, 0.9, 1.0))
	online_session.open_existing(state)


## Dono fecha a sala e continua jogando sozinho; quem não é dono volta para o lobby.
func _leave_room() -> void:
	if not online_session.playing:
		return
	if not online_session.relay.is_master:
		net_bridge._leave_online()
		return
	for signal_name in ["command_received", "packet_received", "connection_lost", "changed", "player_arrived", "progress_received", "hero_learned", "world_progress"]:
		for connection in online_session.get_signal_connection_list(signal_name):
			if connection["callable"].get_object() == self:
				online_session.disconnect(signal_name, connection["callable"])
	online_session.leave()
	hud.save_allowed = true
	hud.load_allowed = true
	hud.set_party_owners({})
	_update_party_progress()
	input_ctl._refresh_end_turn()
	journey_ui._update_journey()


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
	town = get_tree().root.get_meta(TOWN_META, false)
	expedition = false
	if online_session.playing: # online: o mapa vem da sala
		town = online_session.state is TownState
	if town:
		music_manager.play_menu()
	else:
		music_manager.play_combat()
	level_layers = LAYERS_PER_LEVEL
	if exploring:
		level_layers = TOWN_LAYERS_PER_LEVEL if town else WORLD_LAYERS_PER_LEVEL
	if online_session.playing:
		state = online_session.state
		expedition = state is ExpeditionState
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
			town_mode._restore_spot()
		elif expedition:
			state = ExpeditionState.new(party_types, randi(), builds, TownProgress.expedition_setup())
		else:
			state = WorldState.new(party_types, randi(), builds)
	else:
		state = BattleState.from_data(_saved_builds())
	if exploring and "split_fights" in state:
		# Só luta quem está perto; herói longe segue livre e entra chegando perto ou atacando.
		state.split_fights = true
		if state.in_combat() and state.fighting.is_empty(): # save antigo, de antes das lutas separadas
			for member in state.alive_party():
				state.fighting[member] = true
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
	fight_kills = 0
	fight_boss = false
	zoomed = false
	pan = Vector2.ZERO
	dragging = false
	touches.clear()
	gesture = {}
	roam_from = NO_CELL
	together = true # a cidade desliga a fila (só o líder anda); fora dela volta ao padrão do botão
	selected = _first_mine() if exploring else null
	camera_unit = selected
	views.clear()
	cell_nodes.clear()
	z_origin = 0
	overlays.clear()
	reach_lines.clear()
	move_tiles.clear()
	move_shown.clear()
	forests.clear()
	trees.clear()
	tall_props.clear()
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
	town_crew = null
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
	natural = exploring and (town or not TILES_2)
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
	hud.jump_pressed.connect(func(): input_ctl._set_jump_mode(not jump_mode))
	hud.restart_pressed.connect(net_bridge._leave_online if online_session.playing else (_back_to_menu if expedition else _start_battle))
	hud.skills_pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	hud.save_allowed = not online_session.playing or online_session.relay.is_master
	hud.load_allowed = not online_session.playing
	hud.options_toggled.connect(func(open): get_tree().paused = open and not online_session.playing)
	hud.save_pressed.connect(_save_game)
	hud.load_pressed.connect(_load_game)
	hud.quit_pressed.connect(_quit_to_title)
	hud.zoom_toggled.connect(_set_zoomed)
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
		_update_party_progress()
		hud.show_group_button(online_session.playing or (not expedition and not town))
		hud.group_pressed.connect(_open_group)
		hud.open_room_pressed.connect(_open_room)
		hud.leave_room_pressed.connect(_leave_room)
		hud.group_assign.connect(func(unit, id):
			online_session.assign(unit, id)
			_open_group())
		hud.party_pressed.connect(input_ctl._on_party_pick)
		hud.level_up_pressed.connect(input_ctl._on_level_up_pick)
		hud.rotate_held.connect(func(direction): turn_hold = direction)
		hud.together_toggled.connect(func(on): together = on)
		if town:
			town_mode._start_crew()
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
		if exploring and state.in_combat() and not _free_roam():
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
	jump_mode = false
	busy = true
	input_ctl._refresh_end_turn()
	input_ctl._close_menu()
	hud.set_hint("")
	marks_ctl._refresh_overlays()
	await event_player._play(events)
	_advance()


func _base_zoom() -> float:
	return EXPLORE_ZOOM if exploring else 1.0


## Botão, Z, roda do mouse ou pinça: aproxima para 1.25 e libera o arrasto; soltar recentra.
func _set_zoomed(on: bool) -> void:
	if on == zoomed or battle_camera == null:
		return
	zoomed = on
	battle_camera.set_zoom(ZOOM_IN if on else _base_zoom())
	if not on:
		_pan_by(Vector2.ZERO, true)
	hud.set_zoomed(on)


## Move a câmera pelo arrasto na tela. A tela é o chão girado e achatado: desfaz os dois.
func _pan_by(screen_delta: Vector2, reset := false) -> void:
	var before := pan
	if reset:
		pan = Vector2.ZERO
	else:
		var ground: Vector2 = Vector2(screen_delta.x, screen_delta.y / BattleCamera.GROUND_TILT) / battle_camera.zoom
		pan = (pan + ground.rotated(-view_angle)).limit_length(PAN_LIMIT)
	if not exploring:
		board.position = BOARD_POS + pan
	elif not reset:
		board.position += pan - before # na hora, sem a suavização de seguir o herói


## Vida e vez de quem está na casa, para a barra e o selo do menu.
func _menu_status(occupant) -> Dictionary:
	if occupant == null:
		return {}
	var aware: bool = state.takes_turns(occupant)
	return {"hp": occupant.hp, "max_hp": occupant.max_hp, "unaware": not aware, "order": state.turn_order().find(occupant) + 1 if aware else 0}


# --- Exploração --------------------------------------------------------------

## Fora de combate: o herói anda livre, sem fila de turnos.
func _free_roam() -> bool:
	if not exploring or not state.in_combat():
		return exploring
	if not state.split_fights:
		return false
	# Solo: o herói escolhido na barra, se está longe da luta, anda livre enquanto ela espera.
	if not online_session.playing:
		return selected != null and selected.alive() and state.is_hero(selected) and not state.is_fighting(selected)
	# Online: só fico preso aos turnos se algum herói meu estiver nesta luta.
	return not state.party.any(func(u): return online_session.can_control(u) and state.is_fighting(u))


## O herói que recebe as ordens agora: o selecionado fora de combate, o da vez em combate.
func _actor():
	if not _free_roam():
		return state.active_unit()
	if selected == null or not selected.alive():
		selected = _first_mine()
	return selected


func _first_mine():
	var living: Array = state.alive_party()
	if exploring and state.in_combat(): # com luta, quem está nela vem primeiro
		living.sort_custom(func(a, b): return state.is_fighting(a) and not state.is_fighting(b))
	for member in living:
		if online_session.can_control(member):
			return member
	return living[0] if not living.is_empty() else state.hero


# --- Câmera --------------------------------------------------------------------

func _process(delta: float) -> void:
	marks_ctl._pulse_moves(delta)
	if not exploring or board == null:
		return
	_update_turn(delta)
	roam_ctl._update_walks(delta)
	if town and selected != null:
		town_panels.set_nearby(state.person_near(selected.pos))
	if town_crew != null:
		town_crew.tick(delta)
	var goal: Vector2 = camera_look if camera_look != null else BattleCamera.FOCUS - _camera_point() * BOARD_SCALE + pan
	board.position = board.position.lerp(goal, 1.0 - exp(-delta * CAMERA_SPEED))
	board_art._fade_tall_props(delta)
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
	pan = Vector2.ZERO
	_set_camera(unit.pos)


func _set_camera(cell: Vector2i) -> void:
	camera_cell = cell
	board_art._sync_world(cell, false)
	board_art._rebase_depth(_row(cell))


## Em combate a câmera vai até cada herói da vez, e até o inimigo que estiver fora de vista.
func _focus_turn(unit) -> void:
	if state.is_hero(unit) or Hex.distance(unit.pos, camera_cell) > 6:
		_follow(unit)


## Q/E ou o botão da tela: cada toque gira um passo; segurando, repete. A câmera
## desliza rápido até o ângulo fixo e para exatamente nele.
func _update_turn(delta: float) -> void:
	var direction := turn_hold
	if Input.is_key_pressed(KEY_Q):
		direction -= 1
	if Input.is_key_pressed(KEY_E):
		direction += 1
	direction = clampi(direction, -1, 1)
	turn_repeat -= delta
	if direction != 0 and (direction != turn_last or turn_repeat <= 0.0):
		turn_step(direction)
		turn_repeat = TURN_REPEAT
	turn_last = direction
	var gap := angle_difference(view_angle, view_target)
	if gap != 0.0:
		if absf(gap) < 0.002:
			_set_view_angle(view_target)
			marks_ctl._refresh_overlays() # chegou: árvores e casas revisam quem escondem
		else:
			_set_view_angle(view_angle + gap * (1.0 - exp(-delta * TURN_SNAP)))
	map_refresh -= delta


## Um passo de giro para a esquerda (-1) ou direita (1), a partir do ângulo de destino.
func turn_step(direction: int) -> void:
	view_target = fposmod(snappedf(view_target, TURN_STEP) + direction * TURN_STEP, TAU)


## Arrasto do mouse ou torção de dois dedos: soma até valer um passo e então gira.
func drag_turn(amount: float) -> void:
	turn_drag += amount
	if absf(turn_drag) >= TURN_STEP * TURN_DRAG_STEP:
		turn_step(1 if turn_drag > 0.0 else -1)
		turn_drag = 0.0


func _set_view_angle(angle: float) -> void:
	view_angle = fposmod(angle, TAU)
	battle_camera.set_view_angle(view_angle)
	board_art._show_facing_walls()
	board_art._refresh_depths()
	board_art._update_model_frames()
	if expedition and hud != null:
		journey_ui._update_journey() # a bússola do painel gira junto
	if map_refresh <= 0.0:
		map_refresh = MAP_REFRESH
		board_art._sync_world(camera_cell, false)


## Linha de desenho da casa, em meias linhas: nos ângulos livres as casas não ficam alinhadas.
func _row(cell: Vector2i) -> int:
	if not exploring:
		return cell.y
	var flat := Vector2(_column_x(cell), cell.y * ROW_STEP).rotated(view_angle)
	return roundi(flat.y * 2.0 / ROW_STEP)


## Heróis de pé que ganham experiência no save daqui. Online o mundo é do dono da sala:
## ele sobe todos os heróis no save dele; os outros só veem o aviso.
func _my_living_heroes() -> Array:
	if online_session.playing and not online_session.relay.is_master:
		return []
	return state.units.filter(func(unit): return unit.team == Data.Team.PLAYER and unit.alive() and Skills.has_tree(unit.type_id))


## Fim de uma luta: "+N XP" sobe da cabeça de cada herói e, se alguém subiu, "LEVEL UP!".
## A carta dele lá embaixo passa a mostrar os pontos para gastar.
func _reward_fight(bonus := 0) -> void:
	var amount := fight_kills * Skills.HERO_KILL_XP + (Skills.HERO_BOSS_XP if fight_boss else 0) + bonus
	fight_kills = 0
	fight_boss = false
	var heroes := _my_living_heroes()
	if amount <= 0 or heroes.is_empty():
		return
	var raised := HeroProgress.add_xp(heroes.map(func(unit): return unit.type_id), amount)
	for unit in heroes:
		if views.has(unit):
			hero_fx._pop_number(views[unit].position, "+%d XP" % amount, XP_INK, 0.8)
	_update_party_progress()
	_report_progress(heroes.map(func(unit): return unit.type_id), amount, raised)
	if raised.is_empty():
		return
	await get_tree().create_timer(0.7).timeout
	sound_manager.play_sfx(&"heal")
	for unit in heroes:
		if unit.type_id in raised and views.has(unit):
			hero_fx._pop_number(views[unit].position, "LEVEL UP!", LEVEL_INK, 1.3, "Nv %d" % HeroProgress.level(unit.type_id))
	hud.show_banner("Level up!", LEVEL_INK)
	await get_tree().create_timer(0.6).timeout


## Nível, barra de experiência e pontos livres nas cartas dos heróis.
## Online vêm do save do dono da sala (quem entrou recebe uma cópia dele).
func _update_party_progress() -> void:
	if not exploring:
		return
	for unit in state.party:
		hud.set_party_progress(unit, HeroProgress.level_info(unit.type_id), HeroProgress.available(unit.type_id), online_session.can_control(unit))


## Online: conta para a sala o nível dos meus heróis. `raised`: quem acabou de subir.
func _report_progress(type_ids: Array, xp_gain := 0, raised := []) -> void:
	if not online_session.playing:
		return
	var entries := []
	for type_id in type_ids:
		if not Skills.has_tree(type_id):
			continue
		var info := HeroProgress.level_info(type_id)
		entries.append({hero = type_id, level = info["level"], fraction = info["fraction"], max = info["max"],
			points = HeroProgress.available(type_id), xp = xp_gain, up = type_id in raised})
	online_session.report_progress(entries)


func _my_party_types() -> Array:
	return state.party.filter(func(unit): return online_session.can_control(unit)).map(func(unit): return unit.type_id)


## Herói de outro jogador ganhou XP ou subiu: todo mundo vê.
func _on_progress_received(entry: Dictionary) -> void:
	_update_party_progress()
	var unit = null
	for member in state.party:
		if member.type_id == entry["hero"]:
			unit = member
	if unit == null or not views.has(unit):
		return
	if entry["xp"] > 0:
		hero_fx._pop_number(views[unit].position, "+%d XP" % entry["xp"], XP_INK, 0.8)
	if entry["up"]:
		await get_tree().create_timer(0.7).timeout
		if not views.has(unit):
			return
		sound_manager.play_sfx(&"heal")
		hero_fx._pop_number(views[unit].position, "LEVEL UP!", LEVEL_INK, 1.3, "Nv %d" % entry["level"])
		hud.show_banner("%s subiu de nível!" % unit.display_name, LEVEL_INK)


## Online: o dono da sala confirmou o nó; todos aplicam no herói, e quem comprou atualiza a carta.
func _on_hero_learned(type_id: String, node_id: String) -> void:
	_apply_bought_node(type_id, node_id)
	if online_session.relay.is_master:
		online_session.publish([], not busy, _free_roam())
	if type_id in _my_party_types():
		_report_progress([type_id])


## Árvore de talentos por cima do jogo, só com os heróis da party. O que for comprado vale na hora.
## Online, só os heróis com que eu jogo: o nó vai para o dono da sala, que avisa todos.
func _open_tree(unit) -> void:
	if tree_layer != null:
		return
	var mine: Array = _my_party_types().filter(func(type_id): return Skills.has_tree(type_id))
	if mine.is_empty():
		return
	tree_layer = CanvasLayer.new()
	tree_layer.layer = TOWN_PANELS_LAYER + 10
	add_child(tree_layer)
	var screen = SkillTreeScene.instantiate()
	screen.embedded = true
	screen.live = true
	screen.start_hero = unit.type_id if unit.type_id in mine else mine[0]
	screen.only_heroes = mine
	screen.bought.connect(online_session.learn if online_session.playing else _apply_bought_node)
	screen.closed.connect(func():
		tree_layer.queue_free()
		tree_layer = null
		_update_party_progress())
	tree_layer.add_child(screen)


func _apply_bought_node(type_id: String, node_id: String) -> void:
	var found: Dictionary = Skills.locate(type_id, node_id)
	for i in state.party.size():
		var member = state.party[i]
		if member.type_id != type_id or found.is_empty():
			continue
		if state.builds_used is Dictionary and node_id in state.builds_used.get(i, []):
			continue # já está no herói (o aviso da rede chegou de novo)
		member._apply_node(found["node"])
		if state.builds_used is Dictionary:
			var build: Array = state.builds_used.get(i, [])
			build.append(node_id)
			state.builds_used[i] = build
		if views.has(member):
			views[member].set_hp(member.hp)
	_update_party_progress()
	hud.update_party(selected if _free_roam() else state.active_unit())


func _back_to_menu() -> void:
	if online_session.playing and expedition: # online: volta todo mundo para a cidade
		if online_session.relay.is_master:
			online_session.relocate(TownState.new(town_mode._party_types(), randi(), online_session.match_builds(), TownProgress.expedition_setup()))
		return
	if expedition:
		_start_battle() # o fim da expedição já deixou a volta para a cidade marcada
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Menu de opções ------------------------------------------------------------

func _save_game() -> void:
	if (online_session.playing and not online_session.relay.is_master) or state.winner() >= 0:
		return
	if SaveGame.save(state):
		hud.show_options_note("Jogo salvo!")
		hud.load_button.disabled = false
		hud.load_button.text = "Carregar jogo\n%s" % SaveGame.summary()
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


## Online: o dono trocou de mapa; todo mundo refaz a cena com o estado novo.
func _on_relocated() -> void:
	_start_battle()
	if online_session.playing:
		_go_online()
		net_bridge._network_packet({})


# --- Repasses ---------------------------------------------------------------
# Outros scripts e os testes chamam estas funções na tela; o código mora nos módulos.

func _update_journey() -> void:
	journey_ui._update_journey()


func _rebase_depth(row: int) -> void:
	board_art._rebase_depth(row)


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
