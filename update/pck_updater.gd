extends RefCounted
## Downloads and applies the latest PCK published in GitHub Releases.
## Contract: version.json plus patch.pck.parteNN gzip assets.

const BASE_URL := "https://github.com/rocksted21/rpgbolivia/releases/latest/download/"
const FOLDER := "user://combate_update"
const STATE_FILE := FOLDER + "/state.json"
const PACK_FILE := FOLDER + "/patch.pck"
const TEMP_PACK := FOLDER + "/patch.tmp"
const PART_FILE := FOLDER + "/part.tmp"
const MAX_ATTEMPTS := 2
const META_TIMEOUT_S := 8.0
const STALL_TIMEOUT_S := 25.0
const RESTART_WAIT_S := 3.0
const COPY_BLOCK := 4 * 1024 * 1024


static func running_patch_id() -> int:
	return int(ProjectSettings.get_setting("application/config/patch_id", 0))


## First autoload: mount a downloaded pack before other autoloads and game scenes load.
static func apply_saved_pack() -> void:
	if not can_update():
		return
	var state := _read_state()
	var saved_file := _saved_pack_file(state)
	if not FileAccess.file_exists(saved_file):
		return
	var patch_id := int(state.get("patch_id", 0))
	if patch_id <= running_patch_id() or patch_id == int(state.get("broken", 0)):
		return
	if not _pack_matches(saved_file, state):
		return
	if int(state.get("attempts", 0)) >= MAX_ATTEMPTS:
		state["broken"] = patch_id
		state.erase("patch_id")
		state["attempts"] = 0
		_save_state(state)
		_delete(saved_file)
		return
	state["attempts"] = int(state.get("attempts", 0)) + 1
	_save_state(state)
	if not ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(saved_file), true):
		return
	# project.godot's settings are not reloaded when a PCK is mounted.
	ProjectSettings.set_setting("application/config/patch_id", patch_id)
	ProjectSettings.set_setting("application/config/version", str(state.get("version", "")))


## Returns true when an instance restart was started; false means continue loading.
static func run(host) -> bool:
	if not can_update():
		return false
	_cleanup_launcher_packs()
	var running := running_patch_id()
	var state := _read_state()
	var saved_file := _saved_pack_file(state)
	var saved := int(state.get("patch_id", 0)) if _pack_matches(saved_file, state) else 0
	# Only the main menu confirms a healthy boot, after game code has loaded.
	var state_changed := false
	if saved != 0 and saved < running:
		_delete(saved_file)
		state.erase("patch_id")
		saved = 0
		state_changed = true
	if state_changed:
		_save_state(state)

	host.update_status("VERIFICANDO ATUALIZAÇÕES", 0.0, "")
	var metadata := await _fetch_metadata(host)
	var latest := int(metadata.get("patch_id", 0))
	if latest <= maxi(running, saved) or latest == int(state.get("broken", 0)):
		return false

	var destination := "%s/patch-%d.pck" % [FOLDER, latest]
	var downloaded := await _download_pack(host, metadata, destination)
	if not downloaded:
		host.update_status("CARREGANDO", 0.0, "")
		return false
	state["pack_file"] = destination
	state["patch_id"] = latest
	state["version"] = str(metadata.get("version", ""))
	state["size"] = metadata.get("size", 0)
	state["sha256"] = metadata.get("sha256", "")
	state["attempts"] = 0
	state.erase("broken")
	_save_state(state)

	if await _restart(host):
		return true

	# Never mix newly mounted scripts with autoloads from an older release.
	host.update_status("ATUALIZAÇÃO BAIXADA", 1.0, "A nova versão será aplicada na próxima abertura.")
	await host.get_tree().create_timer(2.0).timeout
	return false


static func can_update() -> bool:
	if not OS.has_feature("template"):
		return false
	return OS.has_feature("android") or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linux")


