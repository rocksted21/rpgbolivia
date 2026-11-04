#!/usr/bin/env python3
"""Gera assets/biomes/ a partir das imagens de referencia/biomas.

Os objetos (arvores, cactos, pedras...) sao recortados das imagens; os pisos, as
paredes e a agua sao desenhados aqui com as cores delas. O formato dos pisos e o
mesmo de assets/tiles (186x244), para encaixar na grade e no shader do jogo.

Rodar da raiz do projeto: python tools/build_biomes.py
Precisa de: pip install pillow numpy scipy
"""
from __future__ import annotations

import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
REFS = ROOT / "referencias" / "biomas"
OUT = ROOT / "assets" / "biomes"
TILES = ROOT / "assets" / "tiles"

W, H = 186, 244  # tamanho de um tile
PIXEL = 3  # lado do "pixel" da arte no piso, em pixels da textura
WALL = 31  # altura da parede abaixo da borda da frente
LAYER = 29  # o jogo empilha paredes a cada 29 px
SCALE = 0.5  # as imagens têm 2576 px de largura; metade fica na escala do tile
INK = (20, 19, 24, 255)

# Cores de cada bioma, tiradas das imagens de referência.
PALETTES = {
    "floresta": {
        "top": (87, 170, 38), "dark": (68, 146, 32), "light": (112, 190, 52),
        "shade": (47, 100, 52), "fringe": (45, 118, 34), "fringe_light": (92, 170, 40),
        "wall": (136, 78, 44), "wall_dark": (88, 44, 30), "wall_light": (168, 104, 60),
        "water": (56, 128, 210), "water_dark": (40, 96, 176), "water_light": (150, 205, 245),
        "tuft": (52, 122, 40), "mound": (118, 150, 52), "mound_dark": (72, 112, 44), "mound_light": (146, 186, 64),
    },
    "selva": {
        "top": (58, 122, 58), "dark": (47, 104, 52), "light": (78, 146, 66),
        "shade": (35, 74, 50), "fringe": (32, 88, 44), "fringe_light": (84, 150, 56),
        "wall": (122, 68, 44), "wall_dark": (68, 38, 34), "wall_light": (150, 92, 58),
        "water": (30, 82, 92), "water_dark": (22, 60, 74), "water_light": (120, 190, 190),
        "tuft": (38, 92, 48), "mound": (84, 110, 56), "mound_dark": (50, 78, 48), "mound_light": (112, 142, 66),
    },
    "neve": {
        "top": (222, 241, 248), "dark": (200, 226, 240), "light": (242, 250, 253),
        "shade": (160, 198, 228), "fringe": (120, 168, 208), "fringe_light": (236, 247, 252),
        "wall": (118, 124, 126), "wall_dark": (70, 74, 82), "wall_light": (156, 164, 164),
        "water": (120, 182, 230), "water_dark": (72, 142, 208), "water_light": (232, 246, 252),
        "tuft": (150, 190, 222), "mound": (206, 228, 242), "mound_dark": (148, 188, 222), "mound_light": (244, 251, 254),
    },
    "deserto": {
        "top": (250, 220, 108), "dark": (236, 198, 92), "light": (255, 234, 136),
        "shade": (214, 160, 80), "fringe": (214, 156, 66), "fringe_light": (255, 226, 112),
        "wall": (210, 104, 42), "wall_dark": (140, 54, 24), "wall_light": (238, 136, 60),
        "water": (44, 186, 140), "water_dark": (38, 134, 170), "water_light": (150, 240, 220),
        "tuft": (222, 170, 84), "mound": (236, 190, 90), "mound_dark": (196, 138, 64), "mound_light": (255, 226, 126),
    },
}

# Cores do chão que saem no recorte. O que sobra é o objeto, que tem contorno escuro.
KEYS = {
    "floresta": [(23, 26, 33), (86, 166, 36), (40, 92, 52), (196, 124, 68)],
    "selva": [(23, 26, 31), (60, 116, 58), (54, 110, 52), (148, 94, 58), (45, 80, 55)],
    "neve": [(24, 27, 34), (222, 241, 248), (205, 230, 242), (175, 212, 236), (136, 176, 211)],
    "deserto": [(52, 53, 58), (254, 225, 108), (240, 205, 95), (225, 180, 85), (210, 151, 71), (190, 130, 65)],
}

