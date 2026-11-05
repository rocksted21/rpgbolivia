"""Modelos 3D simples das construções da cidade, desenhados em pixel art de 16 ângulos.

A câmera do jogo gira livre, e um desenho só mostraria sempre o mesmo lado. Aqui cada
prédio é montado com caixas, telhados e cilindros, e renderizado com a mesma projeção
da câmera. O jogo troca o quadro conforme o giro (ver BattleView._update_model_frames).

Rodar na raiz do projeto: python tools/build_town_models.py (precisa de pillow e numpy).
Unidades em pixels de arte: 1 casa do mapa tem cerca de 93 de largura.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path("assets/town/modelos")
VIEWS = 16
COLUMNS = 4
TILT = 0.6  # igual a GROUND_TILT em battle_camera.gd
SIZE = 1.3  # tamanho das construções em relação às medidas abaixo; a textura mantém o pixel
LIGHT = np.array([-0.45, 0.55, 0.7])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
EMISSIVE = 200  # alfa que marca pixel que brilha: a sombra não o escurece
INK = np.array([18, 16, 24], float)

rng = np.random.default_rng(5)


# --- Texturas ------------------------------------------------------------------

def blank(w, h, color):
    img = np.zeros((max(int(h), 1), max(int(w), 1), 4), float)
    img[..., :3] = color
    img[..., 3] = 255
    return img


def speckle(img, amount=8.0):
    img[..., :3] += rng.normal(0, amount, img.shape[:2])[..., None]
    return img


def plaster(w, h, color=(150, 138, 118)):
    img = speckle(blank(w, h, color), 5)
    return img


def stone(w, h, color=(104, 102, 110), course=7, brick=13):
    img = blank(w, h, (46, 44, 52))
    for row, y in enumerate(range(0, int(h), course)):
        x = -(row % 2) * brick // 2
        while x < w:
            tone = np.array(color) + rng.normal(0, 11)
            x0, x1 = max(x, 0), min(x + brick - 1, int(w))
            if x1 > x0:
                img[y: y + course - 1, x0: x1, :3] = tone
            x += brick
    return speckle(img, 3)


def planks(w, h, color=(92, 66, 46), width=6, vertical=True):
    img = blank(w, h, color)
    size = int(w if vertical else h)
    for i in range(0, size, width):
        tone = np.array(color) + rng.normal(0, 8)
        if vertical:
            img[:, i: i + width - 1, :3] = tone
            img[:, i + width - 1: i + width, :3] = np.array(color) * 0.55
        else:
            img[i: i + width - 1, :, :3] = tone
            img[i + width - 1: i + width, :, :3] = np.array(color) * 0.55
    return speckle(img, 3)


def tiles(w, h, color=(58, 60, 74), row=5, width=7):
    img = blank(w, h, np.array(color) * 0.6)
    for n, y in enumerate(range(0, int(h), row)):
        x = -(n % 2) * width // 2
        while x < w:
            tone = np.array(color) + rng.normal(0, 9)
            x0, x1 = max(x, 0), min(x + width - 1, int(w))
            if x1 > x0:
                img[y: y + row - 1, x0: x1, :3] = tone
            x += width
    return img


def cloth(w, h, color):
    img = blank(w, h, color)
    for i in range(0, int(w), 14):
        img[:, i: i + 7, :3] = np.array(color) * 0.82
    return speckle(img, 2)


def rect(img, x, y, w, h, color, alpha=255):
    img[int(y): int(y + h), int(x): int(x + w), :3] = color
    img[int(y): int(y + h), int(x): int(x + w), 3] = alpha


def window(img, x, y, w=9, h=13, lit=True, arch=False):
    rect(img, x - 1, y - 1, w + 2, h + 2, (34, 28, 28))
    glass = (252, 186, 92) if lit else (40, 52, 66)
    rect(img, x, y, w, h, glass, EMISSIVE if lit else 255)
    if lit:
        rect(img, x, y + h // 2, w, h - h // 2, (236, 142, 58), EMISSIVE)
    rect(img, x + w // 2, y, 1, h, (46, 34, 30))
    rect(img, x, y + h // 2, w, 1, (46, 34, 30))
    rect(img, x - 1, y + h + 1, w + 2, 1, (168, 158, 146))
    if arch:
        rect(img, x + 1, y - 3, w - 2, 2, (34, 28, 28))


def door(img, x, h_total, w=13, h=22, color=(70, 44, 32)):
    y = h_total - h
    rect(img, x - 1, y - 1, w + 2, h + 1, (30, 24, 24))
    rect(img, x, y, w, h, color)
    rect(img, x + w // 2, y, 1, h, np.array(color) * 0.6)
    rect(img, x + w - 3, y + h // 2, 1, 2, (214, 176, 90))


def timber(img, color=(52, 36, 28), posts=4, cross=True):
    h, w = img.shape[:2]
    for i in range(posts + 1):
        rect(img, min(i * (w - 3) / posts, w - 3), 0, 3, h, color)
    rect(img, 0, 0, w, 3, color)
    rect(img, 0, h - 3, w, 3, color)
    rect(img, 0, h // 2, w, 2, color)
    if cross:
        for i in range(posts):
            x0 = i * (w - 3) / posts
            span = (w - 3) / posts
            for t in np.linspace(0, 1, 40):
                px = int(x0 + t * span)
                py = int(h // 2 + t * (h - h // 2))
                img[min(py, h - 1): min(py + 2, h), px: px + 2, :3] = color


def triangle_mask(img):
    """Recorta a imagem em triângulo: o oitão da casa."""
    h, w = img.shape[:2]
    for y in range(h):
        half = (y + 1) / h * w / 2
        img[y, : max(int(w / 2 - half), 0), 3] = 0
        img[y, int(w / 2 + half):, 3] = 0
    return img


# --- Geometria -----------------------------------------------------------------

class Model:
    def __init__(self):
        self.quads = []

    def quad(self, a, b, c, d, tex):
        """a-b é a borda de cima da textura; d-c, a de baixo."""
        self.quads.append(([np.array(p, float) for p in (a, b, c, d)], np.clip(tex, 0, 255)))

    def box(self, x0, y0, x1, y1, z0, z1, side, top=None):
        """`side(nome, largura, altura)` devolve a textura de cada parede: frente, fundo, esq, dir."""
        h = z1 - z0
        self.quad((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), side("frente", x1 - x0, h))
        self.quad((x1, y0, z1), (x0, y0, z1), (x0, y0, z0), (x1, y0, z0), side("fundo", x1 - x0, h))
        self.quad((x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (x0, y0, z0), side("esq", y1 - y0, h))
        self.quad((x1, y1, z1), (x1, y0, z1), (x1, y0, z0), (x1, y1, z0), side("dir", y1 - y0, h))
        if top is not None:
            self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), top(x1 - x0, y1 - y0))

    def gable(self, x0, y0, x1, y1, z, rise, roof, gable_tex, along_x=True, over=5):
        """Telhado de duas águas. along_x: a cumeeira corre no eixo x."""
        if along_x:
            mid = (y0 + y1) / 2
            slope = float(np.hypot(mid - y0 + over, rise))
            r = roof(x1 - x0 + over * 2, slope)
            self.quad((x0 - over, mid, z + rise), (x1 + over, mid, z + rise), (x1 + over, y1 + over, z - 3), (x0 - over, y1 + over, z - 3), r)
            r = roof(x1 - x0 + over * 2, slope)
            self.quad((x1 + over, mid, z + rise), (x0 - over, mid, z + rise), (x0 - over, y0 - over, z - 3), (x1 + over, y0 - over, z - 3), r)
            g = triangle_mask(gable_tex(y1 - y0, rise))
            self.quad((x0, y0, z + rise), (x0, y1, z + rise), (x0, y1, z), (x0, y0, z), g)
            g = triangle_mask(gable_tex(y1 - y0, rise))
            self.quad((x1, y1, z + rise), (x1, y0, z + rise), (x1, y0, z), (x1, y1, z), g)
        else:
            mid = (x0 + x1) / 2
            slope = float(np.hypot(mid - x0 + over, rise))
            r = roof(y1 - y0 + over * 2, slope)
            self.quad((mid, y1 + over, z + rise), (mid, y0 - over, z + rise), (x1 + over, y0 - over, z - 3), (x1 + over, y1 + over, z - 3), r)
            r = roof(y1 - y0 + over * 2, slope)
            self.quad((mid, y0 - over, z + rise), (mid, y1 + over, z + rise), (x0 - over, y1 + over, z - 3), (x0 - over, y0 - over, z - 3), r)
            g = triangle_mask(gable_tex(x1 - x0, rise))
            self.quad((x0, y1, z + rise), (x1, y1, z + rise), (x1, y1, z), (x0, y1, z), g)
            g = triangle_mask(gable_tex(x1 - x0, rise))
            self.quad((x1, y0, z + rise), (x0, y0, z + rise), (x0, y0, z), (x1, y0, z), g)

    def pyramid(self, x0, y0, x1, y1, z, rise, roof, over=4):
        apex = ((x0 + x1) / 2, (y0 + y1) / 2, z + rise)
        corners = [(x0 - over, y1 + over), (x1 + over, y1 + over), (x1 + over, y0 - over), (x0 - over, y0 - over)]
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            width = float(np.hypot(a[0] - b[0], a[1] - b[1]))
            self.quad(apex, apex, (b[0], b[1], z - 2), (a[0], a[1], z - 2), roof(width, rise + 12))

    def ring(self, cx, cy, r0, r1, z0, z1, tex, sides=8):
        """Tronco de cone: r0 embaixo, r1 em cima."""
        for i in range(sides):
            t0, t1 = 2 * np.pi * i / sides, 2 * np.pi * (i + 1) / sides
            a = (cx + r1 * np.cos(t0), cy + r1 * np.sin(t0), z1)
            b = (cx + r1 * np.cos(t1), cy + r1 * np.sin(t1), z1)
            c = (cx + r0 * np.cos(t1), cy + r0 * np.sin(t1), z0)
            d = (cx + r0 * np.cos(t0), cy + r0 * np.sin(t0), z0)
            width = 2 * max(r0, r1) * np.sin(np.pi / sides)
            self.quad(a, b, c, d, tex(i, width, z1 - z0))

    def disc(self, cx, cy, r, z, tex, sides=8):
        for i in range(sides):
            t0, t1 = 2 * np.pi * i / sides, 2 * np.pi * (i + 1) / sides
            a = (cx + r * np.cos(t0), cy + r * np.sin(t0), z)
            b = (cx + r * np.cos(t1), cy + r * np.sin(t1), z)
            self.quad((cx, cy, z), (cx, cy, z), b, a, tex)


# --- Renderização --------------------------------------------------------------

def project(points, angle):
    pts = np.array(points) * SIZE
    c, s = np.cos(angle), np.sin(angle)
    x = pts[:, 0] * c - pts[:, 1] * s
    y = pts[:, 0] * s + pts[:, 1] * c
    z = pts[:, 2]
    return x, y * TILT - z, y + TILT * z


def shade_of(points):
    a, b, d = points[0], points[3], points[2]
    if np.allclose(points[0], points[1]):
        n = np.cross(points[3] - points[0], points[2] - points[0])
    else:
        n = np.cross(points[1] - points[0], points[3] - points[0])
    length = np.linalg.norm(n)
    n = n / length if length > 0 else np.array([0, 0, 1.0])
    # A face é sempre iluminada pelo lado de fora: as paredes vêm com a normal para fora.
    return 0.55 + 0.62 * max(0.0, float(np.dot(n, LIGHT))), n


def raster(frame, depth, ident, tri, uv, tex, shade, index):
    sx, sy, d = tri
    h, w = depth.shape
    x0, x1 = int(np.floor(sx.min())), int(np.ceil(sx.max())) + 1
    y0, y1 = int(np.floor(sy.min())), int(np.ceil(sy.max())) + 1
    x0, y0 = max(x0, 0), max(y0, 0)
    x1, y1 = min(x1, w), min(y1, h)
    if x1 <= x0 or y1 <= y0:
        return
    denom = (sy[1] - sy[2]) * (sx[0] - sx[2]) + (sx[2] - sx[1]) * (sy[0] - sy[2])
    if abs(denom) < 1e-6:
        return
    px, py = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
    w0 = ((sy[1] - sy[2]) * (px - sx[2]) + (sx[2] - sx[1]) * (py - sy[2])) / denom
    w1 = ((sy[2] - sy[0]) * (px - sx[2]) + (sx[0] - sx[2]) * (py - sy[2])) / denom
    w2 = 1 - w0 - w1
    inside = (w0 >= -0.01) & (w1 >= -0.01) & (w2 >= -0.01)
    if not inside.any():
        return
    dz = w0 * d[0] + w1 * d[1] + w2 * d[2]
    tu = w0 * uv[0][0] + w1 * uv[1][0] + w2 * uv[2][0]
    tv = w0 * uv[0][1] + w1 * uv[1][1] + w2 * uv[2][1]
    th, tw = tex.shape[:2]
    iu = np.clip((tu * tw).astype(int), 0, tw - 1)
    iv = np.clip((tv * th).astype(int), 0, th - 1)
    sample = tex[iv, iu]
    alpha = sample[..., 3]
    region = depth[y0:y1, x0:x1]
    visible = inside & (dz > region) & (alpha > 0)
    if not visible.any():
        return
    color = sample[..., :3] * np.where(alpha == EMISSIVE, 1.0, shade)[..., None]
    region[visible] = dz[visible]
    frame[y0:y1, x0:x1, :3][visible] = color[visible]
    frame[y0:y1, x0:x1, 3][visible] = 255
    ident[y0:y1, x0:x1][visible] = index


def render(model, angle, size, foot):
    h, w = size[1], size[0]
    frame = np.zeros((h, w, 4), float)
    depth = np.full((h, w), -1e9)
    ident = np.full((h, w), -1)
    for index, (points, tex) in enumerate(model.quads):
        shade, _ = shade_of(points)
        x, y, d = project(points, angle)
        x = x + foot[0]
        y = y + foot[1]
        raster(frame, depth, ident, (x[[0, 1, 2]], y[[0, 1, 2]], d[[0, 1, 2]]), [(0, 0), (1, 0), (1, 1)], tex, shade, index)
        raster(frame, depth, ident, (x[[0, 2, 3]], y[[0, 2, 3]], d[[0, 2, 3]]), [(0, 0), (1, 1), (0, 1)], tex, shade, index)
    return outline(frame, depth, ident)


def outline(frame, depth, ident):
    """Contorno escuro na silhueta e linha fina onde uma peça passa à frente da outra."""
    solid = frame[..., 3] > 0
    grown = solid.copy()
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        grown |= np.roll(solid, (dy, dx), (0, 1))
    edge = grown & ~solid
    out = frame.copy()
    out[edge, :3] = INK
    out[edge, 3] = 255
    for dy, dx in ((0, 1), (1, 0)):
        other = np.roll(depth, (dy, dx), (0, 1))
        step = solid & np.roll(solid, (dy, dx), (0, 1)) & (np.abs(depth - other) > 9)
        out[step, :3] *= 0.55
    # Poucos tons, como pixel art desenhada à mão.
    out[..., :3] = np.round(out[..., :3] / 6.0) * 6.0
    return out


# --- Construções ---------------------------------------------------------------

def walls(painter):
    def side(name, width, height):
        return painter(name, int(round(width)), int(round(height)))
    return side


def casa_a():
    m = Model()
    def paint(name, w, h):
        img = plaster(w, h, (146, 132, 110))
        rect(img, 0, h - 10, w, 10, (84, 82, 88))
        img[h - 10:, :, :3] = stone(w, 10, (92, 90, 98))[..., :3]
        timber(img[: h - 10])
        if name == "frente":
            door(img, w // 2 - 6, h)
            window(img, 8, 14)
            window(img, w - 17, 14)
        elif name == "fundo":
            window(img, w // 2 - 5, 16, lit=False)
        else:
            window(img, w // 2 - 5, 14)
        return img
    m.box(-34, -26, 34, 26, 0, 44, walls(paint))
    m.gable(-34, -26, 34, 26, 44, 30, lambda w, h: tiles(w, h, (88, 56, 48)), lambda w, h: plaster(w, h, (130, 118, 98)))
    m.box(14, -14, 24, -4, 56, 86, walls(lambda n, w, h: stone(w, h, (88, 80, 80))))
    return m


def casa_b():
    m = Model()
    def paint(name, w, h):
        img = stone(w, h, (120, 76, 66), 5, 10)
        rect(img, 0, h // 2, w, 2, (150, 142, 130))
        if name == "frente":
            door(img, w // 2 - 6, h)
            window(img, 6, h // 2 + 9, 9, 13)
            window(img, w - 15, h // 2 + 9, 9, 13)
            for x in (6, w // 2 - 4, w - 15):
                window(img, x, 12, 9, 15, lit=x != w // 2 - 4, arch=True)
        else:
            for x in range(7, w - 12, 18):
                window(img, x, 12, 9, 15, lit=(x + len(name)) % 2 == 1, arch=True)
                window(img, x, h // 2 + 9, 9, 13, lit=False)
        return img
    m.box(-30, -30, 30, 30, 0, 72, walls(paint))
    m.pyramid(-30, -30, 30, 30, 72, 26, lambda w, h: tiles(w, h, (56, 60, 78)))
    m.box(-20, -8, -10, 2, 80, 106, walls(lambda n, w, h: stone(w, h, (92, 66, 60))))
    return m


def casa_c():
    m = Model()
    def paint(name, w, h):
        img = planks(w, h, (98, 72, 50))
        rect(img, 0, h - 7, w, 7, (72, 70, 74))
        if name == "dir":
            door(img, w // 2 - 6, h)
        else:
            window(img, w // 2 - 5, 12, lit=name != "fundo")
        return img
    m.box(-36, -22, 36, 22, 0, 34, walls(paint))
    m.gable(-36, -22, 36, 22, 34, 26, lambda w, h: tiles(w, h, (86, 80, 56), 4, 6), lambda w, h: planks(w, h, (84, 62, 44)))
    # Alpendre de um lado, com dois postes.
    m.box(-34, 22, -30, 26, 0, 24, walls(lambda n, w, h: planks(w, h, (60, 42, 30))))
    m.box(30, 22, 34, 26, 0, 24, walls(lambda n, w, h: planks(w, h, (60, 42, 30))))
    m.quad((-38, 22, 32), (38, 22, 32), (38, 40, 22), (-38, 40, 22), planks(76, 21, (70, 54, 40), 6, False))
    return m


def taverna():
    m = Model()
    def main(name, w, h):
        img = plaster(w, h, (156, 140, 112))
        img[h - 13:, :, :3] = stone(w, 13, (86, 84, 92))[..., :3]
        timber(img[: h - 13], posts=6, cross=True)
        if name == "frente":
            door(img, w // 2 - 8, h, 16, 26, (62, 38, 26))
            for x in (14, 36, w - 45, w - 23):
                window(img, x, 16, 11, 15)
            for x in (14, 36, w - 45, w - 23):
                window(img, x, h - 34, 11, 13)
        else:
            for x in range(14, w - 14, 28):
                window(img, x, 18, 11, 15, lit=(x // 7) % 2 == 0)
                window(img, x, h - 34, 11, 13)
        return img
    m.box(-66, -40, 66, 40, 0, 74, walls(main))
    m.gable(-66, -40, 66, 40, 74, 42, lambda w, h: tiles(w, h, (70, 50, 46)), lambda w, h: plaster(w, h, (136, 122, 98)))
    # Ala de fundos.
    def wing(name, w, h):
        img = plaster(w, h, (146, 130, 106))
        timber(img, posts=3, cross=False)
        window(img, w // 2 - 5, 12)
        return img
    m.box(-20, -74, 34, -40, 0, 54, walls(wing))
    m.gable(-20, -74, 34, -40, 54, 22, lambda w, h: tiles(w, h, (66, 48, 44)), lambda w, h: plaster(w, h, (130, 118, 98)), along_x=False)
    # Alpendre da frente e chaminé.
    for x in (-58, -18, 18, 58):
        m.box(x - 2, 54, x + 2, 58, 0, 32, walls(lambda n, w, h: planks(w, h, (58, 40, 30))))
    m.quad((-64, 40, 42), (64, 40, 42), (64, 62, 30), (-64, 62, 30), planks(128, 25, (84, 58, 40), 7, False))
    m.box(38, -14, 52, 0, 90, 132, walls(lambda n, w, h: stone(w, h, (88, 80, 80))))
    return m


def mansao():
    m = Model()
    def block(name, w, h):
        img = stone(w, h, (136, 132, 128), 9, 22)
        rect(img, 0, h // 2 - 1, w, 3, (168, 164, 156))
        for x in range(10, w - 12, 22):
            window(img, x, 12, 11, 20, lit=(x // 3 + len(name)) % 3 != 0, arch=True)
            if not (name == "frente" and abs(x + 5 - w / 2) < 20):
                window(img, x, h // 2 + 10, 11, 18, lit=(x // 5 + len(name)) % 2 == 0)
        if name == "frente":
            door(img, w // 2 - 9, h, 18, 30, (50, 40, 44))
        return img
    m.box(-52, -42, 52, 42, 0, 90, walls(block))
    m.pyramid(-52, -42, 52, 42, 90, 34, lambda w, h: tiles(w, h, (52, 56, 70), 6, 8), 6)
    for sign in (-1, 1):
        def wing(name, w, h):
            img = stone(w, h, (126, 122, 120), 9, 22)
            for x in range(8, w - 10, 20):
                window(img, x, 14, 10, 18, lit=(x // 4) % 2 == 1)
            return img
        x0, x1 = (52, 86) if sign > 0 else (-86, -52)
        m.box(x0, -30, x1, 30, 0, 62, walls(wing))
        m.pyramid(x0, -30, x1, 30, 62, 20, lambda w, h: tiles(w, h, (50, 54, 66), 6, 8), 4)
    # Pórtico neoclássico: colunas e frontão.
    for x in (-34, -14, 14, 34):
        m.ring(x, 56, 4, 3.4, 4, 66, lambda i, w, h: speckle(blank(w, h, (176, 170, 160) if i % 2 else (156, 150, 142)), 2))
    m.box(-44, 42, 44, 66, 0, 4, walls(lambda n, w, h: stone(w, h, (120, 116, 112), 4, 18)))
    m.box(-44, 42, 44, 66, 66, 72, walls(lambda n, w, h: blank(w, h, (170, 164, 154))), lambda w, h: blank(w, h, (120, 116, 112)))
    m.gable(-44, 42, 44, 66, 72, 20, lambda w, h: tiles(w, h, (52, 56, 70), 6, 8), lambda w, h: speckle(blank(w, h, (166, 160, 150)), 3), along_x=False, over=2)
    return m


def capela():
    m = Model()
    def nave(name, w, h):
        img = stone(w, h, (112, 112, 122), 8, 16)
        if name in ("esq", "dir"):
            for x in range(10, w - 8, 22):
                window(img, x, 14, 9, 28, arch=True)
        elif name == "frente":
            door(img, w // 2 - 9, h, 18, 28, (58, 40, 44))
            window(img, w // 2 - 7, 8, 14, 12, arch=True)
        return img
    m.box(-36, -58, 36, 40, 0, 62, walls(nave))
    m.gable(-36, -58, 36, 40, 62, 42, lambda w, h: tiles(w, h, (58, 60, 76), 6, 8), lambda w, h: stone(w, h, (104, 104, 114), 8, 16), along_x=False)
    def bell(name, w, h):
        img = stone(w, h, (116, 116, 126), 8, 14)
        window(img, w // 2 - 5, 12, 10, 18, lit=False, arch=True)
        return img
    m.box(-52, 8, -22, 40, 0, 112, walls(bell))
    m.pyramid(-52, 8, -22, 40, 112, 46, lambda w, h: tiles(w, h, (52, 54, 70), 5, 7), 3)
    return m


def forja():
    m = Model()
    def paint(name, w, h):
        img = stone(w, h, (92, 88, 90))
        if name == "frente":
            rect(img, w // 2 - 22, h - 34, 44, 34, (26, 20, 20))
            rect(img, w // 2 - 15, h - 18, 30, 18, (250, 120, 40), EMISSIVE)
            rect(img, w // 2 - 9, h - 13, 18, 13, (255, 210, 110), EMISSIVE)
        else:
            window(img, w // 2 - 5, 18)
        return img
    m.box(-60, -44, 60, 44, 0, 54, walls(paint))
    m.gable(-60, -44, 60, 44, 54, 30, lambda w, h: tiles(w, h, (64, 54, 52)), lambda w, h: stone(w, h, (84, 80, 84)))
    m.ring(38, -18, 18, 11, 40, 128, lambda i, w, h: stone(w, h, (82, 76, 76), 6, 11), 6)
    m.box(-52, 44, -10, 74, 26, 30, walls(lambda n, w, h: planks(w, h, (60, 44, 34))), lambda w, h: planks(w, h, (72, 52, 38), 7, False))
    for x, y in ((-50, 72), (-12, 72)):
        m.box(x - 2, y - 2, x + 2, y + 2, 0, 28, walls(lambda n, w, h: planks(w, h, (52, 38, 28))))
    return m


def tenda():
    m = Model()
    purple = lambda w, h: cloth(w, h, (108, 62, 112))
    m.pyramid(-40, -40, 40, 40, 30, 46, purple, 3)
    def wall(name, w, h):
        img = cloth(w, h, (132, 112, 92))
        if name == "frente":
            rect(img, w // 2 - 9, 2, 18, h - 2, (38, 26, 36))
            rect(img, w // 2 - 4, h - 14, 8, 8, (250, 170, 80), EMISSIVE)
        return img
    m.box(-40, -40, 40, 40, 0, 30, walls(wall))
    m.box(-1, -1, 1, 1, 76, 92, walls(lambda n, w, h: blank(w, h, (70, 54, 44))))
    return m


def abrigo():
    m = Model()
    def paint(name, w, h):
        img = planks(w, h, (86, 66, 50))
        if name == "frente":
            door(img, w // 2 - 6, h)
        else:
            window(img, w // 2 - 4, 10, 8, 10)
        return img
    m.box(-30, -24, 30, 24, 0, 30, walls(paint))
    m.gable(-30, -24, 30, 24, 30, 20, lambda w, h: planks(w, h, (70, 58, 46), 6, False), lambda w, h: planks(w, h, (76, 58, 44)))
    return m


def forno():
    m = Model()
    brick = lambda i, w, h: stone(max(w, 2), h, (128, 88, 72), 5, 9)
    m.ring(0, 0, 32, 30, 0, 14, brick, 10)
    m.ring(0, 0, 30, 22, 14, 30, brick, 10)
    m.ring(0, 0, 22, 8, 30, 42, brick, 10)
    mouth = blank(20, 14, (240, 120, 44))
    mouth[..., 3] = EMISSIVE
    m.quad((-10, 31, 18), (10, 31, 18), (10, 32, 2), (-10, 32, 2), mouth)
    m.box(14, -10, 22, -2, 30, 56, walls(lambda n, w, h: stone(w, h, (88, 76, 70), 5, 9)))
    return m


def torre_madeira():
    m = Model()
    post = walls(lambda n, w, h: planks(w, h, (72, 52, 38)))
    for x in (-22, 22):
        for y in (-22, 22):
            m.box(x - 3, y - 3, x + 3, y + 3, 0, 84, post)
    for z in (28, 56):
        for s in (-22, 22):
            m.box(-24, s - 1, 24, s + 1, z, z + 4, post)
            m.box(s - 1, -24, s + 1, 24, z, z + 4, post)
    m.box(-30, -30, 30, 30, 84, 88, post, lambda w, h: planks(w, h, (86, 62, 44), 6, False))
    def rail(name, w, h):
        img = planks(w, h, (78, 56, 40))
        return img
    m.box(-30, -30, 30, 30, 88, 100, walls(rail))
    for x in (-28, 28):
        for y in (-28, 28):
            m.box(x - 2, y - 2, x + 2, y + 2, 100, 124, post)
    m.pyramid(-30, -30, 30, 30, 124, 22, lambda w, h: planks(w, h, (70, 58, 46), 6, False), 5)
    return m


def fonte():
    m = Model()
    rock = lambda i, w, h: stone(max(w, 2), h, (128, 126, 130), 5, 10)
    m.ring(0, 0, 36, 34, 0, 12, rock, 10)
    water = blank(30, 30, (70, 150, 180))
    water[..., 3] = EMISSIVE
    m.disc(0, 0, 32, 10, water, 10)
    m.ring(0, 0, 9, 6, 8, 34, rock, 8)
    m.ring(0, 0, 16, 18, 34, 38, rock, 8)
    m.ring(0, 0, 5, 3, 38, 58, rock, 6)
    glow = blank(6, 6, (255, 196, 110))
    glow[..., 3] = EMISSIVE
    m.ring(0, 0, 3, 3, 58, 66, lambda i, w, h: glow, 6)
    return m


def farol():
    m = Model()
    def body(i, w, h):
        img = stone(max(w, 3), h, (110, 106, 108), 7, 12)
        if i in (2, 6):
            for y in range(24, h - 30, 44):
                window(img, max(w // 2 - 4, 0), y, 8, 14, lit=True)
        if i == 2:
            door(img, max(w // 2 - 7, 0), h, 14, 24, (60, 42, 36))
        return img
    m.ring(0, 0, 46, 40, 0, 26, lambda i, w, h: stone(max(w, 3), h, (92, 90, 96), 8, 16), 8)
    m.ring(0, 0, 36, 22, 26, 196, body, 8)
    m.ring(0, 0, 22, 32, 196, 204, lambda i, w, h: stone(max(w, 3), h, (118, 114, 112), 4, 10), 8)
    m.disc(0, 0, 32, 204, blank(30, 30, (84, 70, 62)), 8)
    def rail(i, w, h):
        img = blank(max(w, 3), h, (40, 34, 36))
        img[3:, :, 3] = 0
        for x in range(0, img.shape[1], 5):
            img[:, x: x + 1, 3] = 255
        return img
    m.ring(0, 0, 32, 32, 204, 216, rail, 8)
    def lamp(i, w, h):
        img = blank(max(w, 3), h, (255, 214, 120))
        img[..., 3] = EMISSIVE
        img[:, : 2, :3] = (46, 36, 34)
        img[:, : 2, 3] = 255
        return img
    m.ring(0, 0, 17, 17, 204, 238, lamp, 8)
    m.ring(0, 0, 21, 3, 238, 264, lambda i, w, h: tiles(max(w, 3), h, (70, 48, 44), 5, 6), 8)
    return m


MODELS = {
    "casa_a": casa_a, "casa_b": casa_b, "casa_c": casa_c, "taverna": taverna, "mansao": mansao,
    "capela": capela, "forja": forja, "tenda": tenda, "abrigo": abrigo, "forno": forno,
    "torre_madeira": torre_madeira, "fonte": fonte, "farol": farol,
}


def bounds(model):
    points = np.array([p for quad, _ in model.quads for p in quad]) * SIZE
    reach = float(np.hypot(points[:, 0], points[:, 1]).max())
    top = float(points[:, 2].max())
    margin = 4
    half = int(np.ceil(reach)) + margin
    above = int(np.ceil(reach * TILT + top)) + margin
    below = int(np.ceil(reach * TILT)) + margin
    return (half * 2, above + below), (half, above)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {}
    for name, build in MODELS.items():
        rng_state = np.random.default_rng(abs(hash_name(name)))
        globals()["rng"] = rng_state
        model = build()
        size, foot = bounds(model)
        rows = VIEWS // COLUMNS
        sheet = np.zeros((size[1] * rows, size[0] * COLUMNS, 4), np.uint8)
        for view in range(VIEWS):
            image = render(model, view * 2 * np.pi / VIEWS, size, foot)
            y, x = view // COLUMNS * size[1], view % COLUMNS * size[0]
            sheet[y: y + size[1], x: x + size[0]] = np.clip(image, 0, 255).astype(np.uint8)
        Image.fromarray(sheet, "RGBA").save(OUT / f"{name}.png", optimize=True)
        meta[name] = {"w": size[0], "h": size[1], "foot_x": foot[0], "foot_y": foot[1], "views": VIEWS, "columns": COLUMNS}
    (OUT / "meta.json").write_text(json.dumps(meta, indent="\t", sort_keys=True))


def hash_name(name):
    value = 0
    for char in name:
        value = value * 31 + ord(char)
    return value % 100000


if __name__ == "__main__":
    main()
