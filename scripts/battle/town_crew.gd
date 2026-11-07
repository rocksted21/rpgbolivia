extends RefCounted

## Na Cidade-Farol o jogador anda só com o líder (o primeiro da party). Os outros heróis
## cuidam da vida: cada um tem os lugares de que gosta, vai até lá, fica um tempo, dá umas
## voltas e às vezes fala alguma coisa. Só no jogo solo; online cada jogador anda com o seu.

const Hex = preload("res://scripts/hex.gd")
const Town = preload("res://scripts/town_data.gd")

const FIRST_WAIT := Vector2(0.6, 2.4) # ao chegar na cidade, cada um sai num tempo diferente
const IDLE_TIME := Vector2(5.0, 11.0) # parado num lugar antes de dar uma volta
const STAYS := Vector2i(2, 4) # quantas voltas dá num lugar antes de ir para outro
const SPOT_RADIUS := 2 # fica até essa distância do lugar (o morador ocupa a casa do meio)
const CHAT_PAUSE := Vector2(6.0, 12.0)
const CHAT_RADIUS := 8 # só fala quem está perto do líder: o balão aparece na tela
const BUBBLE_HEIGHT := 205.0 # acima da cabeça de um herói

# Lugares de cada herói. "near": id de morador, ou nome da arte de um prédio/enfeite
# (scenes/cidade.tscn). Lugar de morador que ainda não foi resgatado fica de fora.
const SPOTS := {
	"guardiao": [
		{"near": "mestre", "lines": ["Escudo alto! De novo!", "O Mestre não perdoa um passo errado.", "Ombro dói, mas a guarda melhorou."]},
		{"near": "fonte", "lines": ["Tudo calmo por aqui.", "Ninguém passa sem eu ver.", "Durmo depois. Agora é vigia."]},
	],
	"duelista": [
		{"near": "taverneira", "lines": ["Mais uma rodada, por favor!", "Aposto que acerto a rolha daqui.", "Alguém topa um duelo de cartas?"]},
		{"near": "mercadora", "lines": ["Bonita lâmina... cara demais.", "Só olhando, só olhando.", "Desconto para heroína?"]},
	],
	"besteiro": [
		{"near": "pescador", "lines": ["Vento leste. Bom para atirar.", "Daqui eu acerto aquela boia.", "Peixe grande hoje?"]},
		{"near": "mural", "lines": ["Hm, recompensa boa nesse aqui.", "Alguém já leu este cartaz?"]},
	],
	"mago": [
		{"near": "guarda", "lines": ["Essa chama... nunca vi fogo assim.", "Posso só encostar? Não? Tá.", "O farol tem mais magia que eu."]},
		{"near": "fogueira_a", "lines": ["Fogueira boa é fogueira grande.", "Quase acendi sem querer de novo."]},
	],
	"mago_agua": [
		{"near": "sacerdotisa", "lines": ["A capela é silenciosa demais.", "Sangue também pode curar.", "Rezo do meu jeito."]},
		{"near": "alquimista", "lines": ["Esse frasco ferve estranho.", "Troco uma receita pela sua."]},
	],
	"druida": [
		{"near": "horta", "lines": ["Essas folhas precisam de sol.", "A terra daqui ainda está triste.", "Cresçam, pequenas."]},
		{"near": "curandeira", "lines": ["Erva-de-luz para os feridos.", "Ela cura rápido. Eu aprendo."]},
		{"near": "fonte", "lines": ["A água da fonte está limpa.", "Ouço o rio daqui."]},
	],
	"fumaca": [
		{"near": "viajante", "lines": ["...", "Já vi essa estrada antes.", "A fumaça conta histórias."]},
		{"near": "mural", "lines": ["Sumir é fácil. Achar é que é difícil.", "Ninguém me viu ler isto."]},
	],
}
const ANYWHERE := [ # herói sem lugar próprio
	{"near": "fonte", "lines": ["Que noite comprida.", "Bom descansar um pouco."]},
	{"near": "taverneira", "lines": ["Uma caneca e eu fico novo."]},
]

var battle # a tela dona deste módulo
var mates := [] # {unit, spots, spot, anchor, stay, wait}
var chat_wait := 0.0


func _init(host: Node) -> void:
	battle = host


