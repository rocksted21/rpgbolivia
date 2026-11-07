class_name CidadePredio
extends Sprite2D
## Um prédio da cidade (scenes/cidade.tscn). Arraste no editor: ele fica no hexágono mais
## perto do centro do desenho (o pé). Troque a arte em Texture e o tamanho em Scale.

## Hexágonos em volta que o prédio ocupa (ninguém passa por eles). 0 = só o do centro.
@export_range(0, 3) var raio := 0
## Morador que precisa ser resgatado para o prédio ficar de pé; antes disso é ruína.
@export_enum("ninguem", "ferreiro", "curandeira", "padeira", "cartografa", "arquivista", "alquimista") var precisa_de := "ninguem"
