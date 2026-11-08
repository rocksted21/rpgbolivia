"""Gera as animações paradas (idle) dos moradores da vila.

Cada morador vira uma folha horizontal de N quadros, cada quadro do mesmo tamanho do PNG
original (o jogo acha o pé no centro do quadro, igual à arte parada). Efeitos:
  - respiração: tudo acima da cintura sobe 1 px no meio do ciclo;
  - piscada: olhos fecham no fim do ciclo (quem tem olhos à vista);
  - chama/brilho: cores quentes (ou ciano, na alquimista) tremulam dentro de uma caixa;
  - lanterna balançando (Faroleiro).

Uso:  python tools/build_npc_idle.py <pasta assets/town> [nome ...]
      sem nomes, gera todos os moradores de CONFIG em <pasta>/anim/morador_<nome>_idle.png.
N tem de bater com Town.IDLE_FRAMES. As caixas estão em pixels da arte (PNG / 2).
"""
import math, os, sys
from PIL import Image

N = 24
BREATH = range(7, 18)                     # quadros com o peito cheio (sobe 1 px)
BLINK = {20: "half", 21: "closed", 22: "half"}
FLICKER = [{"n": "normal", "b": "bright", "d": "dim"}[c] for c in "nbndnbbndnbnndbnbndnnbdn"]

# Por morador: cintura (linha da arte; acima dela respira), olhos e efeitos (caixas x0, y0, x1, y1
# em pixels da arte). "lids" são as caixas dos olhos marcadas à mão: só pisca quem tem olho bem
# à vista; olho na sombra do chapéu, atrás de óculos ou já semicerrado fica só respirando.
CONFIG = {
    "guarda": {"waist": 74, "eye_boxes": [(17, 27, 21, 31), (28, 27, 33, 31)],
               "lantern": {"box": (0, 63, 16, 81), "pivot": 62, "glass": (5, 67, 12, 75)}},
    "a": {},                                                                  # pescador
    "b": {},                                                                  # oficial de monóculo
    "c": {},                                                                  # encapuzado
    "d": {"lids": [(16, 29, 20, 33), (26, 29, 31, 33)], "fire": [(48, 43, 57, 50)]},   # mascate
    "e": {"lids": [(10, 25, 15, 29), (21, 25, 27, 29)], "fire": [(20, 43, 25, 50)]},   # freira com vela
    "f": {},
    "g": {},                                                                  # o guia
    "h": {"lids": [(20, 32, 25, 35), (31, 32, 36, 35)], "fire": [(3, 2, 15, 22)]},     # acendedor
    "alquimista": {"lids": [(9, 28, 15, 32), (20, 28, 26, 32)], "cyan": [(14, 38, 47, 70)], "sparkle": (34, 39, 47, 50)},
    "arquivista": {"fire": [(5, 42, 11, 50)]},
    "cartografa": {"lids": [(22, 22, 29, 28), (35, 22, 40, 28)]},
    "curandeira": {"lids": [(22, 23, 29, 29), (34, 23, 39, 29)]},
    "ferreiro": {"ember": [(48, 55, 77, 72)]},
    "padeira": {},                                                            # olhos fechados, sorrindo
    "taverneira": {"lids": [(10, 31, 16, 36), (22, 31, 29, 36)]},
}


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c[:3])


def skinlike(c):
    r, g, b, a = c
    return a > 0 and r > 140 and r > g + 10 and g > b and 35 < r - b < 150


# --- olhos --------------------------------------------------------------------------

def lid_blink(fp, src, box, state, b, waist):
    """Fecha o olho da caixa: a pele de baixo sobe por cima e fica a linha dos cílios."""
    x0, y0, x1, y1 = box
    dy = b if y0 <= waist else 0
    lash = min((src[x, y] for x in range(x0, x1) for y in range(y0, y1) if src[x, y][3]), key=lum)
    line = y1 - 2 if state == "closed" else (y0 + y1) // 2
    from collections import Counter
    cheek = Counter(src[x, y] for x in range(x0 - 2, x1 + 2) for y in range(y1, y1 + 5) if skinlike(src[x, y]))
    main = cheek.most_common(1)[0][0]
    for x in range(x0, x1):
        skin = next((src[x, y] for y in range(y1, y1 + 4) if skinlike(src[x, y])), main)
        if sum(abs(skin[i] - main[i]) for i in range(3)) > 45:  # cabelo ou blush embaixo: usa a pele do rosto
            skin = main
        lid = shade(skin, 0.93)
        eye_col = [y for y in range(y0, y1) if sum(abs(src[x, y][i] - skin[i]) for i in range(3)) > 50]
        if not eye_col:
            continue
        for y in eye_col:
            if state == "closed" or y < line:
                fp[x, y + dy] = lid + (255,)
        fp[x, line + dy] = lash[:3] + (255,)


# --- brilhos ------------------------------------------------------------------------

def is_fire(c):
    r, g, b, a = c
    return a > 0 and r > 170 and r >= g and g > b and lum(c) > 120


def is_ember(c):  # ferro em brasa: vermelho forte, sem pegar a pele do braço
    r, g, b, a = c
    return a > 0 and r > 190 and r - g > 75


def is_cyan(c):
    r, g, b, a = c
    return a > 0 and g > 140 and b > 120 and r < g - 40


FIRE = {"dim": lambda c: mix(shade(c, 0.86), (200, 80, 40), 0.12),
        "normal": lambda c: c[:3],
        "bright": lambda c: mix(c, (255, 248, 214), 0.3)}
CYAN = {"dim": lambda c: shade(c, 0.82),
        "normal": lambda c: c[:3],
        "bright": lambda c: mix(c, (230, 255, 250), 0.35)}


