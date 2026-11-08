"""Planta dos Subúrbios Apagados (mapa 1). Desenha o mapa fixo com formas simples, confere
se tudo é alcançável e grava scripts/suburbs_plan.gd, que o jogo lê. Rodar na raiz do projeto:

    python3 tools/build_suburbios_map.py [previa.png]

Coordenadas: casas (coluna, linha) do mapa hexagonal, linhas ímpares meia casa para a direita,
como em scripts/hex.gd. O início fica em (0, 0); o norte (linhas negativas) leva ao farol.
Mudar o mapa: mexer nas funções de cada bairro abaixo e rodar de novo.
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

# --- Grade hexagonal (igual a scripts/hex.gd) ---------------------------------------

DIRS_EVEN = [(1, 0), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1)]
DIRS_ODD = [(1, 0), (1, 1), (0, 1), (-1, 0), (0, -1), (1, -1)]


def neighbor(c, d):
    dirs = DIRS_ODD if c[1] & 1 else DIRS_EVEN
    return (c[0] + dirs[d][0], c[1] + dirs[d][1])


def neighbors(c):
    return [neighbor(c, d) for d in range(6)]


def cube(c):
    q = c[0] - (c[1] - (c[1] & 1)) // 2
    return q, c[1]


def from_cube(q, r):
    return (q + (r - (r & 1)) // 2, r)


def distance(a, b):
    aq, ar = cube(a)
    bq, br = cube(b)
    dq, dr = aq - bq, ar - br
    return (abs(dq) + abs(dr) + abs(dq + dr)) // 2


def flat(c):
    return (c[0] + (c[1] & 1) * 0.5, c[1] * 0.866)


def disc(center, radius):
    out = []
    for row in range(center[1] - radius, center[1] + radius + 1):
        for col in range(center[0] - radius - 1, center[0] + radius + 2):
            if distance((col, row), center) <= radius:
                out.append((col, row))
    return out


def hex_line(a, b):
    aq, ar = cube(a)
    bq, br = cube(b)
    n = distance(a, b)
    out = []
    for i in range(n + 1):
        t = i / n if n else 0.0
        q = aq + (bq - aq) * t + 1e-6
        r = ar + (br - ar) * t + 2e-6
        s = -q - r
        rq, rr, rs = round(q), round(r), round(s)
        dq, dr, ds = abs(rq - q), abs(rr - r), abs(rs - s)
        if dq > dr and dq > ds:
            rq = -rr - rs
        elif dr > ds:
            rr = -rq - rs
        cell = from_cube(rq, rr)
        if not out or out[-1] != cell:
            out.append(cell)
    return out


def polyline(points):
    out = []
    for a, b in zip(points, points[1:]):
        for c in hex_line(a, b):
            if not out or out[-1] != c:
                out.append(c)
    return out


# --- O mapa --------------------------------------------------------------------------

COLS = (-32, 32)
ROWS = (-40, 6)
START = (0, 0)

# Uma letra por casa. Ver LEGEND em scripts/suburbs_map.gd.
# ' ' fora do mapa  '.' chão  ',' grama de jardim  ':' calçada  '=' rua  '-' trilha
# '~' água  'o' pedras do vau  'H' ponte  '#' construção  'T' árvore  't' arvoredo
# 'h' sebe  'f' grade de ferro  'w' muro  'g' lápides  'r' entulho  '^' monte de entulho
# 'M' barranco  'c' caixotes (sólido)
terrain: dict = {}
height: dict = {}
district: dict = {}
pieces: list = []  # {cell, art, label, solid}
labels: dict = {}  # casa: nome que aparece ao passar o mouse
sites: dict = {}  # tipo: [casas candidatas]
secrets: list = []  # {name, cell, entry}
lantern_routes: list = []

DISTRICTS = {
    "P": "Praça do Portão",
    "A": "Avenida dos Lampiões",
    "V": "Vila Operária",
    "J": "Jardins Aurélio",
    "C": "Cemitério da Colina",
    "K": "Parque do Coreto",
    "E": "Praça do Mercado",
    "Q": "Quartel da Vigília",
    "N": "Canal das Eclusas",
    "S": "Bairro da Capela",
    "U": "Usina de Gás",
    "O": "Colina do Observatório",
    "T": "Rua das Tílias",
}


def inside_map(c):
    x, y = flat(c)
    if c[1] > 4 or c[1] < -39 or abs(x) > 31:
        return False
    # cantos do norte arredondados, como uma bacia em volta da colina
    if y < -27 and abs(x) > 31 - (-27 - y) * 0.9:
        return False
    return True


def put(cells, ch, h=None, dist=None):
    for c in cells:
        if c in terrain:
            terrain[c] = ch
            if h is not None:
                height[c] = h
            if dist is not None:
                district[c] = dist


def put_height(cells, h):
    for c in cells:
        if c in terrain:
            height[c] = h


def area(fn):
    return [c for c in terrain if fn(c, *flat(c))]


def rect(c0, c1):
    """Casas com coluna e linha entre os dois cantos (inclusive)."""
    return [(x, y) for y in range(min(c0[1], c1[1]), max(c0[1], c1[1]) + 1)
            for x in range(min(c0[0], c1[0]), max(c0[0], c1[0]) + 1) if (x, y) in terrain]


def ring(cells):
    """A beira de um conjunto de casas."""
    s = set(cells)
    return [c for c in cells if any(n not in s for n in neighbors(c))]


def building(center, art, label, radius=1, dist=None):
    cells = disc(center, radius)
    put(cells, "#", dist=dist)
    pieces.append({"cell": center, "art": art, "label": label, "solid": True})
    for c in cells:
        labels[c] = label
    return cells


def prop(cell, art, label="", solid=True, ch="#"):
    if solid:
        put([cell], ch)
    pieces.append({"cell": cell, "art": art, "label": label, "solid": solid})
    if label:
        labels[cell] = label


def wide(points, width):
    """Faixa larga ao longo de uma linha: casas a até width/2 do traço."""
    cells = set()
    line = polyline(points)
    half = width / 2.0
    for c in line:
        for n in disc(c, int(half) + 1):
            if n in terrain:
                cells.add(n)
    segs = [(flat(a), flat(b)) for a, b in zip(points, points[1:])]
    out = []
    for c in cells:
        p = flat(c)
        best = min(_seg_dist(p, a, b) for a, b in segs)
        if best <= half:
            out.append(c)
    return out


def _seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    qx, qy = ax + t * dx, ay + t * dy
    return ((px - qx) ** 2 + (py - qy) ** 2) ** 0.5


def roll(c, salt=0):
    v = (c[0] * 73856093) ^ (c[1] * 19349663) ^ (salt * 83492791)
    v = (v ^ (v >> 13)) * 1274126177
    v = v ^ (v >> 16)
    return (v & 0xFFFFF) / float(0x100000)


# --- Bairros ---------------------------------------------------------------------------

def base():
    for row in range(ROWS[0], ROWS[1] + 1):
        for col in range(COLS[0], COLS[1] + 1):
            c = (col, row)
            if inside_map(c):
                terrain[c] = "."
                height[c] = 1
                district[c] = "T"


def south_wall():
    # A muralha da Cidade-Farol fecha o sul: de lá a party veio, para lá não volta agora.
    for c in list(terrain):
        if c[1] >= 4:
            terrain[c] = "w"
    prop((0, 4), "portao_cidade", "Portão da Cidade-Farol", ch="w")
    for x in (-5, 5):
        prop((x, 4), "lampiao_aceso", "Lampião da cidade", ch="w")


def plaza():
    cells = [c for c in disc(START, 3)]
    put(cells, ":", 1, "P")
    for c in disc(START, 4):
        district.setdefault(c, "P")
        if distance(c, START) == 4 and terrain.get(c) == ".":
            district[c] = "P"
    # Fonte seca, bancos e postes: a última praça com cara de cidade.
    for c in [(-3, -2), (3, -2)]:
        prop(c, "lampiao", "Lampião apagado", solid=False)
    prop((-3, 2), "banco", "Banco da praça", solid=False)
    prop((3, 2), "banco", "Banco da praça", solid=False)


def avenue():
    # A Avenida dos Lampiões corta tudo, do portão até o canal. A ponte do meio caiu.
    cells = area(lambda c, x, y: abs(x - 0.25) <= 1.3 and -21 <= c[1] <= -3)
    put(cells, "=", 1, "A")
    for row in range(-20, -3):
        for side in (-1, 1):
            col = 3 if side > 0 else -3
            c = (col, row)
            if terrain.get(c) not in (".", ","):
                continue
            district[c] = "A"
            if row % 4 == 0:
                put([c], "T")
                labels[c] = "Plátano morto"
            elif row % 4 == 2:
                prop(c, "lampiao", "Lampião apagado", solid=False)
    # Bonde descarrilado atravessado na avenida: passa-se pelos lados.
    prop((-1, -12), "bonde", "Bonde descarrilado", ch="#")
    put([(-2, -12)], "#")
    labels[(-2, -12)] = "Bonde descarrilado"
    prop((1, -13), "caixas", "Carga espalhada", solid=False)
    # Fim da avenida: a ponte central desabou. O farol fica à vista do outro lado.
    put(rect((-2, -21), (2, -21)), ":", 1, "A")
    prop((-1, -21), "barricada", "Barricada da ponte caída", ch="c")
    prop((1, -21), "barricada", "Barricada da ponte caída", ch="c")
    labels[(0, -21)] = "Cabeceira da ponte caída"


def tilias():
    # Rua das Tílias: a transversal que separa a vila e os jardins dos bairros do meio.
    cells = area(lambda c, x, y: c[1] == -9 and -29 <= c[0] <= 29)
    put(cells, "=", 1, "T")


def vila_operaria():
    d = "V"
    for c in rect((-31, -8), (-4, 3)):
        if terrain[c] == ".":
            district[c] = d
    # Rua dos Tecelões: sai da praça para o oeste.
    put(area(lambda c, x, y: c[1] == -3 and -29 <= c[0] <= -3), "=", 1, d)
    # Largo dos Tecelões: pracinha na metade da rua (lanterna 1, rota oeste).
    put(disc((-14, -3), 2), ":", 1, d)
    # Casas geminadas dos dois lados da rua.
    north = [-27, -23, -19, -9, -5]
    south = [-27, -23, -19, -9]
    arts = ["casa_suburbio_a", "casa_suburbio_b", "casa_suburbio_c"]
    for i, col in enumerate(north):
        building((col, -6), arts[i % 3], "Casa operária", 1, d)
    for i, col in enumerate(south):
        building((col, 0), arts[(i + 1) % 3], "Casa operária", 1, d)
    # Quintais cercados entre as casas do norte e a Rua das Tílias.
    for col in north:
        for c in [(col - 1, -8), (col + 1, -8)]:
            if terrain.get(c) == ".":
                put([c], "f")
                labels[c] = "Grade do quintal"
    # Quintal secreto: atrás da casa (-23, 0), fechado por casas e muro. A única entrada é a
    # fresta entre duas casas, escondida atrás de um barracão de ferramentas.
    yard = [(-25, 2), (-24, 2), (-23, 2), (-22, 2), (-21, 2), (-24, 3), (-23, 3), (-22, 3), (-21, 3), (-25, 3)]
    put(yard, ",", 1, d)
    for c in [(-26, 2), (-26, 3), (-20, 2), (-20, 3), (-19, 3), (-27, 3)]:
        put([c], "w")
        labels[c] = "Muro do quintal"
    for c in [(-17, 2), (-18, 2), (-16, 2), (-16, 3), (-17, 3), (-18, 3), (-15, 3), (-15, 2), (-14, 2), (-14, 3)]:
        if terrain.get(c) == ".":
            put([c], ",", 1, d)
    prop((-21, 1), "barracao", "Barracão de ferramentas", ch="#")
    # a fresta: entre a casa (-23,0) e a casa (-19,0) ficam (-21,0)/(-21,-1)... deixadas livres
    secrets.append({"name": "Quintal secreto", "cell": (-23, 3), "hint": "Uma fresta entre as casas, atrás do barracão."})
    # Varais e entulho dão vida aos quintais.
    for c in [(-29, -1), (-11, 2), (-6, 2), (-29, 2)]:
        if terrain.get(c) == ".":
            put([c], "r")
    # Casinha isolada no fim da rua: candidata a vila (casa com morador).
    sites.setdefault("vila", []).append((-29, -5))
    put([(-29, -5)], ".")
    sites.setdefault("ruina", []).append((-12, 1))
    sites.setdefault("bau", []).append((-28, -1))
    sites.setdefault("emboscada", []).append((-16, -6))


def jardins():
    d = "J"
    zone = rect((4, -8), (31, 3))
    for c in zone:
        if terrain[c] in (".",):
            terrain[c] = ","
            district[c] = d
    # Grade de ferro em volta dos jardins, com portão a oeste (de frente para a praça).
    fence = [c for c in zone if (c[0] in (4, 5) and flat(c)[0] in (4.5, 5.0)) or c[1] == -8]
    edge = [c for c in rect((4, -8), (5, 3)) if abs(flat(c)[0] - 4.75) <= 0.3]
    for c in edge + [c for c in zone if c[1] == -8]:
        if terrain.get(c) in (",", "."):
            put([c], "f")
            labels[c] = "Grade dos Jardins Aurélio"
    # Portão do jardim, na Rua do Jardim (que sai da praça para o leste).
    put(area(lambda c, x, y: c[1] == -3 and 3 <= c[0] <= 9), "=", 1, d)
    prop((5, -4), "portao_jardim", "Portão dos Jardins Aurélio", ch="f")
    put([(5, -2)], "f")
    labels[(5, -2)] = "Grade dos Jardins Aurélio"
    # Alameda interna até a mansão.
    put(area(lambda c, x, y: c[1] == -3 and 9 <= c[0] <= 18), "-", 1, d)
    put(disc((10, -3), 1), ":", 1, d)  # pátio do portão (lanterna 1, rota leste)
    building((22, -4), "mansao_aurelio", "Mansão Aurélio", 2, d)
    # Sebes ornamentais e estátuas ao longo da alameda.
    for col in range(12, 19, 2):
        for row in (-5,):
            if terrain.get((col, row)) == ",":
                put([(col, row)], "h")
                labels[(col, row)] = "Sebe aparada"
    prop((15, -6), "estatua", "Estátua de mármore", ch="#")
    # Labirinto de sebes, ao sul: entrada única ao norte, corredores em zigue-zague e um
    # bolsão sem saída antes do baú. As linhas cheias de sebe não deixam passar na diagonal.
    maze = [
        "hhhhh.hhhhhhh",
        "h...........h",
        "hhhhhhhhhh..h",
        "h...........h",
        "hh.hhh.hhhhhh",
    ]
    origin = (8, -1)
    for c in rect((7, -2), (21, -2)):
        if terrain.get(c) == "h":
            put([c], ",")
    for r, line in enumerate(maze):
        for k, ch in enumerate(line):
            c = (origin[0] + k, origin[1] + r)
            if c not in terrain:
                continue
            labels[c] = "Labirinto de sebes"
            if ch == "h":
                put([c], "h")
            else:
                put([c], ",", 1, d)
    secrets.append({"name": "Coração do labirinto", "cell": (10, 3), "hint": "No fundo do labirinto de sebes."})
    # Fonte dos jardins e casa do jardineiro.
    sites.setdefault("fonte", []).append((18, -7))
    sites.setdefault("vila", []).append((27, 1))
    put([(27, 1)], ",")
    sites.setdefault("bau", []).append((29, -6))
    sites.setdefault("ruina", []).append((24, 1))
    # Estufa quebrada no canto.
    building((28, -1), "estufa", "Estufa quebrada", 0, d)
    prop((25, -7), "banco", "Banco do jardim", solid=False)


def cemiterio():
    d = "C"
    zone = area(lambda c, x, y: -30 <= x <= -12.5 and -20 <= c[1] <= -11)
    for c in zone:
        terrain[c] = "."
        height[c] = 2
        district[c] = d
    for c in ring(zone):
        put([c], "f")
        labels[c] = "Grade do cemitério"
    # Portão a leste, para o parque; e uma brecha a sul, na Rua das Tílias.
    gate = (-13, -15)
    prop(gate, "portao_cemiterio", "Portão do Cemitério", solid=False)
    put([gate, (-13, -16)], ":", 2, d)
    labels[(-13, -16)] = "Portão do Cemitério"
    put([(-22, -11), (-21, -11)], ".", 2, d)
    labels[(-22, -11)] = labels[(-21, -11)] = "Grade arrebentada"
    # Fileiras de lápides (dá para andar entre elas) e mausoléus.
    for row in range(-19, -11):
        for col in range(-28, -14):
            c = (col, row)
            if terrain.get(c) == "." and row % 2 == 0 and (col + row // 2) % 3 != 0:
                put([c], "g")
                labels[c] = "Lápides"
    put(area(lambda c, x, y: c[1] == -15 and -28 <= c[0] <= -14), "-", 2, d)
    put(area(lambda c, x, y: -21.2 <= x <= -20.6 and -19 <= c[1] <= -12), "-", 2, d)
    put(disc((-20, -15), 1), ":", 2, d)  # rotunda do cruzeiro (lanterna 2, rota oeste)
    for c in [(-25, -13), (-16, -13), (-16, -18)]:
        building(c, "mausoleu", "Mausoléu", 0, d)
    # Cripta dos Faroleiros: no canto noroeste, num morro cercado de mausoléus.
    # A única passagem é a fresta entre dois deles, de frente para as lápides.
    crypt = disc((-27, -18), 1)
    put(crypt, ":", 3, d)
    for c in crypt:
        labels[c] = "Cripta dos Faroleiros"
    walls = [c for c in disc((-27, -18), 2) if c not in crypt and c in terrain]
    for c in walls:
        put([c], "#")
        labels[c] = "Mausoléu dos Faroleiros"
    door = (-26, -17)
    put([door], ":", 2, d)
    labels[door] = "Fresta entre os mausoléus"
    for c in [(-29, -19), (-29, -17), (-26, -20), (-28, -20)]:
        if c in terrain:
            put([c], "#")
    pieces.append({"cell": (-27, -19), "art": "cripta", "label": "Cripta dos Faroleiros", "solid": True})
    put([(-27, -19)], "#")
    secrets.append({"name": "Cripta dos Faroleiros", "cell": (-27, -18), "hint": "Entre os mausoléus do canto."})
    sites.setdefault("memoria_fixa", []).append((-26, -18))
    sites.setdefault("fonte", []).append((-24, -12))
    sites.setdefault("ruina", []).append((-17, -12))
    sites.setdefault("bau", []).append((-18, -19))


def parque():
    d = "K"
    zone = area(lambda c, x, y: -11.5 <= x <= -3 and -21 <= c[1] <= -10)
    for c in zone:
        terrain[c] = ","
        district[c] = d
    # Arvoredo morto em volta, mais fechado ao norte, junto do canal.
    for c in zone:
        r = roll(c, 3)
        if c[1] <= -19 or (r < 0.18 and c[1] < -11):
            terrain[c] = "t" if r < 0.6 else "T"
    # O lago e a ilha do coreto velho.
    pond = disc((-7, -15), 2) + [(-9, -15), (-5, -15)]
    put(pond, "~", 0, d)
    island = [(-7, -15)]
    put(island, ",", 1, d)
    labels[(-7, -15)] = "Ilhota do lago"
    stones = [(-6, -14), (-6, -13)]
    put(stones, "o", 0, d)
    secrets.append({"name": "Ilhota do lago", "cell": (-7, -15), "hint": "Pedras escondidas atrás dos juncos."})
    for c in [(-5, -13), (-4, -12), (-5, -12), (-4, -13)]:
        put([c], "t")
    # Coreto e trilhas do parque.
    put(polyline([(-2, -15), (-4, -16), (-8, -18), (-11, -17), (-13, -16)]), "-", None, d)
    put(polyline([(-2, -10), (-5, -10), (-9, -12), (-11, -12), (-12, -15)]), "-", None, d)
    building((-9, -11), "coreto", "Coreto", 0, d)
    for c in [(-10, -11), (-8, -11)]:
        if terrain.get(c) in (",", "t", "T"):
            put([c], ",")
    sites.setdefault("fonte", []).append((-4, -18))
    sites.setdefault("bau", []).append((-10, -19))
    # Vau secreto: uma brecha no arvoredo leva a pedras que cruzam o canal.
    gap = polyline([(-8, -18), (-8, -20), (-7, -21)])
    put(gap, ",", 1, d)
    for c in gap:
        labels[c] = "Clareira entre as árvores"


def mercado():
    d = "E"
    zone = area(lambda c, x, y: 2.5 <= x <= 13 and -21 <= c[1] <= -10)
    for c in zone:
        terrain[c] = ":"
        district[c] = d
    # Rua do Mercado: da avenida até o portão do quartel.
    put(area(lambda c, x, y: c[1] == -15 and 2 <= c[0] <= 15), "=", 1, d)
    # Barracas da feira abandonada, em duas fileiras.
    for i, col in enumerate([4, 7, 10]):
        for row in (-18, -12):
            c = (col, row)
            prop(c, "barraca_" + "abc"[(i + (row == -12)) % 3], "Barraca da feira", ch="#")
    building((11, -20), "pensao", "Pensão Estrela", 1, d)
    prop((5, -20), "carroca", "Carroça de flores", ch="#")
    prop((12, -12), "caixas", "Caixotes da feira", ch="c")
    sites.setdefault("fonte", []).append((7, -14))
    sites.setdefault("vila", []).append((13, -17))
    sites.setdefault("emboscada", []).append((8, -11))
    sites.setdefault("ruina", []).append((4, -10))


def quartel():
    d = "Q"
    zone = area(lambda c, x, y: 15.5 <= x <= 30 and -20 <= c[1] <= -10)
    for c in zone:
        terrain[c] = ":"
        district[c] = d
    for c in ring(zone):
        put([c], "w")
        labels[c] = "Muralha do quartel"
    # Portão a oeste, de frente para a Rua do Mercado.
    for c in [(16, -15), (16, -14), (16, -16)]:
        put([c], ":")
        labels[c] = "Portão do Quartel"
    prop((16, -17), "guarita", "Guarita", ch="w")
    prop((16, -13), "guarita", "Guarita", ch="w")
    building((23, -19), "alojamento", "Alojamento", 0, d)
    building((19, -19), "alojamento", "Alojamento", 0, d)
    building((27, -18), "torre_vigia", "Torre de vigia", 0, d)
    prop((20, -11), "caixas", "Caixotes de munição", ch="c")
    prop((25, -11), "carroca", "Carroça do quartel", ch="#")
    # O comandante do Forte da Vigília (só na primeira expedição) espera no pátio.
    sites.setdefault("forte", []).append((22, -15))
    # Arsenal escondido: canto sudeste murado, aberto só por uma brecha na muralha de fora.
    vault = [(28, -12), (28, -11), (27, -11)]
    for c in [(26, -12), (26, -11), (27, -12), (27, -13), (28, -13), (29, -13)]:
        put([c], "w")
        labels[c] = "Parede do arsenal"
    put(vault, ":", 1, d)
    for c in vault:
        labels[c] = "Arsenal esquecido"
    breach = (29, -11)
    put([breach], "r", 1, d)
    labels[breach] = "Brecha na muralha"
    put([(30, -11), (30, -10), (29, -9)], ".", 1, "T")
    secrets.append({"name": "Arsenal esquecido", "cell": (28, -11), "hint": "Uma brecha nos fundos do quartel."})
    sites.setdefault("emboscada", []).append((21, -14))
    sites.setdefault("bau", []).append((18, -11))


def canal():
    d = "N"
    water = area(lambda c, x, y: -24 <= c[1] <= -22)
    put(water, "~", 0, d)
    # Cais dos dois lados.
    south = area(lambda c, x, y: c[1] == -21 and terrain.get(c) in (".", ",", ":"))
    north = area(lambda c, x, y: c[1] == -25)
    put(south, ":", 1, d)
    put(north, ":", 1, d)
    # Pontes: a das Eclusas (oeste) e a de Ferro (leste). A do meio caiu.
    for col, label in ((-18, "Ponte das Eclusas"), (18, "Ponte de Ferro")):
        cells = area(lambda c, x, y, col=col: -24 <= c[1] <= -22 and abs(x - (col + 0.25)) <= 0.8)
        put(cells, "H", 1, d)
        for c in cells:
            labels[c] = label
    for c in area(lambda c, x, y: -24 <= c[1] <= -22 and abs(x - 0.25) <= 0.8):
        labels[c] = "Ponte desabada"
    prop((0, -24), "ponte_caida", "Ponte desabada", solid=False)
    prop((0, -22), "ponte_caida", "Ponte desabada", solid=False)
    # O vau secreto: pedras quase submersas, da clareira do parque até o outro lado.
    ford = [(-7, -22), (-7, -23), (-7, -24)]
    put(ford, "o", 0, d)
    for c in ford:
        labels[c] = "Pedras do vau"
    # Um baú ficou preso nas pedras do meio: o brilho chama quem passa pelo cais.
    secrets.append({"name": "Vau esquecido", "cell": (-7, -23), "hint": "Pedras sob a água, além do parque."})
    # Barcos que ninguém veio buscar.
    for c in [(-26, -23), (11, -23), (26, -22)]:
        prop(c, "barco", "Barco esquecido", solid=False)
    # Ruas que levam às pontes.
    put(polyline([(-18, -21), (-18, -10)]), "=", 1, "T")
    put(polyline([(18, -21), (18, -20), (14, -17), (14, -15)]), "=", 1, "T")


def capela():
    d = "S"
    zone = area(lambda c, x, y: x <= -6 and -39 <= c[1] <= -26)
    for c in zone:
        if terrain[c] == ".":
            district[c] = d
    building((-21, -31), "capela_canal", "Capela do Canal", 1, d)
    put(disc((-16, -30), 1), ":", 1, d)  # adro da capela (lanterna 3, rota oeste)
    put(polyline([(-18, -25), (-16, -29)]), "=", 1, d)
    building((-12, -33), "casa_suburbio_b", "Casa do eclusário", 1, d)
    building((-26, -27), "casa_suburbio_c", "Casa abandonada", 1, d)
    # Rua do Adro: do adro para o oeste, com casas dos dois lados e o cemiteriozinho da capela.
    put(area(lambda c, x, y: c[1] == -34 and -28 <= c[0] <= -14), "=", 1, d)
    put(polyline([(-16, -31), (-16, -34)]), "=", 1, d)
    for col, art in ((-26, "casa_suburbio_a"), (-21, "casa_suburbio_c")):
        building((col, -37), art, "Casa da Rua do Adro", 1, d)
    building((-27, -31), "casa_suburbio_b", "Casa da Rua do Adro", 1, d)
    for c in rect((-24, -29), (-18, -28)):
        if terrain.get(c) == "." and (c[0] + c[1]) % 2 == 0:
            put([c], "g")
            labels[c] = "Túmulos da capela"
    for c in [(-19, -27), (-17, -27)]:
        prop(c, "lampiao", "Lampião apagado", solid=False)
    # Bosque morto que sobe para a colina.
    for c in zone:
        r = roll(c, 7)
        if terrain[c] == "." and c[1] < -28 and r < 0.3 and distance(c, (-16, -30)) > 2:
            terrain[c] = "T" if r < 0.12 else "t"
    # Do outro lado do vau, um bosquinho fecha a margem: quem chega pelas pedras sai no cais.
    for c in [(-10, -26), (-9, -27), (-6, -27), (-5, -26), (-11, -27)]:
        if c in terrain and terrain[c] == ".":
            put([c], "T")
    sites.setdefault("memoria", []).append((-23, -29))
    sites.setdefault("ruina", []).append((-25, -33))
    sites.setdefault("bau", []).append((-14, -36))
    sites.setdefault("emboscada", []).append((-20, -27))
    sites.setdefault("vila", []).append((-28, -30))
    put([(-28, -30)], ".")


def usina():
    d = "U"
    zone = area(lambda c, x, y: x >= 6 and -39 <= c[1] <= -26)
    for c in zone:
        if terrain[c] == ".":
            terrain[c] = ":" if roll(c, 9) < 0.5 else "."
            district[c] = d
    put(polyline([(18, -25), (17, -28)]), "=", 1, d)
    put(disc((16, -29), 1), ":", 1, d)  # pátio da usina (lanterna 3, rota leste)
    building((22, -31), "gasometro", "Gasômetro", 2, d)
    building((13, -33), "gasometro_pequeno", "Gasômetro menor", 1, d)
    building((27, -27), "galpao", "Galpão do bonde", 1, d)
    prop((24, -26), "bonde", "Bonde no depósito", ch="#")
    put([(25, -26)], "#")
    # Passarela da usina: plataforma alta atrás dos gasômetros. Os caixotes viram escada.
    deck = disc((26, -34), 1)
    put(deck, ":", 3, d)
    for c in deck:
        labels[c] = "Passarela da usina"
    for c in [c for c in disc((26, -34), 2) if c not in deck and c in terrain]:
        if terrain[c] in (".", ":"):
            height[c] = 1
    steps = [(24, -35), (23, -35)]
    put(steps, "r", 2, d)
    for c in steps:
        labels[c] = "Caixotes empilhados"
    prop((24, -36), "caixas", "Caixotes empilhados", ch="c")
    secrets.append({"name": "Passarela da usina", "cell": (26, -34), "hint": "Os caixotes atrás do gasômetro viram escada."})
    for c in [(19, -27), (20, -27), (11, -30), (28, -31), (17, -35)]:
        prop(c, "barris", "Barris de piche", ch="c")
    building((9, -36), "casa_suburbio_c", "Casa do gasista", 1, d)
    put(polyline([(18, -28), (24, -27), (27, -25)]), "-", 1, d)  # trilho velho do bonde
    sites.setdefault("memoria", []).append((10, -28))
    sites.setdefault("ruina", []).append((20, -36))
    sites.setdefault("bau", []).append((12, -37))
    sites.setdefault("emboscada", []).append((14, -26))


def observatorio():
    d = "O"
    # Colina em dois degraus: a encosta (2) e o alto (3), onde fica o farol.
    hill = area(lambda c, x, y: ((x) ** 2 + ((y + 30.0) * 1.15) ** 2) ** 0.5 <= 6.2)
    top = disc((0, -35), 2) + disc((0, -33), 2)
    for c in hill:
        if terrain.get(c) not in ("~",):
            terrain[c] = "."
            height[c] = 2
            district[c] = d
    put(top, ":", 3, d)
    # Penhasco em volta do alto: só a escadaria e a trilha dos fundos sobem.
    # (o desnível de 2 entre o chão e o alto já não se anda; a encosta é que abre caminho)
    # Escadaria do Observatório, do cais norte até o alto.
    stairs = polyline([(0, -25), (0, -30)])
    put(stairs, "=", None, d)
    for c in stairs:
        labels[c] = "Escadaria do Observatório"
    for c in [(0, -25), (0, -26)]:
        height[c] = 1
    for c in [(0, -27), (0, -28), (0, -29), (1, -28), (-1, -28)]:
        if c in terrain:
            height[c] = 2
    for c in [(0, -30), (0, -31)]:
        height[c] = 3
        terrain[c] = ":"
    # A encosta só toca o chão na escadaria: em volta, o resto vira penhasco de pedra.
    for c in hill:
        if height[c] == 2 and any(n in terrain and height.get(n, 1) <= 1 and n not in stairs for n in neighbors(c)):
            if c not in stairs and c not in [(1, -28), (-1, -28)]:
                put([c], "M")
                labels[c] = "Encosta de pedra"
    for c in ring(top):
        if all(n in terrain for n in neighbors(c)) and terrain.get(c) == ":" and c not in [(0, -31), (0, -30)]:
            pass
    sites.setdefault("farol", []).append((0, -34))
    prop((-2, -32), "telescopio", "Luneta quebrada", ch="#")
    labels[(0, -34)] = "Farol do Observatório"


def lanterns():
    # Duas rotas espelhadas: a semente escolhe uma. Lanterna 1 de um lado, 2 do outro, 3 de volta.
    lantern_routes.append([(-14, -3), (7, -16), (-16, -30)])  # oeste, leste, oeste
    lantern_routes.append([(15, -3), (-20, -15), (16, -29)])  # leste, oeste, leste


def scatter():
    # Chão comum: entulho, montinhos e mato dão textura sem fechar caminho.
    for c, ch in list(terrain.items()):
        if ch != "." or labels.get(c):
            continue
        r = roll(c, 11)
        if r < 0.05:
            terrain[c] = "r"
        elif r < 0.08:
            terrain[c] = "^"
        elif r < 0.13 and district.get(c) in ("V", "T", "S"):
            terrain[c] = "t"


def build():
    base()
    tilias()
    canal()
    vila_operaria()
    jardins()
    cemiterio()
    parque()
    mercado()
    quartel()
    capela()
    usina()
    observatorio()
    avenue()
    plaza()
    south_wall()
    lanterns()
    scatter()
    # sítios precisam ser chão andável
    for kind, cells in sites.items():
        for c in cells:
            if kind not in ("vila",) and terrain.get(c) in ("#", "w", "f", "h", "T", "~", "M", "c"):
                terrain[c] = ":"


# --- Conferência -----------------------------------------------------------------------

WALKABLE = set(".,:=-oHtgr^")


def walk(start, ignore=()):
    seen = {start}
    queue = deque([start])
    while queue:
        cur = queue.popleft()
        for n in neighbors(cur):
            if n in seen or n not in terrain or terrain[n] not in WALKABLE:
                continue
            if abs(height[n] - height[cur]) > 1:
                continue
            seen.add(n)
            queue.append(n)
    return seen


def show(center, radius=4):
    """Debug: a vizinhança de uma casa, com a altura."""
    for row in range(center[1] - radius, center[1] + radius + 1):
        line = " " if row & 1 else ""
        for col in range(center[0] - radius * 2, center[0] + radius * 2 + 1):
            c = (col, row)
            line += (terrain.get(c, " ") + str(height.get(c, 0))) + " "
        print(f"{row:4d} {line}")


def check():
    reach = walk(START)
    problems = []
    def ok(c):
        return c in reach or any(n in reach for n in neighbors(c))
    for kind, cells in sites.items():
        for c in cells:
            if not ok(c):
                problems.append(f"{kind} {c} sem acesso")
    for route in lantern_routes:
        for c in route:
            if c not in reach:
                problems.append(f"lanterna {c} sem acesso")
            free = [n for n in neighbors(c) if n in reach]
            if len(free) < 4:
                problems.append(f"lanterna {c} com {len(free)} saídas")
    for s in secrets:
        if s["cell"] not in reach:
            problems.append(f"segredo {s['name']} {s['cell']} sem acesso")
    return reach, problems


# --- Saída -----------------------------------------------------------------------------

COLORS = {
    " ": (12, 12, 16), ".": (92, 96, 70), ",": (70, 104, 66), ":": (150, 140, 128), "=": (190, 160, 110),
    "-": (170, 130, 90), "~": (40, 80, 120), "o": (110, 150, 170), "H": (200, 170, 90), "#": (150, 60, 60),
    "T": (30, 60, 34), "t": (52, 80, 50), "h": (36, 90, 44), "f": (60, 60, 90), "w": (110, 90, 80),
    "g": (180, 180, 190), "r": (120, 112, 100), "^": (130, 110, 80), "M": (70, 64, 60), "c": (160, 110, 60),
}


def preview(path, reach):
    from PIL import Image, ImageDraw
    s = 18
    w = (COLS[1] - COLS[0] + 2) * s
    h = int((ROWS[1] - ROWS[0] + 2) * s * 0.866) + s
    im = Image.new("RGB", (w, h), (0, 0, 0))
    dr = ImageDraw.Draw(im)
    def pos(c):
        x, y = flat(c)
        return (x - COLS[0] + 0.5) * s, (y - ROWS[0] * 0.866 + 0.5) * s
    for c, ch in terrain.items():
        col = COLORS[ch]
        hgt = height[c]
        col = tuple(min(255, int(v * (0.75 + 0.12 * hgt))) for v in col)
        if c not in reach and ch in WALKABLE:
            col = tuple(int(v * 0.45) for v in col)
        x, y = pos(c)
        dr.regular_polygon((x, y, s * 0.56), 6, rotation=30, fill=col)
    for p in pieces:
        x, y = pos(p["cell"])
        dr.rectangle((x - 2, y - 2, x + 2, y + 2), fill=(255, 220, 120))
    marks = {"vila": (120, 180, 255), "fonte": (120, 240, 200), "ruina": (240, 200, 120), "emboscada": (255, 90, 80),
             "bau": (255, 180, 40), "memoria": (210, 160, 255), "memoria_fixa": (210, 160, 255), "forte": (255, 100, 90), "farol": (255, 255, 255)}
    for kind, cells in sites.items():
        for c in cells:
            x, y = pos(c)
            dr.ellipse((x - 4, y - 4, x + 4, y + 4), outline=marks.get(kind, (255, 255, 255)), width=2)
    for i, route in enumerate(lantern_routes):
        for k, c in enumerate(route):
            x, y = pos(c)
            dr.text((x - 3, y - 6), str(k + 1), fill=(255, 230, 80) if i == 0 else (255, 120, 230))
    for sc in secrets:
        x, y = pos(sc["cell"])
        dr.text((x - 3, y - 6), "?", fill=(80, 255, 255))
    x, y = pos(START)
    dr.ellipse((x - 5, y - 5, x + 5, y + 5), outline=(255, 0, 0), width=2)
    im.save(path)


# Carta ilustrada: o mapa inteiro em papel velho, com bairros, segredos e as duas rotas.
PAPER = {
    " ": (38, 32, 30), ".": (196, 178, 140), ",": (172, 170, 120), ":": (214, 200, 168), "=": (226, 214, 184),
    "-": (206, 184, 140), "~": (92, 120, 128), "o": (150, 160, 150), "H": (150, 112, 70), "#": (120, 78, 70),
    "T": (96, 104, 70), "t": (150, 150, 104), "h": (92, 118, 78), "f": (70, 66, 80), "w": (128, 104, 92),
    "g": (176, 172, 168), "r": (170, 152, 124), "^": (160, 138, 104), "M": (110, 96, 86), "c": (150, 110, 70),
}
CENTERS = {
    "V": (-17, -1), "J": (19, 1), "C": (-21, -17), "K": (-7, -18), "E": (8, -17), "Q": (23, -16),
    "N": (-24, -23), "S": (-20, -34), "U": (20, -35), "O": (0, -38), "P": (0, 2), "A": (2, -7),
}


def carta(path):
    from PIL import Image, ImageDraw, ImageFont
    s = 26
    w = int((COLS[1] - COLS[0] + 2) * s)
    h = int((ROWS[1] - ROWS[0] + 2) * s * 0.866) + s * 3
    im = Image.new("RGB", (w, h), (38, 32, 30))
    dr = ImageDraw.Draw(im)
    font = lambda size: ImageFont.truetype("assets/fonts/LibreBaskerville.ttf", size)

    def pos(c):
        x, y = flat(c)
        return (x - COLS[0] + 0.5) * s, (y - ROWS[0] * 0.866 + 0.5) * s + s * 2

    for c, ch in terrain.items():
        col = PAPER[ch]
        col = tuple(min(255, int(v * (0.84 + 0.08 * height[c]))) for v in col)
        x, y = pos(c)
        dr.regular_polygon((x, y, s * 0.58), 6, rotation=30, fill=col)
    # bordas de altura: penhasco desenhado como traço escuro
    for c in terrain:
        for d in range(6):
            n = neighbor(c, d)
            if n in terrain and height[c] - height[n] >= 2 and terrain[c] != " ":
                x, y = pos(c)
                nx, ny = pos(n)
                mx, my = (x + nx) / 2, (y + ny) / 2
                dr.ellipse((mx - 2, my - 2, mx + 2, my + 2), fill=(70, 50, 40))
    for p in pieces:
        if p["solid"] and p["art"] not in ("lampiao",):
            x, y = pos(p["cell"])
            dr.regular_polygon((x, y, s * 0.42), 6, rotation=30, fill=(98, 58, 56))
    ink = (52, 36, 30)
    for key, c in CENTERS.items():
        x, y = pos(c)
        name = DISTRICTS[key]
        f = font(17)
        tw = dr.textlength(name, font=f)
        dr.rectangle((x - tw / 2 - 6, y - 12, x + tw / 2 + 6, y + 12), fill=(232, 220, 190))
        dr.text((x - tw / 2, y - 10), name, fill=ink, font=f)
    mark = font(15)
    for sc in secrets:
        x, y = pos(sc["cell"])
        dr.ellipse((x - 11, y - 11, x + 11, y + 11), fill=(40, 120, 140), outline=(230, 250, 255), width=2)
        dr.text((x - 4, y - 9), "?", fill=(255, 255, 255), font=mark)
    colors = [(214, 140, 30), (170, 60, 140)]
    for i, route in enumerate(lantern_routes):
        pts = [pos(START)] + [pos(c) for c in route] + [pos(sites["farol"][0])]
        dr.line(pts, fill=colors[i], width=3)
        for k, c in enumerate(route):
            x, y = pos(c)
            dr.ellipse((x - 13, y - 13, x + 13, y + 13), fill=colors[i], outline=(255, 240, 200), width=2)
            dr.text((x - 5, y - 10), str(k + 1), fill=(255, 255, 255), font=mark)
    x, y = pos(sites["farol"][0])
    dr.ellipse((x - 16, y - 16, x + 16, y + 16), fill=(245, 176, 64), outline=(255, 250, 220), width=3)
    dr.text((x - 22, y + 18), "Farol", fill=(255, 240, 200), font=font(16))
    x, y = pos(START)
    dr.ellipse((x - 12, y - 12, x + 12, y + 12), fill=(200, 40, 40), outline=(255, 230, 220), width=2)
    dr.text((24, 10), "Subúrbios Apagados · Mapa 1", fill=(240, 226, 196), font=font(28))
    legend = [((214, 140, 30), "Rota oeste (1-2-3)"), ((170, 60, 140), "Rota leste (1-2-3)"), ((40, 120, 140), "Segredo: baú escondido"), ((200, 40, 40), "Início")]
    lx = w - 330
    for i, (col, text) in enumerate(legend):
        dr.ellipse((lx, 14 + i * 22, lx + 14, 28 + i * 22), fill=col)
        dr.text((lx + 22, 12 + i * 22), text, fill=(240, 226, 196), font=font(15))
    im.save(path)


def gd_value(v):
    if isinstance(v, tuple):
        return f"Vector2i({v[0]}, {v[1]})"
    if isinstance(v, str):
        return '"' + v.replace('"', '\\"') + '"'
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{gd_value(k)}: {gd_value(x)}" for k, x in v.items()) + "}"
    raise TypeError(v)


def write_plan(path):
    rows_t, rows_h, rows_d = [], [], []
    for row in range(ROWS[0], ROWS[1] + 1):
        rows_t.append("".join(terrain.get((col, row), " ") for col in range(COLS[0], COLS[1] + 1)))
        rows_h.append("".join(str(height.get((col, row), 0)) for col in range(COLS[0], COLS[1] + 1)))
        rows_d.append("".join(district.get((col, row), " ") if (col, row) in terrain else " " for col in range(COLS[0], COLS[1] + 1)))
    out = ['extends RefCounted',
           '## Planta dos Subúrbios Apagados, gerada por tools/build_suburbios_map.py. Não editar à mão:',
           '## mude o script e rode de novo. Leitura em scripts/suburbs_map.gd.',
           '',
           f'const ORIGIN := Vector2i({COLS[0]}, {ROWS[0]}) # casa do primeiro caractere da primeira linha',
           f'const START := {gd_value(START)}',
           '',
           'const TERRAIN := [']
    out += [f'\t"{r}",' for r in rows_t]
    out += [']', '', 'const HEIGHT := [']
    out += [f'\t"{r}",' for r in rows_h]
    out += [']', '', 'const DISTRICT := [']
    out += [f'\t"{r}",' for r in rows_d]
    out += [']', '', 'const DISTRICT_NAMES := ' + gd_value(DISTRICTS), '']
    out.append('const PIECES := [')
    for p in pieces:
        out.append('\t' + gd_value(p) + ',')
    out += [']', '']
    lab = {k: v for k, v in sorted(labels.items(), key=lambda kv: (kv[0][1], kv[0][0]))}
    out.append('const LABELS := {')
    for k, v in lab.items():
        out.append(f'\t{gd_value(k)}: {gd_value(v)},')
    out += ['}', '']
    out.append('const SITES := ' + gd_value({k: v for k, v in sites.items()}))
    out.append('')
    out.append('const LANTERN_ROUTES := ' + gd_value(lantern_routes))
    out.append('')
    out.append('const SECRETS := [')
    for s in secrets:
        out.append('\t' + gd_value(s) + ',')
    out += [']', '']
    Path(path).write_text("\n".join(out), encoding="utf-8")


def main():
    build()
    reach, problems = check()
    for p in problems:
        print("PROBLEMA:", p)
    print(f"{len(terrain)} casas, {len(reach)} alcançáveis, {len(pieces)} peças, {len(secrets)} segredos")
    if len(sys.argv) > 1:
        preview(sys.argv[1], reach)
    if len(sys.argv) > 2:
        carta(sys.argv[2])
    write_plan("scripts/suburbs_plan.gd")


if __name__ == "__main__":
    main()
