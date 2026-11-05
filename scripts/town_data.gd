extends RefCounted
## Planta e textos da Cidade-Farol. Mudar a cidade mexendo só aqui.
## As posições são casas (coluna, linha) do mapa hexagonal; a arte fica em assets/town.

const PLAZA := Vector2i(17, 16)
const VISIT_RADIUS := 2
const TOWN_ROOT := "res://assets/town/%s.png"
const RUBBLE := "res://assets/biomes/floresta/montanha_b.png"
const BASE_PEOPLE := 4
const PEOPLE_PER_RESCUE := 4
const PEOPLE_PER_BEACON := 2

# Cada letra é uma casa, linha por linha (as linhas ímpares ficam meia casa para a direita).
# ~ água, # morro alto ao fundo, p praça de pedra, 0 a 3 o nível do chão.
# A avenida liga o porto, ao sul, à praça e à colina do farol, ao norte. A oeste fica o bairro
# dos ofícios (forja, forno, acampamento); a leste, o bairro nobre (mansão) e a taverna.
const MAP := [
	"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~2222222222~~~~~~~~~~~~",
	"~~~~~~~~~~~~22223333222~~~~~~~~~~~",
	"~~~~~~~~~~##22333333322~~~~~~~~~~~",
	"~~~~~~~~~###223333333322~~~~~~~~~~",
	"~~~~~~222222233333333322~~~~~~~~~~",
	"~~~~~~2222222233333333222~~~~~~~~~",
	"~~~~~22222222233333332222222~~~~~~",
	"~~~~~2222222222233332222222222~~~~",
	"~~~~~2222222211222222212222222~~~~",
	"~~~~~~22221111111111111122222222~~",
	"~~~~~222211111111111111222222222~~",
	"~~~~~~222211111pppppp111222222222~",
	"~~~~~~22211111ppppppp112222222222~",
	"~~~~~~11111111pppppppp11222222222~",
	"~~~~~11111111ppppppppp12222222222~",
	"~~~~~111111111pppppppp11111111111~",
	"~~~~1111111111ppppppp111111111111~",
	"~~~~~1111111111pppppp11111111111~~",
	"~~~~1111111111111111111111111111~~",
	"~~~~~111111111111111111111111111~~",
	"~~~~~11111111111111111111111111~~~",
	"~~~~~~11111111111111111111111~~~~~",
	"~~~~~11111111111111111111111~~~~~~",
	"~~~~~~0000000000000000000000~~~~~~",
	"~~~~~~000000000000000000000~~~~~~~",
	"~~~~~~0000000000~~~~~~00000~~~~~~~",
	"~~~~~~0000000000~~~~~0000~~~~~~~~~",
	"~~~~~~~000000~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
]
const PLAZA_LEVEL := 1
const ROCK_LEVEL := 3
# Ruas de pedra (de, até): a avenida, as ruas dos bairros e a rua do porto.
const ROADS := [
	[Vector2i(17, 12), Vector2i(17, 7)], [Vector2i(17, 18), Vector2i(18, 25)],
	[Vector2i(13, 15), Vector2i(9, 15)], [Vector2i(9, 15), Vector2i(7, 18)],
	[Vector2i(21, 15), Vector2i(26, 13)], [Vector2i(26, 13), Vector2i(29, 13)],
	[Vector2i(14, 13), Vector2i(11, 12)], [Vector2i(20, 13), Vector2i(24, 11)],
	[Vector2i(9, 22), Vector2i(26, 22)], [Vector2i(14, 18), Vector2i(12, 22)], [Vector2i(21, 18), Vector2i(23, 22)],
]

