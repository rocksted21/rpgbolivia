class_name CidadeEnfeite
extends Sprite2D
## Um enfeite da cidade (scenes/cidade.tscn): barril, barraca, tocha, barco...
## Pode ficar fora do centro do hexágono; o jogo respeita o deslocamento.
## Tochas e fogueiras (tocha, fogueira_a, fogueira_b) acendem de noite sozinhas.

## Desligado: dá para passar por cima (tochas na beira da rua).
@export var solido := true
## Só para os enfeites em 3D (porto_barco, porto_pier): para onde a peça aponta, em graus.
@export_range(0, 337.5, 22.5) var giro := 0.0
