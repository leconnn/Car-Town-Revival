class_name CarOptionsPopup
extends Node2D
## The original CarOptions popup (views/car/CarOptions), shown when you click
## one of your own cars: the car on the masthead, Customize and Sell
## buttons, and a scroller of the jobs this car can go out on. 718 x 399
## (PopupSimpleMediumLargeFrameDecorator).

signal customize_pressed
signal sell_pressed
signal start_task(job_id: int)
signal stop_task

const POPUP_SIZE := Vector2(718, 399)

var car_uid: int


static func create(uid: int) -> CarOptionsPopup:
	var p := CarOptionsPopup.new()
	p.car_uid = uid
	p._build()
	return p


func _build() -> void:
	var car := Backend.query().get_car(car_uid)
	var container := Node2D.new()
	container.position.x = 25
	add_child(container)
	var masthead := FlashUi.make("CarOptionsMasthead")
	if masthead != null:
		masthead.position = Vector2(25, 21)
		container.add_child(masthead)

	var bg := FlashNine.make("UIWhiteStrokedRoundedBg", Vector2(664, 247))
	bg.position = Vector2(3, 128)
	container.add_child(bg)

	var view := CarView.new()
	view.setup(car, CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.55, 0.55)
	view.position = Vector2(126, 87)
	container.add_child(view)

	var customize := FlashButton.of("BtnEdit", "Customize")
	if customize != null:
		(customize.body as FlashSymbol).styled_text("fld", "Customize", "casualA01")
		customize.position = Vector2(304, 56)
		customize.pressed.connect(func() -> void: customize_pressed.emit())
		container.add_child(customize)
	var sell := FlashButton.of("BtnTradeIn")
	if sell != null:
		var gfx := sell.body as FlashSymbol
		gfx.styled_text("fldText", "Sell", "casualA01")
		gfx.styled_text("fldCurrency", "$", "sansA02")
		sell.position = Vector2(447, 64)
		sell.pressed.connect(func() -> void: sell_pressed.emit())
		container.add_child(sell)

	# The tasks, 147 px apart, starting at the white panel.
	var ids := Backend.query().car_task_ids(car_uid)
	var running: Dictionary = Backend.state()["car_tasks"].get(str(car_uid), {})
	var scroller := ItemScroller.create(618, 281, 147)
	scroller.position = Vector2(30, 83)
	scroller.position_arrows(25, 149)
	container.add_child(scroller)
	scroller.set_items(ids.size(), func(i: int) -> Node2D:
		var id: int = ids[i]
		var mine: bool = running.get("job_id", 0) == id
		var tile := TaskTile.create(id, running if mine else {}, not running.is_empty() and not mine)
		tile.position.y = 2
		tile.start_pressed.connect(func() -> void: start_task.emit(id))
		tile.stop_pressed.connect(func() -> void: stop_task.emit())
		return tile)
	if ids.is_empty():
		var none := FlashUi.styled_label("This car can't go out on any jobs.", "casualA01", 20, CustomerPopup.TITLE_COLOR)
		none.position = Vector2(180, 240)
		container.add_child(none)
