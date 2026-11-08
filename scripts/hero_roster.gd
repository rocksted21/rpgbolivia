extends RefCounted
## Roster: quem já pode entrar na party. A cidade começa com Data.DEFAULT_PARTY; os outros
## heróis são recrutados nas expedições (ver recruits.gd) e ficam salvos em town_progress.gd.
## Trancados aparecem como silhueta "?" na escolha da party, na árvore de skills e no lobby.

const Data = preload("res://scripts/game_data.gd")
const TownProgress = preload("res://scripts/town_progress.gd")
const HeroProgress = preload("res://scripts/hero_progress.gd")

const LOCKED_NAME := "???"
const LOCKED_TINT := Color(0.0, 0.0, 0.0, 0.85) # silhueta: o retrato fica preto
## Dica curta de onde cada herói trancado está (sem história: só para onde ir).
const HINTS := {
	"fumaca": "Uma névoa que não se dissipa, num parque dos Subúrbios.",
	"besteiro": "Preso numa das vilas dos Subúrbios.",
	"mago_agua": "Espera num Desafio de Arena, o mais longe da entrada dos Subúrbios.",
}


## Já está no roster? Os do começo, os recrutados e, de saves antigos, quem já tem experiência.
static func is_unlocked(type_id: String) -> bool:
	if type_id in Data.DEFAULT_PARTY or type_id in TownProgress.recruited_heroes():
		return true
	return HeroProgress.xp(type_id) > 0


static func unlocked() -> Array:
	return Data.WORLD_HEROES.filter(func(type_id): return is_unlocked(type_id))


static func hint(type_id: String) -> String:
	return HINTS.get(type_id, "Ainda não se juntou à party.")
