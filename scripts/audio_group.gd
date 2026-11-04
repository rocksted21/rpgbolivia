class_name AudioGroup
extends Node
## Grupo de áudio: o volume multiplica o de todos os sons e subgrupos abaixo.
## Para criar Personagens, adicione um Node com este script e coloque os players
## dentro dele. O bus e o envio para o grupo pai são configurados automaticamente.

## Percentual do volume original dos players, sem alterar seu volume individual.
@export_range(0.0, 100.0, 1.0, "suffix:%") var volume: float = 100.0:
	set(value):
		volume = clampf(value, 0.0, 100.0)
		_apply_volume()

@export var muted: bool = false:
	set(value):
		muted = value
		_apply_volume()

## Opcional. Vazio cria um bus a partir da hierarquia dos grupos.
@export var bus_name: StringName = &""

var _bus: StringName = &""


func _enter_tree() -> void:
	_ensure_bus()
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	_route_children(self)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)


func _parent_group() -> AudioGroup:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is AudioGroup:
			return ancestor
		ancestor = ancestor.get_parent()
	return null


func _ensure_bus() -> void:
	var parent_group := _parent_group()
	var send: StringName = &"Master"
	if parent_group != null:
		parent_group._ensure_bus()
		send = parent_group._bus
	_bus = bus_name
	if _bus == &"":
		_bus = StringName(str(send) + "/" + str(name))
	var index := AudioServer.get_bus_index(_bus)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, _bus)
	AudioServer.set_bus_send(index, send)
	_apply_volume()


func _apply_volume() -> void:
	if not is_inside_tree() or _bus == &"":
		return
	var index := AudioServer.get_bus_index(_bus)
	if index >= 0:
		AudioServer.set_bus_volume_linear(index, volume / 100.0)
		AudioServer.set_bus_mute(index, muted)


func _route_children(parent: Node) -> void:
	for child in parent.get_children():
		if child is AudioGroup:
			continue # Cada subgrupo encaminha seus próprios sons.
		_route_player(child)
		_route_children(child)


func _route_player(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		node.set("bus", _bus)


func _on_node_added(node: Node) -> void:
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is AudioGroup:
			if ancestor == self:
				_route_player(node)
			return
		ancestor = ancestor.get_parent()
