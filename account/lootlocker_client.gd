extends Node
## RPG Bolivia's White Label client. No admin credentials belong here.
## Login tokens and game session tokens have different purposes.

var game_key := ""
var domain_key := ""
var base_url := "https://api.lootlocker.io"
var development_mode := false
var request_timeout := 15.0
var session_token := ""
var player_id := 0
var public_uid := ""
var _session_generation := 0

func configure(path := "res://account/lootlocker.cfg") -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	game_key = str(config.get_value("lootlocker", "game_key", "")).strip_edges()
	domain_key = str(config.get_value("lootlocker", "domain_key", "")).strip_edges()
	base_url = str(config.get_value("lootlocker", "base_url", base_url)).strip_edges().trim_suffix("/")
	development_mode = bool(config.get_value("lootlocker", "development_mode", false))

func enabled() -> bool:
	return not game_key.is_empty() and not domain_key.is_empty()

func logged_in() -> bool:
	return not session_token.is_empty() and player_id > 0 and not public_uid.is_empty()

func logout() -> void:
	_session_generation += 1
	session_token = ""
	player_id = 0
	public_uid = ""

func sign_up(email: String, password: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/white-label-login/sign-up", {email = email, password = password}, true)

func login(email: String, password: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/white-label-login/login", {email = email, password = password, remember = true}, true)

func open_session(email: String, token: String) -> Dictionary:
	var generation := _session_generation
	var reply: Dictionary = await _call(HTTPClient.METHOD_POST, "/game/v2/session/white-label", {game_key = game_key, email = email, token = token, game_version = "0.1.0"})
	if generation != _session_generation:
		return {ok = false, code = 0, data = {}, cancelled = true}
	if reply.ok:
		var data: Dictionary = reply.data
		var next_token := str(data.get("session_token", ""))
		var next_uid := str(data.get("public_uid", ""))
		var next_id := int(data.get("player_id", 0))
		if next_token.is_empty() or next_uid.is_empty() or next_id <= 0:
			reply.ok = false
			reply.malformed = true
		else:
			session_token = next_token
			public_uid = next_uid
			player_id = next_id
	return reply

func reset_password(email: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/white-label-login/request-reset-password", {email = email}, true)

func get_player_name() -> Dictionary:
	return await _call(HTTPClient.METHOD_GET, "/game/player/name", {}, false, true)

func set_player_name(value: String) -> Dictionary:
	return await _call(HTTPClient.METHOD_PATCH, "/game/player/name", {name = value}, false, true)

## This one method is overridden by the deterministic protocol tests.
func _call(method: int, path: String, body: Dictionary = {}, white_label := false, authenticated := false) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = request_timeout
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json", "LL-Version: 2021-03-01"])
	if white_label:
		headers.append("domain-key: " + domain_key)
		headers.append("is-development: " + ("true" if development_mode else "false"))
	if authenticated:
		headers.append("x-session-token: " + session_token)
	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	if request.request(base_url + path, headers, method, payload) != OK:
		request.queue_free()
		return {ok = false, code = 0, data = {}}
	var response: Array = await request.request_completed
	request.queue_free()
	var code := int(response[1])
	var raw := (response[3] as PackedByteArray).get_string_from_utf8()
	var parser := JSON.new()
	var parsed: Variant = null
	var malformed := false
	if not raw.strip_edges().is_empty():
		malformed = parser.parse(raw) != OK
		if not malformed:
			parsed = parser.data
			malformed = not parsed is Dictionary
	return {ok = int(response[0]) == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and not malformed,
		code = code, data = parsed if parsed is Dictionary else {}, malformed = malformed}
