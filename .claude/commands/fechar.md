---
description: Fecha a tarefa atual - testes, ESTADO ATUAL, commit e push
---
1. Rode os testes (`powershell -ExecutionPolicy Bypass -File tools/rodar_testes.ps1`). Se algo falhar, pare e me explique.
2. Atualize `docs/claude/ESTADO_ATUAL.md`: data e hora de hoje, o que mudou nesta tarefa (3-5 linhas), resultado dos testes e o próximo passo. Se a tarefa terminou, marque-a como feita no `docs/claude/PLANO_DE_TRABALHO.md`.
3. Mostre `git status` resumido e proponha a mensagem de commit em português.
4. Faça o commit. Depois me pergunte se pode enviar; se eu disser sim: `git pull`, confira conflitos, e só então `git push` (nunca forçar).
