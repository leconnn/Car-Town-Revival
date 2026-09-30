class_name RacePopups
extends RefCounted
## The street race dialogs: the car you clicked in the lot (TownRacingCarInfoPopup),
## picking one of yours (TownRacingSelectCarPopup) and the win / lose results
## (TownRacingYouWinDialog, TownRacingYouLoseDialog).

const NAME_COLOR := Color.WHITE
const OUTLINE := Color8(0x53, 0x2C, 0x16)
const PRIZE_OUTLINE := Color8(0xC0, 0x91, 0x2E)
const PRIZE_COLOR := Color8(0xF3, 0xC8, 0x23)
const XP_COLOR := Color8(0x83, 0xC0, 0x41)
const CAR_SCALE := 0.5
const TILE_STEP := 96.0


## The opponent's car: its name and power, the prize, Race! / Cancel.
## [param on_race] runs when the player says Race.
static func open_car_info(tree: SceneTree, opponent: Dictionary, on_race: Callable) -> FlashPopup:
	var content := Node2D.new()
	var bg := FlashUi.make("TownRacingCarInfoPopupAsset")
	if bg != null:
		content.add_child(bg)
	var def: Dictionary = GameData.catalog.car(opponent["car_id"])
	var maker := FlashUi.styled_label("'%02d %s" % [int(def.get("year", 0)) % 100, def.get("make", "")], "sansD01", 13, Color.WHITE, OUTLINE, 3)
	maker.position = Vector2(43, 53)
	content.add_child(maker)
	var model := FlashUi.styled_label(str(def.get("model", "")), "casualA01", 24, Color.WHITE, OUTLINE, 4)
	model.position = Vector2(43, 62)
	content.add_child(model)
	var power := int(opponent["power"])
	var perf := FlashUi.make("UIPerformanceIconAsset")
	if perf != null:
		perf.position = Vector2(43 + model.get_minimum_size().x + 20, 66)
		content.add_child(perf)
		var amount := FlashUi.styled_label(str(power), "sansD04", 21, Color.WHITE)
		amount.position = perf.position + Vector2(perf.local_bounds().size.x + 2, 0)
		content.add_child(amount)
	var owner_label := FlashUi.styled_label(str(opponent["name"]), "casualA01", 26, Color.WHITE, OUTLINE, 5)
	owner_label.position = Vector2(43, 18)
	content.add_child(owner_label)
	var prize := Backend.query().race_prize(power)
	var caption := FlashUi.styled_label("Race Prize:", "casualA01", 20, Color.WHITE, PRIZE_OUTLINE, 5)
	caption.position = Vector2(55, 133)
	content.add_child(caption)
	var coins := FlashUi.styled_label("$ " + Format.number(prize["coins"]), "casualA01", 34, PRIZE_COLOR, PRIZE_OUTLINE, 6)
	coins.position = Vector2(92, 160)
	content.add_child(coins)
	var xp := FlashUi.styled_label("%d XP" % prize["xp"], "casualA01", 30, XP_COLOR)
	xp.position = Vector2(92, 203)
	content.add_child(xp)
	var view := CarView.new()
	view.setup(CarView.stock_entry(opponent["car_id"], opponent["color_id"]), CarView.VIEW_ANGLE, false)
	view.scale = Vector2(CAR_SCALE, CAR_SCALE)
	view.position = Vector2(340, 190)
	content.add_child(view)
	var logo := FlashUi.make("UIStreetChallengeLogo")
	if logo != null:
		logo.styled_text("fld", "STREET CHALLENGE", "sansD04", 19)
		logo.position = Vector2((445 - logo.local_bounds().size.x) / 2.0, -77)
		content.add_child(logo)
	var race := FrameButton.with_text("Race!", FrameButton.GREEN)
	var cancel := FrameButton.with_text("Cancel", FrameButton.GREY)
	var popup := FlashPopup.open_framed(tree, content, [10, 12, 12, 12], [race, cancel])
	race.pressed.connect(func() -> void:
		popup.close()
		on_race.call())
	cancel.pressed.connect(popup.close)
	return popup


