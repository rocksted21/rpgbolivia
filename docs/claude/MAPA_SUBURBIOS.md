# Mapa 1 — Subúrbios Apagados (08/11/2026)

Mapa fixo desenhado à mão, com variações por expedição. É o padrão: sem bioma escolhido, a expedição vai para cá.
Imagem do mapa inteiro: `docs/mapa_suburbios.png`.

## Estrutura
- Início na Praça do Portão (0,0), muralha da Cidade-Farol ao sul (atrás dela, as casas acesas da cidade). Farol no alto da Colina do Observatório (0,-34), ~34 casas.
- Avenida dos Lampiões corta o mapa até o canal; a ponte do meio caiu (a avenida não atravessa).
- Canal das Eclusas divide sul e norte. Pontes: das Eclusas (oeste, col -18) e de Ferro (leste, col 18). Vau secreto no meio.
- Bairros: Praça do Portão, Avenida, Rua das Tílias (transversal), Vila Operária, Jardins Aurélio, Cemitério da Colina (alto, cercado), Parque do Coreto (lago com ilhota), Praça do Mercado (feira), Quartel da Vigília (= Forte da Vigília na 1ª expedição), Bairro da Capela, Usina de Gás, Colina do Observatório (penhasco, só a escadaria sobe).

## Lanternas (a semente escolhe a rota)
- Rota oeste: Largo dos Tecelões (-14,-3) → Praça do Mercado (7,-16) → Adro da Capela (-16,-30).
- Rota leste: alameda dos Jardins (15,-3) → cruzeiro do Cemitério (-20,-15) → Pátio da Usina (16,-29).
- Acender uma lanterna acende os lampiões de rua a até 9 casas (`LAMP_RADIUS`), um por um. 44 lampiões no mapa.

## Segredos (sempre com baú escondido; contam "Segredos x/7" no painel e avisam ao achar)
1. Quintal secreto (Vila Operária): fresta entre casas atrás do barracão.
2. Coração do labirinto (Jardins): labirinto de sebes, entrada única.
3. Cripta dos Faroleiros (Cemitério): fresta entre mausoléus; também guarda uma memória fixa.
4. Ilhota do lago (Parque): pedras escondidas atrás dos juncos. O brilho do baú aparece de longe.
5. Arsenal esquecido (Quartel): brecha nos fundos da muralha.
6. Vau esquecido (Canal): pedras sob a água; baú no meio. Atalho de ~17 passos para o norte.
7. Passarela da usina: caixotes viram escada atrás do gasômetro.

## Variações por semente (`expedition_data.FIXED_COUNTS`)
- 2 vilas de 4 candidatas, 3 ruínas de 6, 2 emboscadas de 5, 2 fontes de luz de 4, 1 memória de 2 (+ cripta), 3 baús abertos de 7.
- Perigo sobe a cada 13 casas (`FIXED_DANGER_DISTANCE`). Guardião: O Acendedor Apagado (Anselmo), folha do Rei Cervo em cinza — falta arte própria.

## Arte
- Modelos de 16 ângulos (giram com a câmera, como a cidade): `tools/build_suburbios_models.py` → `assets/biomes/suburbios/modelos`.
  Cercas, muros e sebes são trechos de meia casa virados na direção do vizinho (`suburbs_map._build_barriers`).
  Prédios = modelos da cidade com janelas apagadas/tábuas; novos: gasômetros, coreto, bonde, mausoléu, cripta, barracas, lápides, guarita, portão da cidade.
  A frente de cada prédio: `turn` na planta (SOUTH/NORTH/WEST/EAST em `build_suburbios_map.py`).
- Peças planas (árvores, lampiões, estátuas, pedras do vau): `tools/build_suburbios.py`.

## Onde mexe
- Planta: `tools/build_suburbios_map.py` (gera `scripts/suburbs_plan.gd` + prévia). Mudar o .py e rodar de novo; nunca editar o `suburbs_plan.gd` à mão.
- Jogo: `scripts/suburbs_map.gd` (gerador da planta), `suburbs_layout.gd`, `expedition_state.gd` (`_place_fixed_landmarks`, `_place_fixed_fort`, segredos, `lamp_lit`).
- Testes: `tests/test_suburbs.gd` (regras + simulação de robôs). Capturas: `tests/suburbs_shots.gd` ("lugar@graus" gira a câmera, "lugar+" acende as lanternas).
- Modo TILES_2 (tiles hex novos) continua valendo nos biomas sorteados; os Subúrbios usam o chão contínuo (`board_art._tiles_2`).

## Ideias para depois
- Arte própria do Acendedor; nome do bairro aparecendo ao entrar; mais barracas na feira.
