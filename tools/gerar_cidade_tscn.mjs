// Gera scenes/cidade.tscn (a Cidade-Farol editável no Godot) a partir da planta antiga que
// ficava em scripts/town_data.gd, mais o TileSet hexagonal do chão.
// Rodar UMA vez: node tools/gerar_cidade_tscn.mjs  (sobrescreve a cena! depois edite no Godot)
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const TILE_W = 186, TILE_H = 213; // igual ao tile do jogo (battle_view.gd)

const MAP = [
	"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~2222222222~~~~~~~~~~~~",
	"~~~~~~~~~~~~22223333222~~~~~~~~~~~",
	"~~~~~~~~~~##22333333322~~~~~~~~~~~",
	"~~~~~~~~~###223333333322~~~~~~~~~~",
	"~~~~~~222222233333333322~~~~~~~~~~",
	"~~~~~~2222222233333333222~~~~~~~~~",
	"~~~~~22222222233333332222222~~~~~~",
	"~~~~~2222222222233332222222222~~~~",
	"~~~~~2222222211222222212222222~~~~",
	"~~~~~~22221111111111111122222222~~",
	"~~~~~222211111111111111222222222~~",
	"~~~~~~222211111pppppp111222222222~",
	"~~~~~~22211111ppppppp112222222222~",
	"~~~~~~11111111pppppppp11222222222~",
	"~~~~~11111111ppppppppp12222222222~",
	"~~~~~111111111pppppppp11111111111~",
	"~~~~1111111111ppppppp111111111111~",
	"~~~~~1111111111pppppp11111111111~~",
	"~~~~1111111111111111111111111111~~",
	"~~~~~111111111111111111111111111~~",
	"~~~~~11111111111111111111111111~~~",
	"~~~~~~11111111111111111111111~~~~~",
	"~~~~~11111111111111111111111~~~~~~",
	"~~~~~~0000000000000000000000~~~~~~",
	"~~~~~~000000000000000000000~~~~~~~",
	"~~~~~~0000000000~~~~~~00000~~~~~~~",
	"~~~~~~0000000000~~~~~0000~~~~~~~~~",
	"~~~~~~~000000~~~~~~~~~~~~~~~~~~~~~",
	"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~",
];
const ROADS = [
	[[17, 12], [17, 7]], [[17, 18], [18, 25]],
	[[13, 15], [9, 15]], [[9, 15], [7, 18]],
	[[21, 15], [26, 13]], [[26, 13], [29, 13]],
	[[14, 13], [11, 12]], [[20, 13], [24, 11]],
	[[9, 22], [26, 22]], [[14, 18], [12, 22]], [[21, 18], [23, 22]],
];
const TREES = [[5, 7], [5, 11], [5, 16], [5, 19], [5, 23], [6, 5], [6, 25], [7, 9], [7, 28], [8, 5], [9, 7], [9, 28], [11, 5], [11, 26], [12, 2], [12, 28], [14, 26], [15, 1], [16, 25], [17, 1], [21, 2], [21, 7], [23, 4], [23, 27], [24, 6], [27, 7], [27, 24], [28, 17], [28, 22], [30, 15], [30, 21], [31, 10], [31, 18], [32, 12], [32, 15]];
const MODELS = ["casa_a", "casa_b", "casa_c", "taverna", "mansao", "capela", "forja", "tenda", "abrigo", "forno", "torre_madeira", "fonte", "farol"];
const BUILDINGS = [
	["Farol", "farol", [17, 4], 1],
	["Forja (Ferreiro)", "forja", [8, 12], 1, "ferreiro"],
	["Tenda (Curandeira)", "tenda", [10, 19], 0, "curandeira"],
	["Horta", "horta", [7, 20], 0],
	["Taverna", "taverna", [25, 17], 1],
	["Mansão (Arquivista)", "mansao", [27, 10], 1, "arquivista"],
	["Capela", "capela", [11, 9], 1],
	["Acampamento (Viajante)", "acampamento", [6, 17], 0],
	["Forno (Padeira)", "forno", [5, 13], 0, "padeira"],
	["Abrigo (Alquimista)", "abrigo", [15, 24], 0, "alquimista"],
	["Torre (Cartógrafa)", "torre_madeira", [25, 25], 0, "cartografa"],
	["Fonte", "fonte", [17, 14], 0],
	["Casa do Mestre de Armas", "casa_c", [24, 10], 0],
	["Casa do Pavio", "casa_b", [16, 11], 0],
	["Casa do Pescador", "casa_a", [20, 23], 0],
];
const DECOR = [
	["fogueira_a", [12, 18]], ["fogueira_b", [19, 24]], ["fogueira_a", [8, 17]],
	["caldeirao_grande", [9, 20]], ["frascos", [11, 20], 56],
	["bigorna", [10, 13], 20], ["bigorna_b", [6, 15]], ["lenha", [4, 14]],
	["barraca_b", [14, 17]], ["barraca_c", [15, 19]], ["barraca_b", [20, 18]],
	["barris_b", [23, 25]], ["barris_b", [23, 16]],
	["tocha", [16, 10], 50, false], ["tocha", [18, 8], -50, false],
	["tocha", [13, 13], -40, false], ["tocha", [21, 13], 40, false],
	["tocha", [13, 18], 40, false], ["tocha", [21, 19], -40, false],
	["tocha", [16, 21], 50, false], ["tocha", [19, 23], -50, false],
	["tocha", [9, 14], 40, false], ["tocha", [26, 12], 40, false],
	["doca", [18, 26]], ["barco_a", [20, 27]], ["barco_b", [15, 27]], ["barco_a", [22, 28]],
];
const DECOR_NAMES = {
	fogueira_a: "Fogueira", fogueira_b: "Fogueira", caldeirao_grande: "Caldeirão", frascos: "Frascos",
	bigorna: "Bigorna", bigorna_b: "Bigorna", lenha: "Lenha", barraca_b: "Barraca", barraca_c: "Barraca",
	barris_b: "Barris", tocha: "Tocha", doca: "Doca", barco_a: "Barco", barco_b: "Barco",
};
const PEOPLE = [
	["ferreiro", "Ferreiro", "morador_ferreiro", [10, 12], "resident", "ferreiro"],
	["curandeira", "Curandeira", "morador_curandeira", [12, 20], "resident", "curandeira"],
	["taverneira", "Taverneira", "morador_taverneira", [23, 17], "memories"],
	["mestre", "Mestre de Armas", "morador_b", [25, 11], "skills"],
	["guarda", "Faroleiro", "morador_guarda", [20, 6], "beacon"],
	["pescador", "Pescador", "morador_a", [20, 25], "talk"],
	["viajante", "Viajante", "morador_c", [8, 18], "talk"],
	["mercadora", "Mercadora", "morador_d", [15, 18], "shop"],
	["sacerdotisa", "Sacerdotisa", "morador_e", [13, 11], "shop"],
	["padeira", "Padeira", "morador_padeira", [6, 13], "resident", "padeira"],
	["cartografa", "Cartógrafa", "morador_cartografa", [24, 25], "resident", "cartografa"],
	["arquivista", "Arquivista", "morador_arquivista", [27, 12], "resident", "arquivista"],
	["alquimista", "Alquimista", "morador_alquimista", [17, 24], "resident", "alquimista"],
	["mural", "Mural de Missões", "mural", [19, 12], "board"],
	["guia", "Pavio", "morador_g", [18, 14], "guide"],
];
const WALK_ROUTE = [[15, 15], [19, 16], [17, 19], [12, 22], [23, 22], [18, 24], [9, 15], [12, 12], [17, 10], [17, 8], [23, 12], [27, 13]];
const PLAZA = [17, 16];
const BUILDING_ART = ["casa_a", "casa_b", "casa_c", "taverna", "mansao", "capela", "forja", "forno", "abrigo", "tenda", "torre_madeira", "farol"];
const SMALL_ART = ["acampamento", "fonte"];

