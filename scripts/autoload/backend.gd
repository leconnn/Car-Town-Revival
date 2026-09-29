extends Node
## Autoload "Backend": the only way the game reads or changes player data.
##
## The main menu picks an implementation (LocalBackend, LanBackend,
## OnlineBackend); nothing else in the game knows which mode is running.
## Actions are asynchronous for network modes, so always `await` them:
##     var result: GameResult = await Backend.buy_car(car_id, color_id, false)

signal state_changed
## Something to announce: level-up, mission complete, mastery, ...
signal notice(data: Dictionary)
## An action was rejected; the message is safe to show the player.
signal action_failed(message: String)
## An action succeeded (used for sounds and effects).
signal action_done(action: String, result: GameResult)
## The session ended (quit to menu, host left, ...).
signal session_ended(reason: String)

const TICK_SECONDS := 5.0

var _impl: BackendImpl
var _tick_timer: Timer
var _query_logic: GameLogic
var _query_dirty := true


func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = TICK_SECONDS
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)


func use(impl: BackendImpl) -> void:
	end_session("")
	_impl = impl
	_impl.state_changed.connect(_on_state_changed)
	_impl.notice.connect(func(n: Dictionary) -> void: notice.emit(n))
	_query_dirty = true
	_tick_timer.start()
	await act("tick", [])
	state_changed.emit()


func end_session(reason: String) -> void:
	if _impl == null:
		return
	_tick_timer.stop()
	_impl.shutdown()
	_impl = null
	_query_logic = null
	session_ended.emit(reason)


## "local", "lan_host", "lan_guest", "online" or "" (no game). For menus only;
## game code must not behave differently per mode.
func mode() -> String:
	if _impl is LocalBackend:
		return "local"
	if _impl is LanHostBackend:
		return "lan_host"
	if _impl is LanGuestBackend:
		return "lan_guest"
	if _impl is OnlineBackend:
		return "online"
	return ""


func has_game() -> bool:
	return _impl != null and _impl.is_ready()


func state() -> Dictionary:
	return _impl.state() if _impl != null else {}


func now() -> int:
	return _impl.now() if _impl != null else int(Time.get_unix_time_from_system())


## Read-only rule helper for UI queries (prices, dealer list, job payouts).
## Built on the current state; never use it to change anything.
func query() -> GameLogic:
	if _query_dirty or _query_logic == null:
		# A copy, so queries can never change the real save.
		_query_logic = GameLogic.new(GameData.catalog, state().duplicate(true))
		_query_dirty = false
	return _query_logic


func act(action: String, args: Array) -> GameResult:
	if _impl == null:
		return GameResult.fail("No game is running.")
	var result: GameResult = await _impl.act(action, args)
	if not result.ok and action != "tick":
		action_failed.emit(result.error)
	elif result.ok:
		action_done.emit(action, result)
	return result


func _on_state_changed() -> void:
	_query_dirty = true
	state_changed.emit()


## Only asks the backend to tick when something is due (a customer arriving
## or a new day), so online play doesn't call the server every few seconds.
func _on_tick() -> void:
	if not has_game():
		return
	var s := state()
	var t := now()
	var due: bool = s.get("next_customer_at", 0) <= t
	var new_day: bool = s.get("missions", {}).get("daily", {}).get("day", -1) != t / MissionTracker.SECONDS_PER_DAY
	if due or new_day:
		act("tick", [])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		end_session("quit")


# --- Game-level functions ----------------------------------------------------------

func buy_car(car_id: int, color_id: int, use_blue: bool) -> GameResult:
	return await act("buy_car", [car_id, color_id, use_blue])

func sell_car(car_uid: int) -> GameResult:
	return await act("sell_car", [car_uid])

## [param rgb] is 0xRRGGBB.
func paint_car(car_uid: int, rgb: int, use_blue: bool) -> GameResult:
	return await act("paint_car", [car_uid, rgb, use_blue])

func install_part(car_uid: int, part_id: int, use_blue: bool) -> GameResult:
	return await act("install_part", [car_uid, part_id, use_blue])

func remove_part(car_uid: int, category_id: int) -> GameResult:
	return await act("remove_part", [car_uid, category_id])

## Buys the next stage of upgrade [param track] (GameLogic.UPGRADE_*).
func upgrade_car(car_uid: int, track: int) -> GameResult:
	return await act("upgrade_car", [car_uid, track])

func set_ride_height(car_uid: int, height: int, use_blue: bool) -> GameResult:
	return await act("set_ride_height", [car_uid, height, use_blue])

func set_plate(car_uid: int, text: String, use_blue: bool) -> GameResult:
	return await act("set_plate", [car_uid, text, use_blue])

func move_car(car_uid: int, x: int, y: int, rot: int) -> GameResult:
	return await act("move_car", [car_uid, x, y, rot])

func store_car(car_uid: int) -> GameResult:
	return await act("store_car", [car_uid])

func buy_item(item_id: int, x: int, y: int, rot: int, use_blue: bool) -> GameResult:
	return await act("buy_item", [item_id, x, y, rot, use_blue])

func move_item(item_uid: int, x: int, y: int, rot: int) -> GameResult:
	return await act("move_item", [item_uid, x, y, rot])

func store_item(item_uid: int) -> GameResult:
	return await act("store_item", [item_uid])

func place_stored_item(item_id: int, x: int, y: int, rot: int) -> GameResult:
	return await act("place_stored_item", [item_id, x, y, rot])

func sell_item(item_uid: int) -> GameResult:
	return await act("sell_item", [item_uid])

func sell_stored_item(item_id: int) -> GameResult:
	return await act("sell_stored_item", [item_id])

func set_surface(item_id: int, use_blue: bool) -> GameResult:
	return await act("set_surface", [item_id, use_blue])

func expand_land(use_blue: bool) -> GameResult:
	return await act("expand_land", [use_blue])

func put_car_on_bay(car_uid: int, bay_uid: int) -> GameResult:
	return await act("put_car_on_bay", [car_uid, bay_uid])

func take_car_off_bay(car_uid: int) -> GameResult:
	return await act("take_car_off_bay", [car_uid])

func start_job(bay_uid: int, job_id: int) -> GameResult:
	return await act("start_job", [bay_uid, job_id])

func collect_job(bay_uid: int) -> GameResult:
	return await act("collect_job", [bay_uid])

func finish_job_now(bay_uid: int) -> GameResult:
	return await act("finish_job_now", [bay_uid])

func stop_job(bay_uid: int) -> GameResult:
	return await act("stop_job", [bay_uid])

func start_car_task(car_uid: int, job_id: int) -> GameResult:
	return await act("start_car_task", [car_uid, job_id])

func collect_car_task(car_uid: int) -> GameResult:
	return await act("collect_car_task", [car_uid])

func finish_car_task_now(car_uid: int) -> GameResult:
	return await act("finish_car_task_now", [car_uid])

func stop_car_task(car_uid: int) -> GameResult:
	return await act("stop_car_task", [car_uid])

func accept_customer(customer_uid: int, bay_uid: int) -> GameResult:
	return await act("accept_customer", [customer_uid, bay_uid])

func dismiss_customer(customer_uid: int) -> GameResult:
	return await act("dismiss_customer", [customer_uid])

func open_gps() -> GameResult:
	return await act("open_gps", [])

func visit_location(location_id: int) -> GameResult:
	return await act("visit_location", [location_id])

func set_tutorial(step: int, done: bool) -> GameResult:
	return await act("set_tutorial", [step, done])
