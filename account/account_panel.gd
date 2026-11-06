extends Control
## Optional account door. Campaign play and saves never depend on this panel.
signal closed

const Art := preload("res://account/account_art.gd")
const MUTED := Color("b4bccb")
const ERROR := Color("ff9387")

var account
var initial_name := ""
var creating := true
var _email: LineEdit
var _password: LineEdit
var _name_field: LineEdit
var _status: Label
var _submit: Button
var _actions: Array[Button] = []
var _fields: Array[LineEdit] = []
var _body: VBoxContainer
var _scroll: ScrollContainer
var _card: PanelContainer
var _requesting := false
var _dismissed := false
var _email_draft := ""
var _was_registered := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func() -> void:
		size = get_viewport_rect().size
		_layout())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(Art.INK, 0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _style(Color("2a1319"), Color(Art.CYAN, 0.55), 16))
	add_child(_card)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	_card.add_child(margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	margin.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)
	if account != null:
		account.changed.connect(_on_account_changed)
	_build()
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var extent := Vector2(minf(550.0, size.x - 32.0), minf(688.0, size.y - 32.0))
	_card.size = extent
	_card.position = (size - extent) * 0.5


func _input(event: InputEvent) -> void:
	if _dismissed: return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _build() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_actions.clear()
	_fields.clear()
	_email = null
	_password = null
	_name_field = null
	_was_registered = account != null and account.is_registered()
	_label("SEU NOME NA CIDADE-FAROL", 14, Art.CYAN)
	_label("MINHA CONTA" if _was_registered else ("CRIAR CONTA" if creating else "ENTRAR NA CONTA"), 30, Art.PAPER)
	if _was_registered:
		_build_registered()
	else:
		_build_entry()
	_sync_busy()
	_layout.call_deferred()


func _build_entry() -> void:
	_label("Garanta um nome público só seu na Cidade-Farol. Você também pode jogar sem conta.", 17, MUTED)
	if creating:
		_name_field = _field("NOME PÚBLICO", "Como os aventureiros vão chamar você?", 20)
		_name_field.text = initial_name
	_email = _field("E-MAIL", "voce@exemplo.com", 254)
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_email.text = _email_draft
	_password = _field("SENHA", "Pelo menos 8 caracteres", 128)
	_password.secret = true
	_password.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	_password.text_submitted.connect(func(_text: String) -> void: _on_submit())
	var show_password := CheckButton.new()
	show_password.text = "Mostrar senha"
	show_password.add_theme_font_size_override("font_size", 15)
	show_password.toggled.connect(func(pressed: bool) -> void:
		if is_instance_valid(_password): _password.secret = not pressed)
	_body.add_child(show_password)
	_status = _label("", 16, ERROR)
	_status.custom_minimum_size.y = 24
	_submit = _button("CRIAR CONTA" if creating else "ENTRAR", Art.LIME, _on_submit)
	_button("JÁ TENHO CONTA · ENTRAR" if creating else "AINDA NÃO TENHO CONTA", Art.CYAN, _toggle_mode)
	if not creating:
		_button("ESQUECI A SENHA", Art.LIME, _on_reset)
	_button("AGORA NÃO · VOLTAR AO JOGO", MUTED, _close, false)
	_label("Você pode jogar sem conta. Seus saves continuam neste aparelho.", 14, MUTED)
	if account == null or not account.enabled():
		_status.text = "Conta temporariamente indisponível. Você pode continuar jogando."


func _build_registered() -> void:
	_label("CONECTADO", 16, Art.LIME)
	_label(account.account_email, 18, Art.PAPER)
	_name_field = _field("NOME PÚBLICO", "De 3 a 20 caracteres", 20)
	_name_field.text = account.display_name
	_name_field.text_submitted.connect(func(_text: String) -> void: _on_save_name())
	_status = _label("Sua conta está pronta. Os saves continuam neste aparelho.", 16, MUTED)
	_submit = _button("SALVAR NOME", Art.CYAN, _on_save_name)
	_button("VOLTAR AO JOGO", Art.LIME, _close, false)
	_button("SAIR DA CONTA", MUTED, _on_sign_out)
	_label("Sair da conta mantém seus saves locais.", 14, MUTED)


