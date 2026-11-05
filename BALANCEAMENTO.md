# Revisão de combate — 03/11/2026

## Diagnóstico

O combate usa relógios individuais: `round(custo × 10 / velocidade)`.
Um passo também consome uma ação. Portanto, 220 de conjuração não são
"duas rodadas": com dez unidades vivas, muitos movimentos e ataques podem
acontecer antes do impacto. A fila é uma estimativa que supõe um passo por
ação; esperar, atacar, subir e morrer mudam a contagem real.

O problema mais claro do mago era a Explosão: velocidade 9 transformava 220
em 244 de espera, com a área fixada no chão, fogo amigo e cancelamento se o
mago morresse. Ele é frágil e ainda precisa sobreviver durante essa janela.
Bola de Fogo e Cura já tinham efeito imediato: o tempo delas é o atraso até
a próxima ação, e não conjuração.

## Ajuste aplicado

| Magia | Espera anterior até o impacto | Nova espera | Recuperação após impacto | Custo total |
| --- | ---: | ---: | ---: | ---: |
| Explosão / Mago | 244 | 133 | 111 | 244 |
| Chama / Feiticeira | 267 | 156 | 111 | 267 |

São unidades do relógio, não segundos. Os valores já consideram velocidade 9.
Nos dados, `time` continua sendo o custo total; `cast_time` define a parte
antes do impacto. A diferença arredondada é cobrada ao resolver a magia.

Isso antecipa a Explosão em 45,5% e a Chama em 41,6%, mantendo dano, área,
alcance, fogo amigo, atributos e custo de repetição. Atingir antes ainda é
uma vantagem real: pode matar um inimigo antes da ação dele. O custo total
igual conserva a cadência sustentada, mas não garante a mesma força prática.

A ficha mostra `conjuração + recuperação`, com explicação ao passar o mouse;
a prévia da fila usa o momento do impacto.

## Leitura de cada classe

Valores de dano abaixo usam chão aberto, mesma altura, alvo com defesa 2,
sem guarda ou flanqueio. Não representam todas as situações da partida.

| Classe | HP / ATQ / DEF / VEL | Dano e tempo efetivo | Avaliação e próxima prioridade |
| --- | --- | --- | --- |
| Guardião | 46 / 11 / 5 / 9 | Golpe: 9 imediato; próxima ação em 167. Guarda: 89. | Aguenta bem, especialmente porque a defesa é subtraída depois da redução de Guarda. Falta uma ferramenta para obrigar ou incentivar o inimigo a atacá-lo. Avaliar proteção de aliado ou provocação antes de aumentar HP/DEF. |
| Duelista | 28 / 12 / 2 / 14 | Golpe: 10 / 107. Rápido: 6 / 64. | Tem forte economia de ações e boa mobilidade. Rápido ganha contra defesa baixa; Golpe ganha contra armadura alta. As duas escolhas têm função. A IA atual escolhe pelo dano por uso, não pela cadência, e tende a desperdiçar essa vantagem. |
| Besteiro | 26 / 13 / 1 / 10 | Tiro: 10 imediato; próxima ação em 170. Alcance 2–4. | Dano sustentado de alvo único um pouco melhor que Bola de Fogo, com mais HP. O mago tem muito mais utilidade; observar a identidade do Besteiro antes de aumentar o dano bruto. Um futuro tiro de maior alcance pode diferenciá-lo. |
| Mago de Fogo | 24 / 15 / 1 / 9 | Bola: 10 imediato / 178. Explosão: 21 por alvo em 133, mais 111 de recuperação. Cura: 14 / 189. | Conjuração era excessiva para uma área fixa. Ajustada. Em área cheia causa muito dano; aumentar também velocidade, dano ou resistência agora dificultaria avaliar o resultado. Cura dá bastante versatilidade e merece acompanhamento. |
| Druida Élfica | 26 / 10 / 1 / 11 | Golpe: 8 / 136. Cura: 14 imediato / 155. | Cura cerca de 22% mais por tempo que o mago e reposiciona mais rápido. Tem vantagem real como suporte, mas pouca identidade exclusiva. Futuramente, uma cura própria ou proteção pode diferenciá-la; não precisa perder valor porque o mago ficou mais ágil ao conjurar. |
| Esqueleto | 22 / 10 / 1 / 10 | Golpe: 8 / 150. | Inimigo básico coerente. Serve como referência; manter nesta rodada. |
| Múmia | 40 / 11 / 3 / 7 | Golpe: 9 / 214. | Lenta, resistente e fácil de controlar pela distância. Funciona como bloqueio. Se ficar irrelevante em partidas, avaliar pressão de aproximação antes de subir ataque. |
| Diabrete | 16 / 8 / 0 / 15 | Golpe: 6 / 100. | Frágil e rápido, bom para pressionar a retaguarda. A ameaça depende da escolha de alvos e caminhos pela IA. Manter os atributos até avaliar esse comportamento. |
| Feiticeira | 20 / 13 / 0 / 9 | Chama: 14 por alvo em 156, mais 111 de recuperação. | Só tem magia carregada e era muito fácil sair da área antes do impacto. Recebeu a mesma divisão de custo do mago; continua com conjuração mais lenta, dano menor e muita fragilidade. |
| Cérbero | 34 / 14 / 2 / 12 | Golpe: 12 / 125. | Maior pressão física entre os inimigos: combina vida, dano e velocidade. Bom alvo prioritário. Se dominar as lutas jogadas, é o primeiro inimigo a revisar; não há evidência suficiente nesta simulação para um nerf. |