def recolor(fp, src, box, test, table, state, dy_of):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = src[x, y]
            if test(c):
                fp[x, y + dy_of(y)] = table[state](c) + (255,)


# --- montagem -------------------------------------------------------------------------

def build(src_png, name):
    cfg = CONFIG[name]
    big = Image.open(src_png).convert("RGBA")
    W, H = big.size
    art = big.resize((W // 2, H // 2), Image.NEAREST)
    w, h = art.size
    top, bot = art.getbbox()[1], art.getbbox()[3]
    waist = cfg.get("waist", top + round((bot - top) * 0.56))
    lant = cfg.get("lantern")
    body = art.copy(); lp = None
    bp, ap = body.load(), art.load()
    if lant:  # a lanterna sai do corpo e é desenhada à parte, balançando
        lp = Image.new("RGBA", art.size, (0, 0, 0, 0)).load()
        x0, y0, x1, y1 = lant["box"]
        for y in range(y0, y1):
            for x in range(x0, x1):
                if ap[x, y][3]:
                    lp[x, y] = ap[x, y]; bp[x, y] = (0, 0, 0, 0)
    frames = []
    for f in range(N):
        b = -1 if f in BREATH else 0
        dy_of = lambda y: b if y <= waist else 0
        fr = Image.new("RGBA", art.size, (0, 0, 0, 0)); fp = fr.load()
        for y in range(h):
            for x in range(w):
                c = bp[x, y]
                if c[3]:
                    fp[x, y + dy_of(y)] = c
        if b:  # a linha da cintura repete para não abrir buraco
            for x in range(w):
                if not fp[x, waist][3] and bp[x, waist][3]:
                    fp[x, waist] = bp[x, waist]
        state = FLICKER[f]
        for box in cfg.get("fire", []):
            recolor(fp, bp, box, is_fire, FIRE, state, dy_of)
        for box in cfg.get("ember", []):  # brasa: pulsa devagar, sem tremer
            k = 0.5 + 0.5 * math.sin(2 * math.pi * f / N)
            slow = "bright" if k > 0.66 else ("dim" if k < 0.33 else "normal")
            recolor(fp, bp, box, is_ember, FIRE, slow, dy_of)
        for box in cfg.get("cyan", []):
            recolor(fp, bp, box, is_cyan, CYAN, state, dy_of)
        if "sparkle" in cfg and state == "dim":  # faíscas do frasco somem e voltam
            x0, y0, x1, y1 = cfg["sparkle"]
            for y in range(y0, y1):
                for x in range(x0, x1):
                    if is_cyan(bp[x, y]):
                        fp[x, y + dy_of(y)] = (0, 0, 0, 0)
        st = BLINK.get(f)
        if st:
            for box in cfg.get("lids", []):
                lid_blink(fp, ap, box, st, b, waist)
            for (x0, y0, x1, y1) in cfg.get("eye_boxes", []):  # Faroleiro: cores marcadas à mão
                SKIN, LID, LASH = (215, 136, 117), (173, 92, 82), (93, 43, 58)
                for x in range(x0, x1):
                    if st == "half":
                        fp[x, y0 + 1 + b] = LID
                    else:
                        fp[x, y0 + 1 + b] = SKIN; fp[x, y0 + 2 + b] = LID; fp[x, y0 + 3 + b] = LASH
        if lant:
            _lantern(fp, lp, lant, f, b)
        frames.append(fr.resize((W, H), Image.NEAREST))
    sheet = Image.new("RGBA", (W * N, H), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.paste(fr, (i * W, 0))
    return sheet


# A lanterna do Faroleiro: balança a partir da alça e a chama troca de cor.
GUARD_FLAME = {(219, 223, 212): "core", (213, 202, 191): "core2", (253, 193, 163): "hi",
               (222, 164, 123): "mid", (196, 115, 93): "lo"}
GUARD_STATES = {
    "dim": {"core": (250, 214, 150), "core2": (238, 190, 130), "hi": (232, 160, 96), "mid": (204, 124, 74), "lo": (160, 86, 66)},
    "normal": {"core": (255, 240, 196), "core2": (252, 222, 160), "hi": (250, 190, 112), "mid": (226, 146, 80), "lo": (188, 102, 68)},
    "bright": {"core": (255, 252, 226), "core2": (255, 238, 184), "hi": (255, 214, 132), "mid": (244, 172, 88), "lo": (214, 122, 70)},
}


def _lantern(fp, lp, lant, f, b):
    x0, y0, x1, y1 = lant["box"]; gx0, gy0, gx1, gy1 = lant["glass"]; pivot = lant["pivot"]
    s = round(2 * math.sin(2 * math.pi * f / N)); pal = GUARD_STATES[FLICKER[f]]
    for y in range(y0, y1):
        dx = round(s * (y - pivot) / (y1 - 1 - pivot))
        for x in range(x0, x1):
            c = lp[x, y]
            if not c[3]:
                continue
            if gx0 <= x < gx1 and gy0 <= y < gy1 and c[:3] in GUARD_FLAME:
                c = pal[GUARD_FLAME[c[:3]]] + (255,)
            fp[x + dx, y + b] = c
    if FLICKER[f] == "bright":
        y = 70; dx = round(s * (y - pivot) / (y1 - 1 - pivot))
        fp[8 + dx, y + b] = pal["core2"] + (255,)


if __name__ == "__main__":
    root = sys.argv[1]
    names = sys.argv[2:] or list(CONFIG)
    os.makedirs(os.path.join(root, "anim"), exist_ok=True)
    for name in names:
        sheet = build(os.path.join(root, f"morador_{name}.png"), name)
        out = os.path.join(root, "anim", f"morador_{name}_idle.png")
        sheet.save(out)
        print("ok", name, sheet.size)