## O líder é o primeiro da party; os outros ganham seus lugares na cidade.
func setup() -> void:
	mates.clear()
	chat_wait = randf_range(CHAT_PAUSE.x, CHAT_PAUSE.y)
	var party: Array = battle.state.party
	for i in range(1, party.size()):
		var spots := _spots_for(party[i].type_id)
		if spots.is_empty():
			continue
		mates.append({"unit": party[i], "spots": spots, "spot": -1, "anchor": Vector2i.ZERO, "stay": 0,
			"wait": randf_range(FIRST_WAIT.x, FIRST_WAIT.y)})


func leader():
	return battle.state.party[0] if not battle.state.party.is_empty() else null


func is_mate(unit) -> bool:
	return mates.any(func(mate): return mate["unit"] == unit)


## Tocar num companheiro (no mapa ou na carta) faz ele falar do que está fazendo.
func poke(unit) -> void:
	for mate in mates:
		if mate["unit"] == unit:
			_say(mate)
			return


func tick(delta: float) -> void:
	for mate in mates:
		var unit = mate["unit"]
		if not unit.alive() or battle.walk_paths.has(unit) or battle.moving.has(unit):
			continue
		mate["wait"] -= delta
		if mate["wait"] > 0.0:
			continue
		mate["wait"] = randf_range(IDLE_TIME.x, IDLE_TIME.y)
		if mate["stay"] > 0 and mate["spot"] >= 0:
			mate["stay"] -= 1
			_walk_near(mate, mate["anchor"], 1) # uma volta curta perto de onde está
		else:
			_next_spot(mate)
	chat_wait -= delta
	if chat_wait <= 0.0:
		chat_wait = randf_range(CHAT_PAUSE.x, CHAT_PAUSE.y)
		_chat()


func _next_spot(mate: Dictionary) -> void:
	var spots: Array = mate["spots"]
	var pick: int = (mate["spot"] + 1 + randi() % maxi(1, spots.size() - 1)) % spots.size() if spots.size() > 1 else 0
	mate["spot"] = pick
	mate["anchor"] = spots[pick]["cell"]
	mate["stay"] = randi_range(STAYS.x, STAYS.y)
	_walk_near(mate, mate["anchor"], SPOT_RADIUS)


## Vai até uma casa livre perto do lugar. Sem caminho, fica onde está e tenta depois.
func _walk_near(mate: Dictionary, anchor: Vector2i, radius: int) -> void:
	var unit = mate["unit"]
	var state = battle.state
	var taken := []
	for other in mates:
		if other != mate and battle.walk_goals.has(other["unit"]):
			taken.append(battle.walk_goals[other["unit"]])
	var spots: Array = state.area_of(anchor, radius).filter(func(cell):
		return cell != unit.pos and Hex.distance(cell, anchor) >= 1 and state.tile_at(cell)["walkable"] \
			and state.unit_at(cell) == null and cell not in taken)
	if spots.is_empty():
		return
	spots.shuffle()
	var found: Dictionary = state.search(unit)
	for cell in spots:
		if found["cost"].has(cell):
			battle.roam_ctl._start_file(unit, [], cell)
			return


func _chat() -> void:
	var lead = leader()
	if lead == null or battle.town_life == null:
		return
	var near := mates.filter(func(mate):
		return mate["unit"].alive() and mate["spot"] >= 0 and not battle.moving.has(mate["unit"]) \
			and Hex.distance(mate["unit"].pos, lead.pos) <= CHAT_RADIUS)
	if not near.is_empty():
		_say(near[randi() % near.size()])


func _say(mate: Dictionary) -> void:
	if battle.town_life == null:
		return
	var spot: Dictionary = mate["spots"][maxi(mate["spot"], 0)]
	var lines: Array = spot["lines"]
	battle.town_life.say(mate["unit"].pos, lines[randi() % lines.size()], BUBBLE_HEIGHT)


## Os lugares do herói que existem nesta cidade, já com a casa de cada um.
func _spots_for(type_id: String) -> Array:
	var out := []
	for spot in SPOTS.get(type_id, ANYWHERE):
		var cell = _find(spot["near"])
		if cell != null:
			var entry: Dictionary = spot.duplicate()
			entry["cell"] = cell
			out.append(entry)
	return out


func _find(near: String):
	for person in Town.people():
		if person["id"] == near:
			return person["cell"] if battle.state.is_present(person) else null
	for building in Town.buildings():
		if building["art"] == near:
			return building["cell"] if building["needs"] == "" or building["needs"] in battle.state.rescued else null
	for decor in Town.decor():
		if decor["art"] == near:
			return decor["cell"]
	return null
