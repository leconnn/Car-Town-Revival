class_name Tutorial
extends PanelContainer
## A short guided start, told by Rusty like the original. Each step waits for
## something to be true in the save, so it survives quitting mid-way.

const STEPS: Array[Dictionary] = [
	{"text": "Hey {name}, welcome to your new garage! I'm Rusty. I'll show you how to run this place.", "button": "Let's go!"},
	{"text": "Customers pay you to work on their cars. Click the car waiting out on the street and bring it onto your work bay.", "done": "customer_on_bay"},
	{"text": "Now pick a job. A Car Wash only takes a few minutes. Hit Start!", "done": "job_started"},
	{"text": "Jobs take real time, even while the game is closed. When the bubble says Collect!, click it to get paid.", "done": "job_collected"},
	{"text": "Nice work! Now let's make your own car look good. Click your car and try a new paint colour.", "done": "painted"},
	{"text": "Looking sharp! Want more? Buy decorations and more work bays in the Shop, and new cars at the Dealer.", "button": "Got it"},
	{"text": "Check Missions for goals and rewards, and use Town to drive around. Have fun, {name}!", "button": "Thanks, Rusty!"},
]

var _label: Label
var _button: Button
var _skip: Button


static func attach(game: Node) -> void:
	var t: Dictionary = Backend.state().get("tutorial", {})
	if t.get("done", false):
		return
	# Sits in the UI layer under the panels, so open windows cover it.
	game.add_tutorial(Tutorial.new())


func _ready() -> void:
	UiKit.place(self, Rect2(0, 1, 0, 1), Rect2(16, -90, 16, -90))
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(430, 0)
	var box := UiKit.vbox(8)
	add_child(box)
	box.add_child(UiKit.label("Rusty", 20, Color(1, 0.85, 0.3)))
	_label = UiKit.label("", 17)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(400, 0)
	box.add_child(_label)
	var row := UiKit.hbox()
	_button = UiKit.button("", _advance)
	row.add_child(_button)
	_skip = UiKit.button("Skip tutorial", func() -> void: _finish(), 13)
	row.add_child(_skip)
	box.add_child(row)
	Backend.state_changed.connect(_check)
	_show()


func _step() -> int:
	return Backend.state().get("tutorial", {}).get("step", 0)


func _show() -> void:
	var i := _step()
	if i >= STEPS.size():
		_finish()
		return
	var step: Dictionary = STEPS[i]
	_label.text = step["text"].format({"name": Backend.state()["player"]["name"]})
	_button.visible = step.has("button")
	_button.text = step.get("button", "")
	_check()


func _check() -> void:
	var i := _step()
	if i >= STEPS.size():
		return
	var cond: String = STEPS[i].get("done", "")
	if cond != "" and _condition(cond):
		_advance()


func _condition(cond: String) -> bool:
	var s := Backend.state()
	var stats: Dictionary = s.get("stats", {})
	match cond:
		"customer_on_bay":
			return stats.get("customers_accepted", 0) > 0 or s["customers"].any(func(c: Dictionary) -> bool: return c.get("bay_uid", 0) != 0)
		"job_started":
			return not s["jobs"].is_empty() or stats.get("jobs_started", 0) > 0
		"job_collected":
			return stats.get("jobs_collected", 0) > 0
		"painted":
			return stats.get("cars_painted", 0) > 0
	return false


func _advance() -> void:
	var next := _step() + 1
	await Backend.set_tutorial(next, next >= STEPS.size())
	if next >= STEPS.size():
		queue_free()
	else:
		_show()


func _finish() -> void:
	await Backend.set_tutorial(STEPS.size(), true)
	queue_free()
