# rpgbolivia — instruções para o Claude Code

Fale sempre em **português do Brasil**, em linguagem simples (o dono do projeto, Eduardo, não é programador profissional).
Explique o que mudou em poucas linhas, sem jargão. Mostre o resultado, não o passo a passo.

## O jogo em uma frase
RPG tático de fantasia em Godot **4.7.2** (Steam), mapa de hexágonos, party de 4 heróis, tom melancólico Belle Époque com personagens chibi em pixel art.
Ciclo: Cidade-Farol (hub) → expedição (mapa gerado ou fixo) → guardião do farol → volta para casa; a cidade e a progressão ficam (ideia de Hades / Darkest Dungeon II).
Resumo completo: `docs/claude/JOGO.md`. Conceito: `CONCEITO.md`. Estilo: `ESTILO_VISUAL.md`. Números: `BALANCEAMENTO.md`.

## Antes de começar qualquer tarefa
1. Leia `docs/claude/ESTADO_ATUAL.md` e `docs/claude/PLANO_DE_TRABALHO.md`. Só isso; não leia o projeto inteiro.
2. Leia apenas os arquivos que a tarefa toca (o mapa abaixo diz onde fica cada coisa).
3. Mudanças pequenas e fechadas. Se a tarefa crescer, pare e pergunte.

## Onde fica cada coisa
| Parte | Arquivos |
|---|---|
| Tela de jogo (laço de turnos, câmera) | `scripts/battle_view.gd` (classe `BattleView`) + módulos em `scripts/battle/` |
| Módulos da tela | `board_art` (chão/enfeites), `battle_input`, `battle_marks`, `event_player` (anima eventos), `hero_fx`, `roam_control` (andar livre), `journey_ui` (bússola, objetivo), `town_mode`, `net_bridge` |
| HUD | `scripts/hud.gd` (classe `BattleHud`) + `scripts/hud/` |
| Regras de combate | `scripts/battle_state.gd`, `scripts/ai.gd`, `scripts/unit.gd`, `scripts/skill_data.gd`, `scripts/game_data.gd` |
| Expedição | `scripts/expedition_state.gd`, `expedition_data.gd` (números), `expedition_layout.gd`, `expedition_fort.gd`, `world_gen.gd` |
| Lanternas | dentro de `expedition_state.gd` / `expedition_data.gd`; regras em `docs/MAPA_LANTERNAS.md` |
| Mapa 1 Subúrbios (fixo) | `scripts/suburbs_map.gd`, `suburbs_layout.gd`, `suburbs_plan.gd` (GERADO — não editar à mão; editar `tools/build_suburbios_map.py` e rodar de novo) |
| Cidade-Farol | `scripts/town_*.gd`, `scripts/cidade/`, `scenes/town.tscn`, `scenes/cidade.tscn` |
| Save | `scripts/save_game.gd` (ordem fixa por `landmark_order` / id — nunca depender da ordem de Dictionary ou de nós) |
| Online | `net/`, `servidor/` (Node, relay), `scripts/online_lobby.gd`, `scripts/world_state.gd` |
| Conta | `account/` (LootLocker; `account/lootlocker.cfg` é segredo, não commitar) |
| Atualizações | `update/` (cena inicial `update/boot.tscn`, autoload `PatchLoader`) |
| Arte gerada por script | `tools/build_*.py` (Python: pillow, numpy, scipy, opencv-python-headless) → `assets/` |

Os arquivos grandes são `battle_view.gd` (~1270 linhas) e `hud.gd` (~1000). Só divida se for mexer neles.

## Testes (rode depois de qualquer mudança de regra)
Godot no PC: `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`

- Tudo de uma vez (sem janela, sem pausa): `powershell -ExecutionPolicy Bypass -File tools/rodar_testes.ps1`
  Resultado em `tools/saida_testes/resumo.txt` (0 = passou, 1 = falhou; log de cada teste ao lado).
- Um teste só: `"<GODOT>" --headless --path . --script tests/test_<nome>.gd`
- Antes de rodar testes depois de arte ou script novo: `"<GODOT>" --headless --path . --import` (registra `BattleView`/`BattleHud`).
- `SKIP_SIM=1` pula as partidas simuladas (mais rápido). Sem ele, `test_suburbs` e `test_expedition` simulam partidas com robôs.
- Os 11 testes de regras: test_town, test_expedition, test_save, test_battle, test_world, test_battle_camera, test_audio, test_music, test_ruin_scenes, test_lanterns, test_suburbs.
- Capturas de tela (abrem janela): `tests/*_shots.gd -- <pasta>`, ex. `tests/suburbs_shots.gd` ("lugar@graus" gira a câmera, "lugar+" acende as lanternas).
- Se mudar uma regra de propósito, ajuste o teste junto e diga isso ao Eduardo.

## Git
- Repositório: `rocksted21/rpgbolivia` (público), branch `main`. O Eduardo também usa o GitHub Desktop.
- **Sempre `git pull` antes de `git push`.** Nunca `push --force`, nunca `reset --hard`, nunca reescrever histórico.
- Depois de merge com conflito, conferir `git status` e o diff antes de commitar.
- Commit no fim de cada tarefa, mensagem em português dizendo o que mudou. Pergunte antes de fazer push.
- Não commitar: `.godot/`, `tools/saida_testes/`, `account/lootlocker.cfg`, `.env`, builds.

## Não ler (pesado e inútil para código)
`artifacts/` (38 MB de capturas antigas), `_backup_refatoracao/`, `.godot/`, `assets/**/*.png` (salvo se a tarefa for de arte),
`referencias/` (só `referencias/novas/` na Tarefa 7). Não abrir imagens grandes sem necessidade.

## Convenções de código
- GDScript tipado onde já é tipado; nomes de variáveis e comentários seguem o estilo do arquivo (muitos em português).
- Números de jogo ficam em `*_data.gd` (um lugar só), não espalhados.
- Regras ficam nos `*_state.gd` (sem nós de cena); a apresentação fica nos `*_view`/módulos. Os testes dependem dessa separação.
- Arquivos `*.uid` acompanham cada script: ao criar um `.gd`, rode o `--import` para o Godot gerar o `.uid` e commite os dois.
- Não apagar a pasta de experimento `assets/2 tiles*` (TILES_2); vale nos biomas sorteados, não nos Subúrbios.

## Ao fim de cada tarefa
1. Testes verdes (ou falhas explicadas).
2. Atualize `docs/claude/ESTADO_ATUAL.md` em 3–5 linhas (data, o que mudou, próximo passo).
3. Commit. Pergunte se pode dar pull + push.
