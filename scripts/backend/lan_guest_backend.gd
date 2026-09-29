class_name LanGuestBackend
extends BackendImpl
## A guest in someone else's LAN world. Every action is a request to the
## host; the host's reply carries the result and the guest's updated save.

const TIMEOUT_SECONDS := 10.0

signal _replied(req_id: int)

var lan: Node
var _state: Dictionary
## Host clock minus local clock, so timers match the host.
var _clock_offset: int
var _next_id := 1
var _replies: Dictionary[int, GameResult] = {}


func _init(lan_node: Node, player_state: Dictionary, host_now: int) -> void:
	lan = lan_node
	_state = player_state
	_clock_offset = host_now - int(Time.get_unix_time_from_system())


func is_ready() -> bool:
	return not _state.is_empty()


func state() -> Dictionary:
	return _state


func now() -> int:
	return int(Time.get_unix_time_from_system()) + _clock_offset


func act(action: String, args: Array) -> GameResult:
	if BackendImpl.validate(action, args) == null:
		return GameResult.fail("Invalid action.")
	var req_id := _next_id
	_next_id += 1
	lan.send_request(req_id, action, args)
	var deadline := Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000)
	# Wakes the wait below even if the host never answers.
	lan.get_tree().create_timer(TIMEOUT_SECONDS).timeout.connect(func() -> void: _replied.emit(-1))
	while not _replies.has(req_id):
		await _replied
		if Time.get_ticks_msec() >= deadline and not _replies.has(req_id):
			return GameResult.fail("The host didn't answer.")
	var result: GameResult = _replies[req_id]
	_replies.erase(req_id)
	for n: Dictionary in result.notices:
		notice.emit(n)
	return result


## Called by the Lan autoload when the host answers.
func receive(req_id: int, result: Dictionary, player_state: Dictionary, host_now: int) -> void:
	_clock_offset = host_now - int(Time.get_unix_time_from_system())
	var changed := JSON.stringify(player_state) != JSON.stringify(_state)
	_state = player_state
	_replies[req_id] = GameResult.from_dict(result)
	if changed:
		state_changed.emit()
	_replied.emit(req_id)


func shutdown() -> void:
	lan.stop()
