extends RefCounted
## O que há para fazer na Cidade-Farol: itens, melhorias, missões e conversas.
## Mudar textos, preços e recompensas mexendo só aqui. A planta fica em town_data.gd.

# --- Itens ---------------------------------------------------------------------
# seller: quem vende. max: quanto cabe na mochila.
# Poções são usadas durante a expedição. Os outros itens valem para a próxima expedição
# inteira e são gastos quando ela termina. setup: o que somam em TownProgress.expedition_setup().
const ITEMS := {
	"pocao": {
		"name": "Poção de Luz", "seller": "mercadora", "price": 8, "max": 5,
		"text": "Usada na expedição: devolve 40% da vida de toda a party.",
	},
	"racao": {
		"name": "Ração de Viagem", "seller": "mercadora", "price": 6, "max": 1, "setup": {"hp": 6},
		"text": "Próxima expedição: +6 de vida para todos os heróis.",
	},
	"pedra": {
		"name": "Pedra de Amolar", "seller": "mercadora", "price": 8, "max": 1, "setup": {"atk": 2},
		"text": "Próxima expedição: +2 de ataque para todos os heróis.",
	},
	"mapa": {
		"name": "Mapa Rasgado", "seller": "mercadora", "price": 5, "max": 1, "setup": {"far_compass": 1},
		"text": "Próxima expedição: a bússola aponta locais a qualquer distância.",
	},
	"amuleto": {
		"name": "Amuleto da Brasa", "seller": "mercadora", "price": 10, "max": 1, "setup": {"brasa_bonus": 1},
		"text": "Próxima expedição: rende 50% mais brasas.",
	},
	"bencao": {
		"name": "Bênção do Farol", "seller": "sacerdotisa", "price": 12, "max": 1, "setup": {"def": 2},
		"text": "Próxima expedição: +2 de defesa para todos os heróis.",
	},
	"vela": {
		"name": "Vela Votiva", "seller": "sacerdotisa", "price": 9, "max": 1, "setup": {"rest_heal": 1},
		"text": "Próxima expedição: +1 de vida a cada passo fora de combate.",
	},
	# Forja: o Ferreiro vende o que forja, além das melhorias.
	"lamina": {
		"name": "Lâmina de Brasa", "seller": "ferreiro", "price": 14, "max": 1, "setup": {"atk": 3},
		"text": "Próxima expedição: +3 de ataque para todos os heróis.",
	},
	"escudo": {
		"name": "Escudo de Ferro Velho", "seller": "ferreiro", "price": 14, "max": 1, "setup": {"def": 3},
		"text": "Próxima expedição: +3 de defesa para todos os heróis.",
	},
	"pao": {
		"name": "Pão de Mel", "seller": "padeira", "price": 6, "max": 1, "setup": {"rest_heal": 1},
		"text": "Próxima expedição: +1 de vida a cada passo fora de combate.",
	},
	"torta": {
		"name": "Torta de Viagem", "seller": "padeira", "price": 10, "max": 1, "setup": {"hp": 10},
		"text": "Próxima expedição: +10 de vida para todos os heróis.",
	},
	"luneta": {
		"name": "Luneta da Torre", "seller": "cartografa", "price": 9, "max": 1, "setup": {"maps": 2},
		"text": "Próxima expedição: a bússola alcança tudo e mostra os baús escondidos.",
	},
	"tomo": {
		"name": "Tomo das Batalhas", "seller": "arquivista", "price": 12, "max": 1, "setup": {"xp_pct": 30},
		"text": "Próxima expedição: +30% de experiência.",
	},
	"elixir": {
		"name": "Elixir Concentrado", "seller": "alquimista", "price": 10, "max": 1, "setup": {"potion_pct": 20},
		"text": "Próxima expedição: as Poções de Luz curam +20% de vida.",
	},
	"pocao_dupla": {
		"name": "Poção Dupla", "seller": "alquimista", "price": 15, "max": 1, "setup": {"potions": 2, "free_potions": 2},
		"text": "Próxima expedição: +2 Poções de Luz, que não saem da mochila.",
	},
}
const ITEM_ORDER := ["pocao", "racao", "pedra", "mapa", "amuleto", "bencao", "vela", "lamina", "escudo", "pao", "torta", "luneta", "tomo", "elixir", "pocao_dupla"]
const POTION := "pocao"
const POTION_HEAL := 0.4
const BRASA_BONUS := 0.5

