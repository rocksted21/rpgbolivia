# Estilo visual

Referência para qualquer arte, efeito ou tela nova do jogo. Revisado em 05/11/2026, comparando o texto com a arte do projeto e com capturas do jogo.

**Em uma frase:** pixel art chibi em um mundo Belle Époque em ruínas, onde quase tudo é escuro e frio, e a pouca luz quente é o que importa.

## Pilares

### 1. Proporções pocket/chibi
- Heróis e monstros têm cabeça grande, corpo compacto e expressão visível em telas pequenas.
- Cada classe precisa ser reconhecida pela silhueta no grid hexagonal.

### 2. Melancolia Belle Époque e neoclássica
- **Vestuário:** final do século XIX europeu, com cartolas, máscaras de dominó, capas, sobretudos e vestes aristocráticas góticas.
- **Cenário:** ruínas de pedra neoclássicas, grades de ferro, estufas, vilas vitorianas e engrenagens de relógio soterradas.
- **Tema:** a escuridão avança e o tempo se esgota. Faróis apagados e névoa densa dominam o fundo.

### 3. Paleta de alto contraste
- **Mundo:** tons frios e soturnos, como sépia, cinza, marrom, verde-escuro e vinho.
- **Luz e magia:** habilidades e loot usam cores quentes e saturadas, como dourado, laranja, ciano e roxo.
- **Regra prática:** cor saturada significa magia, luz ou algo interativo. O cenário não compete com ela.

### 4. Luz moderna sobre pixel art
- Bloom, névoa e partículas flutuantes: faíscas, cinzas, esporos e gotas.
- O brilho dos faróis e das magias se opõe diretamente à névoa.

## Medidas

| Item | Padrão |
| --- | --- |
| Personagem | Até 96 px de arte de altura; os atuais têm de 77 a 92 |
| Folha de sprites | Arte ampliada 2×, em células de 224 a 288 px (`assets/units/meta.json`) |
| Escala em jogo | Tabuleiro a 0,5: 1 pixel de arte ≈ 1 pixel de tela em 1280×720, antes da perspectiva |
| Casa do mapa | 186 px de largura, 244 px de altura com a lateral |
| Filtro | Sempre o mais próximo (`nearest`) nos sprites com `pixel: true` |

## Paleta por bioma

Cores das pranchas em `referencias/biomas`, que são a referência de cada bioma.

| Bioma | Tema | Terreno e materiais | Destaque |
| --- | --- | --- | --- |
| Floresta | Ruínas petrificadas | `#797844` `#535434` `#535f4d` `#777c80` `#7c7066` `#624f48` `#4c3935` `#38261a` | Chama do farol |
| Selva | Pântano de tinta | `#56623e` `#344a3c` `#356a6e` `#253044` `#594d45` `#5e3a2e` `#372618` `#111113` | Bioluminescência `#4bf8dc` |
| Neve | Cinzas e relógios | `#d9e7f2` `#a6b2c2` `#51555e` `#5a5047` `#5b392d` `#362619` `#111114` | Gelo `#94bacc` `#a3dbee` |
| Deserto | Ouro e ossos | `#cfa24b` `#a35442` `#d6ae7b` `#96724e` `#634233` `#453525` `#474e58` `#131315` | Chama do farol |

A chama fica em torno de `#f5a00a` nos quatro biomas. Cada bioma também tem seu farol nas versões **apagada** (preta, com vapor escuro) e **acesa** (cores e luz na lanterna e nos vitrais).

## Interface

Em uso na Cidade-Farol e na árvore de skills:

| Papel | Cor |
| --- | --- |
| Fundo | `#191e2a` |
| Painel | `#252d3e` |
| Destaque e botão principal | `#f2ca76` |
| Texto | `#f5efdf` |
| Texto secundário | `#aab2c2` |

Herói é azul e inimigo é vermelho nas barras e marcadores. A fonte ainda não foi definida (ver abaixo).

## Mapa das expedições

