"""Jardim, santuário e travessia: pixel art de 16 ângulos no pipeline da cidade.

Rodar na raiz: python tools/build_ruin_models.py.
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image
import build_town_models as art
from build_camp_models import wood, iron


def stone(name, w, h):
    return art.stone(max(w, 2), max(h, 2), (111, 111, 114), 6, 11)


def top(w, h):
    return art.speckle(art.blank(w, h, (130, 129, 124)), 4)


def ivy(m, x, y, z):
    for i in range(9):
        px, py = x + i % 3 * 3, y + i // 3 * 2
        m.box(px, py, px + 4, py + 3, z + i % 2 * 3, z + 4 + i % 2 * 3,
              lambda n, w, h: art.blank(w, h, (61, 73, 54)),
              lambda w, h: art.blank(w, h, (89, 96, 65)))


def garden_gate():
    m = art.Model()
    for x, height in [(-27, 57), (20, 39)]:
        m.box(x - 4, -6, x + 11, 9, 0, 8, stone, top)
        m.box(x, -3, x + 7, 6, 8, height, stone, top)
        m.box(x - 3, -5, x + 10, 8, height, height + 5, stone, top)
    # Ferro forjado neoclássico: falta metade do portão.
    for x in range(-18, 3, 4):
        m.box(x, 0, x + 1, 2, 3, 39 + (x % 3), iron)
    for z in (13, 31):
        m.box(-19, 0, 4, 2, z, z + 2, iron)
    ivy(m, -28, -7, 9)
    ivy(m, 20, 0, 27)
    return m


def dry_fountain():
    m = art.Model()
    m.disc(0, 0, 28, 1, art.blank(42, 42, (68, 65, 65)), 12)
    for i in range(10):
        if i in (1, 2):
            continue
        t = i * np.pi / 5
        x, y = 24 * np.cos(t), 24 * np.sin(t)
        m.box(x - 5, y - 4, x + 5, y + 4, 0, 6 + i % 2 * 2, stone, top)
    # Coluna caída dentro da bacia seca; baixa, para o centro ser caminhável.
    m.box(-15, -4, 12, 4, 1, 7, stone, top)
    ivy(m, -16, 8, 1)
    return m


def garden_wall():
    m = art.Model()
    for x, z in [(-28, 22), (-11, 17), (6, 10)]:
        m.box(x, -6, x + 16, 7, 0, z, stone, top)
        m.box(x - 1, -7, x + 17, 8, z, z + 3, stone, top)
    for x in range(-25, -8, 5):
        m.box(x, -1, x + 1, 1, 25, 39, iron)
    m.box(-26, -1, -8, 1, 32, 34, iron)
    ivy(m, -15, -5, 19)
    ivy(m, 4, -3, 7)
    return m


def shrine():
    m = art.Model()
    m.box(-23, -18, 23, 18, 0, 5, stone, top)
    m.box(-18, -13, 18, 13, 5, 11, stone, top)
    m.box(-12, -9, 12, 9, 11, 45, stone, top)
    # Nicho escuro, sem luz de prêmio.
    m.quad((-7, 9.2, 37), (7, 9.2, 37), (7, 9.2, 19), (-7, 9.2, 19), art.blank(14, 18, (39, 39, 48)))
    m.ring(0, 1, 5, 4, 18, 32, lambda n, w, h: art.plaster(w, h, (132, 128, 125)), 6)
    m.box(-17, -12, 17, 12, 45, 49, stone, top)
    m.pyramid(-17, -12, 17, 12, 49, 16, lambda w, h: art.tiles(w, h, (68, 66, 78)), 2)
    m.box(-2, -2, 2, 2, 65, 76, iron)
    return m


def candles():
    m = art.Model()
    m.disc(0, 0, 25, 0.5, art.blank(42, 42, (82, 79, 84)), 10)
    for x, y, h in [(-12, -5, 7), (-7, -7, 11), (12, 4, 6), (7, 6, 9), (15, -5, 8)]:
        wax = lambda n, w, h: art.blank(w, h, (162, 151, 128))
        m.ring(x, y, 2, 2, 1, h, wax, 6)
        m.box(x, y, x + 1, y + 1, h, h + 2, iron)
    m.box(-4, -2, 6, 7, 1, 4, wood, lambda w, h: art.blank(w, h, (92, 62, 65)))
    return m


def broken_bench():
    m = art.Model()
    for x in (-22, 12):
        m.box(x, -6, x + 6, 8, 0, 12, stone, top)
    m.box(-26, -8, 2, 10, 12, 16, stone, top)
    m.box(7, -8, 23, 10, 10, 14, stone, top)
    m.box(0, 12, 17, 19, 0, 4, stone, top)
    ivy(m, -22, -8, 17)
    return m


def guardhouse():
    m = art.Model()
    m.box(-23, -20, 23, 20, 0, 7, stone, top)
    # Guarita aberta, paredes com alturas diferentes e janelas vazias.
    m.box(-21, -18, -15, 18, 7, 44, stone, top)
    m.box(-15, -18, 20, -12, 7, 26, stone, top)
    m.box(14, -12, 20, 9, 7, 32, stone, top)
    m.box(-21, -20, 21, -12, 44, 48, stone, top)
    for x in (-12, 8):
        m.box(x, -16, x + 3, -13, 27, 44, stone, top)
    m.box(-23, -22, 0, 2, 48, 52, wood, lambda w, h: art.tiles(w, h, (64, 62, 73)))
    ivy(m, -23, 0, 15)
    return m


def bridge_marker():
    m = art.Model()
    # Balizas baixas junto ao piso existente; o tabuleiro da ponte vem do rio.
    for x in (-29, 25):
        m.box(x, -6, x + 5, 6, 0, 11, stone, top)
        m.box(x - 1, -7, x + 6, 7, 11, 13, stone, top)
    return m


def broken_pier():
    m = art.Model()
    for x, y, h in [(-16, 0, 37), (7, 5, 18)]:
        m.box(x - 5, y - 8, x + 9, y + 8, 0, 6, stone, top)
        m.ring(x + 2, y, 6, 5, 6, h, lambda n, w, h: stone(n, max(w, 2), h), 8)
        m.box(x - 5, y - 7, x + 9, y + 7, h, h + 4, stone, top)
    for y in (-16, 17):
        m.box(-19, y, 17, y + 3, 0, 3, wood, lambda w, h: art.planks(w, h, (77, 67, 57)))
    return m


MODELS = {'garden_gate': garden_gate, 'garden_fountain': dry_fountain, 'garden_wall': garden_wall,
          'shrine_monument': shrine, 'shrine_candles': candles, 'shrine_bench': broken_bench,
          'crossing_house': guardhouse, 'crossing_markers': bridge_marker, 'crossing_pier': broken_pier}


def main():
    meta_path = art.OUT / 'meta.json'
    meta = json.loads(meta_path.read_text())
    preview = Image.new('RGBA', (900, 690), (31, 34, 44, 255))
    for i, (name, build) in enumerate(MODELS.items()):
        art.rng = np.random.default_rng(art.hash_name(name))
        model = build()
        size, foot = art.bounds(model)
        sheet = Image.new('RGBA', (size[0] * 4, size[1] * 4))
        for view in range(16):
            pixels = art.render(model, view * 2 * np.pi / 16, size, foot)
            frame = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
            sheet.paste(frame, (view % 4 * size[0], view // 4 * size[1]))
            if view == 2:
                big = frame.resize((frame.width * 2, frame.height * 2), Image.Resampling.NEAREST)
                preview.alpha_composite(big, (i % 3 * 300 + (300 - big.width) // 2,
                                             i // 3 * 230 + (230 - big.height) // 2))
        sheet.save(art.OUT / (name + '.png'), optimize=True)
        meta[name] = dict(w=size[0], h=size[1], foot_x=foot[0], foot_y=foot[1], views=16, columns=4)
    meta_path.write_text(json.dumps(meta, indent='\t', sort_keys=True))
    Path('artifacts').mkdir(exist_ok=True)
    preview.convert('RGB').save('artifacts/ruin_assets.png')


if __name__ == '__main__':
    main()