# --- Melhorias extras dos moradores resgatados -----------------------------------
# A melhoria principal de cada um fica em expedition_data.gd (RESIDENTS).
const UPGRADES := {
	"armadura": {
		"resident": "ferreiro", "name": "Reforçar armaduras", "stat": "def", "per_level": 1, "costs": [20, 40, 60],
		"effect": "+%d de defesa para todos os heróis",
	},
	"frascos": {
		"resident": "curandeira", "name": "Preparar frascos", "stat": "potions", "per_level": 1, "costs": [20, 40],
		"effect": "+%d Poção de Luz de graça em cada expedição",
	},
	"forno_lenha": {
		"resident": "padeira", "name": "Forno a lenha", "stat": "hp", "per_level": 3, "costs": [20, 40],
		"effect": "+%d de vida para todos os heróis",
	},
	"diarios": {
		"resident": "arquivista", "name": "Copiar diários de guerra", "stat": "atk", "per_level": 1, "costs": [35, 70],
		"effect": "+%d de ataque para todos os heróis",
	},
	"destilaria": {
		"resident": "alquimista", "name": "Destilar brasas", "stat": "brasa_pct", "per_level": 10, "costs": [30, 60],
		"effect": "+%d%% de brasas em cada expedição",
	},
}
const UPGRADE_ORDER := ["armadura", "frascos", "forno_lenha", "diarios", "destilaria"]

