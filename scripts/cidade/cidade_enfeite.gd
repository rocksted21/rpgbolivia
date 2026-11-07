class_name CidadeEnfeite
extends Sprite2D
## Um enfeite da cidade (scenes/cidade.tscn): barril, barraca, tocha, barco...
## Pode ficar fora do centro do hexágono; o jogo respeita o deslocamento.
## Tochas e fogueiras (tocha, fogueira_a, fogueira_b) acendem de noite sozinhas.

## Desligado: dá para passar por cima (tochas na beira da rua).
@export var solido := true