## Thin installers mount content before loading any game script or scene.
static func prepare_launcher(host) -> bool:
	_cleanup_launcher_packs()
	apply_saved_pack()
	var mounted := running_patch_id() > 0
	host.update_status("VERIFICANDO ATUALIZAÇÕES", 0.0, "")
	var metadata := await _fetch_metadata(host)
	var latest := int(metadata.get("patch_id", 0))
	var state := _read_state()
	if latest > running_patch_id() and latest != int(state.get("broken", 0)):
		var destination := "%s/patch-%d.pck" % [FOLDER, latest]
		if await _download_pack(host, metadata, destination):
			if ProjectSettings.load_resource_pack(ProjectSettings.globalize_path(destination), true):
				state.merge({"pack_file": destination, "patch_id": latest,
					"version": metadata.get("version", ""), "size": metadata.get("size", 0),
					"sha256": metadata.get("sha256", ""), "attempts": 1}, true)
				state.erase("broken")
				_save_state(state)
				ProjectSettings.set_setting("application/config/patch_id", latest)
				ProjectSettings.set_setting("application/config/version", str(metadata.get("version", "")))
				mounted = true
	if not mounted:
		host.update_status("NÃO FOI POSSÍVEL BAIXAR O JOGO", 0.0,
			"Confira a conexão e tente novamente.")
	return mounted


static func _fetch_metadata(host) -> Dictionary:
	var base: String = str(ProjectSettings.get_setting("updates/base_url", BASE_URL))
	var url := "%sversion.json?t=%d" % [base, int(Time.get_unix_time_from_system())]
	var response := await _request(host, url, "", META_TIMEOUT_S, Callable())
	if not response["ok"]:
		return {}
	var parser := JSON.new()
	if parser.parse((response["body"] as PackedByteArray).get_string_from_utf8()) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


static func _download_pack(host, metadata: Dictionary, destination: String = PACK_FILE) -> bool:
	var parts: Array = metadata.get("parts", [])
	var expected_size := int(metadata.get("size", 0))
	var wire_size := maxi(int(metadata.get("download", expected_size)), 1)
	var compressed := bool(metadata.get("gz", false))
	if parts.is_empty() or expected_size <= 0 or str(metadata.get("sha256", "")).length() != 64:
		return false
	for part in parts:
		if not _valid_part_name(str(part)):
			return false

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var output := FileAccess.open(TEMP_PACK, FileAccess.WRITE)
	if output == null:
		return false
	var assembled := 0
	var received := 0
	for part in parts:
		_delete(PART_FILE)
		var received_before := received
		var on_progress := func(current: int) -> void:
			var ratio := clampf(float(received_before + current) / float(wire_size), 0.0, 1.0)
			host.update_status("BAIXANDO ATUALIZAÇÃO", ratio * 0.97,
				"%d / %d MB" % [roundi((received_before + current) / 1e6), roundi(wire_size / 1e6)])
		# Use the immutable release URL from the manifest so a concurrent release
		# cannot mix parts from different versions. Older manifests use BASE_URL.
		var base := str(metadata.get("base_url", ProjectSettings.get_setting("updates/base_url", BASE_URL)))
		if not base.begins_with("https://github.com/rocksted21/rpgbolivia/releases/download/"):
			base = str(ProjectSettings.get_setting("updates/base_url", BASE_URL))
		var url := "%s%s?v=%s" % [base, str(part), str(metadata.get("patch_id", 0))]
		var response := await _request(host, url, PART_FILE, 0.0, on_progress)
		var input := FileAccess.open(PART_FILE, FileAccess.READ) if response["ok"] else null
		if input == null:
			output.close()
			_delete_temporary_files()
			return false
		var part_size := input.get_length()
		received += part_size
		if compressed:
			var raw := input.get_buffer(part_size).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
			if raw.is_empty():
				input.close()
				output.close()
				_delete_temporary_files()
				return false
			output.store_buffer(raw)
			assembled += raw.size()
		else:
			while input.get_position() < part_size:
				output.store_buffer(input.get_buffer(COPY_BLOCK))
			assembled += part_size
		input.close()
		_delete(PART_FILE)
		if assembled > expected_size:
			output.close()
			_delete_temporary_files()
			return false
	output.close()

	host.update_status("CONFERINDO ATUALIZAÇÃO", 0.98, "")
	await host.get_tree().process_frame
	var valid := assembled == expected_size \
		and FileAccess.get_sha256(TEMP_PACK).to_lower() == str(metadata.get("sha256", "")).to_lower()
	if not valid:
		push_warning("[atualizacao] PCK não confere com tamanho/SHA-256 do version.json")
		_delete_temporary_files()
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(TEMP_PACK), ProjectSettings.globalize_path(destination)) != OK:
		_delete_temporary_files()
		return false
	host.update_status("ATUALIZAÇÃO PRONTA", 1.0, str(metadata.get("version", "")))
	return true


