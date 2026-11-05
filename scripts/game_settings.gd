extends RefCounted
## Preferências do jogador, salvas em user://. O volume vale para música e efeitos.
## Sem autoload, para funcionar com o pacote de atualização e nos testes.

const MASTER_BUS := 0

static var path := "user://settings.cfg"


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(path) # sem arquivo, começa com os valores padrão
	return config


## De 0 a 100.
static func volume() -> int:
	return clampi(int(_load().get_value("audio", "volume", 100)), 0, 100)


static func muted() -> bool:
	return bool(_load().get_value("audio", "muted", false))


static func set_volume(value: int) -> void:
	_save("volume", clampi(value, 0, 100))


static func set_muted(value: bool) -> void:
	_save("muted", value)


## Aplica o que está salvo. Chamado ao abrir o menu e a tela de jogo.
static func apply() -> void:
	AudioServer.set_bus_volume_linear(MASTER_BUS, volume() / 100.0)
	AudioServer.set_bus_mute(MASTER_BUS, muted())


static func _save(key: String, value: Variant) -> void:
	var config := _load()
	config.set_value("audio", key, value)
	var error := config.save(path)
	if error != OK:
		push_error("Não foi possível salvar as opções: %s" % error)
	apply()
