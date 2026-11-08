"""Ferreiro martelando: ergue o martelo por trás da cabeça, desce na lâmina em brasa sobre a
bigorna e solta faíscas. Gera assets/town/anim/morador_ferreiro_idle.png (24 quadros, dois
golpes por volta). O quadro cresce igual dos dois lados, então o pé continua no centro.

Uso: python tools/build_smith_work.py <pasta assets/town>
Coordenadas em pixels da arte (PNG / 2), medidas em morador_ferreiro.png.
"""
import math, os, random, sys
from PIL import Image

N = 24
PX, PY = 14, 10                 # sobra nos lados (pixels da arte) para a bigorna e o martelo erguido
HEAD_BOX = (2, 6, 15, 31)       # cabeça do martelo no desenho parado
HANDLE_BOX = (13, 15, 19, 25)   # pedaço do cabo entre o martelo e a orelha
ARM_X, ARM_Y = (46, 30), 57     # braço direito (com a mão e a ponta do cabo): x >= 46, y 30..56
HAND_BOX = (56, 30, 71, 38)     # o punho fechado
SHOULDER = (49, 43)
UPPER, FORE = 13, 11
HANDLE = 13                     # da mão até o meio do martelo             # braço e antebraço
CONTACT = (73, 66)              # onde o martelo bate (em cima da lâmina)
ANVIL_TOP = 72                  # a lâmina termina na linha 71: a bigorna começa embaixo

OUTLINE = (40, 22, 30)
SKIN = (240, 160, 128); SKIN_DARK = (210, 112, 92); SKIN_LIGHT = (252, 186, 150)
SLEEVE = (229, 216, 182); SLEEVE_DARK = (178, 150, 122)
WOOD = (122, 78, 52); WOOD_DARK = (84, 50, 38)
SPARK = [(255, 248, 200), (255, 222, 120), (255, 170, 70), (236, 110, 50)]

# Os quadros de um golpe (12): mão (x, y), ângulo do cabo (mão -> martelo, graus; 0 = direita),
# martelo atrás do corpo?, faíscas (0 nenhuma, 1 batida, 2 voando, 3 caindo)
STRIKE = [
    ((60, 55), 0, False, 3),     # descansando na lâmina
    ((60, 55), 0, False, 0),
    ((60, 47), -35, False, 0),   # ergue
    ((59, 37), -70, False, 0),
    ((59, 28), -100, True, 0),
    ((61, 22), -118, True, 0),   # no alto, por trás da cabeça
    ((61, 22), -121, True, 0),
    ((62, 32), -60, False, 0),   # desce
    ((61, 46), -18, False, 0),
    ((60, 55), 0, False, 1),     # BATE
    ((60, 53), -6, False, 2),    # quica
    ((60, 55), 0, False, 0),
]


