extends SceneTree
## Real HTTP + gzip assembly + checksum + preservation of a known good pack.
const Updater := preload("res://update/pck_updater.gd")
var server := TCPServer.new()
var peers: Array[StreamPeerTCP] = []
var buffers: Array[String] = []
var payloads: Dictionary = {}
var failures := 0
var host: Node
var destination := "user://combate_update/test.pck"


func _initialize() -> void:
	call_deferred("_run")


func _process(_delta: float) -> bool:
	while server.is_connection_available():
		peers.append(server.take_connection())
		buffers.append("")
	for i in range(peers.size() - 1, -1, -1):
		var peer := peers[i]
		peer.poll()
		if peer.get_available_bytes() > 0:
			buffers[i] += peer.get_utf8_string(peer.get_available_bytes())
		if "\r\n\r\n" in buffers[i]:
			var path := buffers[i].split(" ")[1].split("?")[0].trim_prefix("/")
			var body: PackedByteArray = payloads.get(path, PackedByteArray())
			var code := "200 OK" if payloads.has(path) else "404 Not Found"
			peer.put_data(("HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, body.size()]).to_utf8_buffer())
			peer.put_data(body)
			peers.remove_at(i)
			buffers.remove_at(i)
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	host = Node.new()
	# Only fixture/temp files are touched; installed state and packs are preserved.
	root.add_child(host)
	_expect(server.listen(0, "127.0.0.1") == OK, "HTTP fixture starts")
	ProjectSettings.set_setting("updates/base_url", "http://127.0.0.1:%d/" % server.get_local_port())
	var data := "test content for a verified update".to_utf8_buffer()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	var metadata := {
		"patch_id": 999, "version": "test", "size": data.size(),
		"sha256": hash.finish().hex_encode(), "gz": true,
		"parts": ["patch.pck.parte000", "patch.pck.parte001"]
	}
	payloads["patch.pck.parte000"] = data.slice(0, 10).compress(FileAccess.COMPRESSION_GZIP)
	payloads["patch.pck.parte001"] = data.slice(10).compress(FileAccess.COMPRESSION_GZIP)
	payloads["version.json"] = JSON.stringify(metadata).to_utf8_buffer()
	var callback_host: Node = load("res://tests/updater_host.gd").new()
	root.add_child(callback_host)
	var fetched := await Updater._fetch_metadata(callback_host)
	_expect(fetched.get("patch_id") == 999, "Fetch real version.json")
	_expect(await Updater._download_pack(callback_host, fetched, destination), "Download and assemble gzip parts")
	_expect(FileAccess.get_file_as_bytes(destination) == data, "Assembled bytes match")
	metadata["sha256"] = "0".repeat(64)
	_expect(not await Updater._download_pack(callback_host, metadata, destination), "Reject incorrect checksum")
	_expect(FileAccess.get_file_as_bytes(destination) == data, "Bad download preserves previous pack")
	metadata["parts"] = ["../patch.pck.parte000"]
	_expect(not await Updater._download_pack(callback_host, metadata, destination), "Reject path traversal")
	metadata["parts"] = ["patch.pck.parte999"]
	_expect(not await Updater._download_pack(callback_host, metadata, destination), "Handle missing part")
	payloads["version.json"] = "invalid json".to_utf8_buffer()
	_expect((await Updater._fetch_metadata(callback_host)).is_empty(), "Invalid manifest allows offline fallback")
	_expect(not FileAccess.file_exists(Updater.TEMP_PACK), "Temporary pack cleaned on failure")
	Updater._delete(destination)
	server.stop()
	print("Updater: ", failures, " failures")
	quit(1 if failures else 0)
