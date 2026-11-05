extends RefCounted
## Planta e textos da Cidade-Farol. Mudar a cidade mexendo só aqui.
## As posições são casas (coluna, linha) do mapa hexagonal; a arte fica em assets/town.

const PLAZA := Vector2i(15, 12)
const PLAZA_RADIUS := 3
const VISIT_RADIUS := 2
const TOWN_ROOT := "res://assets/town/%s.png"
const RUBBLE := "res://assets/biomes/floresta/montanha_b.png"
const BASE_PEOPLE := 4
const PEOPLE_PER_RESCUE := 4
const PEOPLE_PER_BEACON := 2

# Discos de terra (centro, raio). O que fica de fora é água.
const LAND := [
	[Vector2i(15, 12), 10], [Vector2i(7, 8), 7], [Vector2i(23, 8), 7], [Vector2i(27, 5), 4],
	[Vector2i(16, 3), 4], [Vector2i(5, 15), 5], [Vector2i(22, 16), 4], [Vector2i(2, 9), 3],
]
# Partes altas (centro, raio, nível). O relevo é suavizado depois, para tudo ter caminho.
const HIGH_GROUND := [
	[Vector2i(16, 3), 4, 2], [Vector2i(16, 3), 2, 3], [Vector2i(7, 6), 4, 2], [Vector2i(13, 6), 2, 2],
	[Vector2i(23, 8), 3, 2], [Vector2i(27, 4), 3, 2],
]
const ROADS := [
	[Vector2i(12, 11), Vector2i(9, 8)], [Vector2i(16, 9), Vector2i(16, 6)],
	[Vector2i(18, 11), Vector2i(20, 11)], [Vector2i(21, 11), Vector2i(24, 11)], [Vector2i(24, 11), Vector2i(27, 7)], [Vector2i(12, 13), Vector2i(10, 15)],
	[Vector2i(18, 15), Vector2i(22, 17)],
]

# radius: casas em volta que o prédio ocupa. needs: morador sem o qual o prédio está em ruínas.
const BUILDINGS := [
	{"art": "farol", "cell": Vector2i(16, 3), "radius": 0},
	{"art": "forja", "cell": Vector2i(7, 6), "radius": 1, "needs": "ferreiro"},
	{"art": "tenda", "cell": Vector2i(13, 7), "radius": 1, "needs": "curandeira"},
	{"art": "horta", "cell": Vector2i(11, 4), "radius": 1},
	{"art": "taverna", "cell": Vector2i(22, 9), "radius": 1},
	{"art": "mansao", "cell": Vector2i(28, 4), "radius": 1},
	{"art": "capela", "cell": Vector2i(8, 14), "radius": 1},
	{"art": "acampamento", "cell": Vector2i(2, 9), "radius": 1},
	{"art": "forno", "cell": Vector2i(3, 17), "radius": 0},
	{"art": "abrigo", "cell": Vector2i(20, 6), "radius": 0},
	{"art": "torre_madeira", "cell": Vector2i(25, 13), "radius": 0},
]
# Enfeites em casas que não dá para atravessar.
const DECOR := [
	{"art": "fogueira_a", "cell": Vector2i(12, 15)}, {"art": "fogueira_b", "cell": Vector2i(18, 9)},
	{"art": "fogueira_a", "cell": Vector2i(9, 11)},
	{"art": "barraca_b", "cell": Vector2i(20, 13)}, {"art": "barraca_b", "cell": Vector2i(14, 16)}, {"art": "barraca_c", "cell": Vector2i(22, 13)},
	{"art": "tocha", "cell": Vector2i(13, 9)}, {"art": "tocha", "cell": Vector2i(18, 8)}, {"art": "tocha", "cell": Vector2i(19, 10)},
	{"art": "tocha", "cell": Vector2i(11, 12)}, {"art": "tocha", "cell": Vector2i(18, 14)}, {"art": "tocha", "cell": Vector2i(15, 8)},
	{"art": "doca", "cell": Vector2i(25, 19)}, {"art": "barco_a", "cell": Vector2i(29, 15)},
	{"art": "barco_b", "cell": Vector2i(27, 21)}, {"art": "barco_b", "cell": Vector2i(18, 22)},
]
# Casas de quem ainda não voltou e árvores: dão corpo à cidade.
const HOUSES := [
	Vector2i(19, 16), Vector2i(12, 18), Vector2i(7, 18), Vector2i(23, 13), Vector2i(4, 12), Vector2i(22, 4), Vector2i(16, 19),
]
const TREES := [
	Vector2i(3, 6), Vector2i(1, 11), Vector2i(4, 9), Vector2i(10, 2), Vector2i(12, 2), Vector2i(20, 2), Vector2i(21, 6),
	Vector2i(29, 7), Vector2i(26, 11), Vector2i(2, 14), Vector2i(1, 16), Vector2i(9, 19), Vector2i(14, 21), Vector2i(21, 19),
	Vector2i(24, 15),
]
const HOUSE_ART := "res://assets/biomes/floresta/casa.png"
const TREE_ART := "res://assets/biomes/floresta/floresta_fundo_%s.png"

const STAIRS := [
	{"art": "escada_a", "cell": Vector2i(16, 7)}, {"art": "escada_b", "cell": Vector2i(10, 9)},
]

# service: "resident" (melhorias), "memories", "skills", "beacon", "shop", "board" ou "talk".
const PEOPLE := [
	{"id": "ferreiro", "name": "Ferreiro", "art": "morador_ferreiro", "cell": Vector2i(9, 7), "service": "resident", "needs": "ferreiro"},
	{"id": "curandeira", "name": "Curandeira", "art": "morador_curandeira", "cell": Vector2i(12, 9), "service": "resident", "needs": "curandeira"},
	{"id": "taverneira", "name": "Taverneira", "art": "morador_taverneira", "cell": Vector2i(20, 10), "service": "memories"},
	{"id": "mestre", "name": "Mestre de Armas", "art": "morador_b", "cell": Vector2i(26, 7), "service": "skills"},
	{"id": "guarda", "name": "Faroleiro", "art": "morador_guarda", "cell": Vector2i(17, 6), "service": "beacon"},
	{"id": "pescador", "name": "Pescador", "art": "morador_a", "cell": Vector2i(21, 15), "service": "talk"},
	{"id": "viajante", "name": "Viajante", "art": "morador_c", "cell": Vector2i(11, 16), "service": "talk"},
	{"id": "mercadora", "name": "Mercadora", "art": "morador_d", "cell": Vector2i(19, 12), "service": "shop"},
	{"id": "sacerdotisa", "name": "Sacerdotisa", "art": "morador_e", "cell": Vector2i(10, 13), "service": "shop"},
	{"id": "mural", "name": "Mural de Missões", "art": "mural", "cell": Vector2i(13, 15), "service": "board"},
]

# Quem anda pelas ruas. A cidade ganha gente com os resgates e os faróis.
const WALKER_ART := ["morador_f", "morador_g", "morador_a", "morador_c"]
const WALKER_BASE := 2
const WALKER_MAX := 6
const WALK_ROUTE := [
	Vector2i(14, 10), Vector2i(12, 11), Vector2i(9, 8), Vector2i(12, 13), Vector2i(10, 15), Vector2i(15, 15),
	Vector2i(18, 15), Vector2i(22, 17), Vector2i(18, 11), Vector2i(20, 11), Vector2i(24, 9), Vector2i(16, 9),
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
