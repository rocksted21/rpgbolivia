"""Modelos de 16 ângulos dos Subúrbios Apagados, no mesmo pipeline da Cidade-Farol.

Cercas, muros e sebes viram trechos de meia casa que o jogo gira na direção da linha
(scripts/suburbs_map.gd), então ficam certos de qualquer lado da câmera. Os prédios usam os
modelos da cidade com as janelas apagadas e as cores lavadas da noite; o resto (gasômetros,
coreto, bonde, mausoléus, barracas, lápides, portão da cidade) é montado aqui.

Rodar na raiz: python tools/build_suburbios_models.py [folha.png]
Saída: assets/biomes/suburbios/modelos (imagens + meta.json).
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import build_town_models as art  # noqa: E402
import build_suburbios as paint  # noqa: E402

OUT = Path("assets/biomes/suburbios/modelos")
HEX = 93 / art.SIZE  # distância entre centros de casas vizinhas, em unidades do modelo
HALF = HEX / 2 + 1.5  # meio trecho, com sobra para emendar com o vizinho


# --- Texturas da noite apagada ---------------------------------------------------------

def iron(name, w, h):
    return art.speckle(art.blank(max(w, 1), max(h, 1), (44, 46, 58)), 3)


def iron_top(w, h):
    return art.blank(max(w, 1), max(h, 1), (70, 74, 92))


def stone(name, w, h, color=(98, 96, 106)):
    return art.stone(max(w, 2), max(h, 2), color, 6, 11)


def stone_top(w, h):
    return art.speckle(art.blank(max(w, 1), max(h, 1), (118, 116, 122)), 4)


def brick(name, w, h):
    img = art.blank(max(w, 2), max(h, 2), (52, 34, 34))
    course, size = 4, 9
    for row, y in enumerate(range(0, int(h), course)):
        x = -(row % 2) * size // 2
        while x < w:
            tone = np.array((112, 64, 54)) + art.rng.normal(0, 10)
            art.rect(img, max(x, 0), y, min(size - 1, w - max(x, 0)), course - 1, tone)
            x += size
    return art.speckle(img, 3)


def leaves(name, w, h, base=(30, 50, 40)):
    img = art.blank(max(w, 2), max(h, 2), base)
    height, width = img.shape[:2]
    for _ in range(int(width * height / 9) + 1):
        x, y = art.rng.integers(0, width), art.rng.integers(0, height)
        light = 1.0 - y / max(height, 1) * 0.5
        tone = np.array(base) * (1.0 + art.rng.uniform(0.1, 0.7) * light)
        art.rect(img, x, y, art.rng.integers(2, 4), art.rng.integers(2, 3), tone)
    return img


def leaves_top(w, h):
    return leaves("topo", w, h, (40, 66, 50))


def tiles(color):
    return lambda w, h: art.tiles(max(w, 3), max(h, 3), color)


def cloth(color, stripe=(150, 140, 120)):
    def tex(w, h):
        img = art.blank(max(w, 2), max(h, 2), color)
        for x in range(0, img.shape[1], 10):
            img[:, x: x + 5, :3] = stripe
        return art.speckle(img, 3)
    return tex


def wood(name, w, h):
    return art.planks(max(w, 2), max(h, 2), (78, 62, 52), width=5)


def flat(color):
    return lambda *args: art.blank(max(int(args[-2]), 1), max(int(args[-1]), 1), color)


# --- Trechos de cerca, muro e sebe (meia casa ao longo de +x) -------------------------

def grade():
    m = art.Model()
    m.box(0, -3, HALF, 3, 0, 6, lambda n, w, h: stone(n, w, h, (86, 84, 94)), stone_top)
    m.box(-3, -3, 3, 3, 0, 46, iron, iron_top)  # pilarete no centro da casa
    m.box(-4, -4, 4, 4, 46, 49, iron, iron_top)
    for x in np.arange(5.0, HALF - 1, 4.5):
        tall = 40 if int(x / 4.5) % 3 == 1 else 37
        m.box(x, -0.8, x + 1.6, 0.8, 6, tall, iron, iron_top)
        m.pyramid(x, -0.8, x + 1.6, 0.8, tall, 4, lambda w, h: art.blank(max(int(w), 1), max(int(h), 1), (70, 74, 92)), 0)
    for z in (13, 31):
        m.box(0, -1, HALF, 1, z, z + 2, iron, iron_top)
    return m


def muro():
    m = art.Model()
    m.box(0, -6, HALF, 6, 0, 30, brick, stone_top)
    m.box(-1, -7, HALF, 7, 30, 33, lambda n, w, h: stone(n, w, h), stone_top)
    m.box(-8, -8, 8, 8, 0, 38, lambda n, w, h: stone(n, w, h, (104, 100, 104)), stone_top)
    m.box(-9, -9, 9, 9, 38, 41, lambda n, w, h: stone(n, w, h, (120, 116, 118)), stone_top)
    return m


def sebe():
    m = art.Model()
    m.box(0, -10, HALF, 10, 0, 28, leaves, leaves_top)
    m.box(-11, -11, 11, 11, 0, 30, leaves, leaves_top)
    return m


def sebe_bloco():
    m = art.Model()
    m.box(-18, -12, 18, 12, 0, 26, leaves, leaves_top)
    m.box(-12, -8, 12, 8, 26, 32, leaves, leaves_top)
    return m


# --- Peças novas ------------------------------------------------------------------------

def lapides(seed=0):
    m = art.Model()
    rng = np.random.default_rng(seed)
    gray = lambda n, w, h: stone(n, w, h, (110, 108, 116))
    spots = [(-24, -10), (-2, -16), (20, -8), (-14, 12), (12, 14)]
    for i, (x, y) in enumerate(spots):
        kind = (i + seed) % 4
        if kind == 0:  # lápide redonda
            m.box(x - 7, y - 2, x + 7, y + 3, 0, 22, gray, stone_top)
        elif kind == 1:  # cruz
            m.box(x - 2, y - 2, x + 2, y + 2, 0, 30, gray, stone_top)
            m.box(x - 8, y - 2, x + 8, y + 2, 20, 24, gray, stone_top)
        elif kind == 2:  # laje deitada
            m.box(x - 10, y - 6, x + 10, y + 6, 0, 4, gray, stone_top)
            m.box(x - 8, y - 6, x + 8, y - 3, 4, 14, gray, stone_top)
        else:  # obelisco
            m.box(x - 5, y - 5, x + 5, y + 5, 0, 6, gray, stone_top)
            m.box(x - 3, y - 3, x + 3, y + 3, 6, 34, gray, stone_top)
            m.pyramid(x - 3, y - 3, x + 3, y + 3, 34, 5, tiles((110, 108, 116)), 0)
        if rng.random() < 0.5:
            m.box(x - 6, y + 3, x + 6, y + 6, 0, 2, flat((54, 70, 52)))  # musgo
    return m


def mausoleu(crypt=False):
    m = art.Model()
    w, d = (30, 26) if crypt else (22, 18)
    wall = lambda n, ww, h: _mausoleum_wall(n, ww, h, crypt)
    m.box(-w - 4, -d - 4, w + 4, d + 4, 0, 6, lambda n, ww, h: stone(n, ww, h, (84, 82, 90)), stone_top)
    m.box(-w, -d, w, d, 6, 50 if crypt else 42, wall, stone_top)
    top = 50 if crypt else 42
    m.gable(-w, -d, w, d, top, 18 if crypt else 14, tiles((74, 72, 84)), lambda ww, h: stone("oitao", ww, h), along_x=False)
    if crypt:
        for x in (-w + 4, w - 10):
            m.box(x, d + 4, x + 6, d + 10, 6, top, lambda n, ww, h: stone(n, ww, h, (126, 122, 124)), stone_top)
        m.box(-w, d, w, d + 12, top, top + 4, lambda n, ww, h: stone(n, ww, h, (120, 116, 118)), stone_top)
    m.box(-1.5, -1.5, 1.5, 1.5, top + 14, top + 30, lambda n, ww, h: stone(n, ww, h, (126, 122, 124)))
    m.box(-6, -1.5, 6, 1.5, top + 22, top + 25, lambda n, ww, h: stone(n, ww, h, (126, 122, 124)))
    return m


def _mausoleum_wall(name, w, h, crypt):
    img = stone(name, w, h, (96, 94, 102) if not crypt else (88, 86, 96))
    if name == "frente":
        door_w = 16 if crypt else 12
        art.rect(img, w // 2 - door_w // 2 - 1, h - 30, door_w + 2, 30, (26, 24, 32))
        art.rect(img, w // 2 - door_w // 2, h - 29, door_w, 29, (40, 36, 46) if not crypt else (20, 18, 26))
        art.rect(img, w // 2 - door_w // 2, h - 33, door_w, 2, (140, 136, 140))
    return img


def coreto():
    m = art.Model()
    m.ring(0, 0, 44, 42, 0, 9, lambda i, w, h: stone("base", w, h, (104, 100, 108)), 12)
    m.disc(0, 0, 42, 9, art.planks(60, 60, (88, 70, 58), 5, False), 12)
    for i in range(8):
        t = i * np.pi / 4
        x, y = 36 * np.cos(t), 36 * np.sin(t)
        m.box(x - 1.8, y - 1.8, x + 1.8, y + 1.8, 9, 64, flat((168, 160, 146)), flat((190, 182, 166)))

    def rail(i, w, h):
        img = art.blank(max(w, 3), h, (60, 62, 76))
        img[3: -2, :, 3] = 0
        for x in range(0, img.shape[1], 4):
            img[:, x: x + 1, 3] = 255
        return img
    m.ring(0, 0, 37, 37, 9, 24, rail, 8)
    m.ring(0, 0, 44, 46, 62, 66, lambda i, w, h: art.blank(max(w, 3), h, (160, 150, 136)), 8)
    m.ring(0, 0, 46, 4, 66, 98, lambda i, w, h: art.tiles(max(w, 3), h, (82, 58, 100), 5, 6), 8)
    m.box(-2, -2, 2, 2, 98, 112, flat((132, 112, 70)))
    return m


def gasometro(big=True):
    m = art.Model()
    radius, height = (104, 118) if big else (62, 80)
    sides = 20 if big else 14

    def shell(i, w, h):
        img = art.blank(max(w, 3), h, (70, 74, 90))
        for y in range(6, h, 12):
            art.rect(img, 0, y, img.shape[1], 2, (50, 52, 66))
            for x in range(1, img.shape[1], 5):
                art.rect(img, x, y - 2, 1, 1, (102, 108, 124))
        for _ in range(3):
            x = int(art.rng.integers(0, img.shape[1]))
            y = int(art.rng.integers(0, max(h // 2, 1)))
            art.rect(img, x, y, 1, int(art.rng.integers(6, 22)), (118, 72, 52))
        return art.speckle(img, 3)
    m.ring(0, 0, radius, radius, 0, height, shell, sides)
    m.ring(0, 0, radius, radius * 0.8, height, height + 8, lambda i, w, h: art.blank(max(w, 3), h, (58, 62, 78)), sides)
    m.disc(0, 0, radius * 0.8, height + 8, art.speckle(art.blank(40, 40, (66, 70, 86)), 4), sides)
    # armação: colunas em volta e uma cinta de vigas no alto
    columns = 8 if big else 6
    frame_r = radius + 8
    frame_top = height + 26
    points = []
    for i in range(columns):
        t = i * 2 * np.pi / columns
        x, y = frame_r * np.cos(t), frame_r * np.sin(t)
        points.append((x, y))
        m.box(x - 2.5, y - 2.5, x + 2.5, y + 2.5, 0, frame_top, iron, iron_top)
    for i in range(columns):
        (x0, y0), (x1, y1) = points[i], points[(i + 1) % columns]
        for z in (frame_top - 4, height * 0.5):
            m.quad((x0, y0, z + 3), (x1, y1, z + 3), (x1, y1, z), (x0, y0, z), art.blank(30, 3, (52, 54, 68)))
        m.quad((x0, y0, frame_top), (x1, y1, frame_top), (x1, y1, frame_top - 1), (x0, y0, frame_top - 1), art.blank(30, 2, (52, 54, 68)))
        # X da treliça
        mid = frame_top - 4
        m.quad((x0, y0, mid), (x0, y0, mid - 1.5), (x1, y1, height * 0.5 + 1.5), (x1, y1, height * 0.5), art.blank(30, 2, (44, 46, 58)))
    # escada e válvula de piche
    m.box(radius - 4, -4, radius + 3, 4, 0, height, iron)
    m.box(-radius - 22, -6, -radius + 2, 6, 0, 10, lambda n, w, h: art.blank(max(w, 1), max(h, 1), (110, 66, 50)), iron_top)
    return m


def bonde():
    m = art.Model()

    def body(name, w, h):
        img = art.blank(max(w, 2), h, (150, 138, 118))
        art.rect(img, 0, h // 2, img.shape[1], h - h // 2, (104, 40, 50))
        art.rect(img, 0, h // 2, img.shape[1], 2, (128, 58, 64))
        if name in ("frente", "fundo"):
            for x in range(6, img.shape[1] - 10, 14):
                art.window(img, x, 4, 10, 10, lit=False)
        else:
            art.window(img, img.shape[1] // 2 - 6, 4, 12, 10, lit=False)
        return art.speckle(img, 2)
    m.box(-58, -14, 58, 14, 8, 40, body, lambda w, h: art.blank(w, h, (64, 46, 80)))
    m.box(-60, -16, 60, 16, 40, 44, lambda n, w, h: art.blank(max(w, 1), max(h, 1), (64, 46, 80)), lambda w, h: art.blank(w, h, (80, 60, 96)))
    for x in (-40, -26, 26, 40):
        for y in (-12, 10):
            m.box(x - 6, y, x + 6, y + 2, 0, 12, iron, iron_top)
    m.box(-2, -1, 2, 1, 44, 62, iron)
    # descarrilado: tomba um pouco para o lado
    tilt = 0.16
    c, s = np.cos(tilt), np.sin(tilt)
    tilted = []
    for points, tex in m.quads:
        new = []
        for p in points:
            y, z = p[1], p[2]
            new.append(np.array([p[0], y * c - z * s, y * s + z * c + 2]))
        tilted.append((new, tex))
    m.quads = tilted
    return m


def barraca(color, stripe):
    m = art.Model()
    for x, y in ((-24, -16), (20, -16), (-24, 14), (20, 14)):
        m.box(x, y, x + 3, y + 3, 0, 40, wood, lambda w, h: art.blank(w, h, (90, 72, 60)))
    m.box(-26, 8, 24, 18, 0, 16, wood, lambda w, h: art.planks(w, h, (96, 78, 62), 5, False))
    m.gable(-26, -18, 24, 18, 40, 12, cloth(color, stripe), lambda w, h: art.blank(w, h, color), along_x=True, over=4)
    m.box(-18, 10, -6, 16, 16, 22, lambda n, w, h: art.blank(max(w, 1), max(h, 1), (92, 70, 54)))
    return m


def guarita():
    m = art.Model()
    m.box(-14, -14, 14, 14, 0, 44, lambda n, w, h: _sentry(n, w, h), lambda w, h: art.blank(w, h, (60, 56, 64)))
    m.pyramid(-14, -14, 14, 14, 44, 16, tiles((70, 58, 72)), 4)
    return m


def _sentry(name, w, h):
    img = art.planks(max(w, 2), h, (86, 70, 58), 5)
    if name == "frente":
        art.rect(img, w // 2 - 6, 10, 12, h - 10, (26, 24, 30))
    return img


def portao_cidade():
    m = art.Model()
    pillar = lambda n, w, h: stone(n, w, h, (118, 112, 110))
    for x in (-62, 34):
        m.box(x, -14, x + 28, 14, 0, 96, pillar, stone_top)
        m.box(x - 3, -17, x + 31, 17, 96, 104, pillar, stone_top)
        m.pyramid(x - 3, -17, x + 31, 17, 104, 18, tiles((92, 52, 58)), 2)
    m.box(-34, -10, 34, 10, 70, 96, pillar, stone_top)
    m.quad((-34, 10.2, 70), (34, 10.2, 70), (34, 10.2, 0), (-34, 10.2, 0), _gate_bars(68, 70))
    for x in (-48, 48):
        lamp = art.blank(8, 10, (255, 206, 110))
        lamp[..., 3] = art.EMISSIVE
        m.box(x - 4, 14, x + 4, 22, 54, 64, lambda n, w, h: lamp, lambda w, h: art.blank(w, h, (60, 50, 50)))
    return m


def _gate_bars(w, h):
    img = art.blank(w, h, (40, 42, 56))
    img[..., 3] = 0
    for x in range(1, w, 5):
        img[:, x: x + 2, 3] = 255
    for y in (8, 30, 52):
        img[y: y + 2, :, 3] = 255
    return img


# --- Prédios da cidade, apagados ------------------------------------------------------

_window = art.window


def _dark_window(img, x, y, w=9, h=13, lit=True, arch=False):
    _window(img, x, y, w, h, False, arch)
    if (int(x) * 7 + int(y) * 3) % 3 == 0:  # tábuas pregadas numa parte das janelas
        for k in range(3):
            art.rect(img, x - 1, y + 2 + k * 4, w + 2, 2, (92, 70, 54))


def abandoned(build):
    def make():
        art.window = _dark_window
        try:
            return build()
        finally:
            art.window = _window
    return make


NIGHT = dict(sat=0.6, val=0.8, windows="keep", greens=(0.35, 0.7, 0.12), tint=(60, 64, 96))

MODELS = {
    "grade": (grade, None), "muro": (muro, None), "sebe": (sebe, None), "sebe_bloco": (sebe_bloco, None),
    "lapides": (lambda: lapides(0), None), "lapides_b": (lambda: lapides(3), None),
    "mausoleu": (lambda: mausoleu(False), None), "cripta": (lambda: mausoleu(True), None),
    "coreto": (coreto, None), "gasometro": (lambda: gasometro(True), None),
    "gasometro_pequeno": (lambda: gasometro(False), None), "bonde": (bonde, None),
    "barraca_a": (lambda: barraca((112, 70, 62), (150, 138, 118)), None),
    "barraca_b": (lambda: barraca((62, 84, 96), (140, 132, 120)), None),
    "barraca_c": (lambda: barraca((96, 90, 60), (128, 112, 90)), None),
    "guarita": (guarita, None), "portao_cidade": (portao_cidade, None),
    "casa_suburbio_a": (abandoned(art.casa_a), NIGHT), "casa_suburbio_b": (abandoned(art.casa_b), NIGHT),
    "casa_suburbio_c": (abandoned(art.casa_c), NIGHT), "pensao": (abandoned(art.taverna), NIGHT),
    "mansao_aurelio": (abandoned(art.mansao), NIGHT), "capela_canal": (abandoned(art.capela), NIGHT),
    "alojamento": (abandoned(art.abrigo), NIGHT), "barracao": (abandoned(art.abrigo), dict(NIGHT, val=0.7)),
    "galpao": (abandoned(art.forja), NIGHT), "torre_vigia": (abandoned(art.torre_madeira), NIGHT),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {}
    for name, (build, night) in MODELS.items():
        art.rng = np.random.default_rng(art.hash_name(name))
        model = build()
        size, foot = art.bounds(model)
        rows = art.VIEWS // art.COLUMNS
        frames = np.zeros((size[1] * rows, size[0] * art.COLUMNS, 4), np.uint8)
        for view in range(art.VIEWS):
            image = art.render(model, view * 2 * np.pi / art.VIEWS, size, foot)
            y, x = view // art.COLUMNS * size[1], view % art.COLUMNS * size[0]
            frames[y: y + size[1], x: x + size[0]] = np.clip(image, 0, 255).astype(np.uint8)
        image = Image.fromarray(frames, "RGBA")
        if night is not None:
            image = paint.recolor(image, **night)
        image.save(OUT / f"{name}.png", optimize=True)
        meta[name] = {"w": size[0], "h": size[1], "foot_x": foot[0], "foot_y": foot[1], "views": art.VIEWS, "columns": art.COLUMNS}
    (OUT / "meta.json").write_text(json.dumps(meta, indent="\t", sort_keys=True))
    print(f"{len(meta)} modelos em {OUT}")
    if len(sys.argv) > 1:
        sheet(sys.argv[1], meta)


def sheet(path, meta):
    """Folha de conferência: 3 ângulos de cada modelo."""
    cells = []
    for name, info in meta.items():
        im = Image.open(OUT / f"{name}.png")
        views = []
        for view in (0, 3, 6):
            x, y = view % info["columns"] * info["w"], view // info["columns"] * info["h"]
            views.append(im.crop((x, y, x + info["w"], y + info["h"])))
        cells.append((name, views))
    width = 1600
    x = y = 0
    row_h = 0
    placed = []
    for name, views in cells:
        w = sum(v.width for v in views) + 20
        h = max(v.height for v in views) + 16
        if x + w > width:
            x, y = 0, y + row_h
            row_h = 0
        placed.append((name, views, x, y))
        x += w
        row_h = max(row_h, h)
    out = Image.new("RGBA", (width, y + row_h), (58, 62, 74, 255))
    d = ImageDraw.Draw(out)
    for name, views, x, y in placed:
        px = x
        for v in views:
            out.alpha_composite(v, (px, y))
            px += v.width
        d.text((x + 2, y + max(v.height for v in views)), name, fill=(230, 230, 230))
    out.save(path)


if __name__ == "__main__":
    main()
