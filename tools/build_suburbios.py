"""Arte dos Subúrbios Apagados (assets/biomes/suburbios). Rodar na raiz do projeto:

    python3 tools/build_suburbios.py [folha.png]

Parte da arte reaproveita peças do jogo (casas da cidade, portões, carroças), recolorida para a
noite apagada: janelas escuras, cores lavadas, musgo cinzento. O resto é desenhado aqui, em
pixel de arte, com o mesmo contorno azul-marinho e sombra em 3 tons dos heróis (ESTILO_VISUAL.md).
Toda peça sai como as outras do jogo: 288x672, pé no centro da imagem, pixel de arte ampliado 2x.
"""
from __future__ import annotations

import colorsys
import math
import random
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path("assets/biomes/suburbios")
SRC = Path("assets")

# Paleta (ESTILO_VISUAL.md): mundo frio e lavado; a luz quente só onde há chama.
INK = (27, 24, 43)  # contorno
IRON = [(30, 33, 48), (48, 53, 72), (74, 81, 104), (104, 112, 138)]
STONE = [(62, 60, 70), (86, 84, 94), (114, 111, 120), (146, 142, 150)]
MOSS = [(48, 62, 52), (66, 84, 64), (90, 108, 80)]
HEDGE = [(20, 32, 32), (28, 46, 40), (38, 62, 48), (56, 82, 60)]
BARK = [(38, 30, 34), (58, 46, 48), (80, 64, 62), (104, 86, 80)]
LEAF = [(56, 40, 40), (84, 56, 48), (112, 74, 56)]
PLUM = [(44, 31, 58), (64, 44, 80), (88, 62, 104), (112, 84, 126)]
WINE = [(66, 28, 40), (98, 40, 52), (130, 58, 66)]
CREAM = [(120, 110, 100), (154, 142, 124), (186, 172, 148)]
STEEL = [(40, 42, 56), (58, 62, 78), (80, 86, 102), (106, 112, 128)]
RUST = [(90, 52, 42), (122, 72, 52), (150, 96, 64)]
GLASS = [(24, 30, 46), (38, 50, 72), (66, 86, 112)]
FLAME = [(214, 120, 40), (245, 176, 64), (255, 232, 160)]
WATER = [(30, 50, 64), (52, 82, 98), (96, 136, 150)]


# --- Base: tela de arte, contorno e saída no tamanho do jogo ------------------------

