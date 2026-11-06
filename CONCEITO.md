# Conceito do jogo

**A escuridão apagou o mundo. A party parte em expedições da Cidade-Farol, resgata quem ainda resiste, acende os faróis de cada região e abre o caminho até o vilão.**

## O ciclo

1. **Cidade-Farol:** a party se prepara, compra melhorias e vê o que mudou.
2. **Expedição:** um mapa novo é gerado. A party explora, luta e sobe de nível.
3. **Caminhos e locais especiais:** uma estrada leva do início ao farol, e trilhas saem dela até vilas para salvar, ruínas, emboscadas, fontes, memórias e baús. Alguns baús ficam longe dos caminhos, para quem explorar.
4. **Farol da região:** o guardião protege o farol. Ao derrotá-lo, a expedição é vencida.
5. **Volta para casa:** vitória ou derrota, a party volta e a cidade cresce.
6. **Vilão:** depois de quatro regiões, a última expedição leva à batalha final.

## O que continua e o que recomeça

| Só na expedição | Continua entre expedições |
| --- | --- |
| Mapa, nível da party e experiência | Brasas guardadas |
| Vida e posição | Moradores resgatados e seus serviços |
| | Memórias encontradas e faróis acesos |
| | Pontos e árvores de skills |

Ao vencer, a party leva todas as brasas. Na derrota, leva metade. Quem foi resgatado continua salvo.

## Primeira versão

Já existe no modo solo: a Cidade-Farol, por onde a party anda e conversa com os moradores, 6 moradores para resgatar, 4 chefes de bioma e 6 tipos de local.

| Morador | Prédio que reabre | Serviço | Vende |
| --- | --- | --- | --- |
| Curandeira | Tenda | Enfermaria (vida) e frascos de poção | — |
| Ferreiro | Forja | Forja (ataque) e armaduras (defesa) | Lâmina de Brasa, Escudo de Ferro Velho |
| Padeira | Forno | Padaria (vida a cada passo fora de combate) e forno a lenha (vida) | Pão de Mel, Torta de Viagem |
| Cartógrafa | Torre de madeira | Torre de Mapas (bússola sem limite; depois, baús escondidos) | Luneta da Torre |
| Arquivista | Mansão | Arquivo (experiência a mais) e diários de guerra (ataque) | Tomo das Batalhas |
| Alquimista | Abrigo das docas | Laboratório (poções mais fortes) e destilaria (brasas a mais) | Elixir Concentrado, Poção Dupla |

Duas vilas por expedição guardam moradores, na ordem da tabela: três expedições salvam todos.

Na cidade também há conversas com escolhas, 20 missões com recompensa (as novas abrem com os resgates ou depois de outra missão), lojas (Mercadora, Sacerdotisa e os moradores resgatados), mochila, melhorias de cada ofício, mural de missões e moradores que andam e falam pelas ruas. A arte dos 4 moradores novos foi recolorida da dos moradores que já existiam.

Os números e textos da expedição ficam em `scripts/expedition_data.gd`, e a planta da cidade, em `scripts/town_data.gd`. Itens, missões e conversas ficam em `scripts/town_content.gd`. As regras estão em `scripts/expedition_state.gd` e `scripts/town_state.gd`, e o save da cidade, em `scripts/town_progress.gd`.

## O que falta

- Testar se a primeira versão faz o grupo querer "só mais uma expedição".
- Ajustar os números em partidas jogadas: os valores atuais são iniciais.
- Levar expedição e cidade para o online, com o save do dono da sala.
- Criar as próximas regiões, os novos biomas, os inimigos próprios e o vilão.
- Dar ao guardião arte e mecânica próprias, em vez de uma múmia reforçada.
- Revisar a história das memórias, que ainda é um rascunho.
