#!/usr/bin/env python3
"""Gera assets/town/ a partir de referencias/cidade.jpg.

Prédios e moradores são separados do fundo com GrabCut, a partir das caixas abaixo.
Rodar da raiz do projeto, depois de tools/build_biomes.py: python tools/build_town.py
Precisa de: pip install pillow numpy opencv-python-headless
"""
from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "referencias" / "cidade.jpg"
OUT = ROOT / "assets" / "town"
VIEW = 2576 / 1998  # as caixas estão em uma imagem de 1998 px de largura
SCALE = 1.15  # na imagem o hexágono é menor que no jogo
W, H = 186, 244
BEACON_SCALE = 1.45
BEAM_COLOR = (255, 214, 120)

BUILDINGS = {
    "forja": (318, 255, 560, 515), "tenda": (580, 275, 790, 482), "horta": (750, 305, 905, 412),
    "taverna": (1230, 345, 1545, 618), "mansao": (1550, 285, 1842, 535), "capela": (270, 560, 525, 772),
    "acampamento": (20, 445, 225, 592), "forno": (170, 725, 265, 842), "abrigo": (1040, 452, 1200, 600),
    "torre_madeira": (1590, 605, 1750, 765), "doca": (1410, 840, 1650, 985),
    "barco_a": (1818, 695, 1930, 832), "barco_b": (1622, 852, 1732, 932),
    "fogueira_a": (678, 395, 732, 458), "fogueira_b": (860, 850, 915, 908),
    "escada_a": (900, 460, 1040, 588), "escada_b": (980, 295, 1092, 402),
    "barraca_b": (930, 768, 1052, 880), "barraca_c": (1512, 682, 1612, 798),
    "tocha": (705, 545, 738, 632),
}
# (caixa, parte certamente do morador): sem ela, o corpo escuro some junto com o chão escuro.
RESIDENTS = {
    "morador_ferreiro": (830, 815, 882, 892), "morador_curandeira": (1602, 458, 1642, 527),
    "morador_taverneira": (238, 535, 277, 606), "morador_guarda": (585, 445, 637, 508),
    "morador_a": (373, 765, 422, 836), "morador_b": (1462, 585, 1502, 652), "morador_c": (925, 830, 966, 906),
    "morador_d": (1138, 645, 1182, 712), "morador_e": (575, 708, 612, 778), "morador_f": (545, 730, 585, 792),
    "morador_g": (1185, 703, 1222, 765),
}
# A fogueira atrás da mercadora: o que for fogo sai da figura.
FIRE_ERASE = ("morador_d",)
# Partes que sobraram na taverna: a cabeça de quem está na frente dela.
ERASE = {"taverna": [(300, 305, 345, 352)]}
STONE = (1000, 625, 1125, 705)


def rect(box, margin: int, shape) -> tuple:
    x0, y0, x1, y1 = (int(v * VIEW) for v in box)
    return x0, y0, x1, y1, max(0, x0 - margin), max(0, y0 - margin), min(shape[1], x1 + margin), min(shape[0], y1 + margin)