# --- Missões -------------------------------------------------------------------
# count: o que conta, de ExpeditionState.tally. Só conta depois de aceitar a missão.
# needs_resident / needs_quest: quando ela aparece. reward: brasas e itens.
const QUESTS := {
	"primeira_chama": {
		"giver": "guarda", "title": "A Primeira Chama", "count": "beacons", "target": 1,
		"goal": "Acenda o farol de uma região.",
		"offer": "Enquanto só esta chama arder, a escuridão sabe onde nos encontrar. Derrote o guardião de um farol e acenda-o.",
		"done": "Eu vi daqui: uma luz nova no horizonte. Faz anos que não dormia tão tranquilo.",
		"reward": {"brasas": 30, "items": {"pocao": 1}},
	},
	"vigilia": {
		"giver": "sacerdotisa", "title": "A Vigília", "count": "beacons", "target": 2, "needs_quest": "primeira_chama",
		"goal": "Acenda mais dois faróis.",
		"offer": "Uma chama pode ser sorte. Três são um juramento. Acenda mais dois e rezarei pelos seus nomes.",
		"done": "Os sinos tocaram sozinhos esta manhã. Aceite esta bênção.",
		"reward": {"brasas": 50, "items": {"bencao": 1}},
	},
	"sucata": {
		"giver": "ferreiro", "title": "Sucata das Ruínas", "count": "ruins", "target": 4, "needs_resident": "ferreiro",
		"goal": "Vasculhe 4 ruínas.",
		"offer": "Minha forja está de pé, mas sem ferro. As ruínas estão cheias de engrenagens velhas. Traga o que achar.",
		"done": "Isto vai virar boas lâminas. Fique com esta pedra, por conta da casa.",
		"reward": {"brasas": 25, "items": {"pedra": 1}},
	},
	"ervas": {
		"giver": "curandeira", "title": "Água Clara", "count": "fountains", "target": 2, "needs_resident": "curandeira",
		"goal": "Visite 2 fontes de luz.",
		"offer": "A água das fontes de luz cura o que as ervas não curam. Passe por duas delas e me conte se ainda brilham.",
		"done": "Ainda brilham, então. Tome, preparei isto com o que sobrou.",
		"reward": {"brasas": 20, "items": {"pocao": 2}},
	},
	"freguesia": {
		"giver": "taverneira", "title": "Estrada Limpa", "count": "kills", "target": 15,
		"goal": "Derrote 15 criaturas da escuridão.",
		"offer": "Ninguém vem beber aqui com medo da estrada. Derrube algumas daquelas coisas e a primeira rodada é minha.",
		"done": "Já tem gente perguntando se o caminho abriu. Leve isto para a viagem.",
		"reward": {"brasas": 15, "items": {"racao": 1}},
	},
	"lembrancas": {
		"giver": "taverneira", "title": "O Que Foi Esquecido", "count": "memories", "target": 2, "needs_quest": "freguesia",
		"goal": "Recupere 2 memórias.",
		"offer": "As histórias daqui têm buracos. Se achar memórias lá fora, traga. Alguém precisa lembrar.",
		"done": "Então era isso. Eu preferia não saber, mas obrigada.",
		"reward": {"brasas": 25, "items": {}},
	},
	"aguas": {
		"giver": "pescador", "title": "Quem Ficou Para Trás", "count": "villages", "target": 2,
		"goal": "Salve 2 vilas.",
		"offer": "Minha irmã morava numa vila depois do lago. Não sei qual. Se puder salvar quem encontrar, já me basta.",
		"done": "Não era ela, mas é gente viva. Achei este mapa no barco, talvez sirva mais a você.",
		"reward": {"brasas": 20, "items": {"mapa": 1}},
	},
	"emboscadas": {
		"giver": "viajante", "title": "Ruínas Que Mordem", "count": "ambushes", "target": 2,
		"goal": "Sobreviva a 2 emboscadas.",
		"offer": "Nem toda ruína está vazia, eu avisei. Se você sobreviver a duas emboscadas, prometo que paro de falar disso.",
		"done": "Duas! E ainda inteiro. Isto me salvou uma vez. Agora é seu.",
		"reward": {"brasas": 25, "items": {"amuleto": 1}},
	},
	"treino": {
		"giver": "mestre", "title": "Prova de Armas", "count": "kills", "target": 30,
		"goal": "Derrote 30 inimigos.",
		"offer": "Treino sem luta é dança. Volte depois de derrubar trinta deles e eu chamo você de soldado.",
		"done": "Soldado. Agora sim.",
		"reward": {"brasas": 40, "items": {}},
	},
	"carga": {
		"giver": "mercadora", "title": "Bom Para o Negócio", "count": "brasas", "target": 60,
		"goal": "Junte 60 brasas nas expedições.",
		"offer": "Mais brasa na cidade é mais gente comprando. Traga sessenta de lá de fora e eu retribuo.",
		"done": "O comércio agradece. Duas das minhas melhores, sem cobrar.",
		"reward": {"brasas": 0, "items": {"pocao": 2}},
	},
	# --- Pedidos de quem foi resgatado e continuações -------------------------------
	"farinha": {
		"giver": "padeira", "title": "Farinha das Vilas", "count": "villages", "target": 3, "needs_resident": "padeira",
		"goal": "Salve 3 vilas.",
		"offer": "Cada vila salva manda um saco de farinha para cá, é o costume. Três sacos e eu volto a fazer pão para a cidade inteira.",
		"done": "Sentiu o cheiro? É a cidade acordando. Leve um para a estrada.",
		"reward": {"brasas": 20, "items": {"pao": 1}},
	},
	"cantos": {
		"giver": "cartografa", "title": "Os Cantos do Mapa", "count": "chests", "target": 4, "needs_resident": "cartografa",
		"goal": "Abra 4 baús.",
		"offer": "Quem esconde um baú sempre deixa marca no terreno. Abra quatro e eu aprendo a ler essas marcas no mapa.",
		"done": "Já vejo o padrão. Leve minha luneta: daqui para frente, nada se esconde de você.",
		"reward": {"brasas": 25, "items": {"luneta": 1}},
	},
	"paginas": {
		"giver": "arquivista", "title": "Páginas Arrancadas", "count": "memories", "target": 3, "needs_resident": "arquivista",
		"goal": "Recupere 3 memórias.",
		"offer": "Alguém arrancou as páginas do fim da crônica da cidade. As memórias lá fora são o que sobrou delas. Traga três.",
		"done": "O nome riscado na parede... está aqui também. Leve este tomo. Eu preciso de um tempo sozinho com isso.",
		"reward": {"brasas": 30, "items": {"tomo": 1}},
	},
	"orvalho": {
		"giver": "alquimista", "title": "Orvalho de Luz", "count": "fountains", "target": 3, "needs_resident": "alquimista",
		"goal": "Visite 3 fontes de luz.",
		"offer": "A água das fontes tem a mesma luz do farol. Se eu entender por quê, minhas poções vão curar o dobro. Passe por três fontes.",
		"done": "É brasa dissolvida! Quem fez as fontes sabia o que fazia. Fique com o primeiro frasco.",
		"reward": {"brasas": 20, "items": {"elixir": 1}},
	},
	"aco_guardiao": {
		"giver": "ferreiro", "title": "O Aço dos Guardiões", "count": "beacons", "target": 1, "needs_quest": "sucata",
		"goal": "Derrote o guardião de um farol.",
		"offer": "Os guardiões dos faróis vestem um metal que eu nunca vi. Derrube um e eu forjo algo digno dessa luta.",
		"done": "Que metal estranho, quente sem fogo. Fiz esta lâmina com ele.",
		"reward": {"brasas": 35, "items": {"lamina": 1}},
	},
	"maos_firmes": {
		"giver": "curandeira", "title": "Mãos Firmes", "count": "fountains", "target": 4, "needs_quest": "ervas",
		"goal": "Visite mais 4 fontes de luz.",
		"offer": "Se eu tiver água de luz suficiente, posso guardar frascos para a pior hora. Passe por mais quatro fontes.",
		"done": "Guardei o que pude. Use antes que precise, não depois.",
		"reward": {"brasas": 20, "items": {"pocao": 3}},
	},
	"rota": {
		"giver": "mercadora", "title": "Rota Comercial", "count": "brasas", "target": 150, "needs_quest": "carga",
		"goal": "Junte mais 150 brasas nas expedições.",
		"offer": "Com tanta gente voltando, dá para abrir uma rota até as vilas salvas. Mas rota custa. Traga cento e cinquenta brasas de lá de fora.",
		"done": "A primeira carroça saiu hoje! Este amuleto me deu sorte. Agora é a sua vez.",
		"reward": {"brasas": 40, "items": {"amuleto": 1}},
	},
	"veterano": {
		"giver": "mestre", "title": "Veterano", "count": "kills", "target": 60, "needs_quest": "treino",
		"goal": "Derrote mais 60 inimigos.",
		"offer": "Soldado você já é. Veterano é outra conversa. Sessenta, e não quero ouvir reclamação.",
		"done": "Veterano. Não vou repetir, então lembre que eu disse.",
		"reward": {"brasas": 60, "items": {}},
	},
	"lago": {
		"giver": "pescador", "title": "Luz do Outro Lado", "count": "villages", "target": 4, "needs_quest": "aguas",
		"goal": "Salve mais 4 vilas.",
		"offer": "Os que você salvou contam de mais gente presa lá fora. Talvez minha irmã esteja entre eles. Salve mais quatro vilas.",
		"done": "Ela mandou recado. Está viva! Não tenho como pagar isso. Tome o pouco que juntei.",
		"reward": {"brasas": 30, "items": {"racao": 1}},
	},
	"tesouros": {
		"giver": "viajante", "title": "Fora do Caminho", "count": "chests", "target": 6, "needs_quest": "emboscadas",
		"goal": "Abra 6 baús.",
		"offer": "Os melhores baús ficam longe das trilhas. Quem só anda na estrada nunca acha nada. Abra seis e me conte.",
		"done": "Seis! Você anda mais que eu. Isto é para a próxima viagem.",
		"reward": {"brasas": 35, "items": {"mapa": 1}},
	},
}
const QUEST_ORDER := [
	"primeira_chama", "sucata", "ervas", "freguesia", "aguas", "emboscadas", "carga", "treino", "lembrancas", "vigilia",
	"farinha", "cantos", "paginas", "orvalho", "aco_guardiao", "maos_firmes", "rota", "veterano", "lago", "tesouros",
]

