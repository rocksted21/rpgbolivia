extends SceneTree

const HeroProgress = preload("res://scripts/hero_progress.gd")
const Skills = preload("res://scripts/skill_data.gd")


func _initialize() -> void:
	HeroProgress.path = "user://test_new_game_progress.cfg"
	HeroProgress.add_xp(Skills.hero_types(), 120)
	assert(HeroProgress.level("mago") > 1)
	assert(HeroProgress.new_game() == OK)
	for type_id in Skills.hero_types():
		assert(HeroProgress.xp(type_id) == 0)
		assert(HeroProgress.level(type_id) == 1)
		assert(HeroProgress.level_info(type_id).fraction == 0.0)
		assert(HeroProgress.earned(type_id) == Skills.START_POINTS)
		assert(HeroProgress.unlocked(type_id).is_empty())
	HeroProgress.add_xp(["mago"], 30)
	assert(HeroProgress.level("mago") == 2)
	assert(HeroProgress.new_game() == OK)
	assert(HeroProgress.level("mago") == 1 and HeroProgress.xp("mago") == 0)
	DirAccess.remove_absolute(HeroProgress.path)
	print("Novo jogo: todos os heróis no nível 1, 0 EXP; reinício e ganho de EXP corretos.")
	quit()