# Partes da imagem que não são o objeto (paredes e vizinhos atrás dele). Elas se repetem
# nas quatro imagens porque o mapa delas tem o mesmo desenho.
WALL_BUSH = [(2062, 800), (2198, 800), (2198, 868), (2165, 854), (2125, 836), (2062, 826)]
WALL_PILE = [(2262, 755), (2410, 755), (2410, 780), (2262, 852)]
WALL_LOG = [(1592, 792), (1738, 792), (1738, 886), (1690, 872), (1592, 826)]
PINE = [(1924, 12), (1985, 120), (2015, 190), (2035, 295), (2065, 395), (2085, 480), (2062, 520), (1960, 530), (1960, 582), (1880, 582), (1880, 530), (1790, 520), (1752, 490), (1765, 425), (1795, 345), (1805, 280), (1830, 190), (1865, 125)]
STAIRS_LOG = [(1790, 925), (1838, 900), (1838, 1022), (1790, 1022)]
WALL_ROCK = [(1062, 256), (1112, 256), (1112, 338), (1062, 312)]

# nome: (caixa na imagem, polígonos para apagar antes do recorte, tolerância)
CUTS = {
    "floresta": {
        "carvalho": ((122, 188, 645, 770), [[(440, 592), (645, 592), (645, 770), (476, 770), (476, 640), (440, 620)]], 12),
        "pinheiro": ((1742, 8, 2095, 590), [("fora", PINE)], 12),
        "pedra_a": ((378, 832, 565, 972), [], 14),
        "pedra_b": ((842, 256, 1112, 395), [WALL_ROCK], 14),
        "pilha": ((2262, 755, 2550, 998), [WALL_PILE], 14),
        "arbusto_a": ((2062, 836, 2198, 958), [WALL_BUSH], 14),
        "arbusto_b": ((1562, 1062, 1700, 1182), [], 14),
        "tronco": ((1592, 792, 1838, 1022), [WALL_LOG, STAIRS_LOG], 14),
        "placa": ((1388, 830, 1490, 975), [], 16),
    },
    "selva": {
        "palmeira_a": ((212, 336, 468, 660), [[(212, 590), (335, 590), (335, 660), (212, 660)], [(405, 590), (468, 590), (468, 660), (405, 660)]], 12),
        "samambaia": ((1780, 420, 2082, 642), [], 12),
        "ruinas": ((512, 248, 868, 528), [], 12),
        "pedra_a": ((378, 832, 565, 972), [], 13),
        "pilha": ((2262, 755, 2550, 998), [WALL_PILE], 13),
        "arbusto_a": ((2062, 836, 2198, 958), [WALL_BUSH], 13),
        "arbusto_b": ((1562, 1062, 1700, 1182), [], 13),
        "flores_a": ((2146, 918, 2290, 1085), [], 12),
        "tronco": ((1592, 792, 1838, 1022), [WALL_LOG, STAIRS_LOG], 13),
    },
    "neve": {
        "pinheiro_b": ((2312, 46, 2514, 386), [], 22, 250),
        "pedra_a": ((378, 832, 565, 966), [], 16),
        "pedra_b": ((838, 256, 1112, 395), [WALL_ROCK], 16),
        "pilha": ((2262, 755, 2550, 998), [WALL_PILE], 16),
        "arbusto_a": ((2062, 836, 2198, 958), [WALL_BUSH], 8),
        "arbusto_b": ((1562, 1062, 1700, 1182), [], 8),
        "galhos_a": ((2146, 942, 2284, 1072), [], 22),
        "galhos_b": ((1640, 660, 1742, 742), [], 22),
    },
    "deserto": {
        "cacto_a": ((636, 232, 782, 482), [], 26),
        "cacto_b": ((306, 508, 448, 742), [], 26),
        "cacto_c": ((1434, 676, 1562, 880), [[(1434, 676), (1446, 676), (1446, 880), (1434, 880)]], 26),
        "cacto_redondo": ((826, 602, 902, 682), [], 26),
        "cacto_baixo": ((1838, 1052, 1938, 1138), [], 26),
        "palmeira": ((1100, 755, 1320, 1035), [[(1100, 950), (1200, 950), (1200, 1035), (1100, 1035)], [(1262, 755), (1320, 755), (1320, 800), (1290, 785)]], 22),
        "pedra_a": ((376, 832, 565, 972), [], 26),
        "pedra_b": ((840, 256, 1112, 395), [WALL_ROCK], 26),
        "pilha": ((2262, 755, 2550, 998), [WALL_PILE], 24),
        "caveira": ((686, 766, 842, 896), [[(686, 766), (770, 766), (770, 806), (686, 806)]], 24),
        "seco_a": ((1566, 1048, 1708, 1172), [], 24),
        "seco_b": ((2146, 942, 2284, 1072), [], 24),
        "feno": ((2062, 832, 2198, 952), [WALL_BUSH], 24),
        "tronco": ((1592, 792, 1838, 1022), [WALL_LOG, STAIRS_LOG], 24),
    },
}