# --- História ------------------------------------------------------------------
# SPOILER: o enredo inteiro está em docs/SPOILER_historia.md.
# Cada capítulo é contado pelo guia na volta para casa. O capítulo atual é o número de faróis
# acesos (0 a 4); o último só aparece depois da batalha final (TownProgress.finish_story()).
# pages: [quem fala (id em Town.PEOPLE), fala]. goal: o objetivo no topo da tela.
# help: o que fazer, em palavras simples. call: o que o guia grita enquanto tem algo a contar.
const GUIDE := "guia"
const KEEPER := "guarda"
const BEACON_GOAL := 4
const GOAL_TALK := "Fale com o Pavio, ao lado da fonte"
const GOAL_KEEPER := "Fale com o Faroleiro, no alto da colina"
const KEEPER_HELP := "Primeiro, subam a avenida até o farol, ao norte, e falem com o Faroleiro. Ele quer conhecer vocês. Depois é só partir: o botão \"Partir para a Expedição\" fica no canto da tela."
const EXPEDITION_GOAL := "Acenda o farol (siga a bússola)"
const STORY := [
	{
		"goal": "Acenda o farol de uma região",
		"help": "Toquem em \"Partir para a Expedição\", no canto da tela, e escolham a party. Lá fora, a bússola no topo da tela aponta o farol. Derrotem o guardião e o farol acende. No caminho, vilas tomadas pela escuridão têm gente para salvar!",
		"call": ["Ei, vocês! Aqui, na fonte!", "Vocês acordaram!", "Aqui! Perto da fonte!"],
		"pages": [
			["guia", "Ei! Vocês acordaram! Achei vocês desmaiados num barco sem remos, lá na doca. Vieram do meio da escuridão."],
			["guia", "Não lembram de nada, né? Tudo bem. Quem sai da escuridão chega sem nome. Eu também cheguei assim. O Faroleiro me chama de Pavio."],
			["guia", "Aqui é a Cidade-Farol, o último lugar com luz. Enquanto a Grande Chama arder lá no alto, quem mora aqui não é esquecido."],
			["guia", "Lá fora, a escuridão apaga tudo: estradas, vilas, até o nome das pessoas. E quem é esquecido de vez... simplesmente some."],
			["guia", "Antigamente, cada região tinha um farol. Todos se apagaram, e uma criatura ficou de guarda em cada um. Se alguém acender os quatro de novo, o mundo volta a lembrar de si."],
			["guia", "E vocês atravessaram o escuro e chegaram inteiros. Ninguém faz isso! O Faroleiro precisa conhecer vocês. Ele fica no alto da colina, ao norte, cuidando da chama."],
		],
	},
	{
		"goal": "Acenda mais um farol",
		"help": "O mesmo caminho: partam, sigam a bússola até o farol e derrotem o guardião. Antes, gastem as brasas em melhorias e poções. Cada farol aceso deixa a cidade maior.",
		"call": ["Vocês voltaram!", "Eu vi a luz da torre!", "Venham aqui, rápido!"],
		"pages": [
			["guia", "Vocês voltaram! Eu vi da torre: uma luz nova, lá longe. A cidade inteira saiu na rua para olhar!"],
			["guia", "O Faroleiro ficou olhando para ela a noite toda. Quando contei que o guardião tinha caído, ele só perguntou: \"Ele disse alguma coisa antes?\""],
			["guia", "Por que ele ia querer saber o que um monstro disse? Eu acho que ele sabe mais do que conta."],
			["guia", "Faltam três faróis. Cada um que acende traz gente de volta e deixa a escuridão mais fraca. Vamos!"],
		],
	},
	{
		"goal": "Acenda o terceiro farol",
		"help": "Partam de novo e acendam o terceiro farol. Os guardiões não perdoam: treinem com o Mestre de Armas e levem poções.",
		"call": ["Tenho uma coisa pra contar!", "Ei! Aqui!", "Vocês precisam ouvir isso!"],
		"pages": [
			["guia", "Dois faróis! A Taverneira diz que nunca vendeu tanta sopa."],
			["guia", "Ontem subi a torre e ouvi o Faroleiro falando sozinho. Ele dizia nomes: Tomé, Killa, Gunnar, Inti... E pedia desculpas para cada um."],
			["guia", "Vocês acham que os guardiões eram... gente? Gente daqui?"],
			["guia", "Se eram, estavam guardando os faróis de alguém. Mas de quem? Eu vou descobrir. Vocês, acendam o terceiro."],
		],
	},
	{
		"goal": "Acenda o último farol",
		"help": "Falta um. Partam, sigam a bússola até o farol e derrotem o último guardião. Com os quatro acesos, a luz vai mostrar onde Vésper se esconde.",
		"call": ["O Faroleiro desceu da torre!", "Venham! Ele quer falar!", "Vocês precisam ouvir isso!"],
		"pages": [
			["guia", "Ele desceu! O Faroleiro desceu da torre pela primeira vez em anos. Disse que vocês merecem ouvir a verdade."],
			["guarda", "Meu nome é Bento. Fui aprendiz de Vésper, o Primeiro Faroleiro. Foi ele quem acendeu a Grande Chama e todos os faróis do mundo."],
			["guarda", "As chamas guardam mais que luz: guardam a memória das coisas. Vésper tinha pavor de que algo fosse esquecido. Então começou a guardar tudo... dentro de si mesmo."],
			["guarda", "Primeiro bebeu as estrelas. Depois as estradas. Depois os nomes. O que ele guarda para si, o mundo esquece. Isso é a escuridão."],
			["guarda", "Fui eu que dei a ordem: apaguem os faróis, e ele não terá o que beber. Tomé, Killa, Gunnar e Inti ficaram no escuro guardando as últimas brasas. Até de quem as acendeu."],
			["guarda", "Agora vocês acendem o que eu mandei apagar. E está certo: a chama de vocês é nova, ele não consegue bebê-la. Mas ele já percebeu. Acendam o último farol, e ele não terá mais onde se esconder."],
		],
	},
	{
		"goal": "Enfrente Vésper no Farol Negro",
		"help": "A última expedição leva ao Farol Negro, onde as quatro terras se encontram. Preparem tudo antes de ir: melhorias, poções e skills.",
		"call": ["Olhem o horizonte!", "Os quatro estão acesos!", "Venham ver isso!"],
		"pages": [
			["guia", "Os quatro faróis estão acesos! E olhem lá longe, onde as quatro terras se encontram... tem uma torre que não estava lá."],
			["guarda", "O Farol Negro. É onde Vésper se escondeu com tudo o que roubou. A luz de vocês finalmente o encontrou."],
			["guarda", "Há mais uma coisa. Vocês não vieram de lugar nenhum: vieram de lá. Eram nomes que ele guardava, e a Grande Chama chamou vocês de volta. Por isso não lembram de nada."],
			["guia", "Então... eu também saí de lá? Meu nome de verdade está com ele?"],
			["guarda", "Está, Pavio. O de vocês também. Vésper vai perguntar se vale a pena viver num mundo que esquece. Pensem bem na resposta. E voltem."],
		],
	},
	{
		"goal": "A luz voltou ao mundo",
		"help": "A história terminou, mas o mundo continua lá fora. Ainda há vilas perdidas e gente para salvar.",
		"call": ["As estrelas voltaram!", "Olhem o céu!"],
		"pages": [
			["guia", "Vocês voltaram! Olhem para cima... as estrelas! Todas elas!"],
			["guarda", "No fim, Vésper soltou tudo. A luz voltou para quem era dona dela. Os nomes também."],
			["guia", "Eu lembrei do meu nome. É Lucas! Mas acho que vou continuar sendo Pavio. Combina com o farol."],
			["guarda", "E vocês? Lembraram quem eram? Não precisam me contar. Agora há uma cidade inteira que nunca vai esquecer vocês."],
			["guarda", "Estou cansado, meus amigos. Pavio, a chama é sua agora. Não a guarde só para você. Divida."],
		],
	},
]

