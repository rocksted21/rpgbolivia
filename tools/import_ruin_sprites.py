"""Recorta as três pranchas ImageGen em sprites com apoio central, como os biomas.

Uso: python tools/import_ruin_sprites.py <pasta das três pranchas originais>.
As fontes são preservadas em assets/scenes/source para reconstrução dos sprites.
"""
from pathlib import Path
import sys
import shutil
import numpy as np
from PIL import Image

ROOT = Path('assets/scenes')
SHEETS = {
    'garden': ('exec-8072fb2e-f4ca-43af-b2e3-193c467ee30a.png', ['garden_fountain', 'garden_gate', 'garden_wall']),
    'shrine': ('exec-ebadd717-f5ac-41cd-9097-9b32a965591b.png', ['shrine_candles', 'shrine_monument', 'shrine_bench']),
    'crossing': ('exec-6b8bef59-c227-44a2-8b5a-97d89d594c2e.png', ['crossing_markers', 'crossing_house', 'crossing_pier']),
}


def main():
    sources = Path(sys.argv[1])
    (ROOT / 'source').mkdir(parents=True, exist_ok=True)
    for theme, (filename, names) in SHEETS.items():
        source = sources / filename
        shutil.copy2(source, ROOT / 'source' / (theme + '.png'))
        image = Image.open(source).convert('RGBA')
        alpha = np.asarray(image)[..., 3]
        occupancy = (alpha > 32).sum(axis=0)
        cuts = [0]
        for fraction in (1/3, 2/3):
            a, b = int(image.width * (fraction - .065)), int(image.width * (fraction + .065))
            counts = occupancy[a:b]
            positions = np.flatnonzero(counts == counts.min())
            cuts.append(a + int(positions[len(positions)//2]))
        cuts.append(image.width)
        for i, name in enumerate(names):
            sprite = image.crop((cuts[i], 0, cuts[i+1], image.height))
            mask = sprite.getchannel('A').point(lambda value: 255 if value >= 128 else 0)
            sprite = sprite.crop(mask.getbbox())
            # Renderização em pixels de arte; nearest 2x igual aos heróis.
            max_width = 108 if i == 1 else 99
            max_height = 140 if i == 1 else 88
            factor = min(max_width / sprite.width, max_height / sprite.height)
            sprite = sprite.resize((round(sprite.width*factor), round(sprite.height*factor)), Image.Resampling.LANCZOS)
            pixels = np.array(sprite)
            pixels[..., 3] = np.where(pixels[..., 3] >= 128, 255, 0)
            sprite = Image.fromarray(pixels)
            canvas = Image.new('RGBA', (128, 320))
            canvas.alpha_composite(sprite, ((128-sprite.width)//2, 160-sprite.height))
            canvas.resize((256, 640), Image.Resampling.NEAREST).save(ROOT / (name+'.png'))
            print(name, sprite.size, 'alpha OK')


if __name__ == '__main__':
    main()