class Canvas:
    """Tela em pixel de arte. O pé da peça fica em (cx, foot)."""

    def __init__(self, w=144, h=168):
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        self.w, self.h = w, h

    def rect(self, x0, y0, x1, y1, c):
        self.d.rectangle((round(x0), round(y0), round(x1), round(y1)), fill=c + (255,))

    def poly(self, pts, c):
        self.d.polygon([(round(x), round(y)) for x, y in pts], fill=c + (255,))

    def ellipse(self, x0, y0, x1, y1, c):
        self.d.ellipse((round(x0), round(y0), round(x1), round(y1)), fill=c + (255,))

    def line(self, pts, c, w=1):
        self.d.line([(round(x), round(y)) for x, y in pts], fill=c + (255,), width=w)

    def px(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.im.putpixel((int(x), int(y)), c + (255,))

    def paste(self, other: Image.Image, x, y):
        self.im.alpha_composite(other, (int(x), int(y)))

    def outline(self, color=INK):
        a = np.array(self.im)
        alpha = a[..., 3] > 0
        grown = alpha.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grown |= np.roll(np.roll(alpha, dy, 0), dx, 1)
        edge = grown & ~alpha
        a[edge] = color + (255,)
        self.im = Image.fromarray(a)
        self.d = ImageDraw.Draw(self.im)
        return self


def drop_specks(art: Image.Image, smallest=14) -> Image.Image:
    """Tira pontinhos soltos (sobras de folha ou de recorte) longe da peça."""
    a = np.array(art)
    solid = a[..., 3] > 0
    seen = np.zeros_like(solid)
    h, w = solid.shape
    for y0 in range(h):
        for x0 in range(w):
            if not solid[y0, x0] or seen[y0, x0]:
                continue
            stack = [(y0, x0)]
            seen[y0, x0] = True
            group = []
            while stack:
                y, x = stack.pop()
                group.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and solid[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if len(group) < smallest:
                for y, x in group:
                    a[y, x, 3] = 0
    return Image.fromarray(a)


def finish(art: Image.Image, foot_x=None, foot_y=None) -> Image.Image:
    """Peça em pixel de arte -> imagem do jogo (288x672, pé no centro, ampliada 2x)."""
    art = drop_specks(art)
    box = art.getbbox()
    if box is None:
        raise ValueError("peça vazia")
    if foot_x is None:
        foot_x = (box[0] + box[2]) / 2
    if foot_y is None:
        foot_y = box[3]
    out = Image.new("RGBA", (144, 336))
    out.alpha_composite(art, (int(round(72 - foot_x)), int(round(168 - foot_y))))
    return out.resize((288, 672), Image.Resampling.NEAREST)


def from_game(path: Path) -> Image.Image:
    """Peça do jogo (288x672, 2x) -> pixel de arte."""
    im = Image.open(path).convert("RGBA")
    return im.resize((im.width // 2, im.height // 2), Image.Resampling.NEAREST)


def save(im: Image.Image, name: str):
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / f"{name}.png", optimize=True)


# --- Recolorir para a noite apagada ---------------------------------------------------

def _hsv(a):
    rgb = a[..., :3].astype(np.float32) / 255.0
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    diff = mx - mn
    h = np.zeros_like(mx)
    m = diff > 1e-6
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    idx = m & (mx == r)
    h[idx] = ((g - b)[idx] / diff[idx]) % 6
    idx = m & (mx == g)
    h[idx] = ((b - r)[idx] / diff[idx]) + 2
    idx = m & (mx == b)
    h[idx] = ((r - g)[idx] / diff[idx]) + 4
    h = h / 6.0
    s = np.where(mx > 1e-6, diff / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def _rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    out = np.zeros(h.shape + (3,), np.float32)
    for k, (a, b, c) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[sel, 0], out[sel, 1], out[sel, 2] = a[sel], b[sel], c[sel]
    return np.clip(out * 255, 0, 255).astype(np.uint8)


def recolor(im: Image.Image, sat=0.65, val=0.82, windows="dark", greens=None, hue_shift=0.0, tint=None) -> Image.Image:
    """Lava as cores. windows: "dark" apaga as janelas acesas, "keep" deixa a luz.
    greens: (sat, val, hue) para folhagem; tint: cor que puxa tudo (frio da noite)."""
    a = np.array(im.convert("RGBA"))
    h, s, v = _hsv(a)
    warm = (h > 0.08) & (h < 0.18) & (s > 0.35) & (v > 0.62)
    green = (h > 0.18) & (h < 0.48) & (s > 0.2)
    s2 = s * sat
    v2 = v * val
    h2 = (h + hue_shift) % 1.0
    if greens is not None:
        gs, gv, gh = greens
        s2 = np.where(green, s * gs, s2)
        v2 = np.where(green, v * gv, v2)
        if gh is not None:
            h2 = np.where(green, gh, h2)
    if windows == "dark":
        # janelas acesas viram vidro escuro com um reflexo azulado
        s2 = np.where(warm, 0.38, s2)
        h2 = np.where(warm, 0.62, h2)
        v2 = np.where(warm, 0.16 + (v - 0.62) * 0.5, v2)
    rgb = _rgb(h2, np.clip(s2, 0, 1), np.clip(v2, 0, 1)).astype(np.float32)
    if tint is not None:
        rgb = rgb * 0.82 + np.array(tint, np.float32) * 0.18
    a[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    return Image.fromarray(a)


def dry(im: Image.Image) -> Image.Image:
    """Tira a água: o azul vira pedra escura e limo."""
    a = np.array(im.convert("RGBA"))
    h, s, v = _hsv(a)
    blue = (a[..., 3] > 0) & (h > 0.45) & (h < 0.7) & (s > 0.25)
    shade = np.clip(v * 0.55, 0, 1)
    a[blue, 0] = (40 + shade[blue] * 60).astype(np.uint8)
    a[blue, 1] = (40 + shade[blue] * 66).astype(np.uint8)
    a[blue, 2] = (46 + shade[blue] * 60).astype(np.uint8)
    return Image.fromarray(a)


def boards(art: Image.Image, seed: int, count=3) -> Image.Image:
    """Tábuas pregadas em algumas janelas escuras (casas abandonadas)."""
    a = np.array(art)
    h, s, v = _hsv(a)
    dark_glass = (a[..., 3] > 0) & (h > 0.55) & (h < 0.7) & (v < 0.32) & (s > 0.25)
    ys, xs = np.nonzero(dark_glass)
    if len(xs) == 0:
        return art
    rng = random.Random(seed)
    c = Canvas(art.width, art.height)
    c.paste(art, 0, 0)
    for _ in range(count):
        k = rng.randrange(len(xs))
        x, y = xs[k], ys[k]
        w = rng.randint(7, 10)
        tilt = rng.choice((-1, 1))
        for dy in range(3):
            c.line([(x - w // 2, y + dy + tilt), (x + w // 2, y + dy - tilt)], BARK[2 if dy else 3])
        c.line([(x - w // 2, y - 1 + tilt), (x + w // 2, y - 1 - tilt)], INK)
    return c.im


# --- Desenhos novos ----------------------------------------------------------------------

def gas_lamp(lit=False) -> Image.Image:
    c = Canvas(40, 120)
    x = 20
    foot = 116
    # pedestal em degraus
    c.rect(x - 7, foot - 5, x + 6, foot, IRON[1])
    c.rect(x - 7, foot - 5, x - 5, foot, IRON[2])
    c.rect(x - 5, foot - 10, x + 4, foot - 5, IRON[1])
    c.rect(x - 5, foot - 10, x - 3, foot - 5, IRON[2])
    # poste com anel e voluta
    c.rect(x - 2, foot - 78, x + 1, foot - 10, IRON[1])
    c.rect(x - 2, foot - 78, x - 1, foot - 10, IRON[3])
    c.rect(x - 4, foot - 44, x + 3, foot - 41, IRON[2])
    c.rect(x - 9, foot - 75, x + 8, foot - 73, IRON[1])  # travessa da escada do acendedor
    c.rect(x - 9, foot - 75, x - 7, foot - 73, IRON[2])
    # lanterna: gaiola trapezoidal
    top = foot - 98
    c.poly([(x - 8, top + 4), (x + 7, top + 4), (x + 5, top + 20), (x - 6, top + 20)], IRON[0])
    glass = FLAME if lit else GLASS
    c.poly([(x - 6, top + 6), (x + 5, top + 6), (x + 3, top + 18), (x - 4, top + 18)], glass[1])
    c.rect(x - 4, top + 7, x - 2, top + 15, glass[2])
    if lit:
        c.rect(x - 1, top + 9, x + 1, top + 15, (255, 250, 220))
    else:
        c.px(x + 2, top + 8, GLASS[2])
        c.px(x + 3, top + 9, GLASS[2])
    c.rect(x - 1, top + 6, x, top + 18, IRON[0])
    c.rect(x - 7, top + 19, x + 6, top + 22, IRON[1])
    c.rect(x - 4, top + 22, x + 3, top + 24, IRON[2])
    # chapéu e ponteira
    c.poly([(x - 10, top + 5), (x + 9, top + 5), (x, top - 3)], IRON[1])
    c.poly([(x - 10, top + 5), (x, top - 3), (x - 1, top + 5)], IRON[2])
    c.rect(x - 1, top - 7, x, top - 3, IRON[2])
    c.px(x - 1, top - 8, IRON[3])
    c.outline()
    return c.im


def fence() -> Image.Image:
    c = Canvas(80, 60)
    foot = 56
    left, right = 4, 75
    # mureta de pedra
    c.rect(left, foot - 7, right, foot, STONE[1])
    c.rect(left, foot - 7, right, foot - 6, STONE[3])
    for k in range(left + 6, right, 12):
        c.rect(k, foot - 6, k, foot, STONE[0])
    c.rect(left, foot - 1, right, foot, STONE[0])
    # barras com ponta de lança
    for i, bx in enumerate(range(left + 3, right - 1, 6)):
        tall = 38 if i % 3 == 1 else 34
        c.rect(bx, foot - tall, bx + 1, foot - 7, IRON[1])
        c.px(bx, foot - tall + 2, IRON[3])
        c.poly([(bx - 1, foot - tall), (bx + 2, foot - tall), (bx + 0.5, foot - tall - 4)], IRON[2])
    c.rect(left + 1, foot - 30, right - 1, foot - 29, IRON[1])
    c.rect(left + 1, foot - 13, right - 1, foot - 12, IRON[1])
    c.rect(left + 1, foot - 30, right - 1, foot - 30, IRON[2])
    # voltas entre as travessas
    for bx in range(left + 6, right - 4, 12):
        c.ellipse(bx - 2, foot - 24, bx + 3, foot - 19, IRON[1])
        c.ellipse(bx - 1, foot - 23, bx + 2, foot - 20, (0, 0, 0))
    a = np.array(c.im)
    a[(a[..., 0] == 0) & (a[..., 1] == 0) & (a[..., 2] == 0)] = 0
    c.im = Image.fromarray(a)
    c.d = ImageDraw.Draw(c.im)
    # um pouco de hera morta
    rng = random.Random(4)
    for _ in range(10):
        x0 = rng.randint(left, right)
        y0 = rng.randint(foot - 16, foot - 6)
        c.rect(x0, y0, x0 + 1, y0 + 1, MOSS[rng.randint(0, 2)])
    c.outline()
    return c.im


def leaf_mass(c: Canvas, cx, cy, rx, ry, palette, seed, holes=0.0):
    """Massa de folhas em tufos: base escura, meio e luz por cima à esquerda."""
    rng = random.Random(seed)
    c.ellipse(cx - rx, cy - ry, cx + rx, cy + ry, palette[0])
    for _ in range(int(rx * ry / 6)):
        ang = rng.random() * math.tau
        r = math.sqrt(rng.random())
        x = cx + math.cos(ang) * rx * r * 0.9
        y = cy + math.sin(ang) * ry * r * 0.9
        light = (cx - x) / rx * 0.6 + (cy - y) / ry * 0.8 + rng.uniform(-0.4, 0.4)
        tone = palette[1] if light < 0.2 else (palette[2] if light < 0.9 else palette[3 if len(palette) > 3 else 2])
        s = rng.randint(2, 4)
        c.ellipse(x - s, y - s * 0.8, x + s, y + s * 0.8, tone)
    for _ in range(int(holes * rx)):
        x = cx + rng.uniform(-rx * 0.7, rx * 0.7)
        y = cy + rng.uniform(-ry * 0.6, ry * 0.6)
        c.ellipse(x - 1, y - 1, x + 1, y + 1, palette[0])


def hedge(seed=1) -> Image.Image:
    c = Canvas(90, 70)
    foot = 64
    rng = random.Random(seed)
    # bloco aparado, meio passado do ponto: topo ondulado
    c.rect(8, foot - 30, 80, foot, HEDGE[0])
    for k in range(9):
        x = 10 + k * 8 + rng.randint(-1, 1)
        leaf_mass(c, x, foot - 28 + rng.randint(-2, 2), 7, 6, HEDGE, seed * 31 + k)
    for k in range(8):
        x = 12 + k * 9
        leaf_mass(c, x, foot - 14, 7, 9, HEDGE[:3] + [HEDGE[2]], seed * 17 + k)
    c.rect(8, foot - 3, 80, foot, HEDGE[0])
    c.outline()
    return c.im


def graves(seed=1) -> Image.Image:
    c = Canvas(100, 70)
    foot = 64
    rng = random.Random(seed)
    spots = [(18, foot - 8), (44, foot - 12), (72, foot - 7), (30, foot), (60, foot - 1)]
    kinds = ["round", "cross", "slab", "round", "obelisk"]
    rng.shuffle(kinds)
    for (x, y), kind in sorted(zip(spots, kinds), key=lambda t: t[0][1]):
        tilt = rng.choice((-1, 0, 0, 1))
        if kind == "round":
            c.rect(x - 7, y - 20, x + 6, y, STONE[1])
            c.ellipse(x - 7, y - 27, x + 6, y - 14, STONE[1])
            c.rect(x - 7, y - 22, x - 5, y, STONE[2])
            c.ellipse(x - 7, y - 27, x - 2, y - 20, STONE[2])
            c.rect(x - 3, y - 17, x + 2, y - 16, STONE[0])
            c.rect(x - 4, y - 13, x + 3, y - 12, STONE[0])
            c.rect(x - 8, y - 2, x + 7, y, STONE[0])
        elif kind == "cross":
            c.rect(x - 2 + tilt, y - 32, x + 2 + tilt, y, STONE[1])
            c.rect(x - 8 + tilt, y - 25, x + 8 + tilt, y - 21, STONE[1])
            c.rect(x - 2 + tilt, y - 32, x - 1 + tilt, y, STONE[2])
            c.rect(x - 8 + tilt, y - 25, x + 8 + tilt, y - 25, STONE[3])
            c.rect(x - 5, y - 3, x + 5, y, STONE[0])
        elif kind == "obelisk":
            c.poly([(x - 5, y - 6), (x + 5, y - 6), (x + 3, y - 34), (x - 3, y - 34)], STONE[1])
            c.poly([(x - 3, y - 34), (x + 3, y - 34), (x, y - 39)], STONE[2])
            c.poly([(x - 5, y - 6), (x - 2, y - 6), (x - 1, y - 34), (x - 3, y - 34)], STONE[2])
            c.rect(x - 8, y - 6, x + 7, y, STONE[0])
            c.rect(x - 8, y - 6, x + 7, y - 6, STONE[2])
        else:
            c.poly([(x - 11, y), (x + 10, y), (x + 8, y - 7), (x - 9, y - 7)], STONE[0])
            c.rect(x - 8, y - 11, x + 7, y - 7, STONE[1])
            c.rect(x - 8, y - 11, x + 7, y - 11, STONE[2])
        for _ in range(5):
            mx = x + rng.randint(-7, 6)
            my = y - rng.randint(0, 5)
            c.rect(mx, my, mx + 1, my, MOSS[rng.randint(0, 2)])
    c.outline()
    return c.im


def bandstand() -> Image.Image:
    c = Canvas(130, 150)
    x = 65
    foot = 146
    # base octogonal de pedra com degraus
    c.ellipse(x - 52, foot - 22, x + 52, foot, STONE[0])
    c.ellipse(x - 52, foot - 26, x + 52, foot - 6, STONE[1])
    c.ellipse(x - 46, foot - 28, x + 46, foot - 12, STONE[2])
    c.rect(x - 10, foot - 14, x + 10, foot - 2, STONE[1])  # escadinha
    for k in range(3):
        c.rect(x - 10, foot - 12 + k * 4, x + 10, foot - 12 + k * 4, STONE[3])
    # colunas finas de ferro e grade baixa
    cols = [-40, -22, 0, 22, 40]
    for k, dx in enumerate(cols):
        back = k in (1, 3)
        top = foot - 82
        bottom = foot - 22 if not back else foot - 25
        c.rect(x + dx - 1, top, x + dx + 1, bottom, CREAM[0] if back else CREAM[1])
        if not back:
            c.rect(x + dx - 1, top, x + dx - 1, bottom, CREAM[2])
            c.rect(x + dx - 3, bottom - 2, x + dx + 3, bottom, CREAM[1])
    c.rect(x - 44, foot - 38, x + 44, foot - 37, IRON[2])
    for bx in range(x - 42, x + 43, 4):
        c.rect(bx, foot - 37, bx, foot - 25, IRON[1])
    # telhado em sino, com beiral rendado
    c.poly([(x - 56, foot - 80), (x + 56, foot - 80), (x + 30, foot - 104), (x, foot - 128), (x - 30, foot - 104)], PLUM[1])
    c.poly([(x - 56, foot - 80), (x - 30, foot - 104), (x, foot - 128), (x - 6, foot - 104), (x - 20, foot - 80)], PLUM[2])
    c.poly([(x - 12, foot - 116), (x, foot - 128), (x - 4, foot - 112)], PLUM[3])
    for k in range(5):
        yy = foot - 86 - k * 8
        half = 52 - k * 9
        c.rect(x - half, yy, x + half, yy, PLUM[0])
    for bx in range(x - 54, x + 55, 6):
        c.ellipse(bx - 3, foot - 82, bx + 3, foot - 75, PLUM[0])
        c.px(bx, foot - 79, CREAM[1])
    c.rect(x - 56, foot - 81, x + 56, foot - 80, CREAM[1])
    # ponteira de latão (apagada)
    c.rect(x - 1, foot - 140, x + 1, foot - 128, (120, 100, 60))
    c.ellipse(x - 3, foot - 136, x + 3, foot - 130, (150, 124, 70))
    c.outline()
    return c.im


def gas_tank(big=True) -> Image.Image:
    """Gasômetro: cilindro de chapas rebitadas dentro de uma armação de colunas de ferro."""
    w, hgt = (124, 104) if big else (86, 72)
    cap = w // 4  # altura da elipse do topo (vista de cima, em 3/4)
    c = Canvas(w + 36, hgt + cap + 44)
    x0 = 18
    foot = hgt + cap + 38
    top = foot - hgt
    rx = w / 2
    a = np.array(c.im)
    rng = random.Random(3 if big else 5)
    for xx in range(w):
        t = (xx + 0.5 - rx) / rx
        # luz vindo da esquerda: claro perto da borda esquerda, escuro na direita
        light = 0.55 - 0.65 * t - 0.15 * t * t
        tone = 0 if light < 0.05 else (1 if light < 0.4 else (2 if light < 0.8 else 3))
        sag = int(round(cap / 2 * math.sqrt(max(0.0, 1 - t * t))))  # base curva do cilindro
        y_top = top
        y_bot = foot - cap // 2 + sag
        a[y_top:y_bot, x0 + xx, :3] = STEEL[tone]
        a[y_top:y_bot, x0 + xx, 3] = 255
        for k, yy in enumerate(range(top + 10, y_bot - 2, 14)):
            ring = yy + sag
            if ring < y_bot - 1:
                a[ring, x0 + xx, :3] = STEEL[max(0, tone - 1)]
                if xx % 6 == 3 and tone > 0:
                    a[ring - 2, x0 + xx, :3] = STEEL[min(3, tone + 1)]  # rebites
    for _ in range(int(w / 6)):
        sx = rng.randint(4, w - 5)
        sy = rng.randint(top + 6, top + hgt // 2)
        ln = rng.randint(6, 26)
        tone = rng.randint(0, 2)
        a[sy:sy + ln, x0 + sx, :3] = RUST[tone]
        if rng.random() < 0.5:
            a[sy:sy + ln // 2, x0 + sx + 1, :3] = RUST[max(0, tone - 1)]
    c.im = Image.fromarray(a)
    c.d = ImageDraw.Draw(c.im)
    # topo: elipse escura com a cúpula rasa e a borda clara
    c.ellipse(x0, top - cap // 2, x0 + w - 1, top + cap // 2, STEEL[0])
    c.ellipse(x0 + 3, top - cap // 2 + 2, x0 + w - 4, top + cap // 2 - 2, STEEL[1])
    c.ellipse(x0 + w * 0.15, top - cap // 2 + 3, x0 + w * 0.6, top + 1, STEEL[2])
    c.rect(x0 + w // 2 - 3, top - cap // 2 - 4, x0 + w // 2 + 2, top - cap // 2 + 2, STEEL[1])
    # armação: colunas na frente do tanque e vigas em treliça no alto
    frame_top = top - cap // 2 - 16
    columns = [x0 - 8, x0 + int(w * 0.22), x0 + int(w * 0.5) - 2, x0 + int(w * 0.78) - 3, x0 + w + 4]
    for fx in columns:
        c.rect(fx, frame_top, fx + 3, foot + 2, IRON[1])
        c.rect(fx, frame_top, fx, foot + 2, IRON[2])
        c.rect(fx - 1, foot, fx + 4, foot + 2, IRON[0])
    for k in (0, 1):
        yy = frame_top + k * 34
        c.rect(columns[0], yy, columns[-1] + 3, yy + 2, IRON[1])
        c.rect(columns[0], yy, columns[-1] + 3, yy, IRON[2])
    for a_, b_ in zip(columns, columns[1:]):
        c.line([(a_ + 3, frame_top + 3), (b_, frame_top + 33)], IRON[0])
        c.line([(a_ + 3, frame_top + 33), (b_, frame_top + 3)], IRON[0])
    # escada de serviço e uma válvula com cano
    lx = columns[-1] - 9
    c.rect(lx, frame_top + 2, lx, foot, IRON[1])
    c.rect(lx + 5, frame_top + 2, lx + 5, foot, IRON[1])
    for yy in range(frame_top + 6, foot, 5):
        c.rect(lx, yy, lx + 5, yy, IRON[2])
    c.rect(x0 - 14, foot - 14, x0 + 6, foot - 9, RUST[1])
    c.rect(x0 - 14, foot - 14, x0 + 6, foot - 14, RUST[2])
    c.ellipse(x0 - 18, foot - 20, x0 - 8, foot - 10, IRON[1])
    c.rect(x0 - 14, foot - 22, x0 - 12, foot - 19, IRON[2])
    c.outline()
    return c.im


def tram(derailed=True) -> Image.Image:
    c = Canvas(150, 100)
    base = 88
    body = Canvas(126, 56)
    b = body
    # caixa do bonde: saia vinho, faixa creme, janelas escuras
    b.rect(4, 22, 121, 46, WINE[1])
    b.rect(4, 22, 121, 24, WINE[2])
    b.rect(4, 8, 121, 22, CREAM[1])
    b.rect(4, 8, 121, 9, CREAM[2])
    for k in range(7):
        wx = 10 + k * 15
        b.rect(wx, 11, wx + 10, 20, GLASS[0])
        b.rect(wx + 1, 12, wx + 3, 15, GLASS[2])
        if k in (2, 5):
            b.line([(wx, 20), (wx + 10, 11)], GLASS[2])  # vidro trincado
    b.rect(2, 4, 123, 8, PLUM[1])
    b.rect(2, 4, 123, 4, PLUM[2])
    b.rect(6, 1, 119, 4, PLUM[0])
    b.rect(52, 28, 72, 31, (150, 124, 70))  # placa do número, sem número
    for wx in (20, 34, 92, 106):
        b.ellipse(wx - 7, 40, wx + 7, 54, IRON[0])
        b.ellipse(wx - 4, 43, wx + 4, 51, IRON[2])
        b.px(wx, 47, IRON[3])
    b.rect(4, 44, 121, 46, IRON[0])
    # alavanca do trole quebrada
    b.line([(60, 1), (78, -10)], IRON[1], 2)
    tilt = -7 if derailed else 0
    rot = body.im.rotate(tilt, expand=True, resample=Image.Resampling.NEAREST)
    c.paste(rot, 12, base - rot.height + 4)
    if derailed:
        # trilho arrancado e pedras soltas
        c.rect(6, base, 144, base + 1, IRON[1])
        for k in range(10, 140, 11):
            c.rect(k, base - 1, k + 6, base + 2, BARK[1])
        c.ellipse(130, base - 6, 142, base + 2, STONE[1])
        c.ellipse(4, base - 4, 14, base + 2, STONE[2])
    c.outline()
    return c.im


def stepping_stones() -> Image.Image:
    c = Canvas(90, 40)
    foot = 34
    for (x, y, rx) in ((22, foot - 4, 11), (50, foot - 10, 9), (70, foot - 2, 10)):
        c.ellipse(x - rx - 3, y - 2, x + rx + 3, y + 6, WATER[2])  # espuma em volta
        c.ellipse(x - rx, y - 5, x + rx, y + 4, STONE[1])
        c.ellipse(x - rx + 2, y - 5, x + rx - 3, y, STONE[2])
        c.rect(x - 3, y - 4, x, y - 4, STONE[3])
        c.rect(x + 2, y + 1, x + 4, y + 1, MOSS[1])
    c.outline((22, 30, 40))
    return c.im


def dead_tree(seed=1, leaves=True, size=1.0) -> Image.Image:
    c = Canvas(140, 170)
    rng = random.Random(seed)
    foot = 164
    x = 70
    # tronco grosso e torto, galhos em forquilha
    def branch(x0, y0, ang, length, width, depth):
        if depth == 0 or length < 6:
            if leaves and rng.random() < 0.85:
                leaf_mass(c, x0, y0, rng.randint(6, 10) * size, rng.randint(4, 7) * size, LEAF + [LEAF[2]], rng.randint(0, 99999), holes=0.6)
            return
        x1 = x0 + math.cos(ang) * length
        y1 = y0 + math.sin(ang) * length
        steps = max(2, int(length / 2))
        for i in range(steps + 1):
            t = i / steps
            px = x0 + (x1 - x0) * t + math.sin(t * 3 + seed) * width * 0.3
            py = y0 + (y1 - y0) * t
            wv = max(2, width * (1 - t * 0.4))
            c.ellipse(px - wv / 2, py - 1, px + wv / 2, py + 1, BARK[1])
            c.ellipse(px - wv / 2, py - 1, px - wv / 2 + max(1, wv * 0.3), py + 1, BARK[2])
        n = 2 if depth > 1 else rng.choice((1, 2))
        for k in range(n):
            spread = rng.uniform(0.35, 0.75) * (1 if k == 0 else -1)
            branch(x1, y1, ang + spread + rng.uniform(-0.15, 0.15), length * rng.uniform(0.6, 0.78), width * 0.62, depth - 1)
    branch(x, foot - 2, -math.pi / 2 + rng.uniform(-0.12, 0.12), 44 * size, 15 * size, 4)
    if leaves:
        for _ in range(3):
            leaf_mass(c, x + rng.uniform(-30, 30) * size, foot - rng.uniform(80, 110) * size, 12 * size, 8 * size, LEAF + [LEAF[2]], rng.randint(0, 99999), holes=0.8)
    # raízes
    for dx in (-9, -4, 5, 10):
        c.poly([(x + dx * 0.4, foot - 8), (x + dx * 1.4, foot), (x + dx * 0.4 + (2 if dx > 0 else -2), foot)], BARK[0])
    c.ellipse(x - 12, foot - 3, x + 12, foot + 1, BARK[0])
    c.outline()
    return c.im


# --- Peças reaproveitadas ------------------------------------------------------------------

def town(name):
    return from_game(SRC / "town" / "ilustrado" / f"{name}.png")


def scene(name):
    return from_game(SRC / "scenes" / f"{name}.png")


def biome(b, name):
    return from_game(SRC / "biomes" / b / f"{name}.png")


def crop_art(im):
    return im.crop(im.getbbox())


def cold_stone(im, val=0.85):
    """Pedra fria e musgo cinzento."""
    return recolor(im, sat=0.45, val=val, greens=(0.4, 0.75, 0.33), tint=(70, 76, 100))


def build_props():
    houses = {
        "casa_suburbio_a": ("casa_a", 11),
        "casa_suburbio_b": ("casa_b", 12),
        "casa_suburbio_c": ("casa_c", 13),
    }
    for name, (src, seed) in houses.items():
        art = recolor(town(src), sat=0.55, val=0.78, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96))
        save(finish(boards(crop_art(art), seed)), name)
    # A casa de quem resiste: a única com luz nas janelas (vila a resgatar).
    lit = recolor(town("casa_a"), sat=0.7, val=0.82, windows="keep", greens=(0.5, 0.75, None), tint=(60, 64, 96))
    save(finish(crop_art(lit)), "casa")
    save(finish(crop_art(recolor(town("taverna"), sat=0.55, val=0.78, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "pensao")
    save(finish(boards(crop_art(recolor(town("mansao"), sat=0.5, val=0.76, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96))), 7, 5)), "mansao_aurelio")
    save(finish(crop_art(recolor(town("capela"), sat=0.45, val=0.78, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "capela_canal")
    save(finish(crop_art(recolor(town("capela"), sat=0.15, val=0.55, greens=(0.3, 0.6, 0.33), tint=(60, 64, 96)))), "mausoleu")
    save(finish(crop_art(recolor(town("abrigo"), sat=0.5, val=0.75, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "barracao")
    save(finish(crop_art(recolor(town("abrigo"), sat=0.55, val=0.78, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "alojamento")
    save(finish(crop_art(recolor(town("forja"), sat=0.5, val=0.72, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "galpao")
    save(finish(crop_art(recolor(town("torre_madeira"), sat=0.5, val=0.78, tint=(60, 64, 96)))), "torre_vigia")
    save(finish(crop_art(recolor(town("torre_madeira"), sat=0.5, val=0.72, tint=(60, 64, 96)))), "guarita")
    fonte = dry(town("fonte"))
    fonte = recolor(fonte, sat=0.3, val=0.75, greens=(0.3, 0.6, 0.12), tint=(60, 64, 96))
    save(finish(crop_art(fonte)), "fonte_seca")
    tents = [("barraca_a", from_game(SRC / "town" / "barraca_b.png"), 0.0, 1.25),
             ("barraca_b", from_game(SRC / "town" / "barraca_c.png"), 0.0, 1.3),
             ("barraca_c", town("tenda"), 0.55, 0.76)]
    for name, im, shift, val in tents:
        save(finish(crop_art(recolor(im, sat=0.6, val=val, hue_shift=shift, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), name)
    # Barcos esquecidos no canal e barris da usina.
    boat = from_game(SRC / "town" / "barco_b.png")
    save(finish(crop_art(recolor(boat, sat=0.45, val=0.72, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "barco")
    save(finish(crop_art(recolor(from_game(SRC / "town" / "barris_b.png"), sat=0.5, val=0.75, tint=(60, 64, 96)))), "barris")
    # Fonte de luz: a única com água, e a água ainda brilha.
    save(finish(crop_art(recolor(town("fonte"), sat=0.8, val=0.9, windows="keep", greens=(0.35, 0.7, 0.12)))), "fonte_luz")
    save(finish(crop_art(recolor(scene("camp_carroca"), sat=0.5, val=0.75, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "carroca")
    save(finish(crop_art(recolor(town("caixas"), sat=0.5, val=0.75, windows="dark", tint=(60, 64, 96)))), "caixas")
    save(finish(crop_art(recolor(scene("shrine_bench"), sat=0.5, val=0.75, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "banco")
    gate = recolor(scene("garden_gate"), sat=0.4, val=0.8, greens=(0.35, 0.7, 0.33), tint=(60, 64, 96))
    save(finish(crop_art(gate)), "portao_jardim")
    save(finish(crop_art(recolor(scene("garden_gate"), sat=0.15, val=0.68, greens=(0.3, 0.6, 0.33), tint=(80, 84, 110)))), "portao_cemiterio")
    save(finish(crop_art(cold_stone(scene("garden_wall")))), "muro")
    save(finish(crop_art(cold_stone(biome("floresta", "ruina_b"), 0.9))), "estatua")
    save(finish(crop_art(cold_stone(biome("floresta", "ruina_a"), 0.72))), "cripta")
    save(finish(crop_art(cold_stone(biome("floresta", "torre"), 0.8))), "portao_cidade")
    save(finish(crop_art(cold_stone(biome("floresta", "enfeite_a"), 0.85))), "coluna")
    save(finish(crop_art(cold_stone(biome("floresta", "pedras_b"), 0.75))), "ponte_caida")
    # Barricada: caixotes e a carroça virada, fechando a cabeceira da ponte.
    bar = Canvas(150, 120)
    crates = crop_art(recolor(town("caixas"), sat=0.45, val=0.7, tint=(60, 64, 96)))
    cart = crop_art(recolor(scene("camp_carroca"), sat=0.45, val=0.7, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))
    bar.paste(cart.transpose(Image.Transpose.FLIP_LEFT_RIGHT), 4, 116 - cart.height)
    bar.paste(crates, 150 - crates.width - 4, 118 - crates.height)
    save(finish(bar.im), "barricada")
    save(finish(gas_lamp(False)), "lampiao")
    save(finish(gas_lamp(True)), "lampiao_aceso")
    save(finish(fence()), "grade")
    save(finish(hedge(1)), "sebe")
    save(finish(hedge(2)), "sebe_b")
    save(finish(graves(1)), "lapides")
    save(finish(graves(2)), "lapides_b")
    save(finish(bandstand()), "coreto")
    save(finish(gas_tank(True)), "gasometro")
    save(finish(gas_tank(False)), "gasometro_pequeno")
    save(finish(tram(True)), "bonde")
    save(finish(stepping_stones()), "pedras_vau")
    # A estufa: a de vidro do pântano, sem cor e quebrada.
    save(finish(crop_art(recolor(biome("floresta", "casa"), sat=0.45, val=0.75, greens=(0.35, 0.7, 0.12), tint=(60, 64, 96)))), "estufa")


def build_biome_pieces():
    """O conjunto padrão de um bioma (66 peças), a partir da floresta, para a noite dos subúrbios."""
    flo = SRC / "biomes" / "floresta"
    for f in flo.glob("*.png"):
        if not (OUT / f.name).exists():
            shutil.copy(f, OUT / f.name)
    # Árvores mortas: plátanos secos, folhas cor de ferrugem.
    save(finish(dead_tree(3, True)), "floresta_fundo_a")
    save(finish(dead_tree(8, True)), "floresta_fundo_b")
    save(finish(dead_tree(5, False, 0.7)), "floresta_frente_a")
    save(finish(dead_tree(14, False, 0.65)), "floresta_frente_b")
    for name in ("pedras_a", "pedras_b", "colinas_a", "colinas_b", "colinas_natural_a", "colinas_natural_b",
                 "montanha_a", "montanha_b", "montanha_natural", "ruina_a", "ruina_b", "enfeite_a", "enfeite_b",
                 "enfeite_c", "torre"):
        save(finish(crop_art(cold_stone(biome("floresta", name), 0.8)), foot_y=None), name)
    # Chão: grama escura pisada; sombra mais funda; trilha de saibro; rua de paralelepípedo; canal.
    ground_tones = {
        "solo": dict(sat=0.55, val=0.72, tint=(54, 60, 84)),
        "sombra_solo": dict(sat=0.5, val=0.55, tint=(40, 44, 70)),
        "trilha_solo": dict(sat=0.45, val=0.78, tint=(70, 66, 80)),
        "agua_solo": dict(sat=0.75, val=1.05, tint=(40, 70, 96)),
    }
    for name, kw in ground_tones.items():
        im = Image.open(flo / f"{name}.png").convert("RGBA")
        recolor(im, windows="keep", greens=(kw["sat"], kw["val"], None), **{k: v for k, v in kw.items()}).convert("RGB").save(OUT / f"{name}.png", optimize=True)
    cob = Image.open(SRC / "town" / "calcada_solo.png").convert("RGBA")
    recolor(cob, sat=0.5, val=0.8, windows="keep", tint=(60, 64, 96)).convert("RGB").save(OUT / "estrada_solo.png", optimize=True)
    # Parede do penhasco vira muro de arrimo de pedra.
    wall = Image.open(flo / "parede.png").convert("RGBA")
    recolor(wall, sat=0.35, val=0.85, windows="keep", tint=(70, 70, 96)).save(OUT / "parede.png", optimize=True)
    for name in ("campo_a", "campo_b", "sombra", "trilha", "estrada", "agua_a", "agua_b"):
        im = Image.open(flo / f"{name}.png").convert("RGBA")
        recolor(im, sat=0.55, val=0.74, windows="keep", tint=(54, 60, 84)).save(OUT / f"{name}.png", optimize=True)
    for f in flo.glob("*.png"):
        stem = f.stem
        if stem.startswith(("borda_", "margem_", "trilha_", "estrada_")) or stem in ("estrada_borda",):
            im = Image.open(f).convert("RGBA")
            recolor(im, sat=0.55, val=0.76, windows="keep", tint=(54, 60, 84)).save(OUT / f.name, optimize=True)
    save(finish(crop_art(recolor(biome("floresta", "farol_apagado"), sat=0.5, val=0.8, windows="keep", greens=(0.35, 0.7, 0.33), tint=(60, 64, 96)))), "farol_apagado")
    save(finish(crop_art(recolor(biome("floresta", "farol_aceso"), sat=0.85, val=0.95, windows="keep", greens=(0.35, 0.7, 0.33)))), "farol_aceso")


def contact_sheet(path):
    names = sorted(p.stem for p in OUT.glob("*.png") if not p.stem.startswith(("borda_", "margem_", "trilha_", "estrada_", "campo", "agua", "sombra", "solo", "trilha", "estrada", "parede")))
    thumbs = []
    for n in names:
        im = Image.open(OUT / f"{n}.png").convert("RGBA")
        im = im.crop(im.getbbox())
        im.thumbnail((150, 170), Image.Resampling.NEAREST)
        thumbs.append((n, im))
    cols = 9
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * 160, rows * 200), (58, 62, 74, 255))
    d = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(thumbs):
        x = (i % cols) * 160 + (160 - im.width) // 2
        y = (i // cols) * 200 + 175 - im.height
        sheet.alpha_composite(im, (x, y))
        d.text(((i % cols) * 160 + 4, (i // cols) * 200 + 184), n, fill=(230, 230, 230))
    sheet.save(path)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    build_props()
    build_biome_pieces()
    print(f"Subúrbios: {len(list(OUT.glob('*.png')))} peças em {OUT}")
    if len(sys.argv) > 1:
        contact_sheet(sys.argv[1])


if __name__ == "__main__":
    main()
