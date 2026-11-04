// PROTOTYPE - NOT FOR PRODUCTION
// Relay do Raid Alien em Node: o mesmo protocolo de ../relay/src/index.js, para rodar
// numa máquina escolhida (a Cloudflare não cria Durable Objects na América do Sul).
// Nota: net/README.md (no protótipo).
//
//   GET  /                 -> "combate-tatico relay ok"
//   GET  /rooms            -> {rooms:[{code,title,host_name,setor,fase,players,max_players}]}
//   WS   /room/<codigo>    -> 1ª mensagem: {"t":"hello","mode":"create"|"join",...}
//
// Quadro binário: cliente manda [alvo][payload] (0 = os outros, 1 = só o master);
// a sala entrega [id_do_remetente][payload]. Tudo fica em memória: reiniciar fecha as salas.

import { createServer } from "node:http";
import { WebSocketServer } from "ws";

const PORT = Number(process.env.PORT) || 8787;
const HOST = process.env.HOST || "0.0.0.0";
const BUILD = "combate-tatico";
const CLIENT_TTL_MS = 75_000;     // remove membro sem ping
const SWEEP_MS = 30_000;
const MAX_PLAYERS_CAP = 4;
const MAX_FRAME_BYTES = 512 * 1024;
const MAX_QUEUED_BYTES = 8 * 1024 * 1024; // cliente que não acompanha cai, em vez de encher a memória
const PROP_KEYS = ["title", "host_name", "locked", "build", "setor", "fase"];
const CLOSE_CODES = { not_found: 4404, full: 4403, exists: 4409, bad: 4400, kicked: 4401, closed: 4410 };

const rooms = new Map(); // código -> {code, props, max, master, next_id, members: Map(id -> ws)}

const sendJson = (ws, obj) => {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
};

function fail(ws, code, msg) {
  sendJson(ws, { t: "error", code, msg });
  ws.close(CLOSE_CODES[code] || 4400, code);
}

function hello(ws, msg) {
  if (ws.room) return;
  if (msg.build !== BUILD) return fail(ws, "bad", "build");
  if (msg.mode !== "create" && msg.mode !== "join") return fail(ws, "bad", "mode");
  let room = rooms.get(ws.code);
  if (msg.mode === "create" && room) return fail(ws, "exists", "A sala já existe.");
  if (msg.mode === "join" && !room) return fail(ws, "not_found", "Sala não encontrada.");
  if (room && room.props.locked) return fail(ws, "full", "Partida em andamento.");
  if (room && room.members.size >= room.max) return fail(ws, "full", "Sala cheia.");

  const created = !room;
  if (created) {
    const props = {};
    for (const k of PROP_KEYS) if (msg.props && k in msg.props) props[k] = msg.props[k];
    room = {
      code: ws.code,
      props,
      max: Math.max(2, Math.min(MAX_PLAYERS_CAP, Number(msg.max) || 2)),
      master: 1,
      next_id: 1,
      members: new Map(),
    };
    rooms.set(ws.code, room);
  }
  const peers = [...room.members.keys()];
  ws.id = room.next_id++; if (ws.id > 255) return fail(ws, "full", "Recrie a sala.");
  ws.room = room;
  ws.lastSeen = Date.now();
  room.members.set(ws.id, ws);
  sendJson(ws, { t: "joined", me: ws.id, master: room.master, peers, spectators: [], created, spectator: false, props: room.props });
  for (const [id, peer] of room.members) if (id !== ws.id) sendJson(peer, { t: "peer_joined", id: ws.id });
}

function gone(ws) {
  const room = ws.room;
  if (!room) return;
  ws.room = null;
  room.members.delete(ws.id);
  if (room.members.size === 0) {
    rooms.delete(room.code);
    return;
  }
  if (room.master === ws.id) { rooms.delete(room.code); for (const peer of room.members.values()) { peer.room = null; peer.close(4410, "host left"); } return; }
  for (const peer of room.members.values()) sendJson(peer, { t: "peer_left", id: ws.id, master: room.master });
}

