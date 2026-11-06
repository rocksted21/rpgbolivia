extends Node
## Optional identity only: campaigns remain local, independent of authentication.
## Persist the remembered login token, never the password or the game session.
signal changed

const Client := preload("res://account/lootlocker_client.gd")
const CONFIG_PATH := "res://account/lootlocker.cfg"
const SAVE_PATH := "user://rpg_bolivia_account.cfg"
var storage_path := SAVE_PATH
var auto_restore := true
var busy := false
var last_error := ""
## True when the last sign-up failed because the e-mail already has an account.
var email_taken := false
var account_email := ""
var display_name := ""
var public_uid := ""
var _login_token := ""
var _generation := 0
var _client: Node

func _ready() -> void:
	if _client == null:
		_client = Client.new()
		_client.configure(CONFIG_PATH)
	if _client.get_parent() == null:
		add_child(_client)
	_load()
	if auto_restore:
		restore_session.call_deferred()

func enabled() -> bool:
	return _client != null and _client.enabled()

func is_registered() -> bool:
	return _client != null and _client.logged_in() and not public_uid.is_empty()

func email_refusal(email: String) -> String:
	var clean := email.strip_edges()
	var at := clean.find("@")
	if at <= 0 or at != clean.rfind("@") or clean.contains(" ") or clean.contains("\n") or clean.contains("\t"):
		return "DIGITE UM E-MAIL VÁLIDO"
	var domain := clean.substr(at + 1)
	if not domain.contains(".") or domain.begins_with(".") or domain.ends_with("."):
		return "DIGITE UM E-MAIL VÁLIDO"
	return ""

func name_refusal(value: String) -> String:
	var clean := value.strip_edges()
	return "O NOME PRECISA TER 3 A 20 CARACTERES" if clean.length() < 3 or clean.length() > 20 or clean.contains("\n") or clean.contains("\t") else ""

func sign_up_email(email: String, password: String, player_name: String) -> bool:
	return await _authenticate(email, password, player_name, true)

func sign_in_email(email: String, password: String) -> bool:
	return await _authenticate(email, password, "", false)

func _authenticate(email: String, password: String, player_name: String, creating: bool) -> bool:
	if not _begin():
		return false
	var generation := _generation
	email_taken = false
	var clean := email.strip_edges().to_lower()
	var refusal := email_refusal(clean)
	if refusal.is_empty() and password.length() < 8:
		refusal = "A SENHA PRECISA TER PELO MENOS 8 CARACTERES"
	if refusal.is_empty() and creating:
		refusal = name_refusal(player_name)
	if not refusal.is_empty():
		return _finish(false, refusal)
	var existed := false
	if creating:
		var signup: Dictionary = await _client.sign_up(clean, password)
		if generation != _generation: return false
		if not signup.ok:
			email_taken = int(signup.code) == 409
			return _finish(false, _error(signup, "ESSE E-MAIL JÁ TEM CONTA. ENTRE OU RECUPERE A SENHA" if email_taken else "NÃO FOI POSSÍVEL CRIAR A CONTA"))
		existed = not signup.data.has("id")
	var login: Dictionary = await _client.login(clean, password)
	if generation != _generation: return false
	if not login.ok:
		email_taken = existed
		return _finish(false, _error(login, "ESSE E-MAIL JÁ TEM CONTA. ENTRE OU RECUPERE A SENHA" if existed else "E-MAIL OU SENHA INCORRETOS"))
	var token := str(login.data.get("session_token", ""))
	if token.is_empty():
		return _finish(false, "RESPOSTA INCOMPLETA DO SERVIDOR. TENTE DE NOVO")
	var session: Dictionary = await _client.open_session(clean, token)
	if generation != _generation:
		return false
	if not session.ok:
		return _finish(false, _error(session, "NÃO FOI POSSÍVEL ABRIR A CONTA. TENTE NOVAMENTE"))
	account_email = clean
	_login_token = token
	public_uid = _client.public_uid
	display_name = ""
	if creating and not existed:
		var name_reply: Dictionary = await _client.set_player_name(player_name.strip_edges())
		if generation != _generation: return false
		if name_reply.ok:
			display_name = player_name.strip_edges()
		else:
			last_error = _error(name_reply, "CONTA CRIADA. ESCOLHA OUTRO NOME PARA CONCLUIR")
	else:
		var name_reply: Dictionary = await _client.get_player_name()
		if generation != _generation: return false
		if name_reply.ok:
			display_name = str(name_reply.data.get("name", name_reply.data.get("player_name", "")))
	_save()
	return _finish(true, last_error)

