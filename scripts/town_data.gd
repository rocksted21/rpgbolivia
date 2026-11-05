extends RefCounted
## Planta e textos da Cidade-Farol. Mudar a cidade mexendo só aqui.
## As posições são casas (coluna, linha) do mapa hexagonal; a arte fica em assets/town.

const PLAZA := Vector2i(9, 13)
const VISIT_RADIUS := 2
const TOWN_ROOT := "res://assets/town/%s.png"
const RUBBLE := "res://assets/biomes/floresta/montanha_b.png"
const BASE_PEOPLE := 4
const PEOPLE_PER_RESCUE := 4
const PEOPLE_PER_BEACON := 2

# A planta segue referencias/cidade.jpg: cada letra é uma casa, linha por linha (as linhas
# ímpares ficam meia casa para a direita). ~ água, # morro alto ao fundo, p praça de pedra, 0 a 3 o nível do chão.
# O farol fica no platô mais alto; forja e tenda à esquerda; taverna e mansão à direita;
# a praça no meio e as docas embaixo, à direita. Os desníveis são penhascos: sobe-se pelas ruas.
const MAP := [
	"~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~",
	"~~######22222~~~~~~",
	"~~####2222333~~~~~~",
	"~~###2222233332~~~~",
	"~~##22222233332~~~~",
	"~~###2222223332221~",
	"~~##22222212222221~",
	"~~1112222211222222~",
	"~~1122221111222221~",
	"~~1111pppppp22222~~",
	"~~1111pppppp1111~~~",
	"~~1111ppppppp1~~~~~",
	"~~1111pppppp10~~~~~",
	"~~1111pppppp1000~~~",
	"~~1111pppp110000~~~",
	"~~11111111111000~~~",
	"~~111111111111~~~~~",
	"~~~~~~~~~~~~~~~~~~~",
]
const PLAZA_LEVEL := 1
const ROCK_LEVEL := 3
# Ruas de pedra (de, até): ligam a praça às escadas e aos platôs.
const ROADS := [
	[Vector2i(7, 12), Vector2i(6, 11)], [Vector2i(9, 12), Vector2i(10, 10)], [Vector2i(10, 10), Vector2i(10, 7)],
	[Vector2i(11, 16), Vector2i(12, 16)], [Vector2i(5, 13), Vector2i(4, 13)], [Vector2i(12, 14), Vector2i(13, 14)],
]

