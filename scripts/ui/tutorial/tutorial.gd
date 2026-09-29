class_name Tutorial
extends StageUi
## The original new-player tutorial (controllers/tutorial/BeginnerTutorialV3),
## told by Roxy. Three steps, saved as the tutorial step so a player who
## quits comes back to the one they were on (with "Welcome back!"):
##   0. Hello; this is your garage; collect the job on your work bay.
##   1. Click the customer waiting outside, then Start their job.
##   2. Click your car, then Customize.
## While it runs, only the thing Roxy points at can be clicked. When it's
## done, the missions dock appears.

## Positions of Roxy on the 760 x 700 stage (AbstractTutorial).
const GUIDE_SIZE := 150.0
const RIGHT_X := 760.0 - GUIDE_SIZE / 2.0 - 10.0
const MIDDLE_X := 760.0 / 2.0
const MIDDLE_Y := 467.0 / 2.0
const STEPS_DONE := 3
## Arrow offsets from the object they point at (AddArrowToGameSpaceObject)
## and positions inside popups (AddArrowToPopup).
const BAY_ARROW := Vector2(-70, 18)
const CUSTOMER_ARROW := Vector2(10, -22)
const CAR_ARROW := Vector2(35, -7)
const START_BUTTON_ARROW := Vector2(335, 398)
const CUSTOMIZE_ARROW := Vector2(330, 78)

var game: Node
var _guide: GuidePopup
var _arrow: PointerArrow
var _name := ""
## Testing aid (`-- tutorial_autoplay`): clicks through every step by itself.
var _auto := OS.get_cmdline_user_args().has("tutorial_autoplay")


static func attach(game_node: Node) -> void:
	var t: Dictionary = Backend.state().get("tutorial", {})
	if t.get("done", false) or int(t.get("step", 0)) >= STEPS_DONE:
		return
	var tut := Tutorial.new()
	tut.game = game_node
	game_node.add_tutorial(tut)


func _ready() -> void:
	super()
	_guide = GuidePopup.new()
	center.add_child(_guide)
	_name = Backend.state()["player"]["name"]
	game.hud.set_mission_dock_visible(false)
	_run.call_deferred()


func _run() -> void:
	var step: int = Backend.state().get("tutorial", {}).get("step", 0)
	var fresh := true
	if step == 0:
		await _step_collect_first_task()
		step = 1
		fresh = false
	if step == 1:
		await _step_start_next_task(fresh)
		step = 2
		fresh = false
	if step == 2:
		await _step_customize_car(fresh)
	_finish()


# --- Step 0: collect the first job ------------------------------------------------------

func _step_collect_first_task() -> void:
	_restrict(func(_k: String, _u: int) -> bool: return false)
	await get_tree().create_timer(1.5).timeout
	_guide.position = Vector2(RIGHT_X, MIDDLE_Y)
	await _say("Hi %s,\nI'm %s." % [_name, GuidePopup.NAME], true, true)
	var bay := _first_busy_bay()
	await _focus_on("item", bay)
	await _say("This is your garage,\nyou can do jobs here and\ndecorate your garage\nhowever you like!", false, true)
	await _guide.move_to(Vector2(RIGHT_X, MIDDLE_X), 1.0)
	_guide.say("Service customers!\nClick to collect your job.", false, false)
	if bay != 0:
		_point_at_object("item", bay, BAY_ARROW, PointerArrow.Dir.RIGHT)
		_restrict(func(k: String, u: int) -> bool:
			return (k in ["item", "bay"] and u == bay) or (k == "car" and _car_on_bay(u) == bay))
		_autoplay(func() -> void: game._on_object_clicked("item", bay))
		await _state_where(func(s: Dictionary) -> bool: return not s["jobs"].has(str(bay)))
		_clear_arrow()
		# RemoveCarInWorkbayProcess: the car rolls off the lift.
		for car: Dictionary in Backend.state()["cars"]:
			if car["bay_uid"] == bay:
				await Backend.take_car_off_bay(car["uid"])
	await Backend.set_tutorial(1, false)
	await get_tree().create_timer(1.0).timeout


