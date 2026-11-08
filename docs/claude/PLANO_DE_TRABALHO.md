# Plano de trabalho — rpgbolivia (atualizado 08/11/2026 para o Claude Code)

## Como trabalhar gastando pouco
- **Uma conversa por tarefa.** Abra o Claude Code na pasta do projeto e digite `/tarefa N`. Para começar do zero entre tarefas, use `/clear`.
- O Claude lê `ESTADO_ATUAL.md` e este plano, mais nada; depois só os arquivos da tarefa.
- O Claude roda os testes sozinho (`/testes`). Não precisa mais colar o `resumo.txt`.
- Peça mudanças pequenas e fechadas: "mexa só em X e Y". Evite "revise o projeto todo".
- Ao fim: `/fechar` (testes, atualiza ESTADO ATUAL, commit, e pergunta antes do push).
- Para jogar e ver o resultado, abra o Godot você mesmo (o Claude não vê a janela do jogo; ele pode gerar capturas com os `tests/*_shots.gd`).

## Feitas
- ~~Tarefa 1 — Testes verdes~~ (sujeira apagada em 08/11).
- ~~Tarefa 2 — Falha do save~~.
- ~~Tarefa 10a — Lanternas: regras, save e testes~~ (07/11).
- ~~Mapa 1 — Subúrbios Apagados~~ (08/11), ver `MAPA_SUBURBIOS.md`.

## A fazer (cada uma cabe numa conversa)

### Tarefa 3 — Campanha, parte 1: dados (média)
- Arquivo de campanha: quais faróis foram acesos, região escolhida, nível de dificuldade.
- Salvar e carregar junto com a cidade. Teste de regras novo para isso.
- Sem tela ainda.

### Tarefa 4 — Campanha, parte 2: escolher a região (média)
- Tela ou mapa simples antes de partir: Subúrbios + 4 biomas, mostrando faróis acesos.
- Dificuldade sobe a cada farol aceso (um multiplicador em vida/dano dos inimigos, num lugar só; vale também para as elites das lanternas).

### Tarefa 5 — Vilão e final (grande; 2 conversas)
- 5a: desenho do vilão e da luta final no papel (história + regras), registrado no `CONCEITO.md`. (Ver também `docs/SPOILER_historia.md`.)
- 5b: implementar a luta e a cena final.

### Tarefa 6 — Balanceamento (contínua, barata)
- Você joga e anota em `BALANCEAMENTO.md`: "preço X caro", "chefe Y fácil".
- Uma conversa curta aplica uma lista de ajustes de uma vez. Os números ficam em `scripts/*_data.gd`.
- Começar pelos Subúrbios: nas simulações a party quase nunca vence.

### Tarefa 7 — Arte dos moradores (fora do código)
- Gerar as imagens fora do Claude com `docs/claude/PROMPTS_DE_ARTE.md`, salvar em `referencias/novas/`, e então `/tarefa 7` para encaixar.

### Tarefa 8 — Online da expedição e da cidade (grande, deixar por último)
- Só depois da campanha pronta, para não refazer duas vezes.

### Tarefa 9 — Texto das memórias (barata)
- Uma conversa só de escrita, com a lista de memórias.

### Tarefa 10b — Lanternas: visual (média)
- Lanterna acesa iluminando em volta, aura da elite, área no radar; ajuste dos números jogando. Regras em `docs/MAPA_LANTERNAS.md`.

### Tarefa 11 — Arte do Acendedor Apagado
- Hoje é a folha do Rei Cervo em cinza. Gerar no PixelLab (ver PROMPTS_DE_ARTE) e encaixar.

## Pacote vida do mapa (ideias, ainda sem regras)
- O mapa reage: vila salva acesa, ruína limpa vira acampamento seguro, fonte com vaga-lumes.
- Coleta ligada à cidade: ervas, sucata, farinha para Alquimista, Ferreiro e Padeira.
- Sobreviventes andando pelas trilhas, escoltados até vila ou cidade.
- Sombras que patrulham; eventos com escolha (carroça, santuário, jardim, travessia); fauna; mercadora ambulante; pesca.
- Subúrbios: nome do bairro aparecendo ao entrar; mais barracas na feira.

## Limpeza opcional
- `artifacts/` (38 MB) e `_backup_refatoracao/` estão no Git: avaliar tirar (`.gitignore` + `git rm --cached`).
- `battle_view.gd` (~1270 linhas) e `hud.gd` (~1000): só dividir mais se for mexer neles.
