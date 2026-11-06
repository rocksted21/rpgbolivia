extends SceneTree
## Cadastro/login/retomada reais no LootLocker com conta QA sintética.
func _init() -> void:
	await process_frame
	var acc = root.get_node("/root/PlayerAccount")
	acc.storage_path = "user://account_live_check.cfg"
	var email := "qa-cidadefarol-%d@example.com" % Time.get_unix_time_from_system()
	var ok: bool = await acc.sign_up_email(email, "QaSenha!2026", "QA Farol")
	print("signup ok=", ok, " err=", acc.last_error, " uid=", acc.public_uid, " name=", acc.display_name)
	ok = await acc.restore_session()
	print("restore ok=", ok, " err=", acc.last_error)
	acc.sign_out()
	ok = await acc.sign_in_email(email, "QaSenha!2026")
	print("login ok=", ok, " err=", acc.last_error, " name=", acc.display_name)
	acc.sign_out()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://account_live_check.cfg"))
	quit()