def front_edge(x: float) -> float:
    return 213.0 - abs(x - 93.0) * (53.0 / 93.0)


def back_edge(x: float) -> float:
    return abs(x - 93.0) * (53.0 / 93.0)


def blend(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# --- Recortes ----------------------------------------------------------------

def cut_prop(image: np.ndarray, biome: str, box, erase, tolerance, ground_from=None) -> Image.Image:
    """ground_from: acima dessa linha só existe o fundo; a neve da ponta da árvore fica."""
    x0, y0, x1, y1 = box
    crop = image[y0:y1, x0:x1].astype(np.int32)
    ground = np.zeros(crop.shape[:2], bool)
    for index, key in enumerate(KEYS[biome]):
        near = np.abs(crop - np.array(key)).max(axis=2) <= tolerance
        if ground_from is not None and index > 0:
            near[:ground_from - y0] = False
        ground |= near
    if erase:
        canvas = Image.new("L", (x1 - x0, y1 - y0), 0)
        for polygon in erase:
            # ("fora", polígono) apaga tudo o que está fora do contorno do objeto.
            inverted = polygon[0] == "fora"
            points = polygon[1] if inverted else polygon
            shape = Image.new("L", canvas.size, 0)
            ImageDraw.Draw(shape).polygon([(x - x0, y - y0) for x, y in points], fill=255)
            area = np.array(shape) > 0
            ground |= ~area if inverted else area
    # Só sai o chão ligado à borda do recorte: cores iguais dentro do objeto ficam.
    labels, _ = ndimage.label(ground)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    outside = np.isin(labels, edge[edge > 0])
    solid = ~outside
    # Fiapos finos (capim, linhas de parede) somem na erosão; só o corpo do objeto volta.
    core = ndimage.binary_erosion(solid, iterations=3)
    labels, count = ndimage.label(core)
    if count > 1:
        sizes = ndimage.sum(core, labels, range(1, count + 1))
        core = labels == int(np.argmax(sizes)) + 1
    solid = ndimage.binary_dilation(core, iterations=4) & solid
    # O que restou por fora do contorno escuro sai camada por camada, parando no contorno.
    luma = crop @ np.array([0.3, 0.59, 0.11])
    for _ in range(0 if ground_from is not None else 5):
        rim = solid & ~ndimage.binary_erosion(solid, border_value=0)
        solid &= ~(rim & (luma >= 62))
    solid = ndimage.binary_fill_holes(solid)
    alpha = (solid * 255).astype(np.uint8)
    rgba = np.dstack([crop.astype(np.uint8), alpha])
    prop = Image.fromarray(rgba, "RGBA")
    prop = prop.crop(prop.getbbox())
    size = (max(1, round(prop.width * SCALE)), max(1, round(prop.height * SCALE)))
    return outlined(prop.resize(size, Image.Resampling.BOX))


def same_silhouette(image: np.ndarray, model: np.ndarray, box) -> Image.Image:
    """Recorta de `image` com o formato do objeto em `model`: as imagens têm o mesmo mapa."""
    x0, y0, x1, y1 = box
    crop = model[y0:y1, x0:x1].astype(np.int32)
    ground = np.zeros(crop.shape[:2], bool)
    for key in KEYS["floresta"]:
        ground |= np.abs(crop - np.array(key)).max(axis=2) <= 12
    shape = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(shape).polygon([(x - x0, y - y0) for x, y in PINE], fill=255)
    ground |= np.array(shape) == 0
    labels, _ = ndimage.label(ground)
    edge = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    solid = ndimage.binary_fill_holes(ndimage.binary_opening(~np.isin(labels, edge[edge > 0]), iterations=3))
    rgba = np.dstack([image[y0:y1, x0:x1], (solid * 255).astype(np.uint8)])
    prop = Image.fromarray(rgba, "RGBA")
    prop = prop.crop(prop.getbbox())
    return outlined(prop.resize((round(prop.width * SCALE), round(prop.height * SCALE)), Image.Resampling.BOX))


def outlined(prop: Image.Image) -> Image.Image:
    """Alfa sem meio-termo e contorno escuro de 1 px, como nas referências."""
    data = np.array(prop)
    solid = data[..., 3] >= 128
    grown = ndimage.binary_dilation(np.pad(solid, 1), iterations=1)
    out = np.zeros((*grown.shape, 4), np.uint8)
    out[grown] = INK
    inner = np.pad(data, ((1, 1), (1, 1), (0, 0)))
    inside = np.pad(solid, 1)
    out[inside] = inner[inside]
    out[inside, 3] = 255
    return Image.fromarray(out, "RGBA")


def scaled(prop: Image.Image, factor: float) -> Image.Image:
    size = (max(1, round(prop.width * factor)), max(1, round(prop.height * factor)))
    if factor >= 1.0:
        return prop.resize(size, Image.Resampling.NEAREST)
    small = np.array(prop.resize(size, Image.Resampling.BOX))
    small[..., 3] = np.where(small[..., 3] >= 128, 255, 0)
    return Image.fromarray(small, "RGBA")


def compose(parts, margin=6) -> Image.Image:
    """parts: (imagem, x do centro, y da base), em volta do ponto de apoio.

    O apoio fica sempre no centro do canvas, para o jogo posicionar qualquer arte igual.
    """
    half_w = int(max(abs(x) + im.width / 2 for im, x, _ in parts)) + margin
    half_h = int(max(max(im.height - y, y) for im, _, y in parts)) + margin
    canvas = Image.new("RGBA", (half_w * 2, half_h * 2), (0, 0, 0, 0))
    for im, x, y in parts:
        canvas.alpha_composite(im, (int(half_w + x - im.width / 2), int(half_h + y - im.height)))
    return canvas


# --- Pisos -------------------------------------------------------------------

def make_tile(biome: str, kind: str, seed: int, fringe=True) -> Image.Image:
    pal = PALETTES[biome]
    rng = random.Random(f"{biome}/{kind}/{seed}")
    cols, rows = W // PIXEL + 2, H // PIXEL + 2
    water = kind.startswith("agua")

    # Topo ---------------------------------------------------------------------
    base = pal["water"] if water else pal["top"]
    cells = [[base for _ in range(cols)] for _ in range(rows)]
    def splat(cx, cy, radius, color, chance=1.0):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if dx * dx + dy * dy * 2 <= radius * radius and rng.random() < chance:
                    if 0 <= cy + dy < rows and 0 <= cx + dx < cols:
                        cells[cy + dy][cx + dx] = color

    if water:
        for _ in range(4):
            cx, cy = rng.randrange(cols), rng.randrange(rows)
            splat(cx, cy, rng.randint(4, 9), blend(pal["water"], pal["water_dark"], 0.4), 0.7)
        for _ in range(8):
            cx, cy = rng.randrange(4, cols - 6), rng.randrange(4, rows - 12)
            for i in range(rng.randint(3, 7)):
                cells[cy + (i % 3 == 2)][cx + i] = pal["water_light"]
    else:
        for _ in range(7):
            splat(rng.randrange(cols), rng.randrange(rows), rng.randint(2, 5), pal["dark"], 0.55)
        for _ in range(5):
            splat(rng.randrange(cols), rng.randrange(rows), rng.randint(1, 3), pal["light"], 0.5)
        for _ in range(26):
            cells[rng.randrange(rows)][rng.randrange(cols)] = pal["dark"] if rng.random() < 0.6 else pal["light"]
        if kind == "sombra":
            cx, cy = cols // 2, 36
            for dy in range(-22, 22):
                for dx in range(-24, 25):
                    d = dx * dx / (23.0 ** 2) + dy * dy / (17.0 ** 2)
                    if d <= 1.0 - rng.random() * 0.22 and 0 <= cy + dy < rows and 0 <= cx + dx < cols:
                        cells[cy + dy][cx + dx] = pal["shade"]
        if kind == "campo_b":
            for _ in range(5):  # tufos de capim, ou riscos do vento na areia
                cx, cy = rng.randrange(14, cols - 16), rng.randrange(14, 56)
                if biome == "deserto":
                    for i in range(rng.randint(4, 8)):
                        cells[cy + (i // 3)][cx + i] = pal["shade"]
                else:
                    for dx, dy in [(-2, -1), (-2, 0), (0, -2), (0, -1), (0, 0), (2, -1), (2, 0)]:
                        cells[cy + dy][cx + dx] = pal["tuft"]

    # Parede: blocos que seguem a inclinação de cada lado do hexágono -----------
    row_height = LAYER / 2.0
    block_colors: dict[tuple, tuple] = {}

    def wall_color(x: int, y: int) -> tuple:
        u = abs(x - 93.0)
        v = y - front_edge(x)
        side = 0 if x < 93 else 1
        row = int(v // row_height)
        block = int((u + row * 15) // 30)
        inside_v = v % row_height
        inside_u = (u + row * 15) % 30
        if water:
            color = pal["water_dark"] if v > 5 else pal["water"]
            return blend(color, (0, 0, 0), 0.18 if side else 0.0)
        if inside_v < PIXEL or inside_u < PIXEL:
            return pal["wall_dark"]
        key = (side, row, block)
        if key not in block_colors:
            roll = random.Random(f"{biome}{key}{seed}").random()
            block_colors[key] = pal["wall_light"] if roll > 0.78 else (blend(pal["wall"], pal["wall_dark"], 0.3) if roll < 0.22 else pal["wall"])
        color = block_colors[key]
        if inside_v < PIXEL * 2 and inside_u > PIXEL * 2:
            color = blend(color, pal["wall_light"], 0.45)
        return blend(color, (0, 0, 0), 0.14 if side else 0.0)

    # Franja de capim, neve ou areia caindo por cima da parede -----------------
    drip = [rng.choice([1, 1, 2, 2, 3, 3, 4]) for _ in range(cols)]

    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for x in range(W):
        cx = x // PIXEL
        front = front_edge(x)
        back = back_edge(x)
        for y in range(H):
            if y < back or y > front + WALL:
                continue
            cy = y // PIXEL
            # Amostra pela grade para manter os "pixels" da arte alinhados.
            sx = cx * PIXEL + 1
            sy = cy * PIXEL + 1
            if y <= front:
                color = cells[cy][cx]
                # Costura escura entre casas, fina como nas referências.
                edge = min(y - back, front - y, x, W - 1 - x)
                if edge < 1.5:
                    color = blend(color, pal["shade"] if not water else pal["water_dark"], 0.55)
                elif edge < PIXEL + 1.5 and not water:
                    color = blend(color, pal["light"], 0.35)
            else:
                color = wall_color(sx if abs(sx - 93) < 93 else x, sy if sy > front else y)
                if fringe and not water:
                    v = y - front
                    length = drip[cx] * PIXEL
                    if v <= length:
                        color = pal["fringe_light"] if v <= PIXEL else pal["fringe"]
                elif water and y - front <= 2:
                    color = pal["water_light"]
            if y >= front + WALL - 1.5:
                color = blend(color, (0, 0, 0), 0.5)
            px[x, y] = (*color, 255)
    return img


# --- Colinas (desenhadas, pois não há montes nas referências) ------------------

def mound(biome: str, width: int, height: int, seed: int) -> Image.Image:
    pal = PALETTES[biome]
    rng = random.Random(f"{biome}/monte/{seed}")
    g = 3
    cols, rows = width // g, height // g
    data = np.zeros((rows, cols, 4), np.uint8)
    for cy in range(rows):
        for cx in range(cols):
            nx = (cx + 0.5) / cols * 2 - 1
            ny = 1 - (cy + 0.5) / rows
            top = (1 - abs(nx) ** 1.7)
            if ny > top:
                continue
            shade = nx + (0.5 - ny / max(top, 0.01)) * 0.5 + rng.uniform(-0.12, 0.12)
            color = pal["mound_light"] if shade < -0.28 else (pal["mound_dark"] if shade > 0.34 else pal["mound"])
            data[cy, cx] = (*color, 255)
    im = Image.fromarray(data, "RGBA")
    return outlined(im.resize((cols * g, rows * g), Image.Resampling.NEAREST))


# --- Prédios do kit, sem o chão ------------------------------------------------

def kit_building(tile_id: int) -> Image.Image:
    src = np.array(Image.open(TILES / f"{tile_id}.png").convert("RGBA")).astype(np.int32)
    base = np.array(Image.open(TILES / "9.png").convert("RGBA")).astype(np.int32)
    same = np.abs(src - base).max(axis=2) < 10
    r, g, b = src[..., 0], src[..., 1], src[..., 2]
    grass = (g >= r * 0.95) & (b < g * 0.62) & (g > 50)  # chão e sombra esverdeados do kit
    keep = ~(same | grass)
    keep[203:] = False
    keep = ndimage.binary_opening(keep, iterations=1)
    labels, count = ndimage.label(keep)
    sizes = ndimage.sum(keep, labels, range(1, count + 1))
    keep = labels == int(np.argmax(sizes)) + 1
    keep = ndimage.binary_fill_holes(keep)
    out = src.astype(np.uint8)
    out[..., 3] = np.where(keep, 255, 0)
    im = Image.fromarray(out, "RGBA")
    return im.crop(im.getbbox())


# --- Montagem por bioma ---------------------------------------------------------

def save(im: Image.Image, biome: str, name: str) -> None:
    folder = OUT / biome
    folder.mkdir(parents=True, exist_ok=True)
    im.save(folder / f"{name}.png", optimize=True)


def build_props(biome: str, c: dict) -> None:
    casa, torre = kit_building(10), kit_building(11)
    if biome == "floresta":
        fundo_a = compose([(scaled(c["carvalho"], 0.72), 0, 0)])
        fundo_b = compose([(scaled(c["pinheiro"], 0.78), 0, 0)])
        frente_a = compose([(scaled(c["pinheiro"], 0.42), -64, 0), (c["arbusto_a"], 62, 4)])
        frente_b = compose([(scaled(c["carvalho"], 0.38), 64, 0), (c["arbusto_b"], -60, 2)])
        pedras_a = compose([(c["pedra_a"], -32, 0), (c["arbusto_a"], 42, 6)])
        pedras_b = compose([(c["pedra_b"], 0, 0)])
        montanha_a = compose([(scaled(c["pilha"], 1.35), 0, 0)])
        montanha_b = compose([(scaled(c["pedra_b"], 1.5), 0, 0), (c["pedra_a"], 56, 12)])
        enfeites = [c["arbusto_b"], c["tronco"], c["placa"]]
    elif biome == "selva":
        fundo_a = compose([(c["palmeira_a"], -8, 0), (c["arbusto_a"], 50, 4)])
        fundo_b = compose([(c["palmeira_a"].transpose(Image.Transpose.FLIP_LEFT_RIGHT), 10, 0), (scaled(c["palmeira_a"], 0.7), -52, -6)])
        frente_a = compose([(scaled(c["samambaia"], 0.8), 50, 0), (scaled(c["flores_a"], 0.75), -60, 0)])
        frente_b = compose([(scaled(c["palmeira_a"], 0.62), -62, 0), (c["arbusto_b"], 58, 2)])
        pedras_a = compose([(c["pedra_a"], -30, 0), (c["arbusto_b"], 44, 6)])
        pedras_b = compose([(c["pedra_a"], 18, 0), (scaled(c["flores_a"], 0.75), -44, 4)])
        montanha_a = compose([(scaled(c["pilha"], 1.35), 0, 0)])
        montanha_b = compose([(scaled(c["pilha"], 1.2), 0, 0), (scaled(c["arbusto_a"], 0.8), -62, 10)])
        enfeites = [c["flores_a"], scaled(c["flores_a"], 0.75), c["tronco"]]
        torre = scaled(c["ruinas"], 1.0)
    elif biome == "neve":
        fundo_a = compose([(scaled(c["pinheiro"], 0.78), 0, 0)])
        fundo_b = compose([(c["pinheiro_b"], -14, 0), (scaled(c["pinheiro_b"], 0.7), 48, -6)])
        frente_a = compose([(scaled(c["pinheiro_b"], 0.55), -64, 0), (c["arbusto_a"], 62, 4)])
        frente_b = compose([(scaled(c["pinheiro"], 0.34), 64, 0), (c["galhos_a"], -60, 2)])
        pedras_a = compose([(c["pedra_a"], -32, 0), (c["arbusto_a"], 42, 6)])
        pedras_b = compose([(c["pedra_b"], 0, 0), (c["galhos_b"], 60, 8)])
        montanha_a = compose([(scaled(c["pilha"], 1.35), 0, 0)])
        montanha_b = compose([(scaled(c["pedra_b"], 1.5), 0, 0), (c["pedra_a"], 56, 12)])
        enfeites = [c["galhos_a"], c["galhos_b"], c["arbusto_b"]]
    else:  # deserto
        fundo_a = compose([(c["cacto_a"], -24, 0), (scaled(c["cacto_b"], 0.8), 48, -8)])
        fundo_b = compose([(c["palmeira"], 0, 0)])
        frente_a = compose([(c["cacto_baixo"], 62, 2), (c["seco_a"], -62, 2)])
        frente_b = compose([(c["cacto_b"], -60, 0), (c["cacto_redondo"], 58, 2)])
        pedras_a = compose([(c["pedra_a"], -28, 0), (c["seco_b"], 46, 6)])
        pedras_b = compose([(c["pedra_b"], 0, 0)])
        montanha_a = compose([(scaled(c["pilha"], 1.35), 0, 0)])
        montanha_b = compose([(scaled(c["pedra_b"], 1.5), 0, 0), (c["pedra_a"], 56, 12)])
        enfeites = [c["caveira"], c["feno"], c["tronco"]]

    for i, name in enumerate(["a", "b"]):
        big = mound(biome, 132 - i * 16, 72 - i * 8, i)
        small = mound(biome, 84, 44, i + 5)
        tiny = mound(biome, 60, 32, i + 9)
        save(compose([(big, -14 + i * 26, -8), (small, 44 - i * 92, 8), (tiny, -58 + i * 104, 16)]), biome, f"colinas_{name}")
    save(fundo_a, biome, "floresta_fundo_a")
    save(fundo_b, biome, "floresta_fundo_b")
    save(frente_a, biome, "floresta_frente_a")
    save(frente_b, biome, "floresta_frente_b")
    save(pedras_a, biome, "pedras_a")
    save(pedras_b, biome, "pedras_b")
    save(montanha_a, biome, "montanha_a")
    save(montanha_b, biome, "montanha_b")
    save(compose([(casa, 0, 0)]), biome, "casa")
    save(compose([(torre, 0, 0)]), biome, "torre")
    for name, im in zip("abc", enfeites):
        save(compose([(im, 0, 0)]), biome, f"enfeite_{name}")


def main() -> None:
    for biome in PALETTES:
        image = np.array(Image.open(REFS / f"{biome}.jpg").convert("RGB"))
        cuts = {name: cut_prop(image, biome, *spec) for name, spec in CUTS[biome].items()}
        if biome == "neve":
            model = np.array(Image.open(REFS / "floresta.jpg").convert("RGB"))
            cuts["pinheiro"] = same_silhouette(image, model, (1742, 8, 2095, 590))
        for name, seed in [("campo_a", 1), ("campo_b", 2), ("sombra", 3), ("agua_a", 4), ("agua_b", 6)]:
            save(make_tile(biome, name, seed), biome, name)
        save(make_tile(biome, "parede", 5, fringe=False), biome, "parede")
        build_props(biome, cuts)
    print("biomas gerados em", OUT)


if __name__ == "__main__":
    main()