# --- Conversas -----------------------------------------------------------------
# first: a primeira vez. greetings: depois disso, muda a cada expedição.
# topics: [pergunta, resposta]. after_beacon: troca o cumprimento quando há farol aceso.
# stages: {capítulo: fala} dita uma vez quando a história chega naquele capítulo.
# topics_at: {capítulo: [pergunta, resposta]} que aparece a partir daquele capítulo.
# guardians: {chefe: [pergunta, resposta]} que aparece depois de vencer aquele guardião.
# defeat: cumprimentos na volta de uma expedição perdida.
const TALK := {
	"guia": {
		"first": "Oi! Eu sou o Pavio, aprendiz do farol. Precisando de alguma coisa, é só chamar!",
		"greetings": ["Precisam de alguma coisa? Eu sei onde fica tudo nesta cidade!", "O Faroleiro diz que eu falo demais. Eu acho que falo o necessário."],
		"defeat": ["Vocês voltaram! Machucados, mas voltaram. Isso já é mais do que a escuridão queria.", "Cair uma vez não apaga ninguém. A Curandeira e o Mestre de Armas podem deixar vocês mais fortes."],
		"stages": {5: "Lucas ou Pavio? Ainda estou decidindo. Acho que Pavio."},
		"topics": [
			["Quem é você?", "Pavio, aprendiz do farol! Também cheguei pelo mar escuro, sem nome. O Faroleiro me deu este porque eu sou pequeno e seguro a chama."],
			["O que tem na cidade?", "A Mercadora e a Sacerdotisa vendem coisas. A Taverneira guarda as memórias que vocês acharem, o Mestre de Armas treina e o Mural tem pedidos. Ferreiro e Curandeira, só se vocês resgatarem."],
		],
	},
	"ferreiro": {
		"first": "Achei que nunca mais ouviria este martelo. Obrigado por me tirar de lá. Agora, o que posso consertar?",
		"greetings": ["Lâmina cega não salva ninguém. Deixe-me ver isso.", "Ferro velho, ideias novas. O que vai ser?"],
		"after_beacon": "Com mais um farol aceso, o carvão até queima melhor. Coisa da minha cabeça, talvez.",
		"stages": {3: "O velho me pediu uma lâmina. Disse que é para quando ele não estiver mais aqui. Não gostei disso."},
		"topics": [
			["Como você foi parar naquela vila?", "Fui buscar ferro e fiquei. A escuridão chegou de noite e a estrada sumiu. Só sobrou a oficina."],
			["O que acontece com a forja agora?", "Agora ela é sua. Traga brasas e todo herói que sair daqui sai mais forte."],
		],
	},
	"curandeira": {
		"first": "Vocês me acharam. Ainda tenho as mãos e as ervas, e isso basta. Sentem-se, por favor.",
		"greetings": ["Quem vem de lá sempre volta com um corte novo. Deixe-me ver.", "As ervas ainda crescem aqui. Pequenos milagres."],
		"after_beacon": "A horta floresceu fora de época. Acho que ela também viu o farol.",
		"stages": {2: "Tem gente chegando com memórias voltando aos pedaços. Dói, mas é bom sinal."},
		"topics": [
			["A escuridão tem cura?", "Para o corpo, sim. Para o que ela apaga da memória, não conheço nenhuma."],
			["Por que as fontes ainda brilham?", "Porque alguém as acendeu antes de nós. Não sei quem. Espero que seja amigo."],
		],
	},
	"taverneira": {
		"first": "Bem-vindos à última taverna do mundo. A bebida é ruim, mas é a única. O que vai ser?",
		"greetings": ["Sentem-se. Aqui ninguém pergunta o que vocês viram lá fora.", "Tem sopa. Não perguntem de quê."],
		"after_beacon": "Depois daquele farol, vendi mais em uma noite do que no ano todo. Continuem.",
		"stages": {
			1: "Gente nova chegando pela estrada! Faz anos que não ouço tanta conversa aqui.",
			3: "Dizem que o velho desceu da torre. O mundo deve estar acabando. Ou começando.",
		},
		"topics": [
			["O que dizem por aí?", "Que as trilhas antigas ligam os faróis. Quem segue o calçamento raramente se perde."],
			["Quem construiu esta cidade?", "Os faroleiros. E depois sumiram quase todos. Só restou aquele velho lá em cima, que não gosta de falar disso."],
		],
	},
	"mestre": {
		"first": "Postura ruim. Guarda baixa. Ótimo, tenho trabalho. Vão ficar parados aí?",
		"greetings": ["De novo. Desta vez, com vontade.", "Cicatriz nova é lição nova. Mostre o que aprendeu."],
		"stages": {4: "Treinem como se fosse a última vez. Porque pode ser."},
		"topics": [
			["Como ficamos mais fortes?", "Cada expedição ensina. O que vocês aprendem vira ponto de skill. Gastem nas árvores de cada herói."],
			["Algum conselho para a luta?", "Terreno alto bate mais forte, floresta protege e quem cerca o inimigo acerta mais. O resto é coragem."],
		],
	},
	"guarda": {
		"first": "Então são vocês que o Pavio tirou do barco. Saíram da escuridão com vida... faz muito tempo que não vejo isso. Cuido desta chama há mais tempo do que deveria, e sozinha ela não basta. Acendam o farol de uma região. Depois conversamos sobre o resto.",
		"greetings": ["A chama está firme hoje.", "Daqui de cima dá para ver onde a escuridão termina. Fica um pouco mais longe a cada dia."],
		"after_beacon": "Mais uma luz no horizonte. Faltam poucas para enxergarmos quem começou tudo isso.",
		"stages": {
			1: "Uma luz nova no horizonte. Eu sabia que ainda havia brasa debaixo daquele escuro.",
			2: "Quando o vento vem das regiões, eu ouço nomes antigos. Não liguem para um velho.",
			3: "Agora vocês sabem quem eu sou. Se ainda quiserem a minha ajuda, ela é de vocês.",
			4: "Não olhem muito tempo para o Farol Negro. Ele olha de volta.",
			5: "Vejam o céu. Eu tinha esquecido como era.",
		},
		"topics": [
			["O que é a escuridão?", "Ela chegou devagar. Primeiro as estrelas, depois as estradas, depois os nomes. Alguém a trouxe."],
			["Para que servem os faróis?", "Cada farol aceso devolve uma região. Com todos acesos, ele não terá onde se esconder."],
		],
		"topics_at": {
			3: ["Quem acendeu as fontes de luz?", "Tomé, Killa, Gunnar e Inti, antes de irem para o escuro. Deixaram água limpa para quem viesse depois. Para vocês, eu acho."],
		},
		"guardians": {
			"boss_cervo": ["Quem era o Rei Cervo?", "Tomé. Caçador, faroleiro da floresta. Errava as flechas de propósito para os cervos fugirem. Fui eu que pedi que ele ficasse lá, no escuro."],
			"boss_serpente": ["Quem era a Rainha Serpente?", "Killa cuidava do farol do pântano e de todo mundo que se perdia nele. Ela disse que cumpriu o juramento? Então quem ainda deve sou eu."],
			"boss_jarl": ["Quem era o Jarl de Gelo?", "Gunnar, capitão da nossa guarda. Foi o primeiro a aceitar ficar. Disse que o frio não assusta quem já perdeu tudo."],
			"boss_farao": ["Quem era o Faraó Eclipse?", "Inti contava as estrelas. Quando elas começaram a sumir, foi ela quem percebeu primeiro quem as estava levando."],
		},
	},
	"pescador": {
		"first": "Os barcos não saem há muito tempo. A água ficou escura como tinta. Se você vai lá fora, talvez possa me ajudar.",
		"greetings": ["Hoje nem os peixes querem saber de mim.", "Dizem que do outro lado do lago ainda há luz. Eu não apostaria nisso."],
		"stages": {
			2: "A água clareou perto da doca. Hoje vi um peixe! Um só, mas vi.",
			4: "Do barco dá para ver uma torre preta no meio da névoa. Eu não remaria até lá nem por toda a sopa do mundo.",
		},
		"topics": [
			["Dá para atravessar o lago?", "De barco, não mais. Mas as pontes velhas ainda aguentam. Quem as fez sabia construir."],
			["O que vive nessa água?", "Antes, trutas. Agora prefiro não puxar a rede para descobrir."],
		],
		"topics_at": {
			0: ["Você viu quando chegamos?", "Vi o Pavio puxando o barco de vocês. Madeira antiga, sem remos e sem nome. Igual aos barcos que os faroleiros usavam."],
		},
	},
	"viajante": {
		"first": "Cheguei seguindo o farol. É a única coisa que a escuridão não apagou. E você, de onde vem?",
		"greetings": ["Nem toda ruína está vazia. Fique de olho.", "Ainda não decidi se fico. Mas a sopa está melhorando."],
		"stages": {3: "Decidi: vou ficar. Quero ver como essa história termina."},
		"topics": [
			["O que você viu lá fora?", "Quatro terras: floresta de ruínas, pântano de tinta, neve de cinzas e deserto de ouro. Nenhuma feliz em me ver."],
			["Como reconhecer uma emboscada?", "Não dá. Ruínas parecem todas iguais. Entre com a vida cheia."],
		],
		"topics_at": {
			4: ["Onde fica o Farol Negro?", "Onde as quatro terras se encontram. Passei perto uma vez. Lá, nem o eco volta."],
		},
	},
	"mercadora": {
		"first": "Cliente novo! Não ligue para a poeira, a mercadoria é honesta. Quase toda. Dê uma olhada.",
		"greetings": ["Brasa na mão e vontade de gastar? Chegou no lugar certo.", "Separei umas coisas boas. Só para você. E para os outros também."],
		"after_beacon": "Mais um farol, mais gente na estrada e mais freguesia. Continue assim.",
		"stages": {4: "Até eu estou com medo daquela torre preta. Leve poções. Leve muitas. Faço preço."},
		"topics": [
			["O que vale levar?", "Poção sempre. Se a expedição parecer longa, ração e pedra de amolar. E o amuleto, se você gosta de lucro."],
			["De onde vem isso tudo?", "De quem não voltou para buscar. Não me olhe assim, alguém tinha de guardar."],
		],
	},
	"sacerdotisa": {
		"first": "Entre, sem medo. Esta capela está meio caída, mas quem reza aqui ainda é ouvido. Eu acho.",
		"greetings": ["A luz o acompanhe. Literalmente, se possível.", "Rezei por quem saiu. Fico feliz que tenha voltado."],
		"after_beacon": "Sinto a luz mais perto. Até os sinos parecem mais leves.",
		"stages": {
			2: "Os sinos tocaram duas vezes esta noite. Alguém lá fora lembrou de rezar.",
			4: "Agora eu sei qual é a pergunta dele. A resposta é de vocês.",
		},
		"topics": [
			["O que é a Bênção do Farol?", "Um pouco da chama que protege a cidade, para levar com você. Dura uma expedição."],
			["Você acredita que vamos vencer?", "Acredito que cada chama acesa é uma resposta. A pergunta dele nós ainda vamos ouvir."],
		],
	},
	"padeira": {
		"first": "Vocês me tiraram de um forno frio no meio do nada. Agora deixem eu esquentar este aqui. Ninguém luta bem com fome.",
		"greetings": ["Pão quente, tirado agora. Leve dois.", "A massa precisa descansar. Vocês também, de vez em quando."],
		"after_beacon": "Com o farol novo, a farinha chega mais rápido das vilas. A cidade está comendo melhor.",
		"topics": [
			["Como pão ajuda lá fora?", "Quem come bem se recupera andando. Cada passo na estrada devolve um pouco do que a luta tirou."],
			["Você estava sozinha na vila?", "Com o forno. Ele me manteve quente quando tudo apagou. Fogo é teimoso, igual a mim."],
		],
	},
	"cartografa": {
		"first": "Finalmente uma torre de novo. Daqui de cima eu desenho o que vocês só veem do chão. Tragam histórias de onde estiveram.",
		"greetings": ["O mapa mudou desde ontem. A escuridão mexe nas estradas.", "Cuidado com os cantos do mapa. É onde moram as surpresas."],
		"after_beacon": "Cada farol aceso devolve um pedaço do mapa. Estou ficando sem papel, e isso é ótimo.",
		"topics": [
			["O que a torre faz por nós?", "Com os meus mapas, a bússola de vocês alcança qualquer lugar. Com os melhores, até os baús escondidos."],
			["Os caminhos mudam mesmo?", "As serras não, mas as trilhas sim. Por isso o mapa nasce de novo a cada saída."],
		],
	},
	"arquivista": {
		"first": "Cuidado com a poeira, ela é mais velha que a cidade. Eu guardo o que aconteceu. Ultimamente, muita coisa foi apagada.",
		"greetings": ["Cada luta que vocês contam vira lição para a próxima.", "Encontrei mais um nome riscado. Sempre o mesmo traço."],
		"after_beacon": "Com o farol aceso, algumas páginas em branco voltaram a ter letras. Não sei explicar. Ainda.",
		"topics": [
			["Para que serve o arquivo?", "Estudar batalhas antigas ensina mais rápido. Quem passa por aqui aprende mais em cada expedição."],
			["Quem riscou os nomes?", "Alguém com acesso a todos os livros da cidade. Os faroleiros tinham. Só estou dizendo."],
		],
	},
	"alquimista": {
		"first": "Não toque em nada que borbulha. Nem no que não borbulha, na verdade. Vocês me salvaram, então vou fazer suas poções valerem a pena.",
		"greetings": ["Hoje explodiu só uma vez. Progresso!", "A brasa é mais que fogo. É luz guardada. Eu só preciso descobrir como abrir a tampa."],
		"after_beacon": "As fontes brilham mais forte desde o último farol. Minhas misturas também. Coincidência é coisa que não existe.",
		"topics": [
			["O que você faz com as brasas?", "Destilo. Uma brasa bem destilada vale por duas. A cidade inteira ganha com isso."],
			["As poções são seguras?", "Para vocês, sim. Para a escuridão, nem um pouco. Para mim, depende do dia."],
		],
	},
}

