# Como passar o rpgbolivia para o Claude Code

## 1. Copiar os arquivos (uma vez)
Descompacte este .zip **dentro** de `C:\Users\Eduardo\OneDrive\Documentos\GitHub\rpgbolivia\`.
Ele só ACRESCENTA arquivos (não substitui nada do jogo):

| Arquivo | Para que serve |
|---|---|
| `CLAUDE.md` | O "manual" que o Claude Code lê sozinho toda vez que abre: o jogo, onde fica cada coisa, como testar, regras do Git. |
| `.claude/settings.json` | Permissões: libera git status/diff/commit e os testes sem perguntar; proíbe push forçado e leitura das pastas pesadas (`artifacts/`, backup). |
| `.claude/commands/` | Atalhos: `/tarefa N`, `/testes`, `/fechar`. |
| `tools/rodar_testes.ps1` | Versão do `rodar_testes.bat` sem pausa, que o Claude consegue rodar sozinho. O .bat continua funcionando para você. |
| `docs/claude/` | Os docs do projeto do claude.ai (ESTADO ATUAL, PLANO, JOGO, SUBÚRBIOS, PROMPTS DE ARTE) em Markdown, atualizados. |

Este `LEIA-ME_CLAUDE_CODE.md` pode ser apagado depois.

## 2. Instalar o Claude Code (uma vez)
Precisa de plano Pro ou Max. Duas opções:

- **Com janela (mais fácil):** baixe o app Claude em claude.com/download, entre na aba **Code** e escolha a pasta do projeto.
- **No terminal:** abra o PowerShell e rode
  `irm https://claude.ai/install.ps1 | iex`
  Recomendado ter o Git for Windows instalado (o GitHub Desktop não basta).

## 3. Primeira conversa
No PowerShell:
```
cd "C:\Users\Eduardo\OneDrive\Documentos\GitHub\rpgbolivia"
claude
```
Na primeira vez ele abre o navegador para você entrar na conta. Depois digite:

> Leia o CLAUDE.md e o docs/claude/ESTADO_ATUAL.md. Rode /testes. Depois apague a sujeira listada no ESTADO ATUAL (hud.gd.tmp, os .bak e o .claudeignore.txt), e faça um commit com os arquivos novos do Claude Code.

## 4. Dia a dia
- `/tarefa 3` → começa a Tarefa 3 do plano (ele explica antes de mexer).
- `/testes` → roda os testes e explica as falhas.
- `/fechar` → testes, atualiza o ESTADO ATUAL, commit e pergunta antes do push.
- `/clear` → limpa a conversa entre tarefas (gasta menos).
- O Godot fecha os arquivos? Não precisa fechar o Godot para o Claude editar, mas feche-o antes de rodar os testes se der erro de arquivo em uso.

## 5. E o projeto do claude.ai?
Pode continuar usando para conversar sobre ideias e história. Mas a "verdade" agora fica nos arquivos `docs/claude/` dentro do repositório; se mudar algo lá no claude.ai, peça ao Claude Code para atualizar o arquivo correspondente.
