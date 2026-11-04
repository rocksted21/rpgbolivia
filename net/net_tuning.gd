extends RefCounted
## Mesmo transporte do Raid Alien, com salas e servidor exclusivos deste jogo.
const BUILD := "combate-tatico"
const MAX_PLAYERS := 4
const JOIN_TIMEOUT := 12.0
const JOIN_RETRY := 1.5
const ROOM_LIST_POLL := 3.0
const ROOM_LIST_WINDOW := 90.0
const PING := 20.0
const BUFFER_BYTES := 1048576
const MAX_QUEUED_BYTES := 65536
## Configuração de desenvolvimento/hospedagem, fora da interface dos jogadores.
const RELAY_HOST := "combate-tatico-relay.fly.dev"
const RELAY_SECURE := true

static func relay_host() -> String:
	var address := OS.get_environment("COMBATE_RELAY").trim_suffix("/")
	if address.is_empty(): return RELAY_HOST
	return address.trim_prefix("wss://").trim_prefix("ws://")

static func relay_secure() -> bool:
	var address := OS.get_environment("COMBATE_RELAY")
	return RELAY_SECURE if address.is_empty() else address.begins_with("wss://")