def art_of(path):
    im = Image.open(path).convert("RGBA")
    return im.resize((im.width // 2, im.height // 2), Image.NEAREST)


def rotate_chunk(chunk, deg):
    return chunk.rotate(-deg, resample=Image.NEAREST, expand=True)


def line_pixels(a, b):
    (x0, y0), (x1, y1) = a, b
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    return [(round(x0 + (x1 - x0) * t / max(1, n - 1)), round(y0 + (y1 - y0) * t / max(1, n - 1))) for t in range(n)]


def thick(img, a, b, r, color):
    p = img.load(); w, h = img.size
    for (x, y) in line_pixels(a, b):
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r + r and 0 <= x + dx < w and 0 <= y + dy < h:
                    p[x + dx, y + dy] = color + (255,)


def outline(img):
    """Contorno escuro em volta de tudo que foi desenhado na camada."""
    p = img.load(); w, h = img.size
    edge = []
    for y in range(h):
        for x in range(w):
            if p[x, y][3] == 0 and any(0 <= x + dx < w and 0 <= y + dy < h and p[x + dx, y + dy][3] > 0
                                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge.append((x, y))
    for q in edge:
        p[q] = OUTLINE + (255,)


def elbow(s, hnd):
    """Cotovelo pelo jeito de dois ossos, dobrando para baixo/fora."""
    dx, dy = hnd[0] - s[0], hnd[1] - s[1]
    d = min(math.hypot(dx, dy), UPPER + FORE - 0.01)
    a = math.atan2(dy, dx)
    cos_b = (UPPER ** 2 + d ** 2 - FORE ** 2) / (2 * UPPER * d)
    b = math.acos(max(-1, min(1, cos_b)))
    options = [(s[0] + UPPER * math.cos(a + k * b), s[1] + UPPER * math.sin(a + k * b)) for k in (1, -1)]
    if hnd[1] > s[1]:  # mão abaixo do ombro: o braço desce, cotovelo embaixo
        return max(options, key=lambda e: e[1])
    return max(options, key=lambda e: e[0])  # braço erguido: cotovelo para fora do corpo (à direita)


def build(root):
    art = art_of(os.path.join(root, "morador_ferreiro.png"))
    w, h = art.size
    W, H = w + 2 * PX, h + 2 * PY
    ap = art.load()

    # peças tiradas do desenho parado
    head = art.crop(HEAD_BOX)
    hand = art.crop(HAND_BOX)
    body = art.copy(); bp = body.load()
    for y in range(HEAD_BOX[1], HEAD_BOX[3]):
        for x in range(HEAD_BOX[0], HEAD_BOX[2]):
            bp[x, y] = (0, 0, 0, 0)
    for y in range(8, 14):  # beirada do martelo que encostava no boné
        for x in range(13, 19):
            bp[x, y] = (0, 0, 0, 0)
    for y in range(HANDLE_BOX[1], HANDLE_BOX[3]):
        for x in range(HANDLE_BOX[0], HANDLE_BOX[2]):
            c = bp[x, y]
            if c[3] and not (c[0] > 180 and c[1] > 110):  # cabo e contorno do cabo, sem pegar a orelha
                bp[x, y] = (0, 0, 0, 0)
    for y in range(ARM_X[1], ARM_Y):
        for x in range(ARM_X[0], w):
            c = bp[x, y]
            if c[3] and not (y >= 49 and x >= 59 and c[0] > 170 and c[0] - c[1] > 60):  # deixa a faísca da lâmina
                bp[x, y] = (0, 0, 0, 0)
    # sobras soltas do martelo e do braço (pedacinhos que não encostam no corpo) somem
    seen = set()
    for y in range(h):
        for x in range(w):
            if bp[x, y][3] and (x, y) not in seen:
                comp = [(x, y)]; seen.add((x, y)); todo = [(x, y)]
                while todo:
                    a, b = todo.pop()
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        q = (a + dx, b + dy)
                        if 0 <= q[0] < w and 0 <= q[1] < h and q not in seen and bp[q][3]:
                            seen.add(q); comp.append(q); todo.append(q)
                if len(comp) < 30 and not any(59 <= qx and 49 <= qy <= 60 for qx, qy in comp):
                    for q in comp:
                        bp[q] = (0, 0, 0, 0)
    # fecha o contorno onde o braço e o martelo saíram
    edge = []
    for y in range(h):
        for x in range(w):
            if bp[x, y][3] == 0 and any(0 <= x + dx < w and bp[x + dx, y][3] and sum(bp[x + dx, y][:3]) > 150 for dx in (-1, 1)) \
                    and (x >= ARM_X[0] - 1 or x <= HANDLE_BOX[2]):
                edge.append((x, y))
    for q in edge:
        bp[q] = OUTLINE + (255,)

    anvil = make_anvil(root)
    head_flip = head.transpose(Image.FLIP_LEFT_RIGHT)  # o martelo agora fica à direita da mão

    rng = random.Random(7)
    rays = [(rng.uniform(-175, -5), rng.uniform(0.8, 1.4)) for _ in range(14)]
    frames = []
    for f in range(N):
        hand_at, deg, behind, spark = STRIKE[f % 12]
        ox, oy = PX, PY
        frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        tool = Image.new("RGBA", (W, H), (0, 0, 0, 0))  # braço + martelo
        hx, hy = hand_at[0] + ox, hand_at[1] + oy
        d = (math.cos(math.radians(deg)), math.sin(math.radians(deg)))
        tip = (hx + d[0] * HANDLE, hy + d[1] * HANDLE)
        butt = (hx - d[0] * 4, hy - d[1] * 4)
        thick(tool, butt, tip, 1, WOOD_DARK)
        for q in line_pixels(butt, tip):
            tool.putpixel(q, WOOD + (255,))
        hd = rotate_chunk(head_flip, deg)
        tool.alpha_composite(hd, (round(tip[0] - hd.width / 2), round(tip[1] - hd.height / 2)))
        arm = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        s = (SHOULDER[0] + ox, SHOULDER[1] + oy)
        e = elbow(s, (hx, hy))
        # antebraço primeiro; o bíceps vem por cima e desce inteiro até o cotovelo
        thick(arm, e, (hx, hy), 4, OUTLINE); thick(arm, e, (hx, hy), 3, SKIN)
        for q in line_pixels((e[0] - 1, e[1] - 2), (hx - 1, hy - 2)):
            arm.putpixel(q, SKIN_LIGHT + (255,))
        mid = (s[0] + (e[0] - s[0]) * 0.5, s[1] + (e[1] - s[1]) * 0.5)
        thick(arm, s, mid, 5, OUTLINE); thick(arm, mid, e, 4, OUTLINE)
        thick(arm, s, mid, 4, SKIN); thick(arm, mid, e, 3, SKIN)
        for q in line_pixels((s[0] + 2, s[1] + 2), (e[0] + 2, e[1])):  # sombra do lado de baixo
            arm.putpixel(q, SKIN_DARK + (255,))
        cap = (s[0] + (e[0] - s[0]) * 0.08, s[1] + (e[1] - s[1]) * 0.08)
        thick(arm, (s[0] - 1, s[1] - 2), cap, 4, OUTLINE); thick(arm, (s[0] - 1, s[1] - 2), cap, 3, SLEEVE)  # manga dobrada, só no ombro
        outline(arm)
        arm.alpha_composite(hand, (round(hx - 6), round(hy - 4)))
        if behind:
            frame.alpha_composite(tool)
        frame.alpha_composite(body, (ox, oy))
        frame.alpha_composite(anvil, (ox + 50, oy + ANVIL_TOP))
        if not behind:
            outline(tool)
            frame.alpha_composite(tool)
        frame.alpha_composite(arm)
        _ember(frame, ox, oy, spark)
        _sparks(frame, (CONTACT[0] + ox, CONTACT[1] + oy), rays, spark)
        frames.append(frame.resize((W * 2, H * 2), Image.NEAREST))
    sheet = Image.new("RGBA", (W * 2 * N, H * 2), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.paste(fr, (i * W * 2, 0))
    return sheet


def make_anvil(root):
    """A bigorna da cidade (bigorna_b), reduzida para caber embaixo da lâmina."""
    a = art_of(os.path.join(root, "bigorna_b.png"))
    a = a.crop(a.getbbox())
    k = 20 / a.height
    small = a.resize((max(1, round(a.width * k)), 20), Image.NEAREST)
    return small


def _ember(frame, ox, oy, spark):
    """A lâmina acende mais forte na hora da batida."""
    if spark not in (1, 2):
        return
    p = frame.load()
    for y in range(52 + oy, 73 + oy):
        for x in range(48 + ox, 77 + ox):
            r, g, b, a = p[x, y]
            if a and r > 190 and r - g > 75:
                k = 0.45 if spark == 1 else 0.25
                p[x, y] = (min(255, int(r + (255 - r) * k)), min(255, int(g + (236 - g) * k)), min(255, int(b + (180 - b) * k)), a)


def _sparks(frame, c, rays, stage):
    if not stage:
        return
    p = frame.load(); w, h = frame.size
    dist = {1: (3, 8), 2: (7, 13), 3: (12, 16)}[stage]
    for i, (ang, speed) in enumerate(rays):
        if stage == 3 and i % 3:
            continue
        for k, rr in enumerate(range(dist[0], dist[1] + 1, 2)):
            r = rr * speed
            drop = 0 if stage == 1 else (stage - 1) * 2  # caem um pouco
            x = round(c[0] + r * math.cos(math.radians(ang)))
            y = round(c[1] + r * math.sin(math.radians(ang)) + drop)
            if 0 <= x < w and 0 <= y < h:
                p[x, y] = SPARK[min(len(SPARK) - 1, k + stage - 1)] + (255,)


if __name__ == "__main__":
    root = sys.argv[1]
    out = os.path.join(root, "anim", "morador_ferreiro_idle.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet = build(root)
    sheet.save(out)
    print("ok", out, sheet.size)