static func _valid_part_name(name: String) -> bool:
	if not name.begins_with("patch.pck.parte"):
		return false
	var suffix := name.trim_prefix("patch.pck.parte")
	return not suffix.is_empty() and suffix.is_valid_int()


## GET: an empty file path keeps the response body in memory; downloads stream to disk.
static func _request(host: Node, url: String, file_path: String, timeout_s: float, progress: Callable) -> Dictionary:
	var request := HTTPRequest.new()
	request.use_threads = true
	request.timeout = timeout_s
	if file_path != "":
		request.accept_gzip = false
		request.download_file = file_path
	host.add_child(request)
	var state := {"finished": false, "ok": false, "body": PackedByteArray()}
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		state["ok"] = result == HTTPRequest.RESULT_SUCCESS and code == 200
		state["body"] = body
		state["finished"] = true)
	if request.request(url) != OK:
		request.queue_free()
		return {"ok": false, "body": PackedByteArray()}
	var previous_bytes := 0
	var last_progress_ms := Time.get_ticks_msec()
	while not state["finished"]:
		await host.get_tree().process_frame
		var current_bytes := request.get_downloaded_bytes()
		if current_bytes != previous_bytes:
			previous_bytes = current_bytes
			last_progress_ms = Time.get_ticks_msec()
		elif file_path != "" and (Time.get_ticks_msec() - last_progress_ms) / 1000.0 > STALL_TIMEOUT_S:
			request.cancel_request()
			break
		if progress.is_valid():
			progress.call(current_bytes)
	request.queue_free()
	return {"ok": state["ok"], "body": state["body"]}


static func _restart(host) -> bool:
	host.update_status("REABRINDO JOGO", 1.0, "")
	await host.get_tree().process_frame
	if not OS.has_feature("android"):
		if OS.create_instance(PackedStringArray()) <= 0:
			return false
		host.get_tree().quit()
		await host.get_tree().create_timer(RESTART_WAIT_S).timeout
		return true
	if not Engine.has_singleton("AndroidRuntime"):
		return false
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	if activity == null:
		return false
	var intent = activity.getPackageManager().getLaunchIntentForPackage(activity.getPackageName())
	if intent == null:
		return false
	intent.addFlags(0x10008000) # NEW_TASK | CLEAR_TASK
	activity.startActivity(intent)
	await host.get_tree().create_timer(0.4).timeout
	OS.kill(OS.get_process_id())
	await host.get_tree().create_timer(RESTART_WAIT_S).timeout
	return false


## Old immutable packs can be removed on the next launch, before any mount.
static func _cleanup_launcher_packs() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(FOLDER)):
		return
	var keep := _saved_pack_file(_read_state())
	for file in DirAccess.get_files_at(FOLDER):
		var path := FOLDER.path_join(file)
		if path == keep: continue
		if file.begins_with("patch-") and file.ends_with(".pck") and file.trim_prefix("patch-").trim_suffix(".pck").is_valid_int():
			_delete(path)


static func _saved_pack_file(state: Dictionary) -> String:
	var path := str(state.get("pack_file", PACK_FILE))
	# Only accept updater-owned files, including the original install's patch.pck.
	if path == PACK_FILE or path == "%s/patch-%d.pck" % [FOLDER, int(state.get("patch_id", 0))]:
		return path
	return PACK_FILE


static func _read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_FILE):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(STATE_FILE)) != OK:
		return {}
	return parser.data if parser.data is Dictionary else {}


static func _pack_matches(path: String, state: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var size := file.get_length()
	file.close()
	return size == int(state.get("size", 0)) and FileAccess.get_sha256(path) == str(state.get("sha256", ""))


static func confirm_boot() -> void:
	if not can_update():
		return
	var state := _read_state()
	if int(state.get("patch_id", 0)) == running_patch_id():
		state["attempts"] = 0
		_save_state(state)


static func _save_state(state: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var file := FileAccess.open(STATE_FILE + ".tmp", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))
		file.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(STATE_FILE + ".tmp"), ProjectSettings.globalize_path(STATE_FILE))


static func _delete(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _delete_temporary_files() -> void:
	_delete(TEMP_PACK)
	_delete(PART_FILE)