// --- Chão: tiles hexagonais ------------------------------------------------------
// Ordem dos tiles no atlas = letra da planta antiga.
const TILES = [
	["~", [60, 110, 190, 255]], ["#", [95, 88, 82, 255]], ["P", [205, 195, 165, 255]],
	["0", [210, 192, 120, 255]], ["1", [112, 172, 82, 255]], ["2", [80, 140, 62, 255]], ["3", [58, 104, 50, 255]],
	["R", [150, 150, 158, 180]],
];
const MARKS = ["~", "#", "p", "0", "1", "2", "3"];
const GLYPHS = {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"P": ["110", "101", "110", "100", "100"], "R": ["110", "101", "110", "101", "101"],
	"#": ["101", "111", "101", "111", "101"], "~": ["000", "110", "101", "011", "000"],
};
const HEX = [[93, 0], [185, 53], [185, 160], [93, 213], [0, 160], [0, 53]];

function inside(px, py, poly) {
	let sign = 0;
	for (let i = 0; i < poly.length; i++) {
		const [ax, ay] = poly[i], [bx, by] = poly[(i + 1) % poly.length];
		const cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
		if (cross !== 0) {
			if (sign === 0) sign = Math.sign(cross);
			else if (Math.sign(cross) !== sign) return false;
		}
	}
	return true;
}