# Construções em 3D têm desenho de todos os lados: ver tools/build_town_models.py.
const MODEL_ROOT := "res://assets/town/modelos/%s.png"
const TREE_ART := "res://assets/biomes/floresta/floresta_fundo_%s.png"
const TREES := [
	Vector2i(5, 7), Vector2i(5, 11), Vector2i(5, 16), Vector2i(5, 19), Vector2i(5, 23), Vector2i(6, 5), Vector2i(6, 25), Vector2i(7, 9), Vector2i(7, 28), Vector2i(8, 5), Vector2i(9, 7), Vector2i(9, 28), Vector2i(11, 5), Vector2i(11, 26), Vector2i(12, 2), Vector2i(12, 28), Vector2i(14, 26), Vector2i(15, 1), Vector2i(16, 25), Vector2i(17, 1), Vector2i(21, 2), Vector2i(21, 7), Vector2i(23, 4), Vector2i(23, 27), Vector2i(24, 6), Vector2i(27, 7), Vector2i(27, 24), Vector2i(28, 17), Vector2i(28, 22), Vector2i(30, 15), Vector2i(30, 21), Vector2i(31, 10), Vector2i(31, 18), Vector2i(32, 12), Vector2i(32, 15),
]
const MODELS := ["casa_a", "casa_b", "casa_c", "taverna", "mansao", "capela", "forja", "tenda", "abrigo", "forno", "torre_madeira", "fonte", "farol"]
# radius: casas em volta que o prédio ocupa. needs: morador sem o qual o prédio está em ruínas.
const BUILDINGS := [
	{"art": "farol", "cell": Vector2i(17, 4), "radius": 1},
	{"art": "forja", "cell": Vector2i(8, 12), "radius": 1, "needs": "ferreiro", "face": Vector2i(10, 15)},
	{"art": "tenda", "cell": Vector2i(10, 19), "radius": 0, "needs": "curandeira", "face": Vector2i(13, 20)},
	{"art": "horta", "cell": Vector2i(7, 20), "radius": 0},
	{"art": "taverna", "cell": Vector2i(25, 17), "radius": 1, "face": Vector2i(22, 15)},
	{"art": "mansao", "cell": Vector2i(27, 10), "radius": 1, "face": Vector2i(27, 13)},
	{"art": "capela", "cell": Vector2i(11, 9), "radius": 1, "face": Vector2i(13, 13)},
	{"art": "acampamento", "cell": Vector2i(6, 17), "radius": 0},
	{"art": "forno", "cell": Vector2i(5, 13), "radius": 0, "face": Vector2i(7, 14)},
	{"art": "abrigo", "cell": Vector2i(15, 24), "radius": 0, "face": Vector2i(17, 23)},
	{"art": "torre_madeira", "cell": Vector2i(25, 25), "radius": 0},
	{"art": "fonte", "cell": Vector2i(17, 14), "radius": 0},
	# Casas dos moradores: viradas para a rua (face).
	{"art": "casa_a", "cell": Vector2i(8, 22), "radius": 0, "face": Vector2i(9, 22)},
	{"art": "casa_b", "cell": Vector2i(10, 23), "radius": 0, "face": Vector2i(10, 22)},
	{"art": "casa_c", "cell": Vector2i(13, 16), "radius": 0, "face": Vector2i(14, 16)},
	{"art": "casa_a", "cell": Vector2i(13, 23), "radius": 0, "face": Vector2i(13, 22)},
	{"art": "casa_c", "cell": Vector2i(16, 23), "radius": 0, "face": Vector2i(16, 22)},
	{"art": "casa_b", "cell": Vector2i(18, 21), "radius": 0, "face": Vector2i(19, 22)},
	{"art": "casa_a", "cell": Vector2i(21, 17), "radius": 0, "face": Vector2i(21, 18)},
	{"art": "casa_b", "cell": Vector2i(21, 21), "radius": 0, "face": Vector2i(22, 21)},
	{"art": "casa_c", "cell": Vector2i(24, 10), "radius": 0, "face": Vector2i(24, 11)},
	{"art": "casa_a", "cell": Vector2i(25, 21), "radius": 0, "face": Vector2i(26, 22)},
	{"art": "casa_c", "cell": Vector2i(26, 14), "radius": 0, "face": Vector2i(25, 14)},
	{"art": "casa_b", "cell": Vector2i(30, 12), "radius": 0, "face": Vector2i(29, 13)},
	{"art": "casa_c", "cell": Vector2i(7, 15), "radius": 0, "face": Vector2i(8, 16)},
	{"art": "casa_a", "cell": Vector2i(9, 17), "radius": 0, "face": Vector2i(9, 16)},
	{"art": "casa_b", "cell": Vector2i(10, 14), "radius": 0, "face": Vector2i(10, 15)},
	{"art": "casa_a", "cell": Vector2i(14, 20), "radius": 0, "face": Vector2i(13, 20)},
	{"art": "casa_b", "cell": Vector2i(16, 11), "radius": 0, "face": Vector2i(17, 11)},
	{"art": "casa_c", "cell": Vector2i(16, 19), "radius": 0, "face": Vector2i(17, 19)},
	{"art": "casa_a", "cell": Vector2i(17, 25), "radius": 0, "face": Vector2i(18, 25)},
	{"art": "casa_b", "cell": Vector2i(18, 9), "radius": 0, "face": Vector2i(17, 9)},
	{"art": "casa_c", "cell": Vector2i(19, 19), "radius": 0, "face": Vector2i(19, 18)},
	{"art": "casa_a", "cell": Vector2i(20, 23), "radius": 0, "face": Vector2i(20, 22)},
	{"art": "casa_b", "cell": Vector2i(21, 11), "radius": 0, "face": Vector2i(22, 12)},
	{"art": "casa_c", "cell": Vector2i(22, 13), "radius": 0, "face": Vector2i(23, 14)},
	{"art": "casa_a", "cell": Vector2i(22, 19), "radius": 0, "face": Vector2i(22, 20)},
	{"art": "casa_b", "cell": Vector2i(22, 23), "radius": 0, "face": Vector2i(22, 22)},
	{"art": "casa_c", "cell": Vector2i(23, 15), "radius": 0, "face": Vector2i(22, 15)},
	{"art": "casa_a", "cell": Vector2i(23, 21), "radius": 0, "face": Vector2i(24, 22)},
	{"art": "casa_b", "cell": Vector2i(24, 23), "radius": 0, "face": Vector2i(24, 22)},
	{"art": "casa_c", "cell": Vector2i(26, 23), "radius": 0, "face": Vector2i(26, 22)},
	{"art": "casa_a", "cell": Vector2i(28, 12), "radius": 0, "face": Vector2i(28, 13)},
	{"art": "casa_b", "cell": Vector2i(29, 14), "radius": 0, "face": Vector2i(28, 13)},
]
# Enfeites. offset: deslocamento para o lado, em pixels do tile, para dividir a casa com outros.
# solid: false deixa passar por cima (tochas na beira da rua).
const DECOR := [
	{"art": "fogueira_a", "cell": Vector2i(12, 18)}, {"art": "fogueira_b", "cell": Vector2i(19, 24)}, {"art": "fogueira_a", "cell": Vector2i(8, 17)},
	{"art": "caldeirao_grande", "cell": Vector2i(9, 20)}, {"art": "frascos", "cell": Vector2i(11, 20), "offset": 56},
	{"art": "bigorna", "cell": Vector2i(10, 13), "offset": 20}, {"art": "bigorna_b", "cell": Vector2i(6, 15)}, {"art": "lenha", "cell": Vector2i(4, 14)},
	{"art": "barraca_b", "cell": Vector2i(14, 17)}, {"art": "barraca_c", "cell": Vector2i(15, 19)}, {"art": "barraca_b", "cell": Vector2i(20, 18)},
	{"art": "barris_b", "cell": Vector2i(23, 25)}, {"art": "barris_b", "cell": Vector2i(23, 16)},
	{"art": "tocha", "cell": Vector2i(16, 10), "offset": 50, "solid": false}, {"art": "tocha", "cell": Vector2i(18, 8), "offset": -50, "solid": false},
	{"art": "tocha", "cell": Vector2i(13, 13), "offset": -40, "solid": false}, {"art": "tocha", "cell": Vector2i(21, 13), "offset": 40, "solid": false},
	{"art": "tocha", "cell": Vector2i(13, 18), "offset": 40, "solid": false}, {"art": "tocha", "cell": Vector2i(21, 19), "offset": -40, "solid": false},
	{"art": "tocha", "cell": Vector2i(16, 21), "offset": 50, "solid": false}, {"art": "tocha", "cell": Vector2i(19, 23), "offset": -50, "solid": false},
	{"art": "tocha", "cell": Vector2i(9, 14), "offset": 40, "solid": false}, {"art": "tocha", "cell": Vector2i(26, 12), "offset": 40, "solid": false},
	{"art": "doca", "cell": Vector2i(18, 26)}, {"art": "barco_a", "cell": Vector2i(20, 27)}, {"art": "barco_b", "cell": Vector2i(15, 27)},
	{"art": "barco_a", "cell": Vector2i(22, 28)},
]
# service: "resident" (melhorias), "memories", "skills", "beacon", "shop", "board" ou "talk".
const PEOPLE := [
	{"id": "ferreiro", "name": "Ferreiro", "art": "morador_ferreiro", "cell": Vector2i(10, 12), "service": "resident", "needs": "ferreiro"},
	{"id": "curandeira", "name": "Curandeira", "art": "morador_curandeira", "cell": Vector2i(12, 20), "service": "resident", "needs": "curandeira"},
	{"id": "taverneira", "name": "Taverneira", "art": "morador_taverneira", "cell": Vector2i(23, 17), "service": "memories"},
	{"id": "mestre", "name": "Mestre de Armas", "art": "morador_b", "cell": Vector2i(25, 11), "service": "skills"},
	{"id": "guarda", "name": "Faroleiro", "art": "morador_guarda", "cell": Vector2i(20, 6), "service": "beacon"},
	{"id": "pescador", "name": "Pescador", "art": "morador_a", "cell": Vector2i(20, 25), "service": "talk"},
	{"id": "viajante", "name": "Viajante", "art": "morador_c", "cell": Vector2i(8, 18), "service": "talk"},
	{"id": "mercadora", "name": "Mercadora", "art": "morador_d", "cell": Vector2i(15, 18), "service": "shop"},
	{"id": "sacerdotisa", "name": "Sacerdotisa", "art": "morador_e", "cell": Vector2i(13, 11), "service": "shop"},
	{"id": "mural", "name": "Mural de Missões", "art": "mural", "cell": Vector2i(19, 12), "service": "board"},
]