# --- Step 1: a customer's job -----------------------------------------------------------

func _step_start_next_task(fresh: bool) -> void:
	_restrict(func(_k: String, _u: int) -> bool: return false)
	if fresh:
		await _welcome_back("Last time you were here,\nyou collected a task.\nLet's move on.")
	_guide.say("Customers will line up\noutside your garage.\nClick to see what the customer needs.", false, false)
	while true:
		var customer := await _waiting_customer()
		await _focus_on("customer", customer)
		_point_at_object("customer", customer, CUSTOMER_ARROW, PointerArrow.Dir.DOWN)
		_restrict(func(k: String, u: int) -> bool: return k == "customer" and u == customer)
		_autoplay(func() -> void: game._on_object_clicked("customer", customer))
		var content: Node = await _popup("customer")
		_autoplay(func() -> void: content.start_pressed.emit())
		_clear_arrow()
		_guide.outro()
		_point_in_popup(content, START_BUTTON_ARROW)
		# Started once the customer's car is on a lift with a job.
		var started: bool = await _either(
			func() -> bool: return await _state_where(func(s: Dictionary) -> bool: return _customer_started(s, customer)),
			func() -> bool: return await _closed(content))
		_clear_arrow()
		if started:
			break
		_guide.say("Customers will line up\noutside your garage.\nClick to see what the customer needs.", true, false)
	await Backend.set_tutorial(2, false)
	_guide.position = Vector2(RIGHT_X, MIDDLE_Y)
	_restrict(func(_k: String, _u: int) -> bool: return false)
	await _say("Collect on time!\nCome back when the job is done to collect your pay.", true, true)


# --- Step 2: customize the car ----------------------------------------------------------

func _step_customize_car(fresh: bool) -> void:
	_restrict(func(_k: String, _u: int) -> bool: return false)
	if fresh:
		await _welcome_back("Last time you were\nhere you started a task.\nLet's move on.")
	var car := _free_car()
	_guide.say("Looks like your car\nneeds some work.\nClick on your car to customize it.", false, false)
	await _guide.move_to(Vector2(RIGHT_X, MIDDLE_Y), 0.5)
	while true:
		await _focus_on("car", car)
		_point_at_object("car", car, CAR_ARROW, PointerArrow.Dir.DOWN)
		_restrict(func(k: String, u: int) -> bool: return k == "car" and u == car)
		_autoplay(func() -> void: game._on_object_clicked("car", car))
		var content: Node = await _popup("car_options")
		_autoplay(func() -> void: content.customize_pressed.emit())
		_clear_arrow()
		_guide.outro()
		_restrict(func(_k: String, _u: int) -> bool: return false)
		_point_in_popup(content, CUSTOMIZE_ARROW)
		var customized: bool = await _either(
			func() -> bool: return await _signal_true(game.customize_opened),
			func() -> bool: return await _closed(content))
		_clear_arrow()
		if customized:
			break
		_guide.say("Looks like your car\nneeds some work.\nClick on your car to customize it.", true, false)
	await Backend.set_tutorial(STEPS_DONE, true)


func _autoplay(action: Callable) -> void:
	if not _auto:
		return
	print("tutorial autoplay: step %d" % Backend.state()["tutorial"]["step"])
	get_tree().create_timer(0.8).timeout.connect(action)


func _finish() -> void:
	if _auto:
		print("tutorial autoplay: done, step %d" % Backend.state()["tutorial"]["step"])
	_restrict(Callable())
	_clear_arrow()
	await _guide.outro()
	game.hud.set_mission_dock_visible(true)
	queue_free()


# --- Helpers ---------------------------------------------------------------------------

