extends SceneTree
## Monta o grupo Combate do SoundManager.tscn a partir de assets/audio/combate.
## Cada som é um player com AudioStreamRandomizer: toca uma variação sorteada,
## com o tom levemente diferente, para não cansar o ouvido.
## Rodar com: godot --headless --path combate --script tools/build_audio.gd

const SCENE := "res://scenes/SoundManager.tscn"
const DIR := "res://assets/audio/combate/"
const GROUP := "Combate"

# nome do som: [arquivos (sem .wav), volume em dB]
const CUES := {
	"swing": [["swish-1", "swish-2", "swish-3", "swish-4", "swish-5", "swish-6", "swish-7", "swish-8", "swish-9", "swish-10", "swish-11", "swish-12", "swish-13"], -4.0],
	"arrow_hit": [["arrowHit01", "arrowHit02", "arrowHit03", "arrowHit04", "arrowHit05", "arrowHit06", "arrowHit07", "arrowHit08"], -6.0],
	"melee_hit": [["sfx_wpn_sword1", "sfx_wpn_sword2", "sfx_wpn_sword3", "sfx_wpn_punch1", "sfx_wpn_punch2", "sfx_wpn_punch3"], -10.0],
	"hurt": [["sfx_damage_hit1", "sfx_damage_hit3", "sfx_damage_hit5", "sfx_damage_hit6", "sfx_damage_hit7", "sfx_damage_hit8", "sfx_damage_hit10"], -14.0],
	"fire_cast": [["sfx_wpn_missilelaunch"], -12.0],
	"fire_hit": [["sfx_exp_short_hard1", "sfx_exp_short_hard2", "sfx_exp_short_hard3", "sfx_exp_short_hard4", "sfx_exp_short_hard6", "sfx_exp_short_hard8", "sfx_exp_short_hard12", "sfx_exp_short_hard14", "sfx_exp_short_hard17"], -10.0],
	"explosion": [["sfx_exp_cluster2", "sfx_exp_cluster3", "sfx_exp_cluster6", "sfx_exp_cluster7"], -8.0],
	"flame": [["sfx_exp_medium3", "sfx_exp_medium8", "sfx_exp_medium10"], -10.0],
	"water": [["sfx_exp_shortest_soft1", "sfx_exp_shortest_soft2", "sfx_exp_shortest_soft3", "sfx_exp_shortest_soft4", "sfx_exp_shortest_soft5"], -8.0],
	"ice": [["sfx_sounds_high2", "sfx_sounds_high3", "sfx_sounds_high4", "sfx_sounds_high5", "sfx_sounds_high7", "sfx_sound_bling"], -12.0],
	"charge": [["sfx_movement_portal3", "sfx_movement_portal5"], -14.0],
	"heal": [["sfx_sounds_powerup3", "sfx_sounds_powerup8", "sfx_sounds_powerup11", "sfx_sounds_powerup13"], -12.0],
	"guard": [["sfx_sounds_impact10", "sfx_sounds_impact11", "sfx_sounds_impact12"], -12.0],
	"step": [["sfx_movement_footsteps1a", "sfx_movement_footsteps1b"], -12.0],
	"death_hero": [["sfx_deathscream_human1", "sfx_deathscream_human2", "sfx_deathscream_human3", "sfx_deathscream_human4", "sfx_deathscream_human5", "sfx_deathscream_human6", "sfx_deathscream_human7", "sfx_deathscream_human8", "sfx_deathscream_human9", "sfx_deathscream_human10", "sfx_deathscream_human11", "sfx_deathscream_human12", "sfx_deathscream_human13", "sfx_deathscream_human14"], -10.0],
	"death_monster": [["sfx_deathscream_alien2", "sfx_deathscream_alien3", "sfx_deathscream_alien4", "sfx_deathscream_alien5", "sfx_deathscream_alien6"], -10.0],
	"victory": [["sfx_sounds_fanfare1"], -8.0],
	"defeat": [["sfx_sounds_negative1"], -8.0],
}
const PITCH := 1.08 # variação de tom entre uma tocada e outra


func _initialize() -> void:
	var manager: Node = load(SCENE).instantiate()
	var old := manager.get_node_or_null(GROUP)
	if old != null:
		manager.remove_child(old)
		old.free()

	var group := Node.new()
	group.name = GROUP
	group.set_script(load("res://scripts/audio_group.gd"))
	group.set("bus_name", StringName(GROUP))
	manager.add_child(group)
	group.owner = manager

	for cue in CUES:
		var random := AudioStreamRandomizer.new()
		random.random_pitch = PITCH
		for file in CUES[cue][0]:
			random.add_stream(-1, load(DIR + file + ".wav"))
		var player := AudioStreamPlayer.new()
		player.name = cue
		player.stream = random
		player.volume_db = CUES[cue][1]
		player.max_polyphony = 6
		player.bus = StringName(GROUP)
		group.add_child(player)
		player.owner = manager

	var packed := PackedScene.new()
	packed.pack(manager)
	ResourceSaver.save(packed, SCENE)
	manager.free()
	print("sons de combate: ", CUES.size())
	quit()
