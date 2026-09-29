class_name WorkPopup
extends Node2D
## The original "Work in Progress" popup (views/tasks/FinishTaskNowPopup with
## FinishJobNowPopupContent): the job's icon and title, what it pays, a large
## progress bar with the time left, Stop Job, and Instant Finish on the frame.
## Open it with [method open] for a work bay or [method open_car] for a car
## out on a car task.

## Frame padding [top, right, bottom, left].
const FRAME_PAD := [-30, 11, 17, 21]
const TITLE_OUTLINE := Color8(0x23, 0x3B, 0x57)

signal stop_pressed
signal finish_pressed

var _job: Dictionary
var _price := 0
var _content: FlashSymbol
var _bar: FlashSymbol
var _progress: FlashProgress
var _stop: FlashTextButton
var _popup: FlashPopup
var _done := false


## Opens the popup for the job on [param bay]. Returns null if there's none.
static func open(tree: SceneTree, bay: int) -> WorkPopup:
	var job: Dictionary = Backend.state()["jobs"].get(str(bay), {})
	return null if job.is_empty() else _open(tree, job, Backend.query().finish_now_price(bay, Backend.now()))


## Opens the popup for the car task [param car_uid] is out on, or null.
static func open_car(tree: SceneTree, car_uid: int) -> WorkPopup:
	var job: Dictionary = Backend.state()["car_tasks"].get(str(car_uid), {})
	return null if job.is_empty() else _open(tree, job, Backend.query().car_task_finish_price(car_uid, Backend.now()))


static func _open(tree: SceneTree, job: Dictionary, price: int) -> WorkPopup:
	var w := WorkPopup.new()
	w._job = job
	w._price = price
	w._build()
	var finish := FrameButton.with_content(w._credit_label(price), w._credit_size, FrameButton.LIGHT_BLUE)
	finish.pressed.connect(func() -> void: w.finish_pressed.emit())
	# The original asked for (-30, 0, 0, 0), but Flash also counted the close
	# button and some invisible zero-scale shapes in the content's bounds, so
	# its frame came out with these margins (measured from the original).
	w._popup = FlashPopup.open_framed(tree, w, FRAME_PAD, [finish])
	w._finish_button = finish
	return w


var _finish_button: FrameButton
var _credit_size := Vector2.ZERO


func close() -> void:
	if _popup != null:
		_popup.close()


func _build() -> void:
	var def: Dictionary = GameData.catalog.job(_job["job_id"])
	var payout: Dictionary = Backend.query().job_payout(_job["job_id"])
	_content = FlashUi.make("FinishJobNowPopupContent")
	if _content == null:
		return
	add_child(_content)
	_content.styled_text("titleField", "Work in Progress", "casualA01")
	_content.outline("titleField", TITLE_OUTLINE, 6)
	_content.styled_text("xpField", "%d XP" % payout["xp"], "sansD01")
	_content.styled_text("coinField", Format.number(payout["coins"]), "sansD01")
	_content.styled_text("messageField", "Pay %d Blue Coins to finish this job now!" % _price, "sansA02")

	# The task icon, centred in its container, with the title banner on it.
	var holder := _content.part("taskIconContainer") as Node2D
	var icon := FlashUi.make("UITaskIcon%d" % _job["job_id"])
	if holder != null and icon != null:
		var title := FlashUi.make("UICustomerTaskTitle")
		if title != null:
			title.styled_text("titleField", def.get("name", ""), "sansD04")
			title.position = Vector2(15, 81)
			icon.add_child(title)
		var r := icon.local_bounds()
		icon.position = -r.position - r.size / 2.0
		holder.add_child(icon)

	# ProgressWithTimeLarge at (56, 250), coloured like the job.
	_bar = FlashUi.make("UIStatusProgressWithTimeGfxLarge")
	if _bar != null:
		_bar.position = Vector2(56, 250)
		_content.add_child(_bar)
		_progress = FlashProgress.attach(_bar, JobStatus.COLORS.get(def.get("color", "green"), JobStatus.COLORS["green"]))
		# textAutoSize(RIGHT): the time hugs the bar's right end.
		var field := _bar.part("timeLeftField") as FlashText
		if field != null:
			field.set_style("sansA01")
			field.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_stop = FlashTextButton.create("Stop Job", FlashTextButton.Kind.GRAY, 108, 49, 23, true)
	_stop.position = Vector2(355, 270)
	_stop.pressed.connect(func() -> void: stop_pressed.emit())
	_content.add_child(_stop)
	_refresh()


func _credit_label(price: int) -> Node2D:
	var label := FlashUi.make("CreditIconLabel")
	if label == null:
		var fallback := Node2D.new()
		_credit_size = Vector2(120, 30)
		return fallback
	label.styled_text("fldAmount", str(price), "sansA02")
	label.styled_text("fldLabel", "Instant Finish", "casualA01")
	# Frame 2 of the icon is the in-game currency (1 was Facebook Credits).
	var icon := label.part("creditIcon")
	if icon is FlashSymbol:
		(icon as FlashSymbol).goto(1)
	var r := label.local_bounds()
	_credit_size = r.size
	var holder := Node2D.new()
	label.position = -r.position
	holder.add_child(label)
	return holder


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _progress == null or _done:
		return
	if not _progress.show_job(_job, Backend.now()):
		return
	# Job complete: no more Stop Job, and Instant Finish becomes a grey Close.
	_done = true
	if _stop != null:
		_stop.queue_free()
	if _finish_button != null:
		var close_btn := FrameButton.with_text("Close", FrameButton.GREY)
		close_btn.position = _finish_button.position
		close_btn.pressed.connect(close)
		_finish_button.get_parent().add_child(close_btn)
		_finish_button.queue_free()
		_finish_button = null
