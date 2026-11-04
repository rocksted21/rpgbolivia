# PROTOTYPE - NOT FOR PRODUCTION
# Question: can friends play one saucer online through Super Heroes-style rooms?
# Date: 2026-10-27
extends Node
## Connection to the Raid Alien relay (servidor/relay/, a copy of the Super Heroes
## one): open or join a room, know the master, who came and left, list the open
## rooms and pass binary frames. Plain WebSocketPeer: runs on desktop and phone
## with no plugin. Trimmed from Super Heroes scripts/rede/relay_conexao.gd (no
## queue, no spectators).

signal connected_as_host
signal connected_as_client
signal join_failed(error: String)
signal peer_joined(id: int)
## Someone left, or MY connection dropped (then one per member).
signal peer_left(id: int)
signal room_list_changed(rooms: Array)
signal room_list_failed(reason: String)
signal frame_received(sender_id: int, payload: PackedByteArray)

const N := preload("res://net/net_tuning.gd")

## Byte 0 of an outgoing frame: everyone but me, or only the master.
const TARGET_OTHERS := 0
const TARGET_MASTER := 1

enum State { IDLE, CONNECTING, HANDSHAKE, IN_ROOM }

var state: int = State.IDLE
var is_master := false
var my_id := 0
var master_id := 0
var peer_ids: Array[int] = []
var room_code := ""
var dropped_code := 0
var relay_host := N.relay_host()
var secure := N.relay_secure()

var _ws: WebSocketPeer
var _closing: Array = []
var _pending_code := ""
var _pending_create := false
var _pending_props := {}
var _deadline := 0.0
var _retry_at := 0.0
var _last_error := ""
var _last_error_code := ""
var _ping_at := 0.0
var _ping_sent := 0.0
var ping_ms := 0.0
var _http: HTTPRequest
var _list_until := 0.0
var _list_next := 0.0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	_http.request_completed.connect(_on_rooms_response)
	add_child(_http)


## Opens (`create`) or joins room `code`. Joining never creates: a wrong code
## can't become an empty room.
func join_room(code: String, create: bool, props := {}) -> void:
	leave()
	dropped_code = 0
	_pending_code = code.strip_edges()
	_pending_create = create
	_pending_props = props.duplicate()
	_last_error = ""
	_last_error_code = ""
	_deadline = _now() + N.JOIN_TIMEOUT
	_retry_at = _now() + N.JOIN_RETRY
	_open_socket()


func leave() -> void:
	_pending_code = ""
	if _ws != null:
		if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_ws.send_text(JSON.stringify({t = "leave"}))
			_ws.close(1000, "leave")
		_closing.append({ws = _ws, until = _now() + 2.0})
		_ws = null
	_reset_room()
	state = State.IDLE


func in_room() -> bool:
	return state == State.IN_ROOM and _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func last_error() -> String:
	return _last_error


## Sends a game frame. Returns the bytes sent (0 = not in a room).
func send(target: int, payload: PackedByteArray) -> int:
	if not in_room():
		return 0
	var frame := PackedByteArray([target])
	frame.append_array(payload)
	if _ws.send(frame) != OK:
		return 0
	return frame.size()


## The connection isn't keeping up: anything sent now would arrive late.
func congested() -> bool:
	return queued_bytes() > N.MAX_QUEUED_BYTES


func queued_bytes() -> int:
	return _ws.get_current_outbound_buffered_amount() if in_room() else 0


## Times one trip to the room and back; the result lands in ping_ms.
func ping_now() -> void:
	if in_room():
		_ping_sent = _now()
		_ws.send_text(JSON.stringify({t = "ping"}))


## Master only: updates what the room list shows.
func set_props(props: Dictionary) -> void:
	if in_room() and is_master:
		_ws.send_text(JSON.stringify({t = "props", props = props}))


## Master only: closes a player's relay connection, so a vote kick cannot be ignored.
func kick(id: int, reason := "A tripulação votou para expulsar você.") -> bool:
	if not in_room() or not is_master or id <= 0 or id == my_id:
		return false
	return _ws.send_text(JSON.stringify({t = "kick", id = id, msg = reason})) == OK


## Asks for the room list now and keeps asking for a while.
func refresh_room_list() -> void:
	_list_until = _now() + N.ROOM_LIST_WINDOW
	_list_next = 0.0


func stop_room_list() -> void:
	_list_until = 0.0
	if _http != null:
		_http.cancel_request()


func _process(_dt: float) -> void:
	_drain_closing()
	if _ws != null:
		_poll_socket()
	_tick_pending()
	_tick_room_list()


