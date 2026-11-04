# RPG Bolivia — Combate Tático

Projeto do jogo em Godot. Esta pasta contém o código, as cenas e os assets usados no desenvolvimento.

## Começar a desenvolver

1. Clone `https://github.com/rocksted21/rpgbolivia.git` pelo GitHub Desktop.
2. Importe o arquivo `project.godot` no Godot 4.7 ou em uma versão compatível.
3. Aguarde a importação dos assets e pressione F6 para executar a cena aberta ou F5 para executar o jogo.

O Godot recria a pasta `.godot/` automaticamente. Compilações em `build/`, dependências em `servidor/node_modules/` e configurações locais não são versionadas.

Para trabalhar em conjunto, crie uma branch no GitHub Desktop, faça seus commits e envie a branch com **Publish branch** ou **Push origin**. Abra um pull request para revisar e juntar as alterações.

## Expedição (Single Player)

O **Single Player** abre a Cidade-Farol, de onde a party parte para um mapa novo a cada expedição, sobe de nível, visita locais especiais e enfrenta o guardião do farol. O conceito está em [CONCEITO.md](CONCEITO.md); os números, em `scripts/expedition_data.gd`.

Testes: `godot --headless --path . --script tests/test_expedition.gd` para as regras (com `SKIP_SIM=1` pula as partidas simuladas) e `godot --path . --script tests/expedition_smoke.gd -- <pasta>` para jogar pela tela e salvar capturas.

## Jornada (Online)

Uma party de até 4 heróis anda por um mapa sem fim, gerado a partir de uma semente em `scripts/world_gen.gd`. Fora de combate, cada herói anda livre, sem turnos; o botão **Em fila/Separados** (tecla G) decide se a party segue o herói selecionado em fila ou se só ele anda (Tab troca de herói). Quando o combate começa, a fila se abre: cada herói anda até uma casa próxima, longe dos outros. Segurar Q ou E, os botões da tela ou o botão do meio do mouse gira a câmera suavemente, e ela para em qualquer ângulo, sem mudar as regras.

Os inimigos surgem na névoa e o perigo sobe com a distância do início. O combate por turnos começa no próprio mapa quando um inimigo vê um herói ou é atacado, e termina quando os inimigos caem ou a party foge para longe. Quem caiu volta ferido ao fim do combate, e a jornada acaba quando todos caem.

No Online, de 2 a 4 pessoas escolhem os heróis na sala e dividem a mesma jornada. O dono da sala simula tudo e valida os comandos; os outros recebem o estado e animam.

O combate está em `scripts/battle_state.gd`; as regras da jornada, em `scripts/world_state.gd`; os números, em `WORLD` e `WORLD_SPAWNS`, em `scripts/game_data.gd`.

Testes: `godot --headless --path . --script tests/test_world.gd` para as regras e `godot --path . --script tests/world_smoke.gd -- <pasta> [herói]` para jogar pela tela e salvar capturas. A integração online está em `tests/test_online.gd` e `tests/test_online_pair.gd`, com o relay aberto na porta 18787.

## Referências

- [Servidor e modo online](servidor/README.md)
- [Atualizações e exportação](update/README.md)
- [Conceito do jogo](CONCEITO.md)
- [Balanceamento e árvores de skills](BALANCEAMENTO.md)