# radius: casas em volta que o prédio ocupa. needs: morador sem o qual o prédio está em ruínas.
const BUILDINGS := [
	{"art": "farol", "cell": Vector2i(12, 6), "radius": 1},
	{"art": "forja", "cell": Vector2i(5, 10), "radius": 1, "needs": "ferreiro"},
	{"art": "tenda", "cell": Vector2i(7, 8), "radius": 0, "needs": "curandeira"},
	{"art": "horta", "cell": Vector2i(9, 8), "radius": 0},
	{"art": "taverna", "cell": Vector2i(13, 12), "radius": 1},
	{"art": "mansao", "cell": Vector2i(16, 10), "radius": 1},
	{"art": "capela", "cell": Vector2i(5, 15), "radius": 1},
	{"art": "acampamento", "cell": Vector2i(3, 12), "radius": 0},
	{"art": "forno", "cell": Vector2i(4, 16), "radius": 0},
	{"art": "abrigo", "cell": Vector2i(10, 11), "radius": 0},
	{"art": "torre_madeira", "cell": Vector2i(13, 15), "radius": 0},
]
# Enfeites. offset: deslocamento para o lado, em pixels do tile, para dividir a casa com outros.
# solid: false deixa passar por cima (tochas na beira da rua).
const DECOR := [
	{"art": "fogueira_a", "cell": Vector2i(7, 9)}, {"art": "fogueira_b", "cell": Vector2i(9, 17)}, {"art": "fogueira_a", "cell": Vector2i(11, 15)},
	{"art": "caldeirao_grande", "cell": Vector2i(8, 8)}, {"art": "frascos", "cell": Vector2i(8, 9), "offset": 56},
	{"art": "bigorna", "cell": Vector2i(6, 10), "offset": 20}, {"art": "bigorna_b", "cell": Vector2i(4, 17)}, {"art": "lenha", "cell": Vector2i(3, 16)},
	{"art": "barraca_b", "cell": Vector2i(12, 15)}, {"art": "barraca_b", "cell": Vector2i(10, 16)}, {"art": "barraca_c", "cell": Vector2i(13, 16)},
	{"art": "barris_b", "cell": Vector2i(14, 16)},
	{"art": "tocha", "cell": Vector2i(8, 12), "offset": -52, "solid": false}, {"art": "tocha", "cell": Vector2i(9, 11), "offset": 48, "solid": false},
	{"art": "tocha", "cell": Vector2i(11, 11), "offset": -40, "solid": false}, {"art": "tocha", "cell": Vector2i(10, 8), "offset": 58, "solid": false},
	{"art": "tocha", "cell": Vector2i(6, 14), "offset": -50, "solid": false}, {"art": "tocha", "cell": Vector2i(11, 13), "offset": 50, "solid": false},
	{"art": "doca", "cell": Vector2i(14, 18)}, {"art": "barco_a", "cell": Vector2i(17, 16)}, {"art": "barco_b", "cell": Vector2i(15, 17)},
	{"art": "barco_a", "cell": Vector2i(14, 19)},
]
# service: "resident" (melhorias), "memories", "skills", "beacon", "shop", "board" ou "talk".
const PEOPLE := [
	{"id": "ferreiro", "name": "Ferreiro", "art": "morador_ferreiro", "cell": Vector2i(7, 10), "service": "resident", "needs": "ferreiro"},
	{"id": "curandeira", "name": "Curandeira", "art": "morador_curandeira", "cell": Vector2i(8, 9), "service": "resident", "needs": "curandeira"},
	{"id": "taverneira", "name": "Taverneira", "art": "morador_taverneira", "cell": Vector2i(14, 13), "service": "memories"},
	{"id": "mestre", "name": "Mestre de Armas", "art": "morador_b", "cell": Vector2i(13, 9), "service": "skills"},
	{"id": "guarda", "name": "Faroleiro", "art": "morador_guarda", "cell": Vector2i(10, 6), "service": "beacon"},
	{"id": "pescador", "name": "Pescador", "art": "morador_a", "cell": Vector2i(13, 17), "service": "talk"},
	{"id": "viajante", "name": "Viajante", "art": "morador_c", "cell": Vector2i(4, 12), "service": "talk"},
	{"id": "mercadora", "name": "Mercadora", "art": "morador_d", "cell": Vector2i(11, 14), "service": "shop"},
	{"id": "sacerdotisa", "name": "Sacerdotisa", "art": "morador_e", "cell": Vector2i(7, 15), "service": "shop"},
	{"id": "mural", "name": "Mural de Missões", "art": "mural", "cell": Vector2i(8, 11), "service": "board"},
]

# Quem anda pelas ruas. A cidade ganha gente com os resgates e os faróis.
const WALKER_ART := ["morador_f", "morador_g", "morador_a", "morador_c"]
const WALKER_BASE := 2
const WALKER_MAX := 6
const WALK_ROUTE := [
	Vector2i(7, 13), Vector2i(10, 13), Vector2i(9, 15), Vector2i(6, 17), Vector2i(10, 18), Vector2i(12, 17),
	Vector2i(4, 14), Vector2i(6, 11), Vector2i(9, 9), Vector2i(10, 7), Vector2i(12, 10), Vector2i(15, 12),
]
# Tochas e fogueiras: de noite, é a luz delas que mostra a cidade.
const LIGHT_ART := {"fogueira_a": 1.0, "fogueira_b": 1.0, "tocha": 0.6}
const BEACON_LIGHT := 2.2
const FORGE_LIGHT := 1.2

const BEACON_TEXT := "Enquanto esta chama arder, a cidade existe. Acendam os faróis das regiões e a escuridão vai recuar até quem a trouxe."
const NEXT_REGION_TEXT := "O farol da região já brilha. O caminho até a próxima região ainda está sendo aberto."
const NO_MEMORY_TEXT := "Ninguém aqui lembra de muita coisa. Traga memórias das expedições e eu conto o que elas significam."
const MISSING_TEXT := "Este lugar está em ruínas. Procure uma vila tomada pela escuridão: quem mora ali pode trazê-lo de volta."
const SKILLS_TEXT := "Treine aqui antes de partir. O que vocês aprenderam nas expedições vira força nas árvores de skills."
