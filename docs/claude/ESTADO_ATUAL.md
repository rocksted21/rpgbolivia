# Estado do projeto — 08/11/2026, 12:00

## Ajuste (08/11) — ferramentas do Claude
- Conferido: 9 skills de Godot, atalhos /tarefa /testes /fechar e PixelLab (pixel art) funcionando. Plugin do GitHub instalado, mas sem conectar (reconectar em claude.ai → Conectores).
- `.claude/settings.json`: as permissões agora valem também para o PowerShell (git, testes, Godot sem janela); as proibições (push forçado, reset, clean) também.
- Próximo passo: o mesmo de antes (jogar os Subúrbios e anotar no `BALANCEAMENTO.md`).

## Última tarefa (08/11, 12:00) — primeira conversa no Claude Code
- Arquivos do Claude Code entraram no projeto (CLAUDE.md, .claude/, docs/claude/, tools/rodar_testes.ps1).
- Testes no PC: 11 de 11 verdes. `test_audio` falhava porque não reconhecia sons de menu ligados por `bind_button` (o `click3` da arena); o teste foi corrigido, o jogo não mudou.
- Sujeira apagada: hud.gd.tmp, town_panels.gd.bak, cidade.tscn.bak, .claudeignore.txt.
- Git de linha de comando não está instalado; o Claude usa o git do GitHub Desktop.
- Próximo passo: jogar os Subúrbios e anotar em `BALANCEAMENTO.md` (item 2 abaixo).

## Onde está
- Pasta no PC: `C:\Users\Eduardo\OneDrive\Documentos\GitHub\rpgbolivia` (Godot 4.7.2, Steam).
- GitHub: `rocksted21/rpgbolivia` (público). Último commit em `main`: `281475a` (08/11, 10:46).
- A partir de hoje o trabalho é feito no **Claude Code**, direto na pasta do PC: ele lê, edita, roda os testes e faz commit.

## O que já foi enviado ao GitHub
- Mapa 1, Subúrbios Apagados (regras em `docs/claude/MAPA_SUBURBIOS.md`): mapa fixo, 12 bairros, 7 segredos, 2 rotas de lanternas, chefe O Acendedor Apagado.
- Lanternas 10a (regras, save, `tests/test_lanterns.gd`). Falta a 10b (visual).

## Testes
- Última rodada: 11 de 11 arquivos verdes (inclui test_suburbs).
- Simulação de robôs: party sem melhorias 0/3 nos Subúrbios, com melhorias 1/3 (no mapa sorteado: 0/3 em todas) → a dificuldade está alta.

## Sujeira conhecida no repositório
- `scripts/hud.gd.tmp.*`, `scripts/town_panels.gd.bak`, `scenes/cidade.tscn.bak`: arquivos temporários que foram para o Git. Podem ser apagados.
- `.claudeignore.txt` na raiz: não é usado pelo Claude Code (o que vale é `.claude/settings.json`). Pode ser apagado.
- `artifacts/` (38 MB) e `_backup_refatoracao/` estão no Git (ver "Limpeza opcional" no plano).

## Próximos passos
1. Primeira conversa no Claude Code: rodar `/testes` para conferir que tudo funciona no PC; apagar a sujeira acima; commit.
2. Jogar uma expedição nos Subúrbios e anotar em `BALANCEAMENTO.md` (distâncias das lanternas, baús a mais dos segredos, perigo a cada 13 casas, vitória difícil demais nas simulações).
3. Arte própria do Acendedor (hoje é o Rei Cervo recolorido).
4. Campanha (Tarefas 3 e 4 do plano).
