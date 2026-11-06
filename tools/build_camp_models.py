"""Renderiza os objetos do acampamento usando o mesmo pipeline da Cidade-Farol.

Rodar na raiz: python tools/build_camp_models.py. Não recria os prédios existentes.
"""
import json
import numpy as np
from PIL import Image
import build_town_models as art


def wood(name, w, h):
    return art.planks(w, h, (91, 77, 65), width=5)


def iron(name, w, h):
    return art.speckle(art.blank(w, h, (47, 48, 55)), 3)


def crate(m, x, y, z, size):
    def side(name, w, h):
        tex = wood(name, w, h)
        art.timber(tex, (49, 43, 42), posts=1)
        for px in (2, max(int(w) - 3, 2)):
            art.rect(tex, px, 3, 1, 1, (147, 135, 110))
        return tex
    m.box(x, y, x + size, y + size, z, z + size, side,
          lambda w, h: art.planks(w, h, (103, 88, 70), 5, False))


def caixas():
    m = art.Model()
    crate(m, -22, -16, 0, 24)
    crate(m, 5, -6, 0, 18)
    crate(m, -19, -13, 24, 15)
    # Uma tampa solta, sem brilho de loot.
    m.box(-17, 15, 12, 23, 0, 3, wood, lambda w, h: art.planks(w, h))
    return m


def fogueira():
    m = art.Model()
    m.disc(0, 0, 20, 0.5, art.speckle(art.blank(36, 36, (45, 44, 49)), 6), 12)
    for i in range(9):
        angle = i * 2 * np.pi / 9
        x, y = 22 * np.cos(angle), 22 * np.sin(angle)
        rock = lambda n, w, h: art.plaster(w, h, (104, 102, 108))
        m.ring(x, y, 5, 4, 0, 5 + i % 3, rock, 5)
    charcoal = lambda n, w, h: art.planks(w, h, (39, 34, 35), 3)
    m.box(-15, -3, 14, 3, 1, 5, charcoal, lambda w, h: art.planks(w, h, (51, 44, 43)))
    m.box(-4, -14, 3, 13, 3, 7, charcoal, lambda w, h: art.planks(w, h, (50, 43, 42)))
    # Cinza fria: nada de chama, emissivo ou luz ativa.
    m.disc(0, 0, 7, 7.5, art.speckle(art.blank(14, 14, (109, 106, 111)), 10), 7)
    return m


def wheel(m, x, y, z, broken=False):
    # A roda está no plano YZ; aro vazado e raios de madeira.
    for i in range(12):
        if broken and i in (7, 8, 9):
            continue
        a, b = i * np.pi / 6, (i + 1) * np.pi / 6
        p = lambda r, t: (x, y + r * np.cos(t), z + r * np.sin(t))
        tex = art.blank(8, 3, (60, 53, 49))
        m.quad(p(13, a), p(13, b), p(10, b), p(10, a), tex)
    for i in range(6):
        t = i * np.pi / 3
        cy, sz = np.cos(t), np.sin(t)
        m.quad((x, y - sz, z + cy), (x, y + 11 * cy - sz, z + 11 * sz + cy),
               (x, y + 11 * cy + sz, z + 11 * sz - cy), (x, y + sz, z - cy),
               art.blank(12, 2, (94, 77, 59)))
    m.box(x - 2, y - 3, x + 2, y + 3, z - 3, z + 3, iron)


def carroca():
    m = art.Model()
    # Carroça de carga do século XIX, com ferragens e lona vinho desbotada.
    for y in (-19, 19):
        m.box(-24, y - 2, 24, y + 2, 11, 15, iron)
        for x in (-25, 25):
            wheel(m, x, y, 13, broken=(x == 25 and y == 19))
    m.box(-22, -32, 22, 31, 16, 20, wood, lambda w, h: art.planks(w, h, (103, 85, 66)))
    for x in (-22, 19):
        m.box(x, -32, x + 3, 31, 20, 34, wood)
        for y in (-30, 0, 28):
            m.box(x - 1, y, x + 4, y + 2, 19, 38, iron)
    m.box(-22, -32, 22, -29, 20, 35, wood)
    # Laterais rasgadas e abertas: a carga e o abandono ficam visíveis.
    for y in (-24, 17):
        m.ring(0, y, 2, 2, 22, 49, lambda n, w, h: wood(n, max(w, 1), h), 5)
    roof = art.cloth(48, 58, (100, 68, 72))
    roof[-13:, 7:16, 3] = 0
    roof[-8:, 31:39, 3] = 0
    m.quad((-24, -27, 46), (24, -27, 46), (24, 23, 39), (-24, 23, 39), roof)
    crate(m, -12, -15, 20, 18)
    for x in (-15, 15):
        m.box(x - 1, 30, x + 2, 54 if x < 0 else 44, 12, 15, wood)
    return m


def main():
    meta_path = art.OUT / 'meta.json'
    meta = json.loads(meta_path.read_text())
    previews = []
    for name, build in {'camp_carroca': carroca, 'camp_caixas': caixas, 'camp_fogueira': fogueira}.items():
        art.rng = np.random.default_rng(art.hash_name(name))
        model = build()
        size, foot = art.bounds(model)
        sheet = Image.new('RGBA', (size[0] * art.COLUMNS, size[1] * 4))
        for view in range(art.VIEWS):
            pixels = art.render(model, view * 2 * np.pi / art.VIEWS, size, foot)
            frame = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
            sheet.paste(frame, (view % 4 * size[0], view // 4 * size[1]))
            if view in (0, 2, 5):
                previews.append(frame)
        sheet.save(art.OUT / (name + '.png'), optimize=True)
        meta[name] = dict(w=size[0], h=size[1], foot_x=foot[0], foot_y=foot[1], views=16, columns=4)
    meta_path.write_text(json.dumps(meta, indent='\t', sort_keys=True))
    preview = Image.new('RGBA', (720, 600), (31, 34, 44, 255))
    for i, frame in enumerate(previews):
        frame = frame.resize((frame.width * 2, frame.height * 2), Image.Resampling.NEAREST)
        preview.alpha_composite(frame, ((i % 3) * 240 + (240 - frame.width) // 2, (i // 3) * 200))
    from pathlib import Path
    Path('artifacts').mkdir(exist_ok=True)
    preview.convert('RGB').save('artifacts/camp_assets.png')


if __name__ == '__main__':
    main()
