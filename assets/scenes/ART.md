# Cenários ilustrados

Arte gerada com a ferramenta integrada ImageGen. Referência de estilo: `artifacts/camp_final.png`, especialmente os heróis e as árvores. Pranchas originais preservadas em `source/`; sprites usados pelo jogo nesta pasta. Importação: `tools/import_ruin_sprites.py`.

## Prompts

Direção comum: production game sprite sheet, transparent PNG; polished hand-painted PIXEL ART matching the detailed heroes and existing trees; three separate props in a horizontal row, with generous transparent gutters; consistent three-quarter view from above, crisp dark plum outlines, finely controlled pixel clusters; melancholy ruined Belle Epoque fantasy, cold limestone gray, dark olive moss, rusty iron and faded wine accents; diffuse light from top left. No text, background, terrain tiles, floating islands, glows, blur or voxel/block rendering. Rich curved sculpting, organic weathered edges and layered materials.

- Jardim: low broken dry neoclassical fountain with carved dolphin fragment, ivy, ferns and fallen leaves; ornate wrought iron entrance between uneven carved limestone pillars, climbing faded roses and vines; crumbling sculpted balustrade, iron scrolls, broken urn and tiny flowers.
- Santuário: spent ivory candles, wax drips and faded wine prayer book; exquisite pointed roadside shrine with weathered veiled angel, ornate finial, layered limestone moldings and patinated iron; broken bench with scrolling iron legs, cracked stone seat and fallen carved finial.
- Travessia: two low ornamental bridge bollards with carved relief and short rusty railing, leaving a walking gap; ruined keeper's guardhouse with arched window, exposed brick, weathered plaster, broken slate mansard and unlit lantern; broken fluted bridge column with carved capital, twisted balustrade, driftwood, moss and ferns. No bridge deck or water: the existing map provides them.

Os novos objetos são sprites fixos voltados para a câmera, como a vegetação dos biomas. O acampamento conserva os modelos de 16 ângulos. Piso, colisão e acessos continuam definidos pela composição procedural.