## Pontos gerais para a próxima rodada

- **IA:** pontua dano por ação, bônus de abate e quantidade de alvos em área.
  Não considera custo de tempo, chance de escapar da área ou risco de morrer
  durante a conjuração. Por isso, uma luta IA × IA não mede o potencial de
  um jogador que usa Golpe rápido, Guarda e posicionamento deliberadamente.
- **Tanque:** Guarda só protege o próprio Guardião, e a IA não a escolhe.
  Resistência sozinha não garante que ele consiga segurar a linha.
- **Cura:** não há mana, cargas ou recarga própria. O custo é o relógio;
  aumentar a cura sem testar pode prolongar muito as lutas.
- **Terreno e alcance:** ataques à distância não verificam linha de visão.
  Obstáculos impedem movimento, mas não bloqueiam tiros. Isso aumenta o valor
  de Besteiro e Mago e precisa ser considerado antes de dar mais alcance.
- **Dano mágico:** usa a mesma defesa física. A Explosão considera cobertura
  e Guarda, mas não altura; ataques imediatos consideram altura. Essas regras
  existentes foram mantidas.

## Validação

- Antes: 90 verificações aprovadas; luta padrão IA × IA com vitória do jogador,
  quatro sobreviventes, 51 ações e 32 decisões do jogador.
- Depois: 106 verificações aprovadas, incluindo impacto adiantado, prévia da
  fila, preservação exata do custo total e recuperação que impede ação imediata.
- Depois: luta padrão IA × IA com vitória do jogador, quatro sobreviventes,
  45 ações e 28 decisões do jogador.
- Projeto importado pelo editor Godot 4.7.2 em modo headless sem erro de análise
  de scripts. O encerramento do teste de regras ainda emite os avisos de
  ObjectDB/recurso já presentes antes da alteração.

O cenário é determinístico e a IA é simples. Estes resultados validam a
implementação e a conclusão da luta, não uma taxa de vitória balanceada.
Ainda falta validar a sensação em partidas jogadas, especialmente contra
duas ou mais unidades agrupadas e com o mago sob pressão do Cérbero.

# Árvores de skills — 03/11/2026

Dados em `scripts/skill_data.gd`; save em `user://progress.cfg`.

- Cada um dos 6 heróis tem 3 ramos com 4 níveis. Custos por nível: 1, 1, 2 e 3
  (21 pontos para a árvore toda). O teto é de 12 pontos, então não dá para ter tudo.
- Pontos por herói: começa com 2. Na exploração, o herói da jornada ganha +1 a
  cada 5 abates e a cada 20 casas de distância, com mínimo de 1. Na batalha
  online: vitória +2, derrota +1. Redistribuir é grátis.
- Online: cada herói usa a build de quem o controla. O dono da sala valida
  requisitos e o teto de 12, mas não confere quantos pontos o jogador ganhou:
  o save é local.
- Magos agora começam com poucas magias e liberam as demais: Mago de Fogo com
  Faísca, Bola de Fogo, Flor de Fogo e Escudo de Fogo; Mago de Água com Gota,
  Bola d'Água e Floco de Neve.
- A tabela de classes acima descreve o herói sem skills, salvo as magias que
  agora precisam ser compradas.

**Ainda não balanceado.** Na batalha, os inimigos não evoluem. Na exploração, o
perigo sobe com a distância, mas não considera a build. Proteção e Pelas Costas
dependem de aliados e não servem para o herói sozinho na exploração. As habilidades novas receberam
valores iniciais e passaram só por testes de regra, não por partidas jogadas.

## Ataques iniciais novos (2026-11-05)

Cada herói tem duas animações de golpe, a normal e a forte, que servem a várias habilidades (lista em `scripts/hero_juice.gd`). Para usar as duas desde o início:

- Duelista ganhou **Corte Giratório** (corpo a corpo, força 1,3, tempo 210).
- Besteiro ganhou **Virote Pesado** (alcance 2–4, força 1,25, tempo 230).
- Druida trocou o Golpe corpo a corpo por **Chicote de Vinhas** (alcance 1–2, força 0,9, tempo 150). A animação de cura dela é a normal; todos os ataques usam a forte.

Ainda não foram medidos em partidas simuladas.
