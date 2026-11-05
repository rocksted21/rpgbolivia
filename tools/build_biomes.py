#!/usr/bin/env python3
"""Gera assets/biomes/ a partir das pranchas de referencias/biomas.

Os objetos sao recortados das pranchas pelo contraste com o fundo. Os pisos e as paredes
tambem vem de la: o topo isometrico de cada bloco e desentortado e ajustado ao formato dos
tiles do jogo (186x244), com os "pixels" alinhados em uma grade.

Rodar da raiz do projeto: python tools/build_biomes.py
Precisa de: pip install pillow numpy scipy
"""
from __future__ import annotations

import random
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
REFS = ROOT / "referencias" / "biomas"
OUT = ROOT / "assets" / "biomes"

W, H = 186, 244  # tamanho de um tile
PIXEL = 3  # lado do "pixel" da arte no piso, em pixels da textura
WALL = 31  # altura da parede abaixo da borda da frente
LAYER = 29  # o jogo empilha paredes a cada 29 px
VIEW = 2576 / 1500  # as caixas abaixo estao em uma prancha de 1500 px de largura
INK = (20, 19, 24, 255)
OBJECT_CONTRAST = 14  # diferenca minima para o fundo da prancha
EDGE_STRENGTH = 70
# Texto da prancha que encosta no telhado da casa de resgate.
CAPTION = (800, 478, 1046, 508)
TREE, SMALL, HOUSE, BEACON = 0.60, 0.62, 0.72, 0.56  # escala da prancha para o jogo
FIELD_CONTRAST = 0.45  # o campo se repete muito: desenhos fortes viram um padrão de escamas
MOUNTAIN = 0.46
CLIFF_TRIM = 8
MANGROVE = 0.46  # a copa larga do mangue cobriria os personagens nas casas vizinhas

# Blocos da prancha: (centro x, y do topo). As pranchas seguem a mesma grade.
LEFT, RIGHT = 101, 266
ROW1, ROW2, ROW3, ROW5 = 152, 292, 473, 688
BLOCK_HALF_W = 74
BLOCK_HALF_H = 37
BLOCK_SIDE = 46

# tile: (prancha, x, y). A floresta usa a agua escura do pantano, e o deserto a do oasis.
TILES = {
    "floresta": {
        "campo_a": ("floresta", LEFT, ROW1), "campo_b": ("floresta", LEFT, ROW5), "sombra": ("floresta", LEFT, ROW3),
        "agua_a": ("selva", LEFT, ROW2), "agua_b": ("selva", RIGHT, ROW2),
    },
    "selva": {
        "campo_a": ("selva", LEFT, ROW1), "campo_b": ("selva", LEFT, ROW3), "sombra": ("selva", RIGHT, ROW3),
        "agua_a": ("selva", LEFT, ROW2), "agua_b": ("selva", RIGHT, ROW2),
    },
    "neve": {
        "campo_a": ("neve", LEFT, ROW1), "campo_b": ("neve", LEFT, ROW5), "sombra": ("neve", RIGHT, ROW3),
        "agua_a": ("neve", LEFT, ROW2), "agua_b": ("neve", RIGHT, ROW2),
    },
    "deserto": {
        "campo_a": ("deserto", LEFT, ROW5), "campo_b": ("deserto", LEFT, ROW1), "sombra": ("deserto", RIGHT, ROW2),
        "agua_a": ("selva", RIGHT, ROW2), "agua_b": ("selva", RIGHT, ROW2),
    },
}
WATER_TINT = {"deserto": (0.55, 1.0, 1.0)}  # o oasis e mais claro e esverdeado que o pantano
# Pecas de piso por lado do hexagono: encostam no meio da aresta, entao duas casas vizinhas
# formam uma linha continua. A ordem dos lados e a de hex.gd (horario, a partir do leste).
CENTER = np.array([93.0, 106.5])
SIDES = [(186.0, 106.5), (139.5, 186.5), (46.5, 186.5), (0.0, 106.5), (46.5, 26.5), (139.5, 26.5)]
# A textura se repete nestes vetores: as pedras seguem de uma casa para a outra.
TILING = (np.array([186.0, 0.0]), np.array([93.0, 160.0]))
PATH_HALF = 27  # meia largura do caminho
BORDER_DEPTH = 46  # ate onde o chao vizinho avanca na casa
SHORE_DEPTH = 24
# Calcamento de cada bioma: pedras (escura, base, clara) e a junta entre elas.
PAVING = {
    "floresta": {"stones": ((96, 92, 88), (122, 118, 110), (146, 140, 128)), "joint": (58, 46, 38), "size": 15},
    "selva": {"planks": ((70, 52, 38), (92, 68, 46), (112, 84, 54)), "joint": (22, 20, 20)},
    "neve": {"stones": ((104, 112, 130), (126, 134, 152), (148, 156, 172)), "joint": (72, 78, 96), "size": 17},
    "deserto": {"stones": ((132, 96, 66), (158, 118, 78), (184, 142, 94)), "joint": (92, 60, 40), "size": 19},
}
# A estrada é a via larga, com meio-fio; a trilha é o caminho estreito de terra batida.
ROAD_HALF = 33  # meia largura da estrada, sem o meio-fio
ROAD_CURB = 6
ROAD_CURB_COLORS = {
    "floresta": ((52, 46, 42), (88, 84, 78)),
    "selva": ((24, 20, 20), (58, 44, 34)),
    "neve": ((70, 76, 92), (112, 120, 138)),
    "deserto": ((84, 54, 36), (128, 88, 56)),
}
TRAIL_HALF = 18
TRAILS = {
    "floresta": ((66, 46, 34), (96, 68, 46), (120, 90, 60)),
    "selva": ((58, 50, 40), (92, 80, 58), (116, 102, 72)),
    "neve": ((128, 142, 166), (150, 164, 186), (176, 188, 204)),
    "deserto": ((122, 74, 46), (150, 96, 58), (174, 118, 72)),
}
BRIDGE = {"planks": ((88, 62, 40), (116, 84, 52), (140, 104, 64)), "joint": (30, 22, 18)}

