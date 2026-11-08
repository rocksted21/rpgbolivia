# Heróis no PixelLab

Os 7 heróis jogáveis e o personagem do PixelLab de cada um. A chave é o nome usado no código
(`combate/scripts/game_data.gd`) e a pasta é onde o ZIP exportado fica (`pixellab/<pasta>`).

| Herói | Chave | Pasta | Link |
|---|---|---|---|
| Guardião (dark) | `guardiao` | `guardiao_dark` | https://www.pixellab.ai/create-character/05442a13-effd-4db9-8324-98dbea4160ff |
| Duelista | `duelista` | `duelista` | https://www.pixellab.ai/create-character/d4e7f625-7e6d-43cc-ba08-f774d1dce271 |
| Besteiro / Arqueiro | `besteiro` | `besteiro` | https://www.pixellab.ai/create-character/f567b418-820f-4d75-8e14-6872ec38edaf |
| Mago de Fogo | `mago` | `mago` | https://www.pixellab.ai/create-character/c5f7d158-be21-460b-a836-cd495b663f8b |
| Mago de Sangue (ex-Água) | `mago_agua` | `mago_sangue` | https://www.pixellab.ai/create-character/77bb861e-ef92-4726-b817-bfffdf139398 |
| Curandeira (dark, ex-Druida) | `druida` | `curandeira_dark` | https://www.pixellab.ai/create-character/3507276c-db46-4f5c-90d9-776c4c768feb |
| Andarilho da Fumaça (Smoke 3) | `fumaca` | `fumaca` | https://www.pixellab.ai/create-character/389e7df3-09d9-475b-98b4-da5ce98ee454 |

Animações que o jogo usa (todas em sul, leste e norte, menos idle e morte, que são só sul):
idle, walking, `attack_normal`, `attack_strong`, hurt (`jerk_backward…`) e morte (`Recoil…` / `Jolt…`).

Para pôr no jogo: baixar o ZIP (`https://api.pixellab.ai/mcp/characters/<id>/download`), extrair em
`pixellab/<pasta>` e rodar `tools/build_pixellab.gd` (ver o cabeçalho do script).