func _field(title: String, placeholder: String, limit: int) -> LineEdit:
	_label(title, 14, MUTED)
	var edit := LineEdit.new()
	edit.custom_minimum_size.y = 46
	edit.placeholder_text = placeholder
	edit.max_length = limit
	edit.add_theme_font_size_override("font_size", 20)
	edit.add_theme_color_override("font_color", Art.PAPER)
	edit.add_theme_color_override("caret_color", Art.LIME)
	edit.add_theme_stylebox_override("normal", _style(Color("16090c"), Color(Art.CYAN, 0.35), 8))
	edit.add_theme_stylebox_override("focus", _style(Color("16090c"), Art.LIME, 8))
	_body.add_child(edit)
	_fields.append(edit)
	return edit


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_body.add_child(label)
	return label


func _button(text: String, color: Color, action: Callable, lock_during_request := true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Art.PAPER)
	button.add_theme_stylebox_override("normal", _style(Color("3a1c22"), Color(color, 0.65), 8))
	button.add_theme_stylebox_override("hover", _style(Color("52282f"), color, 8))
	button.add_theme_stylebox_override("pressed", _style(Color("16090c"), color, 8))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Art.LIME, 8))
	button.pressed.connect(action)
	_body.add_child(button)
	if lock_during_request: _actions.append(button)
	return button


func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _sync_busy() -> void:
	var waiting: bool = _requesting or (account != null and account.busy)
	var configured: bool = account != null and account.enabled()
	for action in _actions: action.disabled = waiting or not configured
	for field in _fields: field.editable = not waiting
	if is_instance_valid(_submit):
		if waiting: _submit.text = "AGUARDE..."
		elif _was_registered: _submit.text = "SALVAR NOME"
		else: _submit.text = "CRIAR CONTA" if creating else "ENTRAR"


func _on_account_changed() -> void:
	var registered: bool = account != null and account.is_registered()
	if registered != _was_registered and not _requesting:
		_build()
	else:
		_sync_busy()


func _toggle_mode() -> void:
	if is_instance_valid(_email): _email_draft = _email.text
	if is_instance_valid(_name_field): initial_name = _name_field.text
	creating = not creating
	_build()


func _on_submit() -> void:
	if _requesting or account == null or account.busy or not account.enabled(): return
	_requesting = true
	_status.text = "CRIANDO SUA CONTA..." if creating else "ENTRANDO..."
	_status.add_theme_color_override("font_color", MUTED)
	_sync_busy()
	var ok: bool
	if creating:
		ok = await account.sign_up_email(_email.text, _password.text, _name_field.text)
	else:
		ok = await account.sign_in_email(_email.text, _password.text)
	_requesting = false
	if _dismissed:
		queue_free()
		return
	if ok or account.is_registered():
		var message: String = account.last_error
		_build()
		if not message.is_empty(): _set_error(message)
	elif creating and account.email_taken:
		# Dead end otherwise: move to sign-in with the e-mail kept, recovery one tap away.
		_email_draft = _email.text
		creating = false
		_build()
		_set_error("ESSE E-MAIL JÁ TEM CONTA. Digite a senha ou toque em ESQUECI A SENHA para receber um link no e-mail.")
	else:
		_password.text = ""
		_set_error(account.last_error)
		_sync_busy()


func _on_reset() -> void:
	if _requesting or account == null or account.busy or not account.enabled(): return
	_requesting = true
	_status.text = "ENVIANDO..."
	_sync_busy()
	var ok: bool = await account.reset_email_password(_email.text)
	_requesting = false
	if _dismissed:
		queue_free()
		return
	if ok:
		_status.add_theme_color_override("font_color", Art.LIME)
		_status.text = "Se esse e-mail tiver uma conta, você receberá a recuperação. Confira também o spam."
	else:
		_set_error(account.last_error)
	_sync_busy()


func _on_save_name() -> void:
	if _requesting or account == null or account.busy: return
	_requesting = true
	_sync_busy()
	var ok: bool = await account.set_display_name(_name_field.text)
	_requesting = false
	if _dismissed:
		queue_free()
		return
	if ok:
		_status.add_theme_color_override("font_color", Art.LIME)
		_status.text = "NOME SALVO"
	else:
		_set_error(account.last_error)
	_sync_busy()


func _on_sign_out() -> void:
	account.sign_out()
	creating = false
	_build()


func _set_error(message: String) -> void:
	_status.text = message if not message.is_empty() else "Não foi possível conectar. Tente de novo."
	_status.add_theme_color_override("font_color", ERROR)


func _close() -> void:
	if _dismissed: return
	_dismissed = true
	set_process_input(false)
	if is_instance_valid(_password): _password.text = ""
	hide()
	closed.emit()
	# The title may disappear as soon as play starts; keep the pending receiver alive.
	if _requesting:
		reparent(get_tree().root)
	else:
		queue_free()
