# Prompts de arte — rpgbolivia (06/11/2026)
Para a Tarefa 7 (arte dos moradores), a Tarefa 11 (Acendedor) e os inimigos fora do tema (`ESTILO_VISUAL.md`).

## Como funciona
1. Você gera a imagem na IA com o prompt daqui, SEMPRE anexando a imagem de referência
   `artifacts/hero_style_reference.png` (os 4 heróis). Sem ela, o estilo sai diferente.
2. Salva com o nome exato pedido em cada bloco, dentro de
   `C:\Users\Eduardo\OneDrive\Documentos\GitHub\rpgbolivia\referencias\novas\`.
3. No Claude Code: `/tarefa 7` (ou "encaixar artes novas"). O Claude faz o resto:
   tira o fundo magenta, reduz para a grade de pixel real, limita a paleta, contorno,
   amplia 2x com nearest e grava no formato do jogo (`assets/town/morador_*.png` e
   `assets/units/*.png` + `meta.json`). Você não precisa recortar nem redimensionar nada.

## Qual IA usar
- **Moradores da cidade** (parados, 1 imagem cada): ChatGPT / ImageGen (a mesma que fez os prédios,
  ver `assets/unified_sources/town_prompt.json`). Gere em PRANCHAS de 4: a escala e o traço
  ficam iguais entre eles. Se um sair ruim, refaça só ele com o prompt individual.
- **Inimigos e heróis** (animados, com direções): PixelLab, que já fez as folhas atuais
  (`unit_view.gd`: "Folhas com direção (PixelLab)").

## Regras que valem para tudo
- Fundo magenta puro chapado (#FF00FF). Nada de chão, sombra, texto ou moldura.
- Corpo inteiro, pés visíveis, nada cortado na borda.
- Virado em 3/4 para a ESQUERDA (os sprites do jogo olham para a esquerda; o jogo espelha).
- Se a IA errar alguma regra (fundo xadrez, sombra no chão, texto), peça de novo; não conserte à mão.

## Bloco de estilo (cole no começo de TODO prompt de morador)
```
Pixel art game sprite, drawn by the same pixel artist as the attached reference heroes: charming pocket chibi proportions (big head about one third of the body height, compact body), strong dark navy and plum outlines, chunky readable pixel clusters, simple clean 3-tone cel shading, limited palette, no gradients, no blur, no painterly texture, no noise, no dithering, no realistic rendering. Late 19th century Belle Epoque clothing in a melancholic, dark, fading world: muted cold colors (sepia, grey, brown, dark green, wine). Only light, magic or one key prop may use a single warm saturated accent (gold or orange). Full body, standing idle, three-quarter view facing slightly to the LEFT, feet fully visible, light from the upper left. Each character about 96 pixels tall at native pixel resolution. Flat solid pure magenta #FF00FF background, no ground, no floor shadow, no text, no frame.
```

## Pranchas de moradores (ChatGPT / ImageGen) — cole o bloco de estilo antes

### Prancha 1 — salvar como `prancha_moradores_1.png`
```
Sprite sheet: exactly FOUR characters in ONE horizontal row, equal spacing, identical scale, wide magenta gutters, nothing overlapping. Left to right:
1) Blacksmith: stocky middle-aged man, thick mustache, flat cap, rolled-up shirt sleeves, soot-stained brown leather apron, heavy hammer resting on his shoulder; the only bright color is the ember-orange glow on a small hot iron piece in his other hand.
2) Healer: young woman in a long wine-red dress with a cream apron, hair tied back with a scarf, leather satchel of herbs at her hip, holding a small potion bottle with a soft amber glow.
3) Baker: plump cheerful woman, flour-dusted cream apron over a dark green dress, headscarf, sleeves rolled up, holding a big round loaf of bread with both hands.
4) Cartographer: young woman explorer, brass goggles on her head, long khaki traveling coat, rolled maps under one arm, holding a brass spyglass.
```

### Prancha 2 — salvar como `prancha_moradores_2.png`
```
Sprite sheet: exactly FOUR characters in ONE horizontal row, equal spacing, identical scale, wide magenta gutters, nothing overlapping. Left to right:
1) Archivist: elderly scholar, round spectacles, long grey frock coat with high collar, a stack of old leather books under one arm, holding a short candle with a small warm flame.
2) Alchemist: thin dockside alchemist, dark leather apron with rows of small vials, a leather respirator mask hanging at the neck, holding a bubbling flask with a cyan glow.
3) Tavern keeper: sturdy woman, hair in a bun, dark wine corset vest over a cream blouse, rolled sleeves, towel over one shoulder, holding a pewter mug.
4) Lighthouse keeper: old man with a thick white beard, navy pea coat, peaked captain cap, holding up a brass oil lantern with a warm golden flame.
```

### Prancha 3 — salvar como `prancha_moradores_3.png`
```
Sprite sheet: exactly FOUR characters in ONE horizontal row, equal spacing, identical scale, wide magenta gutters, nothing overlapping. Left to right:
1) Master-at-arms: retired fencing master and old officer, upright posture, grey military frock coat with tarnished brass epaulettes, monocle, grey mustache, a cavalry saber at his hip.
2) Merchant: traveling merchant woman, wide-brimmed hat, patched shawl, huge backpack with pots, lanterns and bundles hanging from it, small coin purse in hand.
3) Priestess: calm woman in a long dark grey robe with a cream veil, small flame-shaped pendant, holding a brass candle holder with a warm flame.
4) Fisherman: weathered man in a muted ochre oilskin coat and sou'wester hat, tall boots, a fishing net over his shoulder.
```

### Prancha 4 — salvar como `prancha_moradores_4.png`
```
Sprite sheet: exactly FOUR characters in ONE horizontal row, equal spacing, identical scale, wide magenta gutters, nothing overlapping. Left to right:
1) Wanderer: hooded traveler in a long dusty cloak, scarf over the mouth, wooden walking staff, small bundle on the back.
2) Refugee woman: thin woman wrapped in a patched grey shawl, plain brown dress, carrying a wicker basket.
3) Old townsman: hunched old man with a cane, worn dented top hat, patched dark coat, gloves with holes.
4) Lamplighter: teenage boy in a flat cap and short jacket, carrying a long lamplighter pole with a tiny warm flame at the tip.
```

### Nomes no jogo (o Claude faz a troca)
- Prancha 1: morador_ferreiro, morador_curandeira, morador_padeira, morador_cartografa
- Prancha 2: morador_arquivista, morador_alquimista, morador_taverneira, morador_guarda (Faroleiro)
- Prancha 3: morador_b (Mestre de Armas), morador_d (Mercadora), morador_e (Sacerdotisa), morador_a (Pescador)
- Prancha 4: morador_c (Viajante), morador_f, morador_g, morador_h (NOVO: mais um passante nas ruas)

### Refazer UM morador só — salvar como `morador_<nome>.png`
[Bloco de estilo] + "One single character, centered: " + a descrição dele da prancha.
Anexe também a prancha boa como referência e diga: "same scale and style as the attached sheet".

## Inimigos (PixelLab) — redesenho no tema
Problema hoje: Diabrete e Feiticeira são vermelho-vivo e cartunescos; Esqueleto, Múmia e Cérbero
são fantasia genérica. As regras do jogo (vida, papel) NÃO mudam, só o visual.

Configuração no PixelLab:
- Referência de estilo: `hero_style_reference.png`.
- Tela de 128 x 128; personagem com 80 a 95 px de altura (chibi, como os heróis).
- Visão: "low top-down" / 3/4, a mesma dos heróis. Contorno escuro, poucas cores.
- Direções: ESQUERDA (oeste), FRENTE (sul) e COSTAS (norte).
- Animações: parado (só de frente) · andar 8 frames (3 direções) · ataque 8 frames (3 direções)
  · tomar dano 1 a 4 frames (3 direções) · ataque forte (opcional, 3 direções).
- Exporte cada animação como está (zip ou tiras PNG). Salve em `referencias\novas\<id>\`.
  O Claude monta a folha de 13 linhas e o `meta.json`.

Descrição de estilo (cole antes de cada inimigo):
```
Chibi pixel art enemy, same style as the attached heroes: big head, compact body, strong dark navy outline, 3-tone cel shading, muted cold palette from a dark Belle Epoque world in ruins. Only the eyes or the magic glow may be saturated.
```

- **esqueleto** (Soldado · morto-vivo comum): Undead soldier: a skeleton in a torn faded 1880s infantry greatcoat and dented kepi, rusty brass buttons, holding an old rifle with a rusty bayonet. Hollow eye sockets with tiny pale cyan sparks.
- **mumia** (Tanque · lenta e resistente) — Deserto de Ouro: Heavy mummy guardian: wrapped in yellowed, ink-stained bandages, a cracked gold funeral mask, broken brass clockwork gears showing through the wrappings, hunched and broad. Dull gold accents; eyes glowing faint amber.
- **diabrete** (Ágil · fraco, mas age muito): Soot imp: a small, quick creature made of black chimney smoke, wearing a tiny torn chimney-sweep cap, long thin arms with sharp claws, two round glowing eyes like lamp glass in pale orange. Wispy smoky edges, no bright red skin.
- **feiticeira** (Magia · chamas em área): Mourning witch: young sorceress in a black Victorian mourning dress with a lace veil and high collar, pale face, holding a cracked oil lantern that burns with a violet flame. The violet flame is the only saturated color.
- **cerbero** (Fera · forte e veloz): Iron hound: a three-headed hound of black cast iron and smoke, riveted plates, heavy chain collars with broken links, ember-orange eyes and a faint glow between the plates. Compact, chibi-cute but menacing.
- **guardiao** (OPCIONAL, herói — a armadura medieval destoa): Hero version: same Guardian as the attached reference, same face, colors and shield shape, but in Belle Epoque cuirassier armor: polished steel breastplate, crested helmet with a dark wine horsehair plume, navy uniform under the armor, tall boots, short straight saber, round-top shield with the gold rune. Keep it readable as the tank of the party.

## Depois (não gerar ainda)
- Vilão final: só depois da Tarefa 5a.
- O Acendedor Apagado (Tarefa 11): escrever o prompt numa conversa à parte.
- Rostos para os diálogos (retratos): se quiser, pedir numa conversa à parte.