function control(ws, text) {
  let msg;
  try { msg = JSON.parse(text); } catch { return; }
  if (!msg || typeof msg !== "object") return;
  const room = ws.room;
  switch (msg.t) {
    case "hello":
      return hello(ws, msg);
    case "props":
      if (room && ws.id === room.master && msg.props) {
        for (const k of PROP_KEYS) if (k in msg.props) room.props[k] = msg.props[k];
      }
      return;
    case "kick": {
      if (!room || ws.id !== room.master) return;
      const target = room.members.get(Number(msg.id));
      if (!target || target === ws) return;
      const why = typeof msg.msg === "string" && msg.msg ? msg.msg.slice(0, 80) : "Expulso.";
      sendJson(target, { t: "error", code: "kicked", msg: why });
      gone(target);
      target.close(1000, "bye");
      return;
    }
    case "leave":
      ws.close(1000, "leave");
      return;
    case "ping":
      ws.lastSeen = Date.now();
      sendJson(ws, { t: "pong" });
      return;
  }
}

function frame(ws, data) {
  const room = ws.room;
  if (!room || data.length < 2 || data.length > MAX_FRAME_BYTES) return;
  const toMaster = data[0] === 1;
  data[0] = ws.id; // o buffer é nosso: troca o alvo pelo remetente sem copiar
  for (const [id, peer] of room.members) {
    if (peer === ws || (toMaster && id !== room.master) || peer.readyState !== peer.OPEN) continue;
    if (peer.bufferedAmount > MAX_QUEUED_BYTES) {
      peer.terminate();
      continue;
    }
    peer.send(data, { binary: true });
  }
}

function listRooms() {
  const out = [];
  for (const room of rooms.values()) {
    const p = room.props;
    if (p.build !== BUILD || p.locked || room.members.size >= room.max) continue;
    out.push({
      code: room.code,
      title: String(p.title || "Sala"),
      host_name: String(p.host_name || ""),
      setor: String(p.setor || ""),
      fase: String(p.fase || ""),
      locked: Boolean(p.locked),
      players: room.members.size,
      max_players: room.max,
    });
  }
  out.sort((a, b) => b.players - a.players || a.title.localeCompare(b.title));
  return out;
}

const http = createServer((req, res) => {
  const path = new URL(req.url, "http://relay").pathname;
  if (path === "/rooms") {
    res.writeHead(200, {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "cache-control": "no-store",
    });
    res.end(JSON.stringify({ rooms: listRooms() }));
  } else if (path === "/") {
    res.end("combate-tatico relay ok");
  } else {
    res.writeHead(404);
    res.end("not found");
  }
});

// perMessageDeflate desligado: o jogo já comprime, e aqui só importa a pressa.
const wss = new WebSocketServer({ noServer: true, perMessageDeflate: false, maxPayload: MAX_FRAME_BYTES });

http.on("upgrade", (req, socket, head) => {
  const m = new URL(req.url, "http://relay").pathname.match(/^\/room\/([A-Za-z0-9_-]{1,32})$/);
  if (!m) return socket.destroy();
  wss.handleUpgrade(req, socket, head, (ws) => {
    ws.code = m[1];
    ws.room = null;
    ws.on("message", (data, isBinary) => (isBinary ? frame(ws, data) : control(ws, data.toString())));
    ws.on("close", () => gone(ws));
    ws.on("error", () => gone(ws));
  });
});

setInterval(() => {
  const limit = Date.now() - CLIENT_TTL_MS;
  for (const room of rooms.values()) {
    for (const ws of [...room.members.values()]) {
      if (ws.lastSeen < limit) ws.terminate();
    }
  }
}, SWEEP_MS);

http.listen(PORT, HOST, () => console.log(`combate-tatico relay em ${HOST}:${PORT}`));
