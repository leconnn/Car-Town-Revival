class_name CustomerPopup
extends Node2D
## The original Customer popup (views/traffic/CustomerCarInfo), at the
## original coordinates. Shown inside a FlashPopup.

signal start_pressed
signal close_pressed

const TITLE_COLOR := Color8(0x4E, 0x5F, 0x71)
const GLOW := Color8(0x53, 0x1A, 0x16)
## HandleCarClickCommand opens it as a 720 x 380 popup.
const POPUP_SIZE := Vector2(720, 380)


static func create(customer: Dictionary) -> CustomerPopup:
	var p := CustomerPopup.new()
	p._build(customer)
	return p


func _build(customer: Dictionary) -> void:
	var car: Dictionary = GameData.catalog.car(customer.get("car_id", 0))
	var job: Dictionary = GameData.catalog.job(customer.get("job_id", 0))
	var task_name: String = job.get("name", "job").to_lower()

	var masthead := FlashUi.make("CarOptionsMasthead")
	if masthead != null:
		masthead.position = Vector2(50, 20)
		add_child(masthead)
	var bg := FlashNine.make("UITanStrokedRoundedBg", Vector2(680, 225))
	bg.position = Vector2(20, 135)
	add_child(bg)

	var view := CarView.new()
	view.setup(customer, CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.82, 0.82)
	view.position = Vector2(176, 327)
	add_child(view)

	# Year and make, then the model in big letters (max 180 px wide).
	var year_make := FlashUi.styled_label("'%02d %s" % [int(car.get("year", 0)) % 100, car.get("make", "")],
		"casualA01", 22, Color.WHITE, GLOW, 6)
	year_make.position = Vector2(480, 105)
	add_child(year_make)
	var model := FlashUi.styled_label(car.get("model", ""), "casualA01", 40, Color.WHITE, GLOW, 8)
	model.position = Vector2(480, 105 + year_make.get_minimum_size().y + 20 - 10)
	var mw := model.get_minimum_size().x
	if mw > 180:
		model.scale = Vector2(180.0 / mw, 180.0 / mw)
	add_child(model)

	# The job icon sticks out above the frame, "Customer" under it.
	var icon := FlashUi.make("UITaskIcon%d" % customer.get("job_id", 0))
	var icon_w := 110.0
	var icon_h := 110.0
	var icon_x := 20.0 + (680.0 - icon_w) / 2.0
	if icon != null:
		var r := icon.local_bounds()
		icon_w = r.size.x
		icon_h = r.size.y
		icon_x = 20.0 + (680.0 - icon_w) / 2.0
		icon.position = Vector2(icon_x, -30) - r.position
		add_child(icon)
	var title := FlashUi.make("UICustomerTaskTitle")
	if title != null:
		title.styled_text("titleField", job.get("name", "").to_upper(), "sansD04")
		title.position = Vector2(icon_x + 15, -30 + 82)
		add_child(title)
	var who := FlashUi.styled_label("Customer", "casualA01", 36, TITLE_COLOR)
	who.position = Vector2(icon_x + (icon_w - who.get_minimum_size().x) / 2.0, -30 + icon_h - 5)
	add_child(who)

	var info := FlashUi.styled_label("This customer needs a %s!\nWill you take the job?" % task_name,
		"casualA01", 18, TITLE_COLOR)
	info.position = Vector2(430, 190)
	add_child(info)
	var gains := FlashUi.make("UICustomerTaskInfo")
	if gains != null:
		var payout: Dictionary = Backend.query().job_payout(job.get("id", 0))
		gains.styled_text("doneinField", Format.minutes(job.get("minutes", 0)).replace(" ", ""), "sansA02", 12)
		gains.styled_text("xpGainsField", "%d XP" % payout["xp"], "sansA03", 12)
		gains.styled_text("moneyGainsSprite/moneyGainsField", Format.number(payout["coins"]), "sansA03", 15)
		gains.position = Vector2(430, 190 + info.get_minimum_size().y + 5)
		add_child(gains)
	var cost := FlashUi.make("UICustomerTaskCost")
	if cost != null:
		cost.styled_text("fldLabel", "Cost:", "sansA01")
		cost.styled_text("cashSprite/moneyField", Format.number(job.get("price", 0)), "sansA02")
		cost.outline("cashSprite/moneyField", StoreTile.PRICE_GLOW, 4)
		cost.position = Vector2(20 + (680 - cost.local_bounds().size.x) / 2.0 + 50, 320)
		add_child(cost)

	var bubble := TalkBubble.create("I need a\n%s\nplease!" % task_name, 150)
	bubble.position = Vector2(20, 75)
	add_child(bubble)

	# Start (red) and Close (gray), centred under the panel like the original.
	var row := Node2D.new()
	var start := FlashTextButton.create("Start", FlashTextButton.Kind.RED, 85, 50, 22)
	start.position.x = 40
	start.pressed.connect(func() -> void: start_pressed.emit())
	row.add_child(start)
	var close := FlashTextButton.create("Close", FlashTextButton.Kind.GRAY, 85, 50, 22)
	close.position.x = 40 + start.size().x - 10
	close.pressed.connect(func() -> void: close_pressed.emit())
	row.add_child(close)
	var row_w := close.position.x + close.size().x
	row.position = Vector2(20 + (680 - row_w) / 2.0 + 20, 350)
	add_child(row)
