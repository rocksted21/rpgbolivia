#!/usr/bin/env python3
"""Gera assets/menu a partir de referencias/menu.jpg.

Tudo o que muda no jogo sai da imagem (textos, números, botão aceso, chamas, cursor): o
menu desenha isso por cima. Rodar da raiz do projeto: python tools/build_menu.py
Precisa de: pip install pillow numpy opencv-python-headless
"""
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "referencias" / "menu.jpg"
OUT = ROOT / "assets" / "menu"

# Corte para 16:9 e tamanho final. Em scripts/main_menu.gd, ART_LEFT e ART_SCALE usam os mesmos números.
LEFT, RIGHT = 10, 2566
SIZE = (1920, 1080)

STEP = 137  # distância entre botões
FIRST = 546  # centro do primeiro botão (Jornada Solo)
BUTTONS = [FIRST + STEP * i for i in range(6)]
TEXT_LEFT, TEXT_RIGHT = 312, 800
HALF_TEXT = 44
# Área do botão aceso e das suas chamas.
GLOW = (250, 430, 945, 626)
ICON = (246, FIRST, 60)  # o ícone do botão 1 fica como está: centro x, centro y e raio
FRAME = (262, 625, 856, 746)  # moldura apagada do botão 2, que substitui a do botão 1
PANEL_CLEAN_ROW = 752
PANEL_RIGHT = 858  # logo depois da borda dourada do painel
LOGO_RIGHT = 690  # acima do botão, só há faíscas à direita do logotipo
LOGO_BOTTOM = 470


def erase(image: np.ndarray, box, threshold=66, grow=7, radius=6) -> None:
    """Tira letras claras de um fundo escuro e alisa o que sobrou."""
    x0, y0, x1, y1 = box
    crop = image[y0:y1, x0:x1]
    luma = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    mask = (luma > threshold).astype(np.uint8) * 255
    mask = cv2.dilate(mask, np.ones((grow, grow), np.uint8))
    fixed = cv2.inpaint(crop, mask, radius, cv2.INPAINT_TELEA)
    smooth = cv2.GaussianBlur(fixed, (0, 0), 7)
    soft = cv2.GaussianBlur((mask > 0).astype(np.float32), (0, 0), 5)[..., None]
    image[y0:y1, x0:x1] = fixed * (1 - soft) + smooth * soft


def icon_mask(shape, x0, y0) -> np.ndarray:
    ys, xs = np.mgrid[y0:y0 + shape[0], x0:x0 + shape[1]]
    return np.hypot(xs - ICON[0], ys - ICON[1]) <= ICON[2]