func _welcome_back(last_time: String) -> void:
	await get_tree().create_timer(2.0).timeout
	_guide.position = Vector2(MIDDLE_X, MIDDLE_Y)
	await _say("Hi %s.\nWelcome back to Car Town!" % _name, true, true)
	await _say(last_time, false, true)
	await _guide.move_to(Vector2(RIGHT_X, MIDDLE_Y), 0.5)


## Shows a message and, with [param ok], waits for OK.
func _say(text: String, intro: bool, ok: bool) -> void:
	await _guide.say(text, intro, ok)
	if ok:
		_autoplay(func() -> void: _guide.ok_pressed.emit())
		await _guide.ok_pressed


func _restrict(filter: Callable) -> void:
	game.tutorial_filter = filter


func _focus_on(kind: String, uid: int) -> void:
	var pos: Variant = game.garage.object_anchor(kind, uid)
	if pos != null:
		await game.focus_camera(game.garage.to_global(pos) - Vector2(0, 40), 1.0, 1.0)


func _point_at_object(kind: String, uid: int, offset: Vector2, dir: PointerArrow.Dir) -> void:
	_clear_arrow()
	var pos: Variant = game.garage.object_anchor(kind, uid)
	if pos == null:
		return
	_arrow = PointerArrow.create(dir)
	_arrow.position = pos + offset
	game.garage.add_overlay(_arrow)


func _point_in_popup(content: Node, pos: Vector2) -> void:
	_clear_arrow()
	_arrow = PointerArrow.create(PointerArrow.Dir.UP)
	_arrow.position = pos
	content.add_child(_arrow)


func _clear_arrow() -> void:
	if _arrow != null and is_instance_valid(_arrow):
		_arrow.queue_free()
	_arrow = null


func _first_busy_bay() -> int:
	for key: String in Backend.state()["jobs"]:
		return int(key)
	return 0


func _car_on_bay(car_uid: int) -> int:
	return Backend.query().get_car(car_uid).get("bay_uid", 0)


func _free_car() -> int:
	for car: Dictionary in Backend.state()["cars"]:
		if car["placed"] and car["bay_uid"] == 0:
			return car["uid"]
	var cars: Array = Backend.state()["cars"]
	return cars[0]["uid"] if not cars.is_empty() else 0


static func _customer_started(s: Dictionary, customer: int) -> bool:
	for c: Dictionary in s["customers"]:
		if c["uid"] == customer:
			return c.get("bay_uid", 0) != 0 and s["jobs"].has(str(c["bay_uid"]))
	return true


## The first customer waiting outside, once there is one.
func _waiting_customer() -> int:
	while true:
		var drawn: Array[int] = game.garage.drawn_uids("customer")
		for c: Dictionary in Backend.state()["customers"]:
			if c.get("bay_uid", 0) == 0 and drawn.has(c["uid"]):
				return c["uid"]
		await Backend.state_changed
	return 0


func _state_where(test: Callable) -> bool:
	while not test.call(Backend.state()):
		await Backend.state_changed
	return true


func _popup(kind: String) -> Node:
	while true:
		var args: Array = await _signal_args(game.popup_opened)
		if args[0] == kind:
			return args[1]
	return null


static func _signal_args(sig: Signal) -> Array:
	var args: Variant = await sig
	return args if typeof(args) == TYPE_ARRAY else [args]


func _signal_true(sig: Signal) -> bool:
	await sig
	return true


func _closed(content: Node) -> bool:
	await content.tree_exiting
	return false


## Runs two waits side by side; returns the result of whichever ends first.
func _either(a: Callable, b: Callable) -> bool:
	var box := {"done": false, "value": false}
	var take := func(v: bool) -> void:
		if not box["done"]:
			box["done"] = true
			box["value"] = v
	_await_into(a, take)
	_await_into(b, take)
	while not box["done"]:
		await get_tree().process_frame
	return box["value"]


static func _await_into(wait: Callable, take: Callable) -> void:
	take.call(await wait.call())
