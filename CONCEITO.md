# Conceito do jogo

**A escuridão apagou o mundo. A party parte em expedições da Cidade-Farol, resgata quem ainda resiste, acende os faróis de cada região e abre o caminho até o vilão.**

## O ciclo

1. **Cidade-Farol:** a party se prepara, compra melhorias e vê o que mudou.
2. **Expedição:** um mapa novo é gerado. A party explora, luta e sobe de nível.
3. **Locais especiais:** vilas para salvar, ruínas, emboscadas, fontes e memórias.
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

Já existe no modo solo: a Cidade-Farol, por onde a party anda e conversa com os moradores, 2 moradores para resgatar (Curandeira e Ferreiro), 1 região, 5 tipos de local e 1 chefe.

Os números e textos da expedição ficam em `scripts/expedition_data.gd`, e a planta e os textos da cidade, em `scripts/town_data.gd`. As regras estão em `scripts/expedition_state.gd` e `scripts/town_state.gd`, e o save da cidade, em `scripts/town_progress.gd`.

## O que falta

- Testar se a primeira versão faz o grupo querer "só mais uma expedição".
- Ajustar os números em partidas jogadas: os valores atuais são iniciais.
- Levar expedição e cidade para o online, com o save do dono da sala.
- Criar as próximas regiões, os novos biomas, os inimigos próprios e o vilão.
- Dar ao guardião arte e mecânica próprias, em vez de uma múmia reforçada.
- Revisar a história das memórias, que ainda é um rascunho.
