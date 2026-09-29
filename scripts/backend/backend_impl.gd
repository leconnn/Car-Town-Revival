class_name BackendImpl
extends RefCounted
## Base class for the three backends (local, LAN, online).
##
## Every game action is named in ACTIONS with its argument types. Backends
## receive actions by name, which makes them easy to send over the network and
## to validate on the receiving side.

signal state_changed
signal notice(data: Dictionary)

## name -> {"args": [types], "now": whether GameLogic takes a trailing `now`}
const ACTIONS: Dictionary[String, Dictionary] = {
	"buy_car": {"args": [TYPE_INT, TYPE_INT, TYPE_BOOL], "now": true},
	"sell_car": {"args": [TYPE_INT], "now": true},
	"paint_car": {"args": [TYPE_INT, TYPE_INT, TYPE_BOOL], "now": true},
	"install_part": {"args": [TYPE_INT, TYPE_INT, TYPE_BOOL], "now": true},
	"remove_part": {"args": [TYPE_INT, TYPE_INT], "now": false},
	"upgrade_car": {"args": [TYPE_INT, TYPE_INT], "now": true},
	"set_ride_height": {"args": [TYPE_INT, TYPE_INT, TYPE_BOOL], "now": true},
	"set_plate": {"args": [TYPE_INT, TYPE_STRING, TYPE_BOOL], "now": true},
	"move_car": {"args": [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT], "now": false},
	"store_car": {"args": [TYPE_INT], "now": false},
	"buy_item": {"args": [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT, TYPE_BOOL], "now": true},
	"move_item": {"args": [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT], "now": false},
	"store_item": {"args": [TYPE_INT], "now": false},
	"place_stored_item": {"args": [TYPE_INT, TYPE_INT, TYPE_INT, TYPE_INT], "now": false},
	"sell_item": {"args": [TYPE_INT], "now": false},
	"sell_stored_item": {"args": [TYPE_INT], "now": false},
	"set_surface": {"args": [TYPE_INT, TYPE_BOOL], "now": true},
	"expand_land": {"args": [TYPE_BOOL], "now": true},
	"put_car_on_bay": {"args": [TYPE_INT, TYPE_INT], "now": false},
	"take_car_off_bay": {"args": [TYPE_INT], "now": false},
	"start_job": {"args": [TYPE_INT, TYPE_INT], "now": true},
	"collect_job": {"args": [TYPE_INT], "now": true},
	"finish_job_now": {"args": [TYPE_INT], "now": true},
	"stop_job": {"args": [TYPE_INT], "now": false},
	"start_car_task": {"args": [TYPE_INT, TYPE_INT], "now": true},
	"collect_car_task": {"args": [TYPE_INT], "now": true},
	"finish_car_task_now": {"args": [TYPE_INT], "now": true},
	"stop_car_task": {"args": [TYPE_INT], "now": false},
	"accept_customer": {"args": [TYPE_INT, TYPE_INT], "now": false},
	"dismiss_customer": {"args": [TYPE_INT], "now": false},
	"tick": {"args": [], "now": true},
	"open_gps": {"args": [], "now": true},
	"visit_location": {"args": [TYPE_INT], "now": true},
	"set_tutorial": {"args": [TYPE_INT, TYPE_BOOL], "now": false},
	"rename": {"args": [TYPE_STRING], "now": false},
}


## Checks an action name and arguments. Converts whole floats to ints (they
## arrive as floats from JSON). Returns the cleaned args, or null if invalid.
static func validate(action: String, args: Array) -> Variant:
	if not ACTIONS.has(action):
		return null
	var types: Array = ACTIONS[action]["args"]
	if args.size() != types.size():
		return null
	var clean: Array = []
	for i in types.size():
		var v: Variant = JsonUtil.ints(args[i])
		if typeof(v) != types[i]:
			return null
		if typeof(v) == TYPE_STRING and (v as String).length() > 64:
			return null
		clean.append(v)
	return clean


## Runs a validated action on [param logic]. Shared by local play and the
## LAN host.
static func run_on(logic: GameLogic, action: String, args: Array, now: int) -> GameResult:
	var clean: Variant = validate(action, args)
	if clean == null:
		return GameResult.fail("Invalid action.")
	var call_args: Array = clean
	if ACTIONS[action]["now"]:
		call_args.append(now)
	var result: Variant = logic.callv(action, call_args)
	if not result is GameResult:
		return GameResult.fail("Action failed.")
	if result.ok:
		logic.save["updated_at"] = now
	return result


# --- Interface (overridden by each backend) ------------------------------------

func is_ready() -> bool:
	return false


## The current save as a read-only snapshot. Don't modify it.
func state() -> Dictionary:
	return {}


## Trusted current time in unix seconds.
func now() -> int:
	return int(Time.get_unix_time_from_system())


## Performs an action. May be awaited (network backends are asynchronous).
@warning_ignore("unused_parameter")
func act(action: String, args: Array) -> GameResult:
	return GameResult.fail("No game is running.")


func shutdown() -> void:
	pass