# Quem anda pelas ruas. A cidade ganha gente com os resgates e os faróis.
const WALKER_ART := ["morador_f", "morador_g", "morador_a", "morador_c"]
const WALKER_BASE := 2
const WALKER_MAX := 6
const WALK_ROUTE := [
	Vector2i(15, 15), Vector2i(19, 16), Vector2i(17, 19), Vector2i(12, 22), Vector2i(23, 22), Vector2i(18, 24),
	Vector2i(9, 15), Vector2i(12, 12), Vector2i(17, 10), Vector2i(17, 8), Vector2i(23, 12), Vector2i(27, 13),
]
# Tochas e fogueiras: de noite, é a luz delas que mostra a cidade.
const LIGHT_ART := {"fogueira_a": 1.0, "fogueira_b": 1.0, "tocha": 0.6}
const BEACON_LIGHT := 2.2
const BEACON_HEIGHT := 288.0 # altura da lanterna do farol no modelo
const FORGE_LIGHT := 1.2

const BEACON_TEXT := "Enquanto esta chama arder, a cidade existe. Acendam os faróis das regiões e a escuridão vai recuar até quem a trouxe."
const NEXT_REGION_TEXT := "O farol da região já brilha. O caminho até a próxima região ainda está sendo aberto."
const NO_MEMORY_TEXT := "Ninguém aqui lembra de muita coisa. Traga memórias das expedições e eu conto o que elas significam."
const MISSING_TEXT := "Este lugar está em ruínas. Procure uma vila tomada pela escuridão: quem mora ali pode trazê-lo de volta."
const SKILLS_TEXT := "Treine aqui antes de partir. O que vocês aprenderam nas expedições vira força nas árvores de skills."