# Falas soltas que os moradores dizem quando a party passa por perto.
const AMBIENT := {
	"guia": ["O farol nunca dorme!", "Já foram na taverna?"],
	"ferreiro": ["Quente o bastante...", "Onde deixei o martelo?"],
	"curandeira": ["Cuidado com a horta!", "Falta musgo-de-sal."],
	"taverneira": ["Sopa quente!", "Última taverna do mundo!"],
	"mestre": ["Guarda alta!", "De novo!"],
	"guarda": ["A chama está firme.", "Olhos no horizonte."],
	"pescador": ["Nada de peixe hoje...", "Essa água não é normal."],
	"viajante": ["Bonita, esta cidade.", "Já vi coisa pior. Pouca."],
	"mercadora": ["Poção fresquinha!", "Olha a ração de viagem!"],
	"sacerdotisa": ["Que a luz os guarde.", "Os sinos estão quietos."],
	"padeira": ["Pão saindo!", "Quem quer o primeiro?"],
	"cartografa": ["Essa trilha não estava aqui...", "Mais um canto do mapa."],
	"arquivista": ["Página trezentos e doze...", "Quem riscou isto?"],
	"alquimista": ["Não respirem perto daqui!", "Quase lá... quase!"],
}
const WALKER_LINES := ["Bom dia, heróis!", "Viram o farol?", "Voltem com vida!", "Está mais claro hoje.", "Obrigado por virem."]
const BOARD_TEXT := "Pedidos de quem ainda resiste. Fale com quem pediu para aceitar a missão ou receber a recompensa."
const NOTHING_TEXT := "Sem pedidos novos por enquanto. Volte depois da próxima expedição."
const QUEST_READY := "Missão cumprida: %s. Volte e fale com quem pediu."
