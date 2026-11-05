"""Gera as texturas contínuas do chão das expedições, a partir das peças de cada bioma.

O chão não tem desenho de casa: cada textura se repete sem emenda e é desenhada na
posição do mundo. As cores vêm da arte já pronta, então o bioma não muda de paleta.

Rodar na raiz do projeto: python tools/build_ground.py (precisa de pillow e numpy).
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path("assets/biomes")
BIOMES = ["floresta", "selva", "neve", "deserto"]
ART_SIZE = 512  # em pixels de arte; a imagem final tem o dobro, como os personagens
SCALE = 2
TONES = 7
# nome da textura: (peças de origem, tamanho das manchas, esticada na horizontal, grão, contraste)
KINDS = {
    "solo": (["campo_a", "campo_b"], 30.0, 1.0, 0.25, 0.72),
    "sombra_solo": (["sombra"], 24.0, 1.0, 0.25, 0.42),
    "agua_solo": (["agua_a", "agua_b"], 14.0, 4.0, 0.12, 0.8),
    "trilha_solo": (["trilha"], 12.0, 1.0, 0.3, 0.2),
    "estrada_solo": (["estrada"], 14.0, 1.0, 0.3, 0.22),
}
HEX_TOP_LIMIT = 200  # abaixo disso a peça mostra a lateral, que não é chão


def periodic_noise(size, blob, stretch, rng):
    """Ruído que se repete sem emenda: filtra ruído branco nas frequências certas."""
    white = np.fft.fft2(rng.standard_normal((size, size)))
    fy = np.fft.fftfreq(size)[:, None] * size
    fx = np.fft.fftfreq(size)[None, :] * size * stretch
    radius = np.sqrt(fx * fx + fy * fy)
    cycles = size / blob
    gain = np.exp(-((radius / cycles) ** 2)) * (radius > 0)
    out = np.fft.ifft2(white * gain).real
    return (out - out.mean()) / (out.std() + 1e-9)


def rank(values):
    """Troca cada valor pela sua posição, de 0 a 1: as cores saem na proporção certa."""
    order = values.ravel().argsort().argsort().reshape(values.shape)
    return order / float(values.size - 1)


def source_tones(biome, pieces):
    pixels = []
    for piece in pieces:
        art = np.array(Image.open(ROOT / biome / f"{piece}.png").convert("RGBA"))[:HEX_TOP_LIMIT]
        solid = art[art[..., 3] > 240][..., :3]
        pixels.append(solid)
    pixels = np.concatenate(pixels).astype(float)
    light = pixels.sum(1)
    # Sem os extremos: contornos e brilhos da peça não fazem parte do piso.
    low, high = np.percentile(light, [6, 94])
    pixels = pixels[(light >= low) & (light <= high)]
    pixels = pixels[pixels.sum(1).argsort()]
    return np.array([band.mean(0) for band in np.array_split(pixels, TONES)])


def build(biome, name, pieces, blob, stretch, grain, contrast, seed):
    rng = np.random.default_rng(seed)
    tones = source_tones(biome, pieces)
    middle = tones[TONES // 2]
    tones = middle + (tones - middle) * contrast
    wide = periodic_noise(ART_SIZE, blob, stretch, rng)
    fine = periodic_noise(ART_SIZE, blob / 4.0, stretch, rng)
    speck = periodic_noise(ART_SIZE, 1.6, 1.0, rng)
    value = rank(wide + 0.5 * fine + grain * speck)
    index = np.minimum((value * TONES).astype(int), TONES - 1)
    image = tones[index].round().astype(np.uint8)
    out = Image.fromarray(image, "RGB").resize((ART_SIZE * SCALE,) * 2, Image.NEAREST)
    out.save(ROOT / biome / f"{name}.png", optimize=True)


def build_cobbles():
    """Calçada da Cidade-Farol: pedras soltas que se repetem sem emenda, nas cores da peça antiga."""
    art = np.array(Image.open("assets/town/calcada.png").convert("RGBA"))[:HEX_TOP_LIMIT]
    pixels = art[art[..., 3] > 240][..., :3].astype(float)
    pixels = pixels[pixels.sum(1).argsort()]
    mortar = pixels[: len(pixels) // 8].mean(0)
    stones = np.array([band.mean(0) for band in np.array_split(pixels[len(pixels) // 4 :], 5)])
    rng = np.random.default_rng(55)
    grid = 36  # pedras por lado
    step = ART_SIZE / grid
    points = []
    tones = []
    for gy in range(grid):
        for gx in range(grid):
            spot = (np.array([gx + (gy % 2) * 0.5, gy]) + rng.uniform(-0.28, 0.28, 2)) * step
            points.append(spot)
            tones.append(stones[rng.integers(len(stones))])
    points = np.array(points)
    tones = np.array(tones)
    axis = np.arange(ART_SIZE) + 0.5
    px, py = np.meshgrid(axis, axis)
    best = np.full((ART_SIZE, ART_SIZE), np.inf)
    second = best.copy()
    owner = np.zeros((ART_SIZE, ART_SIZE), int)
    for i, (x, y) in enumerate(points):
        dx = np.abs(px - x)
        dy = np.abs(py - y)
        dist = np.hypot(np.minimum(dx, ART_SIZE - dx), np.minimum(dy, ART_SIZE - dy))
        closer = dist < best
        second = np.where(closer, best, np.minimum(second, dist))
        owner = np.where(closer, i, owner)
        best = np.where(closer, dist, best)
    image = tones[owner]
    image[(second - best) < 1.6] = mortar
    shade = periodic_noise(ART_SIZE, 40.0, 1.0, rng)[..., None] * 5.0
    out = Image.fromarray(np.clip(image + shade, 0, 255).round().astype(np.uint8), "RGB")
    out.resize((ART_SIZE * SCALE,) * 2, Image.NEAREST).save("assets/town/calcada_solo.png", optimize=True)


def build_edge_noise():
    """Manchas que recortam a fronteira entre dois terrenos, para ela não seguir a grade."""
    rng = np.random.default_rng(77)
    value = rank(periodic_noise(256, 24.0, 1.0, rng) + 0.6 * periodic_noise(256, 7.0, 1.0, rng))
    Image.fromarray((value * 255).astype(np.uint8), "L").save(ROOT / "comum" / "ruido_chao.png", optimize=True)


def main():
    for b, biome in enumerate(BIOMES):
        for k, (name, (pieces, blob, stretch, grain, contrast)) in enumerate(KINDS.items()):
            build(biome, name, pieces, blob, stretch, grain, contrast, 1000 + b * 10 + k)
    build_cobbles()
    build_edge_noise()


if __name__ == "__main__":
    main()