# Montes: claro, base e escuro, nas cores de cada prancha.
MOUNDS = {
    "floresta": ((132, 130, 74), (98, 100, 60), (62, 68, 48)),
    "selva": ((76, 92, 62), (54, 70, 50), (34, 46, 38)),
    "neve": ((238, 243, 249), (206, 216, 230), (138, 154, 178)),
    "deserto": ((232, 194, 112), (204, 158, 82), (146, 98, 58)),
}

# nome: caixa na prancha, em coordenadas de 1500 px.
CUTS = {
    "floresta": {
        "penhasco": (578, 352, 722, 572), "arvore_a": (362, 150, 516, 370), "arvore_b": (514, 195, 618, 367), "arvore_c": (612, 150, 728, 367),
        "moita_a": (380, 385, 447, 452), "moita_b": (456, 389, 528, 452), "galhos": (374, 465, 463, 570),
        "folha": (470, 509, 533, 574), "cogumelo": (545, 516, 591, 567), "pilha": (375, 597, 478, 685),
        "escombros": (493, 573, 722, 694), "coluna": (825, 180, 872, 298), "arco_a": (762, 302, 912, 480),
        "arco_b": (932, 310, 1105, 492), "estatua": (760, 490, 835, 615), "engrenagem": (844, 522, 920, 578),
        "casa": (915, 497, 1112, 699), "farol_apagado": (1122, 186, 1322, 707), "farol_aceso": (1315, 185, 1477, 705),
    },
    "selva": {
        "penhasco": (538, 352, 722, 562), "arvore_a": (362, 148, 562, 372), "arvore_b": (574, 150, 737, 367), "samambaia_a": (369, 377, 457, 456),
        "samambaia_b": (463, 373, 538, 451), "cristal_a": (552, 367, 618, 444), "cogumelo": (543, 291, 602, 359),
        "cristal_b": (470, 492, 535, 570), "galhos": (375, 458, 463, 570), "cristal_grande": (374, 573, 477, 688),
        "tronco": (493, 560, 722, 694), "estufa_a": (760, 138, 933, 325), "estufa_b": (948, 154, 1121, 325),
        "portao": (762, 327, 913, 480), "arco": (926, 334, 1109, 480), "engrenagens": (759, 545, 910, 686),
        "casa": (915, 482, 1127, 702), "farol_apagado": (1122, 184, 1308, 710), "farol_aceso": (1308, 184, 1482, 710),
    },
    "neve": {
        "penhasco": (578, 352, 722, 572), "pinheiros": (371, 148, 578, 373), "arvore": (578, 153, 729, 370), "samambaia_a": (370, 377, 457, 458),
        "samambaia_b": (463, 384, 537, 451), "cristal_a": (551, 377, 616, 450), "galhos": (375, 465, 464, 575),
        "cristal_b": (471, 500, 538, 575), "cogumelo": (545, 516, 591, 567), "cristal_grande": (375, 586, 486, 690),
        "tronco": (493, 558, 722, 694), "engrenagens": (759, 195, 921, 321), "relogios": (932, 149, 1124, 320),
        "portao": (757, 328, 915, 485), "arco": (925, 335, 1110, 480), "casa": (910, 482, 1127, 702),
        "farol_apagado": (1122, 184, 1310, 712), "farol_aceso": (1310, 184, 1492, 712),
    },
    "deserto": {
        "penhasco": (576, 368, 722, 562), "cacto": (372, 152, 465, 344), "seco_a": (454, 190, 581, 370), "arvore": (573, 153, 729, 370),
        "samambaia_a": (370, 378, 457, 457), "samambaia_b": (463, 385, 537, 451), "seco_b": (552, 378, 616, 450),
        "galhos": (375, 466, 465, 575), "pedra": (512, 451, 568, 503), "cogumelo": (545, 516, 591, 567),
        "caveira": (374, 607, 486, 691), "tronco": (493, 558, 722, 694), "ossada": (755, 151, 936, 326),
        "colunas": (936, 144, 1124, 325), "escada": (757, 333, 923, 465), "arco": (925, 327, 1110, 482),
        "engrenagens": (759, 545, 910, 686), "casa": (912, 482, 1127, 702),
        "farol_apagado": (1123, 180, 1310, 712), "farol_aceso": (1310, 180, 1492, 712),
    },
}