def blend_patch(image: np.ndarray, source_box, target_xy, feather=14, soft_top=False) -> None:
    """Copia um pedaço da imagem para outro lugar, com a borda suave (a de cima só se pedir)."""
    x0, y0, x1, y1 = source_box
    tx, ty = target_xy
    w, h = x1 - x0, y1 - y0
    alpha = np.zeros((h, w), np.float32)
    alpha[feather if soft_top else 0:-feather, feather:-feather] = 1.0
    alpha = cv2.GaussianBlur(alpha, (0, 0), feather / 2.0)[..., None]
    if not soft_top:
        alpha[:feather // 2] = alpha[feather // 2]
    image[ty:ty + h, tx:tx + w] = image[y0:y1, x0:x1] * alpha + image[ty:ty + h, tx:tx + w] * (1 - alpha)


def lit_button(original: np.ndarray, clean: np.ndarray) -> np.ndarray:
    """O botão aceso sem texto e sem cursor, transparente onde é igual ao botão apagado."""
    x0, y0, x1, y1 = GLOW
    crop = original[y0:y1, x0:x1].copy()
    # Letras e cursor saem: o miolo é refeito com as cores de cima e de baixo dele.
    top, bottom = FIRST - 48 - y0, FIRST + 52 - y0
    left, right = TEXT_LEFT - x0, 815 - x0
    edge_top = cv2.GaussianBlur(crop[top - 3:top, left:right].astype(np.float32).mean(axis=0, keepdims=True), (0, 0), 16)[0]
    edge_bottom = cv2.GaussianBlur(crop[bottom:bottom + 3, left:right].astype(np.float32).mean(axis=0, keepdims=True), (0, 0), 16)[0]
    ramp = np.linspace(0, 1, bottom - top)[:, None, None]
    crop[top:bottom, left:right] = edge_top[None] * (1 - ramp) + edge_bottom[None] * ramp
    difference = np.abs(crop.astype(np.int32) - clean[y0:y1, x0:x1]).max(axis=2).astype(np.float32)
    alpha = np.clip((difference - 12.0) / 30.0, 0.0, 1.0)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 1.2)
    # O interior fica opaco; só as chamas e as faíscas se desfazem nas pontas.
    alpha[top:bottom, left:right] = 1.0
    alpha[icon_mask(alpha.shape, x0, y0)] = 0.0
    return np.dstack([crop[..., ::-1], (alpha * 255).astype(np.uint8)])


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    original = cv2.imread(str(SOURCE))
    clean = original.copy()

    # Botão 1 apagado: painel limpo em volta e a moldura do botão 2 no lugar.
    gx0, gy0, gx1, gy1 = GLOW
    row = clean[PANEL_CLEAN_ROW - 3:PANEL_CLEAN_ROW + 3].mean(axis=0)
    fill = np.broadcast_to(row[gx0:PANEL_RIGHT], (gy1 - gy0, PANEL_RIGHT - gx0, 3)).copy()
    keep = icon_mask(fill.shape, gx0, gy0)
    keep[:LOGO_BOTTOM - gy0, :LOGO_RIGHT - gx0] = True
    clean[gy0:gy1, gx0:PANEL_RIGHT][~keep] = fill[~keep]
    # Fora do painel: um pedaço de nuvem de baixo cobre as chamas e o marcador.
    height = gy1 + 12 - gy0
    source_top = gy1 + 20
    blend_patch(clean, (PANEL_RIGHT - 30, source_top, gx1 + 50, source_top + height), (PANEL_RIGHT - 30, gy0), feather=26, soft_top=True)
    # Faixa da borda dourada, copiada do trecho de baixo do painel.
    clean[gy0:gy1 + 12, PANEL_RIGHT - 16:PANEL_RIGHT + 2] = original[source_top:source_top + height, PANEL_RIGHT - 16:PANEL_RIGHT + 2]
    fx0, fy0, fx1, fy1 = FRAME
    frame = clean[fy0:fy1, fx0:fx1]
    target = clean[fy0 - STEP:fy1 - STEP, fx0:fx1]
    outside_icon = ~icon_mask(frame.shape, fx0, fy0 - STEP)
    target[outside_icon] = frame[outside_icon]

    for center in BUTTONS:
        erase(clean, (TEXT_LEFT, center - HALF_TEXT, TEXT_RIGHT, center + HALF_TEXT))
    erase(clean, (135, 28, 335, 118), threshold=75)  # contadores
    clean[28:72, 2352:2538] = (31, 26, 32)  # volume: fundo liso, o texto é do jogo
    erase(clean, (18, 1392, 480, 1432), threshold=70, grow=9)  # versão
    # Q/E e Tab só valem na expedição: saem, com um pedaço do céu ao lado.
    blend_patch(clean, (1830, 0, 2085, 112), (2085, 0))

    lit = lit_button(original, clean)
    Image.fromarray(lit, "RGBA").resize(
        (round(lit.shape[1] * SIZE[0] / (RIGHT - LEFT)), round(lit.shape[0] * SIZE[1] / clean.shape[0])), Image.Resampling.LANCZOS
    ).save(OUT / "botao_aceso.png", optimize=True)

    art = cv2.cvtColor(clean[:, LEFT:RIGHT], cv2.COLOR_BGR2RGB)
    Image.fromarray(art).resize(SIZE, Image.Resampling.LANCZOS).save(OUT / "fundo.jpg", quality=92)
    print("menu gerado em", OUT)


if __name__ == "__main__":
    main()
