"""Barco de pesca e píer de madeira do porto da Cidade-Farol, no mesmo pipeline 3D da cidade.

Rodar na raiz: python tools/build_harbor_models.py. Gera assets/town/modelos/porto_barco.png e
porto_pier.png (16 ângulos) e uma prévia de um quadro em assets/town/porto_barco.png e
assets/town/porto_pier.png, que é o que aparece no editor (scenes/cidade.tscn).
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import build_town_models as art  # noqa: E402

HULL = (104, 38, 44)  # vinho, como a interface
STRIPE = (214, 190, 140)  # faixa creme
BRASS = (196, 158, 98)
DECK = (112, 84, 60)
DARK_WOOD = (66, 48, 38)
GROW = {"porto_barco": 1.45, "porto_pier": 1.25}


def hull_planks(w, h, color=HULL, stripe=True):
    img = art.planks(max(int(w), 2), max(int(h), 2), color, width=4, vertical=False)
    if stripe:
        art.rect(img, 0, 0, img.shape[1], 3, STRIPE)
        art.rect(img, 0, 3, img.shape[1], 1, np.array(STRIPE) * 0.6)
    return img


def boat():
    """Casco afilado na proa (+x), popa reta, convés de tábuas, cabine, mastro e lanterna."""
    m = art.Model()
    length, beam = 78.0, 24.0
    stations = np.linspace(-length, length, 13)
    top, chine, keel = 22.0, 9.0, 0.0

    def half(x):
        t = (x + length) / (2 * length)  # 0 popa, 1 proa
        return beam * (0.78 + 0.22 * np.sin(np.pi * min(t, 0.5))) if t < 0.5 else beam * np.sqrt(max(0.0, 1 - ((t - 0.5) / 0.5) ** 1.6))

    def sheer(x):  # a borda sobe na proa
        t = (x + length) / (2 * length)
        return top + 7 * max(0.0, t - 0.6) ** 2 / 0.16

    for i in range(len(stations) - 1):
        x0, x1 = stations[i], stations[i + 1]
        w0, w1 = half(x0), half(x1)
        s0, s1 = sheer(x0), sheer(x1)
        for side in (1, -1):
            up = [(x0, side * w0, s0), (x1, side * w1, s1)]
            mid = [(x0, side * w0 * 0.86, chine), (x1, side * w1 * 0.86, chine)]
            low = [(x0, side * w0 * 0.35, keel), (x1, side * w1 * 0.35, keel)]
            width = float(np.hypot(x1 - x0, w1 - w0))
            if side == 1:
                m.quad(up[0], up[1], mid[1], mid[0], hull_planks(width, s0 - chine))
                m.quad(mid[0], mid[1], low[1], low[0], hull_planks(width, chine, np.array(HULL) * 0.7, False))
            else:
                m.quad(up[1], up[0], mid[0], mid[1], hull_planks(width, s0 - chine))
                m.quad(mid[1], mid[0], low[0], low[1], hull_planks(width, chine, np.array(HULL) * 0.7, False))
        # convés, um pouco abaixo da borda
        deck = art.planks(int(x1 - x0) + 1, int(w0 * 2) + 1, DECK, width=4, vertical=True)
        z = min(s0, s1) - 3
        m.quad((x0, -w0 * 0.94, z), (x1, -w1 * 0.94, z), (x1, w1 * 0.94, z), (x0, w0 * 0.94, z), deck)
    # popa reta
    w = half(-length)
    m.quad((-length, w, sheer(-length)), (-length, -w, sheer(-length)), (-length, -w * 0.86, chine), (-length, w * 0.86, chine), hull_planks(w * 2, top - chine))
    m.quad((-length, w * 0.86, chine), (-length, -w * 0.86, chine), (-length, -w * 0.35, keel), (-length, w * 0.35, keel), hull_planks(w * 2, chine, np.array(HULL) * 0.7, False))
    # amurada: uma tábua escura por cima da borda
    for i in range(len(stations) - 1):
        x0, x1 = stations[i], stations[i + 1]
        for side in (1, -1):
            a, b = (x0, side * half(x0), sheer(x0) + 2), (x1, side * half(x1), sheer(x1) + 2)
            c, d = (x1, side * half(x1), sheer(x1)), (x0, side * half(x0), sheer(x0))
            rail = art.blank(6, 2, DARK_WOOD)
            m.quad(*(a, b, c, d) if side == 1 else (b, a, d, c), rail)

    # cabine na popa
    def cabin(name, w, h):
        img = art.planks(w, h, (150, 128, 96), width=4)
        art.rect(img, 0, 0, w, 2, DARK_WOOD)
        if name in ("frente", "fundo", "dir", "esq") and w > 14:
            art.window(img, w // 2 - 4, 5, 8, 7, lit=True)
        return img
    m.box(-62, -15, -30, 15, top - 3, top + 18, art.walls(cabin))
    m.gable(-64, -17, -28, 17, top + 18, 9, lambda w, h: art.tiles(w, h, (58, 44, 52), 4, 6),
            lambda w, h: art.planks(w, h, (150, 128, 96), 4), along_x=False, over=3)
    # mastro, verga com a vela enrolada e lanterna no alto
    m.ring(4, 0, 2.6, 2.0, top - 3, 112, lambda i, w, h: art.planks(max(w, 2), h, DARK_WOOD, 3), 6)
    sail = lambda i, w, h: art.cloth(max(w, 2), h, (196, 182, 152))
    for i in range(6):
        t0, t1 = 2 * np.pi * i / 6, 2 * np.pi * (i + 1) / 6
        r = 4.0
        a = (-34, r * np.cos(t0), 58 + r * np.sin(t0))
        b = (4, r * np.cos(t0), 58 + r * np.sin(t0))
        c = (4, r * np.cos(t1), 58 + r * np.sin(t1))
        d = (-34, r * np.cos(t1), 58 + r * np.sin(t1))
        m.quad(a, b, c, d, sail(i, 38, 4))
    glow = art.blank(6, 6, (255, 200, 112))
    glow[..., 3] = art.EMISSIVE
    m.box(1, -3, 7, 3, 104, 112, lambda name, w, h: glow, lambda w, h: art.blank(w, h, BRASS))
    m.box(0, -4, 8, 4, 112, 114, lambda name, w, h: art.blank(w, h, BRASS), lambda w, h: art.blank(w, h, BRASS))
    # proa: um gurupés curto
    m.box(length - 6, -1.5, length + 16, 1.5, sheer(length) - 2, sheer(length) + 1, lambda name, w, h: art.blank(w, h, DARK_WOOD),
          lambda w, h: art.blank(w, h, DARK_WOOD))
    # rolo de corda e caixote no convés
    m.ring(30, 9, 6, 6, top - 3, top + 1, lambda i, w, h: art.blank(max(w, 2), h, (170, 146, 104)), 8)
    m.box(36, -14, 50, -2, top - 3, top + 8, lambda name, w, h: art.planks(w, h, (128, 100, 70), 4),
          lambda w, h: art.planks(w, h, (140, 110, 78), 4, False))
    return m


def pier():
    """Píer de tábuas sobre estacas, com dois postes de amarra e uma lanterna na ponta (+x)."""
    m = art.Model()
    length, half_w, z = 150.0, 22.0, 24.0  # o convés na altura do cais
    deck = lambda w, h: art.planks(w, h, (104, 80, 58), width=5, vertical=True)
    m.box(-length / 2, -half_w, length / 2, half_w, z - 3, z, lambda name, w, h: art.planks(w, h, DARK_WOOD, 5, False), deck)
    post = lambda i, w, h: art.planks(max(w, 2), h, (58, 44, 36), 3)
    for x in np.linspace(-length / 2 + 6, length / 2 - 6, 5):
        for y in (-half_w + 3, half_w - 3):
            m.ring(x, y, 3.2, 3.2, -14, z - 3, post, 6)
    for y in (-half_w + 4, half_w - 4):  # postes de amarra
        m.ring(length / 2 - 8, y, 3, 3, z, z + 12, post, 6)
        m.disc(length / 2 - 8, y, 3.6, z + 12, art.blank(4, 4, (70, 54, 42)), 6)
    m.ring(length / 2 - 4, 0, 2, 2, z, z + 46, post, 6)  # poste da lanterna
    glow = art.blank(6, 6, (255, 200, 112))
    glow[..., 3] = art.EMISSIVE
    m.box(length / 2 - 8, -4, length / 2, 4, z + 46, z + 56, lambda name, w, h: glow, lambda w, h: art.blank(w, h, BRASS))
    m.pyramid(length / 2 - 8, -4, length / 2, 4, z + 56, 6, lambda w, h: art.blank(max(int(w), 2), h, BRASS), over=1)
    return m


def main():
    meta_path = art.OUT / "meta.json"
    meta = json.loads(meta_path.read_text())
    previews = []
    base = art.SIZE
    for name, build in {"porto_barco": boat, "porto_pier": pier}.items():
        art.SIZE = base * GROW[name]  # maiores que os prédios: o porto precisa ler de longe
        art.rng = np.random.default_rng(art.hash_name(name))
        model = build()
        size, foot = art.bounds(model)
        sheet = Image.new("RGBA", (size[0] * art.COLUMNS, size[1] * (art.VIEWS // art.COLUMNS)))
        for view in range(art.VIEWS):
            pixels = art.render(model, view * 2 * np.pi / art.VIEWS, size, foot)
            frame = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
            sheet.paste(frame, (view % art.COLUMNS * size[0], view // art.COLUMNS * size[1]))
            if view == 0:
                frame.save(Path("assets/town") / f"{name}.png")
            if view in (0, 2, 5, 10):
                previews.append(frame)
        sheet.save(art.OUT / f"{name}.png", optimize=True)
        meta[name] = dict(w=size[0], h=size[1], foot_x=foot[0], foot_y=foot[1], views=art.VIEWS, columns=art.COLUMNS)
    meta_path.write_text(json.dumps(meta, indent="\t", sort_keys=True))
    width = max(f.width for f in previews) * 2
    height = max(f.height for f in previews) * 2
    preview = Image.new("RGBA", (width * 4, height * 2), (31, 34, 44, 255))
    for i, frame in enumerate(previews):
        frame = frame.resize((frame.width * 2, frame.height * 2), Image.Resampling.NEAREST)
        preview.alpha_composite(frame, ((i % 4) * width, (i // 4) * height))
    Path("artifacts").mkdir(exist_ok=True)
    preview.convert("RGB").save("artifacts/porto_modelos.png")


if __name__ == "__main__":
    main()