def cut(image: np.ndarray, box, person=False) -> Image.Image:
    x0, y0, x1, y1, ox0, oy0, ox1, oy1 = rect(box, 12, image.shape)
    crop = image[oy0:oy1, ox0:ox1].copy()
    mask = np.full(crop.shape[:2], cv2.GC_BGD, np.uint8)
    mask[y0 - oy0:y1 - oy0, x0 - ox0:x1 - ox0] = cv2.GC_PR_FGD
    if person:
        w, h = x1 - x0, y1 - y0
        center = (x0 - ox0 + w // 2, y0 - oy0 + h // 2)
        core = np.zeros(mask.shape, np.uint8)
        cv2.ellipse(core, center, (max(4, w // 5), int(h * 0.42)), 0, 0, 360, 1, -1)
        mask[core == 1] = cv2.GC_FGD
    background, foreground = np.zeros((1, 65)), np.zeros((1, 65))
    cv2.setRNGSeed(7)
    cv2.grabCut(crop, mask, None, background, foreground, 6, cv2.GC_INIT_WITH_MASK)
    solid = ((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)).astype(np.uint8)
    solid = cv2.morphologyEx(solid, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid)
    if count > 1:
        biggest = int(np.argmax(stats[1:, 4])) + 1
        solid = np.isin(labels, [i for i in range(1, count) if stats[i, 4] >= 0.08 * stats[biggest, 4]]).astype(np.uint8)
    picture = Image.fromarray(np.dstack([crop[..., ::-1], solid * 255]), "RGBA")
    return picture.crop(picture.getbbox())


def anchored(picture: Image.Image, foot_from_bottom=0) -> Image.Image:
    """O ponto de apoio fica no centro do canvas, como nos biomas."""
    half_w = picture.width // 2 + 4
    half_h = max(picture.height, 4) + 4
    canvas = Image.new("RGBA", (half_w * 2, half_h * 2), (0, 0, 0, 0))
    canvas.alpha_composite(picture, (half_w - picture.width // 2, half_h - picture.height + foot_from_bottom))
    return canvas


def resized(picture: Image.Image, factor: float) -> Image.Image:
    return picture.resize((round(picture.width * factor), round(picture.height * factor)), Image.Resampling.LANCZOS)


def beacon_with_beams() -> Image.Image:
    tower = Image.open(ROOT / "assets" / "biomes" / "floresta" / "farol_aceso.png").convert("RGBA")
    tower = tower.crop(tower.getbbox())
    tower = tower.resize((round(tower.width * BEACON_SCALE), round(tower.height * BEACON_SCALE)), Image.Resampling.NEAREST)
    width, height = tower.width + 620, tower.height + 90
    lamp = np.array([width / 2.0, 90 + tower.height * 0.075])
    ys, xs = np.mgrid[0:height, 0:width].astype(np.float32)
    dx, dy = xs - lamp[0], ys - lamp[1]
    distance = np.hypot(dx, dy) + 1
    angle = np.abs(np.arctan2(dy, np.abs(dx)))  # os dois feixes saem para os lados
    beam = np.clip(1.0 - np.abs(angle - 0.38) / 0.26, 0, 1) * np.clip(1.0 - distance / 340.0, 0, 1) * 96
    glow = np.clip(1.0 - distance / 90.0, 0, 1) ** 2 * 150
    alpha = np.maximum(beam, glow).astype(np.uint8)
    light = np.dstack([np.full(alpha.shape, BEAM_COLOR[0], np.uint8), np.full(alpha.shape, BEAM_COLOR[1], np.uint8), np.full(alpha.shape, BEAM_COLOR[2], np.uint8), alpha])
    canvas = Image.fromarray(light, "RGBA")
    canvas.alpha_composite(tower, ((width - tower.width) // 2, 90))
    return canvas


def stone_tile(image: np.ndarray) -> Image.Image:
    """Calçada: pedras da praça da imagem, no formato de um tile do jogo."""
    x0, y0, x1, y1, *_ = rect(STONE, 0, image.shape)
    stone = Image.fromarray(image[y0:y1, x0:x1, ::-1]).resize((W, 213), Image.Resampling.BOX)
    tile = np.array(Image.open(ROOT / "assets" / "biomes" / "floresta" / "campo_a.png").convert("RGBA"))
    top = np.array(stone)
    for y in range(213):
        for x in range(W):
            front = 213.0 - abs(x - 93.0) * (53.0 / 93.0)
            back = abs(x - 93.0) * (53.0 / 93.0)
            if back <= y <= front:
                edge = min(y - back, front - y, x, W - 1 - x)
                tile[y, x, :3] = (top[y, x] * (0.6 if edge < 1.5 else 1.0)).astype(np.uint8)
    return Image.fromarray(tile, "RGBA")


def mural() -> Image.Image:
    """Quadro de missoes, desenhado em "pixels" de 3, com as cores da madeira da cidade."""
    wood, dark, light, paper, ink, seal = (92, 66, 44), (46, 32, 26), (124, 92, 60), (222, 208, 170), (96, 82, 66), (196, 72, 56)
    g = 3
    cols, rows = 32, 34
    data = np.zeros((rows, cols, 4), np.uint8)

    def box(x0, y0, x1, y1, color):
        data[y0:y1, x0:x1] = (*color, 255)

    box(4, 8, 7, 34, dark); box(25, 8, 28, 34, dark)  # postes
    box(5, 8, 6, 34, wood); box(26, 8, 27, 34, wood)
    box(1, 6, 31, 25, dark); box(2, 7, 30, 24, wood)  # quadro
    for y in range(9, 24, 4):
        box(2, y, 30, y + 1, (74, 52, 36))
    box(0, 3, 32, 7, dark); box(1, 4, 31, 6, light)  # telhadinho
    for x0, y0, seal_on in ((4, 9, True), (13, 8, False), (22, 10, True), (8, 16, False), (18, 16, True)):
        box(x0, y0, x0 + 6, y0 + 7, paper)
        for line in (y0 + 2, y0 + 4):
            box(x0 + 1, line, x0 + 5, line + 1, ink)
        if seal_on:
            box(x0 + 2, y0, x0 + 4, y0 + 1, seal)
    return Image.fromarray(data, "RGBA").resize((cols * g, rows * g), Image.Resampling.NEAREST)


def main() -> None:
    image = cv2.imread(str(SOURCE))
    OUT.mkdir(parents=True, exist_ok=True)
    for name, box in BUILDINGS.items():
        picture = cut(image, box)
        if name in ERASE:
            data = np.array(picture)
            for ex0, ey0, ex1, ey1 in ERASE[name]:
                data[ey0:ey1, ex0:ex1, 3] = 0
            picture = Image.fromarray(data, "RGBA")
        anchored(resized(picture, SCALE)).save(OUT / f"{name}.png", optimize=True)
    for name, box in RESIDENTS.items():
        picture = cut(image, box, person=True)
        if name in FIRE_ERASE:
            data = np.array(picture).astype(np.int32)
            fire = (data[..., 0] > 170) & (data[..., 0] - data[..., 2] > 90) & (data[..., 1] > 55)
            data[..., 3][np.array(fire)] = 0
            picture = Image.fromarray(data.astype(np.uint8), "RGBA")
        anchored(resized(picture, SCALE * 1.15)).save(OUT / f"{name}.png", optimize=True)
    anchored(mural()).save(OUT / "mural.png", optimize=True)
    # A chama saiu da imagem sem a haste, que é escura como o chão atrás dela.
    flame = Image.open(OUT / "tocha.png").convert("RGBA")
    flame = flame.crop(flame.getbbox())
    pole = Image.new("RGBA", (10, 58), (58, 40, 30, 255))
    pole.paste((96, 70, 48, 255), (3, 0, 7, 58))
    torch = Image.new("RGBA", (max(flame.width, 10), flame.height + 50), (0, 0, 0, 0))
    torch.alpha_composite(pole, ((torch.width - 10) // 2, torch.height - 58))
    torch.alpha_composite(flame, ((torch.width - flame.width) // 2, 0))
    anchored(torch).save(OUT / "tocha.png", optimize=True)
    beacon = beacon_with_beams()
    anchored(beacon, foot_from_bottom=0).save(OUT / "farol.png", optimize=True)
    stone_tile(image).save(OUT / "calcada.png", optimize=True)
    print("cidade gerada em", OUT)


if __name__ == "__main__":
    main()