func reset_email_password(email: String) -> bool:
	if not _begin(): return false
	var refusal := email_refusal(email)
	if not refusal.is_empty(): return _finish(false, refusal)
	var generation := _generation
	var reply: Dictionary = await _client.reset_password(email.strip_edges().to_lower())
	if generation != _generation: return false
	return _finish(reply.ok, "" if reply.ok else _error(reply, "NÃO FOI POSSÍVEL ENVIAR. TENTE NOVAMENTE"))

func set_display_name(value: String) -> bool:
	if busy: return false
	last_error = name_refusal(value)
	if not last_error.is_empty():
		changed.emit()
		return false
	if not is_registered():
		last_error = "ENTRE NA CONTA PARA SALVAR O NOME"
		changed.emit()
		return false
	busy = true
	changed.emit()
	var generation := _generation
	var reply: Dictionary = await _client.set_player_name(value.strip_edges())
	if generation != _generation: return false
	if not reply.ok: return _finish(false, _error(reply, "ESSE NOME NÃO ESTÁ DISPONÍVEL. ESCOLHA OUTRO"))
	display_name = value.strip_edges()
	_save()
	return _finish(true, last_error)

## Network failures keep the remembered account for a later manual retry.
func restore_session() -> bool:
	if busy or not enabled() or _login_token.is_empty() or account_email.is_empty(): return false
	busy = true
	last_error = ""
	changed.emit()
	var generation := _generation
	var reply: Dictionary = await _client.open_session(account_email, _login_token)
	if generation != _generation:
		return false
	if not reply.ok:
		if int(reply.code) == 401 or int(reply.code) == 403:
			_login_token = ""
			_save()
		return _finish(false, _error(reply, "ENTRE NOVAMENTE PARA CONECTAR SUA CONTA"))
	public_uid = _client.public_uid
	var name_reply: Dictionary = await _client.get_player_name()
	if generation != _generation: return false
	if name_reply.ok:
		display_name = str(name_reply.data.get("name", name_reply.data.get("player_name", display_name)))
	_save()
	return _finish(true, last_error)

func sign_out() -> void:
	_generation += 1
	busy = false
	if _client != null: _client.logout()
	account_email = ""
	display_name = ""
	public_uid = ""
	_login_token = ""
	last_error = ""
	_save()
	changed.emit()

func _begin() -> bool:
	if busy: return false
	last_error = ""
	if not enabled():
		last_error = "CONTA INDISPONÍVEL NESTA VERSÃO. VOCÊ PODE CONTINUAR JOGANDO"
		changed.emit()
		return false
	busy = true
	changed.emit()
	return true

func _finish(ok: bool, error := "") -> bool:
	busy = false
	last_error = error
	changed.emit()
	return ok

func _error(reply: Dictionary, fallback: String) -> String:
	var code := int(reply.get("code", 0))
	if code == 0: return "SEM CONEXÃO. VERIFIQUE SUA INTERNET E TENTE DE NOVO"
	if code == 429: return "MUITAS TENTATIVAS. AGUARDE UM POUCO E TENTE DE NOVO"
	if code >= 500: return "SERVIDOR INDISPONÍVEL. TENTE NOVAMENTE MAIS TARDE"
	if bool(reply.get("malformed", false)): return "RESPOSTA INCOMPLETA DO SERVIDOR. TENTE DE NOVO"
	return fallback

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(storage_path) != OK: return
	account_email = str(config.get_value("account", "email", ""))
	display_name = str(config.get_value("account", "name", ""))
	public_uid = str(config.get_value("account", "uid", ""))
	_login_token = str(config.get_value("account", "login_token", ""))

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("account", "email", account_email)
	config.set_value("account", "name", display_name)
	config.set_value("account", "uid", public_uid)
	config.set_value("account", "login_token", _login_token)
	if config.save(storage_path) != OK:
		last_error = "CONTA CONECTADA, MAS NÃO FOI POSSÍVEL LEMBRAR NESTE APARELHO"