func _poll_socket() -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state == State.CONNECTING:
				state = State.HANDSHAKE
				_ws.send_text(JSON.stringify({t = "hello", mode = "create" if _pending_create else "join",
						build = N.BUILD, max = N.MAX_PLAYERS, props = _pending_props}))
			while _ws != null and _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				if _ws.was_string_packet():
					_on_control(packet.get_string_from_utf8())
				elif state == State.IN_ROOM and packet.size() >= 2:
					frame_received.emit(int(packet[0]), packet.slice(1))
			if _ws != null and _now() >= _ping_at:
				_ping_at = _now() + N.PING
				_ws.send_text(JSON.stringify({t = "ping"}))
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			_ws = null
			_on_closed(code)


func _drain_closing() -> void:
	var still: Array = []
	for item in _closing:
		var ws: WebSocketPeer = item.ws
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED and _now() < float(item.until):
			still.append(item)
	_closing = still


## ENTRAR retries until the deadline: the host may be opening the room right now.
func _tick_pending() -> void:
	if _pending_code.is_empty():
		return
	if _now() >= _deadline:
		_fail("A sala não respondeu." if _last_error.is_empty() else _last_error)
	elif _ws == null and _now() >= _retry_at:
		_retry_at = _now() + N.JOIN_RETRY
		_open_socket()


func _tick_room_list() -> void:
	if state != State.IDLE or _now() >= _list_until or _now() < _list_next:
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_list_next = _now() + N.ROOM_LIST_POLL
	var err := _http.request("%s://%s/rooms" % ["https" if secure else "http", relay_host])
	if err != OK:
		room_list_failed.emit("Não foi possível buscar as salas.")


func _open_socket() -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = N.BUFFER_BYTES
	ws.outbound_buffer_size = N.BUFFER_BYTES
	var url := "%s://%s/room/%s" % ["wss" if secure else "ws", relay_host, _pending_code.uri_encode()]
	if ws.connect_to_url(url) != OK:
		_last_error = "Sem conexão."
		return
	_ws = ws
	state = State.CONNECTING
	_ping_at = _now() + N.PING


func _on_control(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match str(msg.get("t", "")):
		"pong":
			if _ping_sent > 0.0:
				ping_ms = (_now() - _ping_sent) * 1000.0
				_ping_sent = 0.0
		"joined":
			room_code = _pending_code
			_pending_code = ""
			_last_error = ""
			_last_error_code = ""
			my_id = int(msg.get("me", 0))
			master_id = int(msg.get("master", 1))
			is_master = my_id == master_id
			peer_ids.clear()
			for raw in msg.get("peers", []):
				if int(raw) > 0:
					peer_ids.append(int(raw))
			state = State.IN_ROOM
			if bool(msg.get("created", false)):
				connected_as_host.emit()
			else:
				connected_as_client.emit()
			for id in peer_ids.duplicate():
				peer_joined.emit(id)
		"peer_joined":
			var id := int(msg.get("id", 0))
			if id > 0 and not peer_ids.has(id):
				peer_ids.append(id)
			peer_joined.emit(id)
		"peer_left":
			var id := int(msg.get("id", 0))
			peer_ids.erase(id)
			master_id = int(msg.get("master", master_id))
			is_master = my_id == master_id
			peer_left.emit(id)
		"error":
			_last_error_code = str(msg.get("code", ""))
			_last_error = str(msg.get("msg", "Erro de rede."))


func _on_closed(close_code: int) -> void:
	if state == State.IN_ROOM:
		var gone := peer_ids.duplicate()
		_reset_room()
		state = State.IDLE
		dropped_code = close_code if close_code > 0 else 1
		if _last_error_code.is_empty():
			_last_error = "Conexão caiu."
		for id in gone:
			peer_left.emit(id)
		return
	state = State.IDLE
	if _pending_code.is_empty():
		return
	var retryable := _last_error_code == "not_found" or _last_error_code.is_empty()
	if retryable and close_code != 4400 and _now() < _deadline:
		return   # _tick_pending reopens the socket
	_fail(_last_error if not _last_error.is_empty() else "A sala não respondeu.")


func _fail(reason: String) -> void:
	leave()  # a late handshake must not create/join a room after the timeout
	_last_error = reason
	join_failed.emit(reason)


func _reset_room() -> void:
	is_master = false
	my_id = 0
	master_id = 0
	peer_ids.clear()
	room_code = ""


func _on_rooms_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		room_list_failed.emit("Não foi possível buscar as salas.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		room_list_failed.emit("Não foi possível buscar as salas.")
		return
	var rooms: Array = []
	for raw in parsed.get("rooms", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		rooms.append({code = str(raw.get("code", "")), title = str(raw.get("title", "Sala")),
				host_name = str(raw.get("host_name", "")), setor = str(raw.get("setor", "")),
				fase = str(raw.get("fase", "")), players = int(raw.get("players", 0)),
				max_players = int(raw.get("max_players", N.MAX_PLAYERS))})
	room_list_changed.emit(rooms)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
