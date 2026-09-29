class_name LanHostBackend
extends BackendImpl
## The hosting player's own backend: actions run directly on the host's
## world, the same rules guests go through.

var lan: Node
var player_id: String


func _init(lan_node: Node, host_player_id: String) -> void:
	lan = lan_node
	player_id = host_player_id


func is_ready() -> bool:
	return not lan.host_state(player_id).is_empty()


func state() -> Dictionary:
	return lan.host_state(player_id)


func act(action: String, args: Array) -> GameResult:
	var result: GameResult = lan.host_act(player_id, action, args)
	if result.ok and (action != "tick" or result.data.get("arrived", 0) > 0):
		state_changed.emit()
	for n: Dictionary in result.notices:
		notice.emit(n)
	return result


func shutdown() -> void:
	lan.stop()