## Your cars, strongest first: pick one to race with.
static func open_pick_car(tree: SceneTree, opponent: Dictionary, on_pick: Callable) -> GenericPopup:
	var cars: Array[Dictionary] = []
	for c: Dictionary in Backend.state()["cars"]:
		if not Backend.state()["car_tasks"].has(str(c["uid"])):
			cars.append(c)
	cars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Backend.query().car_score(a["uid"]) > Backend.query().car_score(b["uid"]))
	var holder := Node2D.new()
	var scroller := ItemScroller.create(500, 125, TILE_STEP)
	scroller.position_arrows(20, 50)
	holder.add_child(scroller)
	var popup_ref: Array[GenericPopup] = []
	scroller.set_items(cars.size(), func(i: int) -> Node2D:
		var car: Dictionary = cars[i]
		var tile := StoreTile.create(_car_picture(car), -1, false)
		tile.pressed.connect(func() -> void:
			popup_ref[0].close()
			on_pick.call(car["uid"]))
		return tile)
	var prize := Backend.query().race_prize(int(opponent["power"]))
	var hint := FlashUi.styled_label("Beat %s for $ %s and %d XP" % [opponent["name"], Format.number(prize["coins"]), prize["xp"]],
		"casualA01", 20, GenericPopup.TEXT_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size = Vector2(500, 26)
	hint.position = Vector2(0, 128)
	holder.add_child(hint)
	var cancel := FrameButton.with_text("Cancel", FrameButton.GREY)
	var p := GenericPopup.custom(tree, "Choose your car!", holder, Vector2(500, 158), [cancel])
	popup_ref.append(p)
	cancel.pressed.connect(p.close)
	return p


static func _car_picture(car: Dictionary) -> Node2D:
	var holder := Node2D.new()
	var view := CarView.new()
	view.setup(car, CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.17, 0.17)
	view.position = Vector2(0, 14)
	holder.add_child(view)
	var power := FlashUi.styled_label(str(Backend.query().car_score(car["uid"])), "sansD04", 16, GenericPopup.TEXT_COLOR)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power.size = Vector2(70, 20)
	power.position = Vector2(-35, 14)
	holder.add_child(power)
	return holder


## The result: both names and scores, and what you won. [param result] is
## Backend.finish_race's data.
static func open_result(tree: SceneTree, opponent: Dictionary, result: Dictionary, on_close: Callable) -> FlashPopup:
	var won: bool = result["win"]
	var gfx := FlashUi.make("TownRacingYouWinDialogGraphics" if won else "TownRacingYouLoseDialogGraphics")
	if gfx == null:
		return null
	if not won:
		_erase_lose_caption(gfx)
	var mine: String = Backend.state()["player"]["name"]
	gfx.styled_text("fldTitle", "You Win!" if won else "You Lose!", "casualA01")
	gfx.styled_text("yourNameField", mine, "casualA01")
	gfx.styled_text("challengerNameField", str(opponent["name"]), "casualA01")
	var score: int = result["score"]
	gfx.styled_text("yourScoreField", "FOUL" if score < 0 and result.get("fouled", false) else Format.number(score), "casualA01")
	gfx.styled_text("challengerScoreField", Format.number(result["opponent_score"]), "casualA01")
	gfx.styled_text("coinField", Format.number(result.get("coins", 0)), "casualA01")
	gfx.styled_text("xpField", "%d XP" % result.get("xp", 0), "casualA01")
	if won:
		gfx.styled_text("fldWinnings", "Winnings:", "casualA01")
	else:
		gfx.styled_text("fldConsolation", "Better luck next time!", "casualA01")
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(tree, gfx, [10, 12, 12, 12], [ok])
	Sound.play("SuccessSound2" if won else "ApprovalSound")
	ok.pressed.connect(popup.close)
	popup.closed.connect(on_close)
	return popup


## The lose graphic's background has a leftover "Car Number:" caption baked
## into its top edge (white, above the panel), which the game never used.
static func _erase_lose_caption(gfx: FlashSymbol) -> void:
	for c in gfx.get_children():
		if c is Sprite2D and (c as Sprite2D).texture != null and (c as Sprite2D).texture.resource_path.ends_with("trlose_26_0_0.png"):
			var img := (c as Sprite2D).texture.get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.fill_rect(Rect2i(360, 0, 90, 14), Color(0, 0, 0, 0))
			(c as Sprite2D).texture = ImageTexture.create_from_image(img)
			return
