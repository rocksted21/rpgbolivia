"""Gera a animação parada (idle) do Faroleiro a partir de assets/town/morador_guarda.png.
Respiração (tronco sobe 1 px), lanterna balançando, chama tremulando e piscada.
Saída: folha horizontal de N quadros, cada um no mesmo tamanho do PNG original.

Uso: python tools/build_npc_idle.py assets/town/morador_guarda.png assets/town/anim/morador_guarda_idle.png
O jogo acha a folha sozinho (Town.IDLE_ROOT); N tem de bater com Town.IDLE_FRAMES.
As caixas (LANT, GLASS, EYES...) são da arte do Faroleiro: outro morador precisa das dele."""
import math, sys
from PIL import Image

SRC = sys.argv[1]; OUT = sys.argv[2]
N = 24
big = Image.open(SRC).convert("RGBA")
W, H = big.size                        # 110 x 348 (arte em 2x)
art = big.resize((W // 2, H // 2), Image.NEAREST)   # grade real: 55 x 174
w, h = art.size

LANT = (0, 63, 16, 81)      # caixa da lanterna (x0,y0,x1,y1) em pixels da arte
PIVOT_Y = 62                # alça presa na mão
WAIST = 74                  # linha da barra do casaco; abaixo disso as pernas ficam paradas
GLASS = (5, 67, 12, 75)     # vidro com a chama
EYES = [(17, 27, 21, 31), (28, 27, 33, 31)]

def is_lantern(x, y):
    return LANT[0] <= x < LANT[2] and LANT[1] <= y < LANT[3]

# separa lanterna do corpo
body = art.copy(); lant = Image.new("RGBA", art.size, (0, 0, 0, 0))
bp, lp, ap = body.load(), lant.load(), art.load()
for y in range(LANT[1], LANT[3]):
    for x in range(LANT[0], LANT[2]):
        if ap[x, y][3]:
            lp[x, y] = ap[x, y]; bp[x, y] = (0, 0, 0, 0)

# cores da chama (original -> por estado)
FL = {(219,223,212): "core", (213,202,191): "core2", (253,193,163): "hi", (222,164,123): "mid", (196,115,93): "lo"}
STATES = {
 "dim":    {"core": (250,214,150), "core2": (238,190,130), "hi": (232,160,96),  "mid": (204,124,74), "lo": (160,86,66)},
 "normal": {"core": (255,240,196), "core2": (252,222,160), "hi": (250,190,112), "mid": (226,146,80), "lo": (188,102,68)},
 "bright": {"core": (255,252,226), "core2": (255,238,184), "hi": (255,214,132), "mid": (244,172,88), "lo": (214,122,70)},
}
FLICKER = "nbndnbbndnbnndbnbndnnbdn"
FLICKER = [{"n": "normal", "b": "bright", "d": "dim"}[c] for c in FLICKER]

def breath(f):        # sobe 1 px no meio do ciclo (inspira)
    return -1 if 7 <= f <= 17 else 0

def sway(f):          # desloca o fundo da lanterna até 2 px
    return round(2 * math.sin(2 * math.pi * f / N))

BLINK = {20: "half", 21: "closed", 22: "half"}
SKIN, LID, LASH = (215,136,117), (173,92,82), (93,43,58)

frames = []
for f in range(N):
    fr = Image.new("RGBA", art.size, (0, 0, 0, 0)); fp = fr.load()
    b = breath(f)
    # corpo: acima da cintura sobe b; a linha da cintura repete para não abrir buraco
    for y in range(h):
        for x in range(w):
            c = bp[x, y]
            if not c[3]: continue
            ny = y + b if y <= WAIST else y
            fp[x, ny] = c
    if b:
        for x in range(w):
            if not fp[x, WAIST][3] and bp[x, WAIST][3]: fp[x, WAIST] = bp[x, WAIST]
    # piscada
    st = BLINK.get(f)
    if st:
        for (x0, y0, x1, y1) in EYES:
            for x in range(x0, x1):
                if st == "half":
                    fp[x, y0 + 1 + b] = LID
                else:
                    fp[x, y0 + 1 + b] = SKIN; fp[x, y0 + 2 + b] = LID; fp[x, y0 + 3 + b] = LASH
    # lanterna: cisalhamento a partir da alça + sobe com a mão + chama
    s = sway(f); pal = STATES[FLICKER[f]]
    for y in range(LANT[1], LANT[3]):
        dx = round(s * (y - PIVOT_Y) / (LANT[3] - 1 - PIVOT_Y))
        for x in range(LANT[0], LANT[2]):
            c = lp[x, y]
            if not c[3]: continue
            if GLASS[0] <= x < GLASS[2] and GLASS[1] <= y < GLASS[3] and c[:3] in FL:
                c = pal[FL[c[:3]]] + (255,)
            fp[x + dx, y + b] = c
    # chama mais alta nos quadros fortes
    if FLICKER[f] == "bright":
        y = 70; dx = round(s * (y - PIVOT_Y) / (LANT[3] - 1 - PIVOT_Y))
        fp[8 + dx, y + b] = pal["core2"] + (255,)
    frames.append(fr.resize((W, H), Image.NEAREST))

sheet = Image.new("RGBA", (W * N, H), (0, 0, 0, 0))
for i, fr in enumerate(frames): sheet.paste(fr, (i * W, 0))
sheet.save(OUT)
print("ok", sheet.size, "flicker", FLICKER[:4])
