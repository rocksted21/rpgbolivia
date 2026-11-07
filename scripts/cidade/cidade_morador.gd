class_name CidadeMorador
extends Sprite2D
## Um morador parado da cidade (scenes/cidade.tscn). Fica no hexágono mais perto do pé.
## A arte (Texture) tem de estar em assets/town/: o retrato do painel usa o mesmo arquivo.

## Nome interno: as falas e missões (town_content.gd) usam este id. Não mude à toa.
@export var id := ""
## Nome que aparece no jogo.
@export var nome := ""
## talk = só conversa · resident = melhorias · memories = memórias · skills = árvores de skills
## beacon = farol · shop = loja · board = mural de missões · guide = guia (história)
@export_enum("talk", "resident", "memories", "skills", "beacon", "shop", "board", "guide") var servico := "talk"
## Só aparece depois que este morador for resgatado.
@export_enum("ninguem", "ferreiro", "curandeira", "padeira", "cartografa", "arquivista", "alquimista") var precisa_de := "ninguem"
