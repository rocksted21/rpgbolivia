# Lanternas do mapa

**Status:** 10a implementada em 07/11/2026 (regras, save e `tests/test_lanterns.gd`). Falta a 10b (visual).

Decidido em 06/11/2026. Primeiro item do "Pacote Vida" do mapa (Tarefa 10 do plano).

## Ideia
Cada expedição tem **3 lanternas apagadas**, cada uma guardada por uma **elite**. Elas formam uma corrente até o guardião:
ao entrar no mapa você sabe onde fica a 1ª; ao acender uma, recebe a área da próxima; a 3ª revela o farol.
Dá objetivo à exploração e uma escada de dificuldade até o chefe.

## Regras

### 1. Posição (gerada com o mapa, em zigue-zague)
| Local | Distância do início |
|---|---|
| Lanterna 1 | 14 a 18 casas |
| Lanterna 2 | 26 a 30 casas |
| Lanterna 3 | 36 a 40 casas |
| Farol | 45 (`BEACON_DISTANCE`, como hoje) |

- Cada lanterna fica a **pelo menos 18 casas da anterior** (força ir para outro lado e cruzar vilas e ruínas).
- Mas de preferência **no máximo 26** da anterior, e a 3ª entre 12 e 24 casas do farol (para não virar uma caminhada sem fim). Mapas apertados afrouxam essas regras aos poucos, nunca abaixo de 9 casas.
- Mesmas regras dos outros locais: alcançável, longe da borda, com espaço em volta para a luta (como `BEACON_MIN_EXITS`).

### 2. Revelação
- Ao entrar no mapa, a **área** da lanterna 1 aparece na bússola: círculo de 6 casas, não o ponto exato.
- Com `far_compass` (Cartógrafa ou Mapa Rasgado), o círculo cai para 3 casas.
- A 2 casas da lanterna, ela aparece exata.
- Acender a lanterna N revela a área da N+1. Acender a 3ª revela o farol exato.
- Lanterna acesa ilumina em volta: os locais a até 10 casas entram na bússola.

### 3. Elite (guarda de cada lanterna)
- 1 elite + escolta: lanterna 1 = 1 escolta, 2 = 2, 3 = 3.
- Elite = o tipo mais forte do bioma, chamada "Sentinela da Lanterna", com aura visível.

| Lanterna | Vida | Ataque | Brasas | XP |
|---|---|---|---|---|
| 1 | ×1,8 | ×1,10 | 10 | 40 |
| 2 | ×2,2 | ×1,15 | 14 | 60 |
| 3 | ×2,8 | ×1,20 | 18 | 80 |

(Para comparar: o guardião hoje tem vida ×3,5 e ataque ×1,25.)
- Ao vencer: a lanterna acende e a party cura 30%.
- **Perder para a elite = derrota normal da expedição** (sobra `DEFEAT_BRASAS` = 50% das brasas).

### 4. Farol e guardião (opção B)
- O farol **não aparece na bússola** até a 3ª lanterna. Explorando, ele aparece ao chegar perto (regra das 2 casas).
- Dá para lutar sem as lanternas, mas cada lanterna **apagada** deixa o guardião com **+20% de vida e +8% de ataque**.
  - 3 acesas: normal (×3,5 / ×1,25).
  - 0 acesas: vida ×1,6 e ataque ×1,24 em cima disso.
- Prêmio de ousadia: +5 brasas por lanterna apagada ao vencer o guardião.

### 5. Interações
- Cartógrafa e Mapa Rasgado continuam ampliando a bússola, mas nunca revelam o farol nem uma lanterna antes da hora: só deixam a área mais precisa.
- Dificuldade da campanha (Tarefa 4): o multiplicador por farol aceso também vale para as elites.

## Save
- Guardar a posição de cada lanterna, quais estão acesas e quais áreas foram reveladas.
- Usar a mesma ordem fixa dos landmarks (`landmark_order`) para não embaralhar ao carregar.

## Testes de regras (arquivo novo)
- 20 mapas com sementes diferentes: sempre 3 lanternas, alcançáveis, nas faixas de distância e a 18+ casas da anterior.
- Revelação em cadeia: no início só a área da 1ª; acender a 1 revela a 2ª; acender a 3 revela o farol.
- Força do guardião com 0, 1, 2 e 3 lanternas acesas.
- Save/load no meio da corrente mantém lanternas e revelações.

## Onde mexe no código (previsto)
- `scripts/expedition_data.gd`: constantes das lanternas e da elite.
- `scripts/expedition_state.gd`: posicionar (`_place_landmarks`), acordar a elite (como `_wake_guards`/`_wake_beacon`), acender, revelar, força do guardião em `_wake_beacon`.
- `scripts/battle/journey_ui.gd`: bússola sem o farol antes da hora; chip de área para a próxima lanterna.
- `scripts/save_game.gd`: salvar e carregar o estado das lanternas.
- Arte: lanterna apagada/acesa (dá para reaproveitar tochas e fogueiras da cidade); aura da elite por cor/brilho.

## Divisão em conversas
- **10a**: geração, elite, cadeia de revelação, guardião, save e testes (só regras, sem arte nova).
- **10b**: visual (lanterna acesa iluminando, aura da elite, área no radar) e ajuste dos números jogando.

## Pacote Vida do mapa (depois das lanternas, ainda sem regras)
- O mapa reage: vila salva acesa, ruína limpa vira acampamento seguro, fonte com vaga-lumes.
- Coleta ligada à cidade: ervas, sucata e farinha para Alquimista, Ferreiro e Padeira.
- Sobreviventes andando pelas trilhas, escoltados até vila ou cidade.
- Sombras que patrulham, eventos com escolha nos cenários (carroça, santuário, jardim, travessia), fauna de ambiente, mercadora ambulante, pesca.
