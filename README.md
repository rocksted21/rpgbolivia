# RPG Bolivia — Combate Tático

Projeto do jogo em Godot. Esta pasta contém o código, as cenas e os assets usados no desenvolvimento.

## Começar a desenvolver

1. Clone `https://github.com/rocksted21/rpgbolivia.git` pelo GitHub Desktop.
2. Importe o arquivo `project.godot` no Godot 4.7 ou em uma versão compatível.
3. Aguarde a importação dos assets e pressione F6 para executar a cena aberta ou F5 para executar o jogo.

O Godot recria a pasta `.godot/` automaticamente. Compilações em `build/`, dependências em `servidor/node_modules/` e configurações locais não são versionadas.

Para trabalhar em conjunto, crie uma branch no GitHub Desktop, faça seus commits e envie a branch com **Publish branch** ou **Push origin**. Abra um pull request para revisar e juntar as alterações.

## Expedição (Single Player)

O **Single Player** abre a Cidade-Farol, um mapa fixo por onde a party anda e conversa com os moradores. De lá ela parte para um mapa novo a cada expedição, sobe de nível, visita locais especiais e enfrenta o guardião do farol. O conceito está em [CONCEITO.md](CONCEITO.md); os números, em `scripts/expedition_data.gd`.

A arte da cidade é gerada a partir de `referencias/cidade.jpg` por `tools/build_town.py` (com `opencv-python-headless`). As construções têm desenho de todos os lados: são modelos em `tools/build_town_models.py` (Python, com `pillow` e `numpy`), e a planta fica em `scripts/town_data.gd`. A arte dos biomas é gerada a partir das pranchas de `referencias/biomas` por `tools/build_biomes.py` (Python, com `pillow`, `numpy` e `scipy`). As texturas contínuas do chão saem dessa arte com `tools/build_ground.py` (Python, com `pillow` e `numpy`). `tests/biome_shots.gd` salva uma captura de cada bioma. `tests/map_preview.gd` desenha o mapa visto de cima, para comparar mudanças no gerador (`scripts/world_gen.gd`).

A forma tática do mapa da expedição fica em `scripts/expedition_layout.gd`: zonas separadas por serras, ligadas por passagens de 2 casas, com um platô e uma rampa em cada zona. Depois de pôr os locais, ele confere se tudo é alcançável e abre caminho no que não for. A Jornada online continua sem zonas. `tests/layout_shots.gd` salva capturas das passagens e dos platôs.

Os caminhos ficam em `scripts/world_gen.gd`: as linhas de ruído formam estradas e trilhas em todo mapa, e `route()` e `carve()` abrem os que ligam lugares. A expedição abre uma estrada do início ao farol e uma trilha até cada local (`_carve_trails`, em `scripts/expedition_state.gd`). Cada braço do caminho é uma peça de `assets/biomes/<bioma>` (`estrada_*`, `estrada_borda_*` e `trilha_*`), e `scripts/biome_art.gd` escolhe quais desenhar em cada casa.

Testes: `godot --headless --path . --script tests/test_expedition.gd` para as regras (com `SKIP_SIM=1` pula as partidas simuladas) e `godot --path . --script tests/expedition_smoke.gd -- <pasta>` para jogar pela tela e salvar capturas.

## Jornada (Online)

Uma party de até 4 heróis anda por um mapa sem fim, gerado a partir de uma semente em `scripts/world_gen.gd`. Fora de combate, cada herói anda livre, sem turnos; o botão **Em fila/Separados** (tecla G) decide se a party segue o herói selecionado em fila ou se só ele anda (Tab troca de herói). Quando o combate começa, a fila se abre: cada herói anda até uma casa próxima, longe dos outros. Segurar Q ou E, os botões da tela ou o botão do meio do mouse gira a câmera suavemente, e ela para em qualquer ângulo, sem mudar as regras.

Os inimigos surgem na névoa e o perigo sobe com a distância do início. O combate por turnos começa no próprio mapa quando um inimigo vê um herói ou é atacado, e termina quando os inimigos caem ou a party foge para longe. Em cada turno, a unidade anda várias casas e depois usa uma ação, que encerra o turno; o botão **Encerrar turno** (ou Espaço) passa a vez sem agir. Quem caiu volta ferido ao fim do combate, e a jornada acaba quando todos caem.

