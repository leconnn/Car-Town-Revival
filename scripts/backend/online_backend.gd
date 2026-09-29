class_name OnlineBackend
extends BackendImpl
## Online play: the save lives on the server and every action is checked by
## the server functions (supabase/functions/act). The client only reads.

var online: Node
var _state: Dictionary = {}
var _clock_offset := 0


func _init(online_node: Node) -> void:
	online = online_node


## Loads the player's save. Returns "", "no_save" (needs start()), or an error.
func load_state() -> String:
	var r: Dictionary = await online.call_function("act", {"action": "state"})
	if r["code"] == 404:
		return "no_save"
	return _take(r)


## Creates the player's online garage with their chosen display name.
func start(display_name: String) -> String:
	var r: Dictionary = await online.call_function("act", {"action": "start", "display_name": display_name})
	return _take(r)


func _take(r: Dictionary) -> String:
	var body: Dictionary = r["body"]
	if r["code"] >= 400 or not body.has("state"):
		return str(body.get("error", "The server didn't answer."))
	_state = body["state"]
	_clock_offset = int(body.get("now", Time.get_unix_time_from_system())) - int(Time.get_unix_time_from_system())
	return ""


func is_ready() -> bool:
	return not _state.is_empty()


func state() -> Dictionary:
	return _state


func now() -> int:
	return int(Time.get_unix_time_from_system()) + _clock_offset


func act(action: String, args: Array) -> GameResult:
	if BackendImpl.validate(action, args) == null:
		return GameResult.fail("Invalid action.")
	var r: Dictionary = await online.call_function("act", {"action": action, "args": args})
	var body: Dictionary = r["body"]
	if r["code"] >= 400 or not body.has("result"):
		return GameResult.fail(str(body.get("error", "The server didn't answer.")))
	var result := GameResult.from_dict(body["result"])
	var old := JSON.stringify(_state)
	_take(r)
	if JSON.stringify(_state) != old:
		state_changed.emit()
	for n: Dictionary in result.notices:
		notice.emit(n)
	return result