def front_edge(x: float) -> float:
    return 213.0 - abs(x - 93.0) * (53.0 / 93.0)


def back_edge(x: float) -> float:
    return abs(x - 93.0) * (53.0 / 93.0)


class Sheet:
    def __init__(self, path: Path) -> None:
        self.rgb = np.array(Image.open(path).convert("RGB")).astype(np.float32)
        # Suaviza o ruido do JPEG sem desfazer os "pixels" da arte.
        self.soft = np.dstack([ndimage.uniform_filter(self.rgb[..., i], 3) for i in range(3)])
        self.back = np.median(self.rgb[200:].reshape(-1, 3), axis=0)

    def sample(self, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
        """Cor nos pontos dados, em coordenadas da prancha de 1500 px."""
        coords = [ys * VIEW, xs * VIEW]
        return np.dstack([ndimage.map_coordinates(self.soft[..., i], coords, order=1) for i in range(3)])

    def cut(self, box, by_edges=False) -> Image.Image:
        """by_edges: para arte com fumaca ou brilho em volta. O fundo suave nao tem bordas."""
        x0, y0, x1, y1 = (round(v * VIEW) for v in box)
        crop = self.rgb[y0:y1, x0:x1]
        if by_edges:
            luma = crop @ np.array([0.3, 0.59, 0.11], np.float32)
            edges = np.hypot(ndimage.sobel(luma, axis=0), ndimage.sobel(luma, axis=1))
            solid = ndimage.binary_closing(edges > EDGE_STRENGTH, iterations=4)
            solid = ndimage.binary_fill_holes(np.pad(solid, 4))[4:-4, 4:-4]
            solid = ndimage.binary_opening(solid, iterations=3)
        else:
            solid = np.abs(crop - self.back).max(axis=2) > OBJECT_CONTRAST
            cx0, cy0, cx1, cy1 = (round(v * VIEW) for v in CAPTION)
            solid[max(0, cy0 - y0):max(0, cy1 - y0), max(0, cx0 - x0):max(0, cx1 - x0)] = False
            solid = ndimage.binary_opening(solid, iterations=1)
        labels, count = ndimage.label(solid)
        if count > 1:  # so o objeto principal: textos e vizinhos da prancha ficam de fora
            sizes = ndimage.sum(solid, labels, range(1, count + 1))
            solid = labels == int(np.argmax(sizes)) + 1
        solid = ndimage.binary_fill_holes(solid)
        rgba = np.dstack([crop, solid * 255.0]).astype(np.uint8)
        prop = Image.fromarray(rgba, "RGBA")
        return prop.crop(prop.getbbox())


def scaled(prop: Image.Image, factor: float) -> Image.Image:
    size = (max(1, round(prop.width * factor)), max(1, round(prop.height * factor)))
    data = np.array(prop.resize(size, Image.Resampling.BOX))
    solid = data[..., 3] >= 128
    grown = ndimage.binary_dilation(np.pad(solid, 1), iterations=1)
    out = np.zeros((*grown.shape, 4), np.uint8)
    out[grown] = INK
    inner = np.pad(data, ((1, 1), (1, 1), (0, 0)))
    inside = np.pad(solid, 1)
    out[inside] = inner[inside]
    out[inside, 3] = 255
    return Image.fromarray(out, "RGBA")


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

def block_top(sheet: Sheet, x: int, y: int) -> np.ndarray:
    """Topo do bloco, desentortado, em uma grade de "pixels" do tamanho do tile."""
    cols, rows = W // PIXEL + 1, H // PIXEL + 1
    margin = 0.08  # a borda do topo tem o contorno do bloco
    grid_v, grid_u = np.mgrid[0:rows, 0:cols].astype(np.float32)
    u = margin + (grid_u + 0.5) / cols * (1 - 2 * margin)
    # O topo do tile ocupa só 213 das 244 linhas; o resto da grade repete o fim.
    v = margin + np.minimum((grid_v + 0.5) * PIXEL / 213.0, 1.0) * (1 - 2 * margin)
    return sheet.sample(x + (u - v) * BLOCK_HALF_W, y + (u + v) * BLOCK_HALF_H)


def block_face(sheet: Sheet, x: int, y: int, right: bool, along: np.ndarray, down: np.ndarray) -> np.ndarray:
    """Lateral do bloco: `along` de 0 a 1 pela borda, `down` de 0 a 1 descendo."""
    if right:
        xs = x + along * BLOCK_HALF_W
        ys = y + 2 * BLOCK_HALF_H - along * BLOCK_HALF_H
    else:
        xs = x - BLOCK_HALF_W + along * BLOCK_HALF_W
        ys = y + BLOCK_HALF_H + along * BLOCK_HALF_H
    return sheet.sample(xs, ys + down * BLOCK_SIDE)


def make_tile(sheet: Sheet, x: int, y: int, wall_only=False, tint=(1.0, 1.0, 1.0), contrast=1.0) -> Image.Image:
    top = block_top(sheet, x, y)
    average = top.reshape(-1, 3).mean(axis=0)
    top = average + (top - average) * contrast
    shade = average * 0.55
    out = np.zeros((H, W, 4), np.float32)
    for py in range(H):
        for px in range(W):
            front, back = front_edge(px), back_edge(px)
            if py < back or py > front + WALL:
                continue
            if py <= front:
                color = top[py // PIXEL, px // PIXEL]
                if min(py - back, front - py, px, W - 1 - px) < 1.5:  # costura entre casas
                    color = color * 0.45 + shade * 0.55
            else:
                right = px >= 93
                along = np.array([[(((px - 93) if right else px) // PIXEL * PIXEL + 1) / 93.0]], np.float32)
                depth = py - front
                # O topo da parede tem a franja de capim ou neve; a parede repetida usa o meio.
                down = 0.3 + 0.55 * (depth % LAYER) / LAYER if wall_only else depth / WALL * 0.6
                color = block_face(sheet, x, y, right, along, np.array([[down]], np.float32))[0, 0]
                if depth >= WALL - 1.5:
                    color = color * 0.5
            out[py, px, :3] = color * np.array(tint, np.float32)
            out[py, px, 3] = 255
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def mound(biome: str, width: int, height: int, seed: int) -> Image.Image:
    light, base, dark = MOUNDS[biome]
    rng = random.Random(f"{biome}/monte/{seed}")
    g = 3
    cols, rows = width // g, height // g
    data = np.zeros((rows, cols, 4), np.uint8)
    for cy in range(rows):
        for cx in range(cols):
            nx = (cx + 0.5) / cols * 2 - 1
            ny = 1 - (cy + 0.5) / rows
            top = 1 - abs(nx) ** 1.7
            if ny > top:
                continue
            shade = nx + (0.5 - ny / max(top, 0.01)) * 0.5 + rng.uniform(-0.12, 0.12)
            color = light if shade < -0.28 else (dark if shade > 0.34 else base)
            data[cy, cx] = (*color, 255)
    return scaled(Image.fromarray(data, "RGBA").resize((cols * g, rows * g), Image.Resampling.NEAREST), 1.0)


# --- Montagem por bioma ---------------------------------------------------------

def save(im: Image.Image, biome: str, name: str) -> None:
    folder = OUT / biome
    folder.mkdir(parents=True, exist_ok=True)
    im.save(folder / f"{name}.png", optimize=True)


def build_props(biome: str, c: dict) -> None:
    def s(name: str, factor: float = SMALL) -> Image.Image:
        return scaled(c[name], factor)

    # A prancha mostra só metade do penhasco, cortada na vertical: espelhada, vira um morro inteiro.
    half = c["penhasco"]
    half = half.crop((0, 0, half.width - CLIFF_TRIM, half.height))  # sem o contorno do corte
    whole = Image.new("RGBA", (half.width * 2, half.height), (0, 0, 0, 0))
    whole.alpha_composite(half)
    whole.alpha_composite(half.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (half.width, 0))
    mountain = scaled(whole, MOUNTAIN)

    if biome == "floresta":
        sets = {
            "floresta_fundo_a": [(s("arvore_a", TREE), 0, 0)],
            "floresta_fundo_b": [(s("arvore_c", TREE), 0, 0)],
            "floresta_frente_a": [(s("arvore_b", 0.3), -62, 0), (s("moita_a"), 58, 4)],
            "floresta_frente_b": [(s("galhos", 0.5), 60, 0), (s("moita_b"), -58, 2)],
            "pedras_a": [(s("pilha", 0.75), -18, 0), (s("cogumelo", 0.5), 48, 6)],
            "pedras_b": [(s("folha", 0.7), 34, 2), (s("pilha", 0.5), -30, 0)],
            "montanha_a": [(mountain, 0, 0)],
            "montanha_b": [(s("escombros", 0.68), 0, 0)],
            "torre": [(s("arco_b", 0.6), 0, 0)],
            "ruina_a": [(s("arco_a", 0.55), 0, 0)],
            "ruina_b": [(s("estatua", 0.7), -22, 0), (s("coluna", 0.6), 44, 4)],
            "enfeite_a": [(s("coluna", 0.62), 0, 0)],
            "enfeite_b": [(s("estatua", 0.62), 0, 0)],
            "enfeite_c": [(s("engrenagem", 0.5), 0, 0)],
        }
    elif biome == "selva":
        sets = {
            "floresta_fundo_a": [(s("arvore_a", MANGROVE), 0, 0)],
            "floresta_fundo_b": [(s("arvore_b", MANGROVE), 0, 0)],
            "floresta_frente_a": [(s("samambaia_a", 0.55), -60, 2), (s("cristal_a", 0.5), 58, 4)],
            "floresta_frente_b": [(s("samambaia_b", 0.55), 60, 2), (s("cogumelo", 0.5), -56, 2)],
            "pedras_a": [(s("cristal_grande", 0.6), 0, 0)],
            "pedras_b": [(s("galhos", 0.5), -22, 0), (s("cogumelo", 0.45), 40, 6)],
            "montanha_a": [(mountain, 0, 0)],
            "montanha_b": [(s("estufa_b", 0.6), 0, 0)],
            "torre": [(s("estufa_a", 0.6), 0, 0)],
            "ruina_a": [(s("portao", 0.55), 0, 0)],
            "ruina_b": [(s("engrenagens", 0.5), 0, 0)],
            "enfeite_a": [(s("cristal_b", 0.5), 0, 0)],
            "enfeite_b": [(s("cogumelo", 0.5), 0, 0)],
            "enfeite_c": [(s("portao", 0.5), 0, 0)],
        }
    elif biome == "neve":
        sets = {
            "floresta_fundo_a": [(s("pinheiros", TREE), 0, 0)],
            "floresta_fundo_b": [(s("arvore", TREE), 0, 0)],
            "floresta_frente_a": [(s("samambaia_a", 0.55), -60, 2), (s("cristal_a", 0.5), 58, 4)],
            "floresta_frente_b": [(s("galhos", 0.5), 58, 0), (s("samambaia_b", 0.55), -58, 2)],
            "pedras_a": [(s("cristal_grande", 0.6), 0, 0)],
            "pedras_b": [(s("cristal_b", 0.6), -24, 0), (s("cogumelo", 0.5), 38, 6)],
            "montanha_a": [(mountain, 0, 0)],
            "montanha_b": [(s("relogios", 0.62), 0, 0)],
            "torre": [(s("arco", 0.62), 0, 0)],
            "enfeite_a": [(s("portao", 0.4), 0, 0)],
            "ruina_a": [(s("portao", 0.55), 0, 0)],
            "ruina_b": [(s("engrenagens", 0.55), 0, 0)],
            "enfeite_b": [(s("engrenagens", 0.45), 0, 0)],
            "enfeite_c": [(s("cristal_b", 0.45), 0, 0)],
        }
    else:  # deserto
        sets = {
            "floresta_fundo_a": [(s("cacto", 0.72), -16, 0), (s("seco_b", 0.5), 46, 4)],
            "floresta_fundo_b": [(s("arvore", TREE), 0, 0)],
            "floresta_frente_a": [(s("samambaia_a", 0.55), -60, 2), (s("seco_b", 0.5), 58, 4)],
            "floresta_frente_b": [(s("galhos", 0.5), 58, 0), (s("samambaia_b", 0.55), -58, 2)],
            "pedras_a": [(s("pedra", 0.8), -20, 0), (s("cogumelo", 0.5), 36, 6)],
            "pedras_b": [(s("caveira", 0.6), 0, 0)],
            "montanha_a": [(mountain, 0, 0)],
            "montanha_b": [(s("ossada", 0.62), 0, 0)],
            "torre": [(s("arco", 0.62), 0, 0)],
            "enfeite_a": [(s("pedra", 0.6), 0, 0)],
            "ruina_a": [(s("colunas", 0.55), 0, 0)],
            "ruina_b": [(s("escada", 0.6), 0, 0)],
            "enfeite_b": [(s("caveira", 0.5), 0, 0)],
            "enfeite_c": [(s("engrenagens", 0.42), 0, 0)],
        }
    for name, parts in sets.items():
        save(compose(parts), biome, name)
    save(compose([(s("casa", HOUSE), 0, 0)]), biome, "casa")
    save(compose([(s("farol_apagado", BEACON), 0, 0)]), biome, "farol_apagado")
    save(compose([(s("farol_aceso", BEACON), 0, 0)]), biome, "farol_aceso")
    for i, name in enumerate("ab"):
        big = mound(biome, 132 - i * 16, 72 - i * 8, i)
        small = mound(biome, 84, 44, i + 5)
        tiny = mound(biome, 60, 32, i + 9)
        save(compose([(big, -14 + i * 26, -8), (small, 44 - i * 92, 8), (tiny, -58 + i * 104, 16)]), biome, f"colinas_{name}")


# --- Pecas que ligam as casas ------------------------------------------------------

def pixel_grid() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Centro de cada "pixel" da arte e a mascara do topo do hexagono."""
    rows, cols = H // PIXEL + 1, W // PIXEL + 1
    gy, gx = np.mgrid[0:rows, 0:cols].astype(np.float32)
    xs, ys = gx * PIXEL + PIXEL / 2, gy * PIXEL + PIXEL / 2
    top = (ys >= np.abs(xs - 93) * 53 / 93) & (ys <= 213 - np.abs(xs - 93) * 53 / 93)
    return xs, ys, top


def to_tile(rgb: np.ndarray, mask: np.ndarray) -> Image.Image:
    data = np.zeros((*mask.shape, 4), np.uint8)
    data[mask, :3] = np.clip(rgb[mask], 0, 255)
    data[mask, 3] = 255
    big = np.repeat(np.repeat(data, PIXEL, axis=0), PIXEL, axis=1)[:H, :W]
    # So o topo: a grade de "pixels" nao pode vazar pela borda do hexagono.
    yy, xx = np.mgrid[0:H, 0:W]
    big[(yy < np.abs(xx - 93) * 53 / 93) | (yy > 213 - np.abs(xx - 93) * 53 / 93), 3] = 0
    return Image.fromarray(big, "RGBA")


def smooth_noise(shape, seed: str, blur: float) -> np.ndarray:
    rng = np.random.default_rng(abs(hash_text(seed)))
    noise = ndimage.gaussian_filter(rng.random(shape), blur, mode="wrap")
    return (noise - noise.min()) / max(noise.max() - noise.min(), 1e-6)


def hash_text(text: str) -> int:
    return sum((i + 1) * ord(c) for i, c in enumerate(text)) * 2654435761 % (2 ** 32)


def stone_pattern(xs, ys, size: int, seed: str):
    """Pedras irregulares que se repetem junto com a grade de hexagonos."""
    rng = np.random.default_rng(hash_text(seed))
    a, b = TILING
    count = max(4, round(abs(a[0] * b[1] - a[1] * b[0]) / size ** 2))
    base = [rng.random() * a + rng.random() * b for _ in range(count)]
    points = np.array([p + i * a + j * b for p in base for i in range(-2, 3) for j in range(-2, 3)], np.float32)
    ids = np.repeat(np.arange(count), 25)
    dist = np.hypot(xs[..., None] - points[:, 0], ys[..., None] - points[:, 1])
    order = np.argsort(dist, axis=-1)
    near = np.take_along_axis(dist, order[..., :2], axis=-1)
    stone = ids[order[..., 0]]
    shade = rng.integers(0, 3, count)[stone]
    joint = near[..., 1] - near[..., 0] < 2.6
    return shade, joint


def paving_colors(xs, ys, style: dict, seed: str, along: np.ndarray | None = None):
    if "planks" in style:
        # Tabuas atravessadas no sentido do caminho: a junta e uma linha a cada tabua.
        offset = along if along is not None else ys
        plank = np.floor(offset / 13.0).astype(int)
        rng = np.random.default_rng(hash_text(seed))
        shade = rng.integers(0, 3, 256)[plank % 256]
        joint = (offset % 13.0) < 3.0
        colors = np.array(style["planks"], np.float32)
    else:
        shade, joint = stone_pattern(xs, ys, style["size"], seed)
        colors = np.array(style["stones"], np.float32)
    rgb = colors[shade]
    rgb[joint] = style["joint"]
    return rgb


def side_piece(style: dict, seed: str, side: int | None) -> Image.Image:
    """Um braco do caminho, do centro ate o meio da aresta. side None: o miolo redondo."""
    xs, ys, top = pixel_grid()
    if side is None:
        distance = np.hypot(xs - CENTER[0], ys - CENTER[1])
        wobble = (smooth_noise(xs.shape, seed + "/miolo", 2.0) - 0.5) * 7
        mask = distance < PATH_HALF + 2 + wobble
        along = None
    else:
        end = np.array(SIDES[side])
        vec = end - CENTER
        length = np.linalg.norm(vec)
        unit = vec / length
        t = ((xs - CENTER[0]) * unit[0] + (ys - CENTER[1]) * unit[1]) / length
        d = (xs - CENTER[0]) * -unit[1] + (ys - CENTER[1]) * unit[0]
        # Ondula so no meio: nas pontas a largura e exata, para encontrar a vizinha.
        taper = np.sin(np.clip(t, 0, 1) * np.pi)
        edge = (smooth_noise(xs.shape, f"{seed}/{side}", 2.5) - 0.5) * 14 * taper
        mask = (t >= -0.02) & (np.abs(d) < PATH_HALF + edge)
        along = t * length
    mask &= top
    rgb = paving_colors(xs, ys, style, seed, along)
    # Contorno escuro, como na arte das pranchas.
    inner = ndimage.binary_erosion(mask, border_value=1)
    rgb[mask & ~inner] = np.array(style["joint"], np.float32) * 0.8
    return to_tile(rgb, mask)


def edge_mask(xs, ys, side: int, depth: float, seed: str) -> np.ndarray:
    """Faixa junto de uma aresta, cheia na borda e cada vez mais rala para dentro."""
    vec = np.array(SIDES[side]) - CENTER
    length = np.linalg.norm(vec)
    from_edge = length - ((xs - CENTER[0]) * vec[0] + (ys - CENTER[1]) * vec[1]) / length
    clumps = smooth_noise(xs.shape, f"{seed}/{side}", 2.0)
    specks = smooth_noise(xs.shape, f"{seed}/{side}/fino", 0.6)
    return from_edge + (clumps * 0.75 + specks * 0.25 - 0.5) * depth * 1.5 < depth * 0.55


def build_edges(biome: str) -> None:
    xs, ys, top = pixel_grid()
    ground = np.array(Image.open(OUT / biome / "campo_a.png").convert("RGB"), np.float32)
    cols = np.clip((xs / 1).astype(int), 0, W - 1)
    rows = np.clip((ys / 1).astype(int), 0, H - 1)
    colors = ground[rows, cols]
    bank = np.median(colors[top], axis=0)
    water = np.array(Image.open(OUT / biome / "agua_a.png").convert("RGB"), np.float32)[rows, cols]
    foam = np.median(water[top], axis=0) * 0.45 + np.array([236, 240, 240], np.float32) * 0.55
    for side in range(6):
        save(to_tile(colors, edge_mask(xs, ys, side, BORDER_DEPTH, f"{biome}/borda") & top), biome, f"borda_{side}")
        vec = np.array(SIDES[side]) - CENTER
        length = np.linalg.norm(vec)
        from_edge = length - ((xs - CENTER[0]) * vec[0] + (ys - CENTER[1]) * vec[1]) / length
        land = edge_mask(xs, ys, side, SHORE_DEPTH, f"{biome}/margem") & top
        rgb = np.broadcast_to(bank, colors.shape).copy()
        grown = ndimage.binary_dilation(land) & top & ~land
        rgb[grown] = foam
        save(to_tile(rgb, (land | grown) & (from_edge < SHORE_DEPTH * 1.6)), biome, f"margem_{side}")


def arm_geometry(xs, ys, side: int | None):
    """t: de 0 (centro) a 1 (meio da aresta); d: distância até o eixo. side None: o miolo."""
    if side is None:
        return None, np.hypot(xs - CENTER[0], ys - CENTER[1])
    vec = np.array(SIDES[side]) - CENTER
    length = np.linalg.norm(vec)
    unit = vec / length
    t = ((xs - CENTER[0]) * unit[0] + (ys - CENTER[1]) * unit[1]) / length
    d = (xs - CENTER[0]) * -unit[1] + (ys - CENTER[1]) * unit[0]
    return t, d


def road_pieces(biome: str, side: int | None) -> tuple[Image.Image, Image.Image]:
    """O piso e o meio-fio de um braço da estrada. O jogo desenha todos os meios-fios primeiro
    e os pisos depois: assim, onde os braços se juntam, não sobra borda no meio da via."""
    xs, ys, top = pixel_grid()
    t, d = arm_geometry(xs, ys, side)
    seed = f"{biome}/estrada"
    if side is None:
        floor = d < ROAD_HALF
        outer = d < ROAD_HALF + ROAD_CURB
        along = None
    else:
        reach = t >= -0.02
        floor = reach & (np.abs(d) < ROAD_HALF)
        outer = reach & (np.abs(d) < ROAD_HALF + ROAD_CURB)
        along = t * np.linalg.norm(np.array(SIDES[side]) - CENTER)
    rgb = paving_colors(xs, ys, PAVING[biome], seed, along)
    # Sulcos das rodas: duas faixas um pouco mais escuras seguindo a via.
    if side is not None:
        rut = np.abs(np.abs(d) - ROAD_HALF * 0.5) < 3.2
        rgb[rut] = rgb[rut] * 0.86
    dark, light = (np.array(c, np.float32) for c in ROAD_CURB_COLORS[biome])
    curb = np.broadcast_to(light, rgb.shape).copy()
    inner = ndimage.binary_erosion(outer, border_value=1)
    curb[outer & ~inner] = dark
    if side is not None:
        blocks = (((t * 200.0).astype(int)) % 9) < 1
        curb[blocks] = dark
    return to_tile(rgb, floor & top), to_tile(curb, outer & top)


def trail_piece(biome: str, side: int | None) -> Image.Image:
    """Um braço da trilha: terra batida sem contorno, com a borda irregular e algumas pedrinhas."""
    xs, ys, top = pixel_grid()
    t, d = arm_geometry(xs, ys, side)
    seed = f"{biome}/trilha/{side}"
    wobble = (smooth_noise(xs.shape, seed, 2.0) - 0.5) * 9
    specks = smooth_noise(xs.shape, seed + "/fino", 0.5)
    if side is None:
        mask = d < TRAIL_HALF + 2 + wobble * 0.5
    else:
        # Nas pontas a largura é exata, para encontrar a trilha da casa vizinha.
        taper = np.sin(np.clip(t, 0, 1) * np.pi)
        mask = (t >= -0.02) & (np.abs(d) < TRAIL_HALF + wobble * taper)
    mask &= top
    dark, base, light = (np.array(c, np.float32) for c in TRAILS[biome])
    rgb = np.broadcast_to(base, (*xs.shape, 3)).copy()
    tone = smooth_noise(xs.shape, f"{biome}/trilha/tom", 1.4)
    rgb[tone < 0.42] = dark * 0.5 + base * 0.5
    rgb[tone > 0.6] = light * 0.5 + base * 0.5
    rgb[specks > 0.82] = light
    rgb[specks < 0.13] = dark
    inner = ndimage.binary_erosion(mask, border_value=1)
    rgb[mask & ~inner] = dark
    return to_tile(rgb, mask)


def build_chests() -> None:
    """O baú: madeira gasta e ferro, com fechadura e ouro; a única cor forte é o prêmio."""
    wood, wood_dark, wood_light = (92, 56, 42), (62, 36, 30), (122, 78, 54)
    iron, iron_light = (58, 60, 70), (98, 102, 114)
    gold, gold_dark, gold_light = (242, 176, 40), (178, 112, 24), (255, 232, 130)

    def fill(px, box, color):
        x0, y0, x1, y1 = box
        px[y0:y1, x0:x1] = (*color, 255)

    def body(px):
        fill(px, (4, 19, 40, 36), wood)
        for y in (24, 30):
            fill(px, (4, y, 40, y + 1), wood_dark)
        fill(px, (4, 19, 40, 20), wood_light)
        fill(px, (4, 34, 40, 36), wood_dark)
        for x in (9, 32):
            fill(px, (x, 19, x + 3, 36), iron)
            fill(px, (x, 19, x + 1, 36), iron_light)

    closed = np.zeros((38, 44, 4), np.uint8)
    body(closed)
    # Tampa arredondada.
    for y, inset in zip(range(7, 19), (9, 6, 4, 3, 2, 2, 1, 1, 1, 1, 1, 1)):
        fill(closed, (3 + inset, y, 41 - inset, y + 1), wood_light if y < 10 else wood)
    fill(closed, (4, 13, 40, 14), wood_dark)
    for x in (9, 32):
        fill(closed, (x, 8, x + 3, 19), iron)
        fill(closed, (x, 8, x + 1, 19), iron_light)
    fill(closed, (3, 18, 41, 20), iron)
    fill(closed, (18, 16, 26, 26), gold_dark)
    fill(closed, (19, 17, 25, 25), gold)
    fill(closed, (19, 17, 25, 18), gold_light)
    fill(closed, (21, 20, 23, 23), wood_dark)
    for x, y in ((1, 6), (41, 11), (38, 3)):
        fill(closed, (x, y, x + 1, y + 1), gold_light)

    opened = np.zeros((38, 44, 4), np.uint8)
    # Tampa aberta, para trás, com o forro escuro à mostra.
    fill(opened, (6, 2, 38, 13), wood_dark)
    fill(opened, (6, 2, 38, 4), wood)
    for x in (9, 32):
        fill(opened, (x, 2, x + 3, 13), iron)
    # Moedas iluminando o interior.
    fill(opened, (6, 13, 38, 20), gold_dark)
    for y, inset in zip(range(11, 18), (10, 7, 5, 3, 2, 1, 1)):
        fill(opened, (5 + inset, y, 39 - inset, y + 1), gold)
    rng = np.random.default_rng(7)
    for _ in range(18):
        x, y = int(rng.integers(8, 36)), int(rng.integers(12, 19))
        fill(opened, (x, y, x + 2, y + 1), gold_light)
    body(opened)

    for name, art in (("bau_fechado", closed), ("bau_aberto", opened)):
        big = np.repeat(np.repeat(art, 2, axis=0), 2, axis=1)
        save(compose([(scaled(Image.fromarray(big, "RGBA"), 1.0), 0, 0)]), "comum", name)


def build_paths() -> None:
    for biome in PAVING:
        for side in [*range(6), None]:
            suffix = "" if side is None else f"_{side}"
            floor, curb = road_pieces(biome, side)
            save(floor, biome, f"estrada{suffix}")
            save(curb, biome, f"estrada_borda{suffix}")
            save(trail_piece(biome, side), biome, f"trilha{suffix}")
        build_edges(biome)
    build_chests()
    for side in range(6):
        save(side_piece(BRIDGE, "ponte", side), "comum", f"ponte_{side}")
    save(side_piece(BRIDGE, "ponte", None), "comum", "ponte")


def main() -> None:
    sheets ={biome: Sheet(REFS / f"{biome}.jpg") for biome in CUTS}
    for biome, boxes in CUTS.items():
        sheet = sheets[biome]
        cuts = {
            name: sheet.cut(box, by_edges=name.startswith("farol") or (biome == "selva" and name.startswith(("cristal", "cogumelo"))))
            for name, box in boxes.items()
        }
        for name, (source, x, y) in TILES[biome].items():
            tint = WATER_TINT.get(biome, (1.0, 1.0, 1.0)) if name.startswith("agua") else (1.0, 1.0, 1.0)
            contrast = FIELD_CONTRAST if name.startswith("campo") else 1.0
            save(make_tile(sheets[source], x, y, tint=tint, contrast=contrast), biome, name)
        source, x, y = TILES[biome]["campo_a"]
        save(make_tile(sheets[source], x, y, wall_only=True), biome, "parede")
        build_props(biome, cuts)
    build_paths()
    print("biomas gerados em", OUT)


if __name__ == "__main__":
    main()