No Online, de 2 a 4 pessoas escolhem os heróis na sala e dividem a mesma jornada. O dono da sala simula tudo e valida os comandos; os outros recebem o estado e animam.

O combate está em `scripts/battle_state.gd`; as regras da jornada, em `scripts/world_state.gd`; os números, em `WORLD` e `WORLD_SPAWNS`, em `scripts/game_data.gd`.

Testes: `godot --headless --path . --script tests/test_world.gd` para as regras e `godot --path . --script tests/world_smoke.gd -- <pasta> [herói]` para jogar pela tela e salvar capturas. A integração online está em `tests/test_online.gd` e `tests/test_online_pair.gd`, com o relay aberto na porta 18787.

## Peso dos golpes (juice)

Golpes e magias dos 6 heróis têm hitstop, tremor de tela, clarão, tranco em quem apanha, números que saltam, rastros e câmera lenta no abate final. É só apresentação: as regras e os eventos não mudam. O peso de cada habilidade está em `scripts/hero_juice.gd`; os efeitos de tela, em `scripts/battle_juice.gd`. Os brilhos usam o shader aditivo `scripts/battle_perspective_add.gdshader` e partículas do Kenney Particle Pack (CC0) em `assets/fx/kenney`.

Para ver cada golpe quadro a quadro: `godot --path . --fixed-fps 30 --script tests/juice_shots.gd -- <pasta> [cena]`. Com `--write-movie <arquivo>.avi` e a cena `video`, grava os melhores momentos.

## Onde fica cada parte da tela de jogo

`scripts/battle_view.gd` (classe `BattleView`) é a tela de jogo: começa a partida, roda o laço de turnos, a câmera e as contas de posição das casas. O resto mora em módulos em `scripts/battle/`, cada um com acesso à tela por `battle`:

| Arquivo | O que faz |
| --- | --- |
| `board_art.gd` | Chão, casas, paredes, enfeites, locais e o mapa que carrega aos poucos |
| `battle_input.gd` | Cliques, teclas, menu de ações, ficha e troca de herói |
| `battle_marks.gd` | Destaques no chão (caminho, alcance, área), dica do rodapé e marcadores da fila |
| `event_player.gd` | Anima os eventos das regras: andar, atacar, dano, cura, morte e magias |
| `hero_fx.gd` | Peso dos golpes dos heróis (juice) |
| `roam_control.gd` | Caminhada livre e fila da party fora de combate |
| `journey_ui.gd` | Objetivo, bússola, missão, poção e resultado da expedição |
| `town_mode.gd` | Cidade-Farol: moradores e partida |
| `net_bridge.gd` | Comandos e pacotes do online |

O HUD segue a mesma ideia: `scripts/hud.gd` (classe `BattleHud`) guarda os sinais e os textos do topo, e os componentes ficam em `scripts/hud/` (`options_menu.gd`, `unit_card.gd`, `action_menu.gd`, `party_bar.gd` e `timeline.gd`). As funções que outros scripts e os testes chamam continuam na tela e no HUD, no fim de cada arquivo, em "Repasses".

Os nomes `BattleView` e `BattleHud` são registrados pelo editor: depois de baixar o projeto, abra-o uma vez no Godot (ou rode `godot --headless --path . --import`) antes de rodar os testes pela linha de comando.

## Referências

- [Servidor e modo online](servidor/README.md)
- [Atualizações e exportação](update/README.md)
- [Conceito do jogo](CONCEITO.md)
- [Estilo visual](ESTILO_VISUAL.md)
- [Balanceamento e árvores de skills](BALANCEAMENTO.md)

## Menu principal

`scripts/main_menu.gd` desenha o menu sobre `assets/menu/fundo.jpg`. Essa arte é gerada de `referencias/menu.jpg` por `tools/build_menu.py` (Python, com `pillow`, `numpy` e `opencv-python-headless`), que tira da imagem os textos, o botão aceso e os atalhos. `godot --path . --script tests/test_menu.gd -- <pasta>` confere o menu e salva capturas.
