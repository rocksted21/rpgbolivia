# Gera assets/biomes/comum/lanterna_apagada.png e lanterna_acesa.png (pixel art, 3x).
import sys
from PIL import Image
W, H, S = 30, 72, 3
OUT = (0x1a, 0x16, 0x26, 255)
C = {
 'stone_d': (0x6e, 0x5f, 0x6e), 'stone': (0x9a, 0x8a, 0x92), 'stone_l': (0xc4, 0xb6, 0xb6),
 'iron_d': (0x22, 0x26, 0x38), 'iron': (0x36, 0x3c, 0x55), 'iron_l': (0x58, 0x62, 0x82),
 'brass_d': (0x8a, 0x5a, 0x22), 'brass': (0xc8, 0x8a, 0x30), 'brass_l': (0xf0, 0xc8, 0x60),
 'wine_d': (0x5e, 0x1e, 0x34), 'wine': (0x8e, 0x2e, 0x4a), 'wine_l': (0xb8, 0x50, 0x68),
}
def draw(lit):
    px = {}
    def rect(x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                px[(x, y)] = col
    def shade_rect(x0, y0, x1, y1, base):
        rect(x0, y0, x1, y1, C[base])
        for y in range(y0, y1 + 1):
            px[(x0, y)] = C[base + '_l']
            px[(x1, y)] = C[base + '_d']
            if x1 - x0 > 3: px[(x1 - 1, y)] = C[base + '_d']
    cx = 15
    # base de pedra (dois degraus)
    shade_rect(cx - 7, 66, cx + 6, 70, 'stone')
    shade_rect(cx - 5, 62, cx + 4, 65, 'stone')
    for x in range(cx - 7, cx + 7): px[(x, 66)] = C['stone_l']
    for x in range(cx - 5, cx + 5): px[(x, 62)] = C['stone_l']
    px[(cx - 3, 68)] = C['stone_d']; px[(cx + 2, 68)] = C['stone_d']; px[(cx - 1, 64)] = C['stone_d']
    # poste de ferro
    shade_rect(cx - 3, 57, cx + 2, 61, 'iron')       # pé
    shade_rect(cx - 2, 26, cx + 1, 56, 'iron')       # haste
    shade_rect(cx - 3, 42, cx + 2, 44, 'iron')       # anel
    px[(cx - 2, 43)] = C['brass_l']; px[(cx - 1, 43)] = C['brass']; px[(cx, 43)] = C['brass']; px[(cx + 1, 43)] = C['brass_d']
    shade_rect(cx - 4, 24, cx + 3, 26, 'iron')       # suporte da lanterna
    # volutas do suporte
    for (x, y) in [(cx - 5, 25), (cx - 6, 26), (cx - 6, 27), (cx - 5, 28), (cx + 4, 25), (cx + 5, 26), (cx + 5, 27), (cx + 4, 28)]:
        px[(x, y)] = C['iron']
    # caixa da lanterna: base de latão
    shade_rect(cx - 6, 21, cx + 5, 23, 'brass')
    # vidros
    for y in range(10, 21):
        for x in range(cx - 5, cx + 5):
            if lit:
                d = abs(x - (cx - 0.5)) / 5.0 + abs(y - 15) / 8.0
                col = (0xff, 0xf6, 0xc8) if d < 0.45 else (0xff, 0xd8, 0x6a) if d < 0.8 else (0xf0, 0x9a, 0x36)
            else:
                col = (0x2c, 0x34, 0x4a) if (x + y) % 7 else (0x3a, 0x44, 0x5e)
                if x == cx - 4 and 11 <= y <= 15: col = (0x7a, 0x8c, 0xa8)  # reflexo
                if x == cx - 3 and 11 <= y <= 13: col = (0x5a, 0x6a, 0x88)
            px[(x, y)] = col
    if lit:  # chama
        for (x, y, col) in [(cx - 1, 14, (255, 255, 255)), (cx, 14, (255, 255, 240)), (cx - 1, 15, (255, 250, 220)), (cx, 15, (255, 250, 220)), (cx - 1, 13, (255, 240, 180)), (cx - 1, 16, (255, 200, 90)), (cx, 16, (255, 200, 90))]:
            px[(x, y)] = col
    else:  # pavio apagado
        px[(cx - 1, 17)] = C['iron_d']; px[(cx - 1, 16)] = (0x55, 0x55, 0x60)
    for x in (cx - 6, cx - 1, cx + 4 + 1):  # grades
        for y in range(10, 21):
            px[(x, y)] = C['brass_d'] if x != cx - 6 else C['brass']
    # telhado vinho, como o farol
    for i, y in enumerate(range(4, 10)):
        half = 2 + i
        for x in range(cx - half - 1, cx + half + 1):
            px[(x, y)] = C['wine']
        px[(cx - half - 1, y)] = C['wine_l']; px[(cx + half, y)] = C['wine_d']
    for x in range(cx - 8, cx + 8): px[(x, 9)] = C['brass']
    px[(cx - 8, 9)] = C['brass_l']; px[(cx + 7, 9)] = C['brass_d']
    px[(cx - 2, 5)] = C['wine_l']; px[(cx - 3, 6)] = C['wine_l']  # brilho do telhado
    # pináculo
    rect(cx - 1, 1, cx, 3, C['brass']); px[(cx - 1, 1)] = C['brass_l']
    # contorno
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for (x, y), col in px.items():
        img.putpixel((x, y), (*col, 255))
    out = img.copy()
    for y in range(H):
        for x in range(W):
            if img.getpixel((x, y))[3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and img.getpixel((nx, ny))[3]:
                        out.putpixel((x, y), OUT); break
    # O ponto de apoio das artes do mapa é o centro da imagem: os pés da lanterna ficam no meio.
    tall = Image.new('RGBA', (W, H * 2), (0, 0, 0, 0))
    tall.alpha_composite(out, (0, 0))
    return tall.resize((W * S, H * 2 * S), Image.NEAREST)
root = sys.argv[1]
draw(False).save(root + '/lanterna_apagada.png')
draw(True).save(root + '/lanterna_acesa.png')
