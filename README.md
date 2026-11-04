# RPG Bolivia — Combate Tático

Projeto do jogo em Godot. Esta pasta contém o código, as cenas e os assets usados no desenvolvimento.

## Começar a desenvolver

1. Clone `https://github.com/rocksted21/rpgbolivia.git` pelo GitHub Desktop.
2. Importe o arquivo `project.godot` no Godot 4.7 ou em uma versão compatível.
3. Aguarde a importação dos assets e pressione F6 para executar a cena aberta ou F5 para executar o jogo.

O Godot recria a pasta `.godot/` automaticamente. Compilações em `build/`, dependências em `servidor/node_modules/` e configurações locais não são versionadas.

Para trabalhar em conjunto, crie uma branch no GitHub Desktop, faça seus commits e envie a branch com **Publish branch** ou **Push origin**. Abra um pull request para revisar e juntar as alterações.

## Exploração (Single Player)

O herói escolhido no menu anda por um mapa sem fim, gerado a partir de uma semente em `scripts/world_gen.gd`. Os inimigos surgem na névoa e o perigo sobe com a distância do início. A jornada acaba quando o herói cai. O combate continua sendo o de `scripts/battle_state.gd`; as regras próprias do modo ficam em `scripts/world_state.gd`, e os números em `WORLD` e `WORLD_SPAWNS`, no fim de `scripts/game_data.gd`. O modo Online continua usando o mapa fixo.

Os biomas (floresta, selva, neve e deserto) mudam a aparência, os nomes das casas e quanto aparece de cada terreno; custo e proteção de cada tipo de terreno são os mesmos em todos. Os números ficam em `BIOMES`, em `scripts/game_data.gd`, e a escolha da arte em `scripts/biome_art.gd`. Os arquivos de `assets/biomes` são gerados a partir de `referencias/biomas` por `tools/build_biomes.py` (Python, com `pillow`, `numpy` e `scipy`).

Testes: `godot --headless --path . --script tests/test_world.gd` para as regras e `godot --path . --script tests/world_smoke.gd -- <pasta> [herói]` para jogar pela tela e salvar capturas. `godot --path . --script tests/biome_shots.gd -- <pasta>` salva uma captura de cada bioma.

## Referências

- [Servidor e modo online](servidor/README.md)
- [Atualizações e exportação](update/README.md)
- [Balanceamento e árvores de skills](BALANCEAMENTO.md)
