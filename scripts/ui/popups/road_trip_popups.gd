class_name RoadTripPopups
extends Node2D
## Road trips: picking where to go (views/roadtrip/RoadTripDestinationsPopup,
## a destination tile per place, DestinationSprite on UITaskSpriteGfxNew) and
## "Back home!" when the car returns.

signal destination_chosen(trip_id: int)

const POPUP_SIZE := Vector2(710, 390)
const TITLE_COLOR := Color8(0xFF, 0xF5, 0xE5)
## RoadTrip.DESTINATION_SNOW_BEACH: the CR-Z's two-in-one trip.
const SNOW_BEACH := 6

var car_uid: int


static func open_destinations(tree: SceneTree, uid: int) -> RoadTripPopups:
	var p := RoadTripPopups.new()
	p.car_uid = uid
	p._build()
	var popup := FlashPopup.open(tree, p, true, false, POPUP_SIZE)
	p.destination_chosen.connect(func(_id: int) -> void: popup.close())
	return p


## "Back home!": who came along and what the trip made.
static func open_complete(tree: SceneTree, r: GameResult) -> void:
	var d := r.data
	var trip: Dictionary = GameData.catalog.road_trips.get(int(d.get("road_trip", 0)), {})
	var text := "%s Road Trip complete!\n%d/%d passengers.\n\nYou made $%s\nand %d XP" % [
		trip.get("name", ""), d["passengers"], d["seats"], Format.number(d["coins"]), d["xp"]]
	if d.get("full", false):
		text += "\n\nAwesome trip! Everyone chipped in for gas."
	GenericPopup.message(tree, "Back home!", text)
	Sound.play("SuccessSound1")


func _build() -> void:
	var car := Backend.query().get_car(car_uid)
	var container := Node2D.new()
	container.position.x = 25
	add_child(container)
	var masthead := FlashUi.make("CarOptionsMasthead")
	if masthead != null:
		masthead.position = Vector2(25, 21)
		container.add_child(masthead)
	var icon := FlashUi.make("UITaskIcon%d" % GameLogic.ROAD_TRIP_JOB)
	if icon != null:
		icon.position = Vector2(263, -25)
		container.add_child(icon)
		var title := FlashUi.styled_label("Road Trip", "sansD04", 20, TITLE_COLOR, Color.BLACK, 2)
		title.position = Vector2(70 - title.get_minimum_size().x / 2.0, 82)
		icon.add_child(title)
	var view := CarView.new()
	view.setup(car, CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.55, 0.55)
	view.position = Vector2(126, 87)
	container.add_child(view)
	var cls := int(GameData.catalog.car(car["car_id"]).get("class_id", 0))
	var rating := FlashUi.make("swcassets.roadtrip.CarClassRating%d" % cls)
	if rating != null:
		rating.scale = Vector2(0.72, 0.72)
		rating.position = Vector2(5, 35)
		container.add_child(rating)

	var bg := FlashNine.make("UIWhiteStrokedRoundedBg", Vector2(664, 247))
	bg.position = Vector2(2, 128)
	container.add_child(bg)
	var ids := Backend.query().road_trip_ids(car_uid)
	var scroller := ItemScroller.create(592, 281, 148)
	scroller.position = Vector2(44, 83)
	scroller.position_arrows(25, 149)
	container.add_child(scroller)
	scroller.set_items(ids.size(), func(i: int) -> Node2D:
		var tile := _destination(car["car_id"], ids[i])
		tile.position.y = 2
		return tile)


## DestinationSprite: the place's icon and name, "Done in", what each
## passenger earns, the cost and a Go button.
func _destination(car_id: int, trip_id: int) -> Node2D:
	var root := Node2D.new()
	var job: Dictionary = GameData.catalog.job(GameLogic.ROAD_TRIP_JOB)
	var trip: Dictionary = GameData.catalog.road_trips[trip_id]
	var gfx := FlashUi.make("UITaskSpriteGfxNew")
	if gfx == null:
		return root
	root.add_child(gfx)
	for part: String in ["masteryLevels", "fldClickToCancel", "fldUnlocksAt", "fldUnlocksLevel", "creditsSprite",
			"freeField", "moneyGainsSprite", "gigawattsLabel", "additionalCostText"]:
		var p := gfx.part(part) as CanvasItem
		if p != null:
			p.visible = false
	var holder := gfx.part("icon") as Node2D
	var dest_icon := FlashUi.make("UIDestIcon%d" % trip_id)
	if holder != null and dest_icon != null:
		holder.add_child(dest_icon)
	gfx.styled_text("titleField", str(trip.get("name", "")), "sansD04")
	gfx.styled_text("doneinField", "Done in: %s" % Format.minutes(job.get("minutes", 0)).replace(" ", ""), "sansA01")
	if trip_id == SNOW_BEACH:
		gfx.styled_text("roadTripGainsSprite/moneyGainsField", "CR-Z 2 in 1 BONUS", "sansA03", 10)
	else:
		# "Earns per passenger:", with the amount the original left to the class badge.
		var pay := Backend.query().road_trip_pay(car_id, trip_id, 1)
		gfx.styled_text("roadTripGainsSprite/moneyGainsField", "Per passenger: $%s" % Format.number(pay["per_coins"]), "sansA01")
	var xp := gfx.part("xpGainsField") as CanvasItem
	if xp != null:
		xp.visible = false
	gfx.styled_text("costHead", "Cost:", "sansA01")
	gfx.styled_text("cashSprite/moneyField", Format.number(job.get("price", 0)), "sansA03")
	gfx.outline("cashSprite/moneyField", StoreTile.PRICE_GLOW, 4)
	var size := gfx.local_bounds().end
	var go := FlashTextButton.create("Go", FlashTextButton.Kind.RED, 62, 35, 18, true)
	go.position = Vector2(int((size.x - go.size().x) / 2.0), 216)
	go.pressed.connect(func() -> void: destination_chosen.emit(trip_id))
	root.add_child(go)
	if job.get("price", 0) > Backend.state()["player"]["coins"]:
		go.modulate = Color(0.7, 0.7, 0.7)
	return root
