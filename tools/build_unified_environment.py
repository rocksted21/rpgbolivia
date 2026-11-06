"""Importa o conjunto visual dirigido pelos heróis: objetos, cenários e hexágonos.

As pranchas ImageGen ficam em assets/unified_sources, nomeadas por bioma,
scenes.png e ground.png. Rodar na raiz do projeto.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageOps

SOURCE = Path('assets/unified_sources')
BIOMES = ['floresta', 'selva', 'neve', 'deserto']
SCENES = ['camp_fogueira','camp_carroca','camp_caixas',
          'garden_fountain','garden_gate','garden_wall',
          'shrine_candles','shrine_monument','shrine_bench',
          'crossing_markers','crossing_house','crossing_pier']
PROPS = {
 'floresta_fundo_a':(0,100,135), 'floresta_fundo_b':(1,100,135),
 'floresta_frente_a':(15,65,35), 'floresta_frente_b':(15,70,30),
 'pedras_a':(2,72,48), 'pedras_b':(2,58,40),
 'colinas_a':(3,82,40), 'colinas_b':(4,82,40),
 'colinas_natural_a':(3,82,40), 'colinas_natural_b':(4,82,40),
 'montanha_a':(5,94,105), 'montanha_natural':(5,94,105),
 'montanha_b':(14,90,66), 'casa':(6,100,120), 'torre':(7,95,120),
 'ruina_a':(13,95,110), 'ruina_b':(8,70,90),
 'enfeite_a':(9,45,70), 'enfeite_b':(10,55,40), 'enfeite_c':(15,50,28),
 'farol_apagado':(11,94,150), 'farol_aceso':(12,94,150),
}


def cell(sheet, index, columns=4, rows=4):
    w,h=sheet.size
    x,y=index%columns,index//columns
    return sheet.crop((round(x*w/columns),round(y*h/rows),round((x+1)*w/columns),round((y+1)*h/rows)))


def prop(image, width, height):
    mask=image.getchannel('A').point(lambda v:255 if v>=128 else 0)
    box=mask.getbbox()
    if box is None:
        raise ValueError('Célula sem objeto')
    image=image.crop(box)
    scale=min(width/image.width,height/image.height)
    image=image.resize((max(1,round(image.width*scale)),max(1,round(image.height*scale))),Image.Resampling.LANCZOS)
    pixels=np.array(image)
    pixels[...,3]=np.where(pixels[...,3]>=128,255,0)
    image=Image.fromarray(pixels)
    out=Image.new('RGBA',(144,336))
    out.alpha_composite(image,((144-image.width)//2,168-image.height))
    return out.resize((288,672),Image.Resampling.NEAREST)


def texture(image):
    # Repetição espelhada elimina emendas; pixel de arte sempre ampliado 2x.
    image=image.convert('RGB').resize((128,128),Image.Resampling.NEAREST)
    out=Image.new('RGB',(256,256))
    out.paste(image,(0,0)); out.paste(ImageOps.mirror(image),(128,0))
    out.paste(ImageOps.flip(image),(0,128));out.paste(ImageOps.flip(ImageOps.mirror(image)),(128,128))
    return out.resize((512,512),Image.Resampling.NEAREST)


def hex_tile(surface, biome):
    out=Image.new('RGBA',(186,244))
    d=ImageDraw.Draw(out)
    rock={'floresta':(72,61,65),'selva':(47,57,68),'neve':(64,70,99),'deserto':(114,65,66)}[biome]
    d.polygon([(0,160),(93,213),(93,243),(0,190)],fill=rock)
    d.polygon([(93,213),(185,160),(185,190),(93,243)],fill=tuple(int(v*.77) for v in rock))
    for x in range(0,186,2):
        y=int(213-abs(x-93)*53/93)
        for depth in range(0,30,2):
            shade=(9 if depth<6 else (-12 if depth>23 else 0))
            shade+=((x//22+depth//12)%3-1)*5
            color=tuple(max(0,min(255,int(v*(.82 if x>93 else 1)+shade))) for v in rock)
            if depth in (12,14) and (x//22)%3!=1:
                color=tuple(max(0,v-16) for v in color)
            d.rectangle((x,y+depth,x+1,y+depth+1),fill=color)
    mask=Image.new('L',out.size)
    ImageDraw.Draw(mask).polygon([(93,0),(185,53),(185,160),(93,213),(0,160),(0,53)],fill=255)
    out.paste(surface.crop((0,0,186,244)),(0,0),mask)
    return out


def main():
    ground=Image.open(SOURCE/'ground.png').convert('RGB')
    for b,biome in enumerate(BIOMES):
        folder=Path('assets/biomes')/biome
        sheet=Image.open(SOURCE/(biome+'.png')).convert('RGBA')
        if np.array(sheet)[...,3].min()>0:
            raise ValueError('Prancha sem transparência: '+biome)
        for name,(index,w,h) in PROPS.items():
            prop(cell(sheet,index),w,h).save(folder/(name+'.png'))
        materials=[texture(cell(ground,b*4+i)) for i in range(4)]
        for name,index in {'solo':0,'sombra_solo':0,'trilha_solo':1,'estrada_solo':2,'agua_solo':3}.items():
            materials[index].save(folder/(name+'.png'))
        for name,index in {'campo_a':0,'campo_b':0,'sombra':0,'trilha':1,'estrada':2,'agua_a':3,'agua_b':3,'parede':0}.items():
            hex_tile(materials[index],biome).save(folder/(name+'.png'))
        if biome=='floresta':
            materials[2].save('assets/town/calcada_solo.png')
            for terrain in range(1,17):
                index=3 if terrain in (5,14) else (2 if terrain in (12,15) else (1 if terrain==13 else 0))
                hex_tile(materials[index],biome).save(Path('assets/tiles')/(str(terrain)+'.png'))
    sheet=Image.open(SOURCE/'scenes.png').convert('RGBA')
    for i,name in enumerate(SCENES):
        column=i%3
        w,h=(80,45) if column==0 else ((100,130) if column==1 else (82,70))
        prop(cell(sheet,i,3,4),w,h).save(Path('assets/scenes')/(name+'.png'))
    town_names=['casa_a','casa_b','casa_c','taverna','mansao','capela','forja','tenda',
                'abrigo','forno','torre_madeira','fonte','farol','horta','acampamento','caixas']
    town=Image.open(SOURCE/'town.png').convert('RGBA')
    folder=Path('assets/town/ilustrado')
    folder.mkdir(exist_ok=True)
    for i,name in enumerate(town_names):
        width,height=(132,160) if name in ['mansao','taverna','capela','farol'] else (105,130)
        if name in ['fonte','horta','acampamento','caixas']:
            width,height=95,65
        prop(cell(town,i),width,height).save(folder/(name+'.png'))
        if name in ['horta','acampamento','caixas']:
            prop(cell(town,i),width,height).save(Path('assets/town')/(name+'.png'))
    print('Ambiente unificado: 4 biomas, 16 pisos hexagonais e 12 objetos de cenários.')


if __name__=='__main__':
    main()