- **Sem casas à vista:** as regras continuam em hexágonos, mas o chão é contínuo, com bordas recortadas e cantos fora do lugar. As casas só aparecem no combate, como marcação de movimento e alcance.
- **Um pedaço de cada bioma:** Floresta, Selva, Neve e Deserto são quatro regiões contínuas que se encontram em um ponto. Neve e Deserto nunca fazem fronteira, a não ser nesse ponto.
- **Terra alta:** planaltos largos, em até três degraus, com penhascos irregulares.
- **Cenário solto:** árvores e pedras saem do centro da casa. Nas matas, só parte das casas tem árvore, e cada árvore é sólida: a party contorna, sem atravessar. Uma árvore fica transparente quando esconde alguém.
- **Texturas:** `tools/build_ground.py` gera o chão a partir das cores das peças de cada bioma. A Cidade-Farol usa o mesmo chão, com calçada de pedras soltas nas ruas e os degraus menos tortos, porque escadas e prédios seguem a planta.

## Cidade-Farol

- **Espaço:** a avenida liga o porto, ao sul, à praça com a fonte e à colina do farol, ao norte. A oeste fica o bairro dos ofícios; a leste, o bairro nobre e a taverna.
- **Construções de todos os lados:** cada prédio é um modelo 3D simples, renderizado em pixel art de 16 ângulos por `tools/build_town_models.py`. O jogo troca o desenho conforme a câmera gira.
- **Medidas dos modelos:** 1 casa do mapa tem cerca de 93 pixels de arte. Casas viram a frente para a rua (`face`, em `scripts/town_data.gd`).
- **Luz:** janelas acesas continuam vivas à noite, e as fachadas seguem os tons de pedra, reboco e madeira das pranchas.

## Noite e luz nas expedições

- **Escuro:** chão e cenário recebem o tom do bioma (`NIGHT_TINT`, em `scripts/biome_art.gd`). Heróis, inimigos, marcações e magias não escurecem.
- **Luz:** a party e o farol aceso clareiam o chão e os objetos em volta, e clarões marcam as magias. Os números ficam em `scripts/world_light.gd`.
- **O que não escurece:** farol aceso, baú fechado e cristais da selva. Ruínas escurecem menos, para serem achadas.
- **Ar:** cada bioma tem suas partículas: esporos na Floresta, esporos ciano na Selva, cinzas na Neve e poeira no Deserto.
- **Bloom:** só o que já é muito claro brilha, nas expedições e na cidade. A interface fica de fora.

## Como está o jogo hoje

Avaliado em capturas do jogo em 05/11/2026.

**Já segue o estilo**
- **Heróis:** Mago de Fogo, Duelista e Besteiro definem bem o visual, e o Mago de Água e a Druida acompanham.
- **Cidade-Farol:** é a tela mais fiel. Está quase igual à referência em brilho (0,33 contra 0,31) e saturação (0,30 contra 0,27), e já tem luz e faíscas.
- **Biomas:** a arte segue as pranchas, incluindo os faróis apagado e aceso.
- **Expedições:** agora são noturnas, com luz vinda da party, do farol aceso, dos baús, dos cristais da selva e das magias.

**Ainda não segue**

| Prioridade | Problema | O que foi visto |
| --- | --- | --- |
| Média | Inimigos fora do tema | Diabrete e Feiticeira são vermelho-vivo e cartunescos; Esqueleto, Múmia e Cérbero são fantasia genérica |
| Média | Interface misturada | A ficha de combate é creme, enquanto o resto é azul-escuro |
| Média | Fonte indefinida | `hud.gd` espera Lilita One e Fredoka, mas `assets/fonts` não existe. As pranchas usam serifada em versalete |
| Média | Heróis escondidos | Na Neve, as árvores densas chegam a cobrir o Guardião quase por inteiro |
| Baixa | Guardião medieval | A armadura de cavaleiro destoa dos outros heróis |
| Baixa | Névoa uniforme | Hoje é uma faixa escura com a mesma cor em todos os biomas |

## Antes de aprovar uma arte nova

1. A silhueta é reconhecível em tamanho de jogo?
2. Pertence ao final do século XIX, e não à fantasia medieval genérica?
3. Só a luz, a magia ou o que é interativo usa cor saturada?
4. As cores seguem a paleta do bioma?
5. O pixel tem a mesma densidade dos sprites ao lado?
6. Personagens continuam visíveis na frente e atrás do objeto?
7. Funciona no escuro, com a luz vindo de uma fonte dentro da cena?
