# ⚠ SPOILER — História da Cidade-Farol

> O dono do projeto quer jogar sem spoiler. **Não mostre nada deste arquivo no chat.**
> Este arquivo existe só para manter a história coerente entre sessões.
> Os textos que vão para o jogo ficam em `scripts/town_content.gd` (STORY, TALK) e
> `scripts/expedition_data.gd` (MEMORIES, BOSS_LINES, BOSS_FAREWELL, VILLAIN).

## A verdade (o que o jogador descobre aos poucos)

- **Vésper, o Primeiro Faroleiro**, acendeu a Grande Chama da Cidade-Farol e os quatro faróis
  das regiões. As chamas guardam mais que luz: guardam a **memória** das coisas. Enquanto uma
  chama arde perto de algo, esse algo é lembrado — e por isso existe.
- Vésper tinha pavor de que algo fosse esquecido. Começou a **guardar tudo dentro de si**:
  bebeu as estrelas, depois as estradas, depois os nomes. O que ele guarda para si, o mundo
  esquece. **Isso é a escuridão.** Ele não se acha vilão: acha que está salvando tudo.
  A pergunta dele: *"Num mundo que esquece, quem vai lembrar de vocês se eu soltar?"*
- A **Ordem dos Faroleiros** estava lá quando começou. **Bento**, aprendiz de Vésper (hoje o
  velho Faroleiro da cidade), deu a ordem: **apaguem os faróis** — sem chama acesa, Vésper não
  tem o que beber. Quatro faroleiros ficaram no escuro, cada um guardando a última brasa do
  farol da sua região, "mesmo de quem a acendeu". Antes de ir, acenderam as **fontes de luz**
  para quem viesse depois.
- Com os anos, a escuridão transformou os quatro nos **guardiões** (os chefes):
  - Tomé, caçador da floresta → **Rei Cervo Sombrio** (Floresta das Ruínas)
  - Killa, curandeira do pântano → **Rainha Serpente** (Pântano de Tinta)
  - Gunnar, capitão da guarda → **Jarl de Gelo Negro** (Neve de Cinzas)
  - Inti, astrônoma que contava as estrelas → **Faraó Eclipse** (Deserto de Ouro)
  Eles lutam contra os heróis porque não distinguem mais amigo de Vésper. Ao cair, lembram o
  próprio nome e entregam a brasa.
- Bento ficou na cidade mantendo a Grande Chama, vivendo muito mais do que devia, com culpa.
  Ele riscou na parede os nomes dos que mandou para o escuro.
- **Os heróis** (e o Pavio) chegaram pelo mar escuro em barcos antigos, sem remos e sem nome.
  Eram **nomes que Vésper guardava**; a Grande Chama os chamou de volta. Por isso não lembram
  de nada. A chama que eles levam é **nova**: Vésper não consegue bebê-la. Por isso os
  faróis reacendidos por eles são seguros — e, com os quatro acesos, a luz encontra o
  esconderijo dele.
- **O Farol Negro** aparece onde as quatro terras se encontram (o centro dos biomas no
  world_gen). É onde Vésper se esconde com tudo o que roubou. É a batalha final.
- **Final**: Vésper, vencido, solta tudo ("Então... lembrem por mim."). As estrelas voltam.
  Pavio lembra o nome verdadeiro (**Lucas**) mas prefere continuar Pavio. Bento entrega a
  chama ao Pavio — "Não a guarde. Divida." — o contrário de Vésper. Tema: **o que se guarda
  só para si apaga; o que se divide continua aceso.**

## Personagens novos

- **Pavio** (id `guia`, arte `morador_g`): aprendiz do Faroleiro, garoto animado. Também veio
  do mar escuro sem nome. Fica ao lado da fonte da praça, perto de onde a party começa.
  É o guia: conta a história em capítulos e diz o objetivo.
- **Bento**: o Faroleiro (id `guarda`). Na interface continua "Faroleiro"; o nome é revelado
  no capítulo 3.
- **Vésper**: o vilão. Só é nomeado no capítulo 3 (antes: "ele", "quem acendeu a luz").

## Capítulos (STORY em town_content.gd, contados pelo Pavio)

O capítulo atual = faróis acesos (0 a 4); 5 = depois da batalha final (`story/final` no save).
Se o jogador pula capítulos (acende 2 faróis sem falar com o Pavio), ele conta todos em
sequência.

0. **O despertar** (início): acharam vocês num barco; cidade é o último lugar com luz;
   escuridão apaga nomes; acender os 4 faróis; falem com o Faroleiro.
1. **Uma luz no horizonte** (1 farol): o Faroleiro perguntou se o guardião disse algo antes de cair.
2. **Os guardiões tinham nome** (2): o Faroleiro diz nomes e pede desculpas; eram gente daqui?
3. **O Primeiro Faroleiro** (3): Bento desce da torre e conta a verdade sobre Vésper e a ordem.
4. **O Farol Negro** (4): a torre apareceu no centro; os heróis (e o Pavio) saíram de lá.
5. **Final** (depois da batalha final): estrelas de volta, Lucas/Pavio, Bento passa a chama.

## Pistas espalhadas

- **Memórias** (expedições, em ordem): medo de Vésper; mapa de estrelas riscado (Inti);
  diário "estavam aqui quando começou"; sino de barco com nome raspado; nomes riscados na
  parede; carta assinada "B." a Vésper; ordem selada de apagar os faróis; juramento; voz de
  Vésper ("só não queria perder mais ninguém"); nome escrito num barco que faz um herói chorar.
- **Chefes**: fala ao começar a luta (BOSS_LINES) e últimas palavras na tela de vitória
  (BOSS_FAREWELL) — cada uma dá o nome antigo e uma pista.
- **Faroleiro**: depois de vencer cada guardião, ganha a pergunta "Quem era o ...?".
- **Pescador**: viu o Pavio puxar o barco dos heróis — madeira antiga, igual à dos faroleiros.
- **Moradores**: falas novas por capítulo (TALK[...]["stages"]) e perguntas que se abrem
  (TALK[...]["topics_at"]).

## O que ainda não existe no jogo

- As regiões não têm ordem: cada expedição sorteia o bioma do farol, então dá para vencer
  o mesmo guardião mais de uma vez. A história conta faróis, não regiões.
- Não existe a expedição final/Farol Negro nem a luta contra Vésper. Os textos estão prontos:
  `Exp.VILLAIN` (nome, fala de entrada, últimas palavras) e o capítulo 5 (STORY[5]), que
  aparece quando algo chamar `TownProgress.finish_story()`.
