# O jogo — resumo

RPG tático de fantasia feito no Godot (4.7), em que você controla uma party de quatro heróis num mapa de hexágonos. Tom melancólico, estética Belle Époque, personagens chibi (ver `ESTILO_VISUAL.md`).

## História
A escuridão apagou o mundo. Sobrou a Cidade-Farol, cuja chama mantém a cidade de pé. Daí a party parte em expedições para resgatar quem ainda resiste e acender os faróis de cada região, até chegar ao vilão que trouxe a escuridão.

## Como se joga (o ciclo)
- **Na cidade:** anda pelas ruas, conversa com os moradores, aceita missões, compra itens e melhora os serviços de quem foi resgatado.
- **Na expedição:** mapa fixo (Subúrbios Apagados, o padrão) ou gerado num bioma: Floresta das Ruínas, Pântano de Tinta, Neve de Cinzas, Deserto de Ouro.
- Exploração em tempo real; combate por turnos ao encontrar inimigos.
- A party sobe de nível e visita vilas para salvar, ruínas, emboscadas, fontes de luz, memórias e lanternas guardadas por elites.
- No fim, um guardião protege o farol da região; derrotá-lo vence a expedição.
- **De volta para casa**, ganhando ou perdendo, a cidade cresce: moradores resgatados reabrem prédios e serviços; brasas, memórias e skills continuam.

Mesma ideia de Hades e Darkest Dungeon II: as expedições recomeçam, a cidade e a progressão ficam.

## O que já existe
- Mapas gerados com rios, cordilheiras, trilhas de pedra, pontes, margens de água e transição entre biomas.
- Mapa fixo 1: Subúrbios Apagados (`MAPA_SUBURBIOS.md`).
- Lanternas: 3 por expedição, cada uma com uma elite, em corrente até o farol (`docs/MAPA_LANTERNAS.md`).
- Combate tático com seis heróis (Guardião, Duelista, Besteiro, Mago de Fogo, Mago de Água, Druida Élfica), árvores de skills e modo online.
- Quatro chefes de bioma: Rei Cervo Sombrio, Rainha Serpente, Jarl de Gelo Negro, Faraó Eclipse. Chefe dos Subúrbios: O Acendedor Apagado.
- A Cidade-Farol, iluminada de noite por tochas e fogueiras, com moradores andando e falando.
- Catorze personagens na cidade. Seis são resgatados nas vilas e cada um reabre um prédio:
  - Curandeira (tenda): vida e frascos de poção.
  - Ferreiro (forja): ataque e armaduras; vende Lâmina de Brasa e Escudo de Ferro Velho.
  - Padeira (forno): cura a cada passo fora de combate e vida; vende Pão de Mel e Torta de Viagem.
  - Cartógrafa (torre de madeira): bússola alcança tudo e depois mostra baús escondidos; vende a Luneta.
  - Arquivista (mansão): experiência a mais e ataque; vende o Tomo das Batalhas.
  - Alquimista (abrigo das docas): poções mais fortes e brasas a mais; vende Elixir Concentrado e Poção Dupla.
- Vinte missões com recompensa, lojas, mochila e mural de missões. Controle de volume.

## O que falta
- A campanha: escolher a região antes de partir, guardar quais faróis foram acesos, dificuldade subindo a cada farol; depois o vilão e o final.
- Ajustar preços, recompensas e dificuldade jogando de verdade (os números atuais são um primeiro chute).
- Arte dos moradores (a original foi recortada da referência e ficou pequena e borrada).
- Levar a expedição e a cidade para o modo online.
- Revisar a história das memórias (rascunho).