function png(width, height, rgba) {
	const raw = Buffer.alloc((width * 4 + 1) * height);
	for (let y = 0; y < height; y++) rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
	const chunk = (type, data) => {
		const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
		const body = Buffer.concat([Buffer.from(type), data]);
		const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(body) >>> 0);
		return Buffer.concat([len, body, crc]);
	};
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8; ihdr[9] = 6;
	return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

function atlas() {
	const width = TILE_W * TILES.length, height = TILE_H;
	const img = Buffer.alloc(width * height * 4);
	const inner = HEX.map(([x, y]) => [93 + (x - 93) * 0.93, 106.5 + (y - 106.5) * 0.93]);
	TILES.forEach(([glyph, color], t) => {
		const dark = color.map((c, i) => (i < 3 ? Math.round(c * 0.6) : c));
		const ink = [255, 255, 255, Math.min(255, color[3] + 40)];
		for (let y = 0; y < TILE_H; y++) for (let x = 0; x < TILE_W; x++) {
			if (!inside(x + 0.5, y + 0.5, HEX)) continue;
			const c = inside(x + 0.5, y + 0.5, inner) ? color : dark;
			const gx = Math.floor((x - 81) / 8), gy = Math.floor((y - 86) / 8);
			const lit = gx >= 0 && gx < 3 && gy >= 0 && gy < 5 && GLYPHS[glyph][gy][gx] === "1";
			(lit ? ink : c).forEach((v, i) => (img[(y * width + t * TILE_W + x) * 4 + i] = v));
		}
	});
	return png(width, height, img);
}

// --- Geometria igual à do jogo (world_state.gd) ----------------------------------
const flat = ([x, y]) => [x + (y & 1) * 0.5, y * 0.866];
function line(from, to) {
	const out = [], a = flat(from), b = flat(to);
	const steps = Math.floor(Math.hypot(b[0] - a[0], b[1] - a[1]) * 2) + 1;
	for (let i = 0; i <= steps; i++) {
		const t = i / steps, px = a[0] + (b[0] - a[0]) * t, py = a[1] + (b[1] - a[1]) * t;
		const row = Math.round(py / 0.866);
		const cell = [Math.round(px - (row & 1) * 0.5), row];
		if (!out.some((c) => c[0] === cell[0] && c[1] === cell[1])) out.push(cell);
	}
	return out;
}
// Centro do hexágono no TileMapLayer (TileSet hexagonal, linhas ímpares meia casa à direita).
const center = ([x, y]) => [(x + (y & 1) * 0.5 + 0.5) * TILE_W, (y * 0.75 + 0.5) * TILE_H];

function tileData(cells) {
	const buf = Buffer.alloc(2 + cells.length * 12);
	buf.writeUInt16LE(0, 0);
	cells.forEach(([x, y, tile], i) => {
		const o = 2 + i * 12;
		buf.writeInt16LE(x, o); buf.writeInt16LE(y, o + 2);
		buf.writeUInt16LE(0, o + 4); buf.writeUInt16LE(tile, o + 6); buf.writeUInt16LE(0, o + 8); buf.writeUInt16LE(0, o + 10);
	});
	return `PackedByteArray(${[...buf].join(", ")})`;
}

// --- Cena --------------------------------------------------------------------------
const ext = [];
const extId = new Map();
function res(type, p) {
	if (!extId.has(p)) { extId.set(p, `${ext.length + 1}_r`); ext.push(`[ext_resource type="${type}" path="${p}" id="${ext.length + 1}_r"]`); }
	return `ExtResource("${extId.get(p)}")`;
}
const vec = ([x, y]) => `Vector2(${+x.toFixed(2)}, ${+y.toFixed(2)})`;
const nodes = [];
const used = new Map();
function node(name, type, parent, props) {
	const key = parent + "/" + name;
	const n = (used.get(key) || 0) + 1;
	used.set(key, n);
	const unique = n === 1 ? name : `${name} ${n}`;
	nodes.push(`[node name="${unique}" type="${type}" parent="${parent}"]\n${props.filter(Boolean).join("\n")}`);
}
function numbered(list) { // "Tocha" -> "Tocha 1", "Tocha 2"... quando há mais de uma
	const count = {};
	list.forEach((n) => (count[n] = (count[n] || 0) + 1));
	const seen = {};
	return list.map((n) => (count[n] > 1 ? `${n} ${(seen[n] = (seen[n] || 0) + 1)}` : n));
}

const tileset = res("TileSet", "res://assets/town/editor/chao_cidade.tres");
const scriptBuilding = res("Script", "res://scripts/cidade/cidade_predio.gd");
const scriptPerson = res("Script", "res://scripts/cidade/cidade_morador.gd");
const scriptDecor = res("Script", "res://scripts/cidade/cidade_enfeite.gd");

