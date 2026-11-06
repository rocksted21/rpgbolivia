"""Prepara as pranchas ImageGen de relevos naturais; preserva os sprites antigos.
Uso na raiz: python tools/import_natural_relief.py <pasta das pranchas>.
"""
from pathlib import Path
import sys
import shutil
import numpy as np
from PIL import Image

SHEETS = {'floresta': 'exec-7dea7b02-a7a8-4968-bc11-0681e8b0f371.png',
          'selva': 'exec-acff7ec6-72e6-4a6e-a967-8cb9c8dcad00.png'}


def main():
    source_dir = Path('assets/terrain_sources')
    source_dir.mkdir(exist_ok=True)
    (source_dir / '.gdignore').touch()
    for biome, filename in SHEETS.items():
        source = Path(sys.argv[1]) / filename
        shutil.copy2(source, source_dir / (biome+'.png'))
        image = Image.open(source).convert('RGBA')
        counts = (np.array(image)[..., 3] >= 128).sum(axis=0)
        cuts = [0]
        for fraction in (1/3, 2/3):
            a, b = int(image.width*(fraction-.05)), int(image.width*(fraction+.05))
            values = counts[a:b]
            positions = np.flatnonzero(values == values.min())
            cuts.append(a+int(positions[len(positions)//2]))
        cuts.append(image.width)
        for i, name in enumerate(['colinas_natural_a', 'colinas_natural_b', 'montanha_natural']):
            sprite = image.crop((cuts[i],0,cuts[i+1],image.height))
            mask = sprite.getchannel('A').point(lambda v:255 if v>=128 else 0)
            sprite = sprite.crop(mask.getbbox())
            scale = min((88 if i<2 else 96)/sprite.width, (48 if i<2 else 92)/sprite.height)
            sprite = sprite.resize((round(sprite.width*scale),round(sprite.height*scale)),Image.Resampling.LANCZOS)
            pixels = np.array(sprite)
            pixels[...,3] = np.where(pixels[...,3]>=128,255,0)
            sprite = Image.fromarray(pixels)
            canvas = Image.new('RGBA',(128,240))
            canvas.alpha_composite(sprite,((128-sprite.width)//2,120-sprite.height))
            canvas.resize((256,480),Image.Resampling.NEAREST).save(Path('assets/biomes')/biome/(name+'.png'))
            print(biome,name,sprite.size)


if __name__ == '__main__':
    main()