const ground = [];
MAP.forEach((row, y) => [...row].forEach((mark, x) => { if (mark !== "~") ground.push([x, y, MARKS.indexOf(mark)]); }));
const isLand = ([x, y]) => (MAP[y] || "")[x] !== undefined && MAP[y][x] !== "~";
const roads = [];
for (const [a, b] of ROADS) for (const c of line(a, b)) if (isLand(c) && !roads.some((r) => r[0] === c[0] && r[1] === c[1])) roads.push([c[0], c[1], 7]);

node("Chao", "TileMapLayer", ".", [`tile_map_data = ${tileData(ground)}`, `tile_set = ${tileset}`]);
node("Ruas", "TileMapLayer", ".", [`tile_map_data = ${tileData(roads)}`, `tile_set = ${tileset}`]);

node("Arvores", "Node2D", ".", ["y_sort_enabled = true"]);
TREES.forEach((cell, i) => node(`Arvore ${i + 1}`, "Sprite2D", "Arvores", [
	`position = ${vec(center(cell))}`, `texture = ${res("Texture2D", `res://assets/biomes/floresta/floresta_fundo_${i % 2 === 0 ? "a" : "b"}.png`)}`, i % 3 === 0 ? "flip_h = true" : "",
]));

node("Predios", "Node2D", ".", ["y_sort_enabled = true"]);
for (const [name, art, cell, radius, needs] of BUILDINGS) {
	const file = MODELS.includes(art) ? `res://assets/town/ilustrado/${art}.png` : `res://assets/town/${art}.png`;
	const s = BUILDING_ART.includes(art) ? 2.5 : SMALL_ART.includes(art) ? 1.5 : 1;
	node(name, "Sprite2D", "Predios", [
		`position = ${vec(center(cell))}`, s !== 1 ? `scale = Vector2(${s}, ${s})` : "", `texture = ${res("Texture2D", file)}`,
		`script = ${scriptBuilding}`, radius ? `raio = ${radius}` : "", needs ? `precisa_de = "${needs}"` : "",
	]);
}

node("Moradores", "Node2D", ".", ["y_sort_enabled = true"]);
for (const [id, name, art, cell, service, needs] of PEOPLE) node(name, "Sprite2D", "Moradores", [
	`position = ${vec(center(cell))}`, `texture = ${res("Texture2D", `res://assets/town/${art}.png`)}`,
	`script = ${scriptPerson}`, `id = "${id}"`, `nome = "${name}"`, `servico = "${service}"`, needs ? `precisa_de = "${needs}"` : "",
]);

node("Enfeites", "Node2D", ".", ["y_sort_enabled = true"]);
const decorNames = numbered(DECOR.map(([art]) => DECOR_NAMES[art]));
DECOR.forEach(([art, cell, offset = 0, solid = true], i) => {
	const [x, y] = center(cell);
	node(decorNames[i], "Sprite2D", "Enfeites", [
		`position = ${vec([x + offset, y])}`, `texture = ${res("Texture2D", `res://assets/town/${art}.png`)}`,
		`script = ${scriptDecor}`, solid ? "" : "solido = false",
	]);
});

node("Rota", "Node2D", ".", []);
WALK_ROUTE.forEach((cell, i) => node(`Ponto ${i + 1}`, "Marker2D", "Rota", [`position = ${vec(center(cell))}`, "gizmo_extents = 40.0"]));
node("Praca", "Marker2D", ".", [`position = ${vec(center(PLAZA))}`, "gizmo_extents = 80.0"]);

const header = `[gd_scene format=3]\n\n${ext.join("\n")}\n\n[node name="Cidade" type="Node2D"]\ny_sort_enabled = true\n`;
fs.mkdirSync(path.join(ROOT, "assets/town/editor"), { recursive: true });
fs.writeFileSync(path.join(ROOT, "assets/town/editor/chao_cidade.png"), atlas());
fs.writeFileSync(path.join(ROOT, "assets/town/editor/chao_cidade.tres"), `[gd_resource type="TileSet" format=3]

[ext_resource type="Texture2D" path="res://assets/town/editor/chao_cidade.png" id="1_chao"]

[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_chao"]
texture = ExtResource("1_chao")
texture_region_size = Vector2i(${TILE_W}, ${TILE_H})
${TILES.map((_, i) => `${i}:0/0 = 0`).join("\n")}

[resource]
tile_shape = 3
tile_size = Vector2i(${TILE_W}, ${TILE_H})
sources/0 = SubResource("TileSetAtlasSource_chao")
`);
fs.writeFileSync(path.join(ROOT, "scenes/cidade.tscn"), header + "\n" + nodes.join("\n\n") + "\n");
console.log(`cidade.tscn: ${ground.length} hexágonos, ${roads.length} de rua, ${nodes.length} nós`);
