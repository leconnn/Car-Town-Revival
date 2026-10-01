class_name DocksPopups
extends RefCounted
## The Docks' popups (integrations/docks/views): Tony's boats to choose from,
## the shipping manifest, the car you found in a crate, asking for a
## particular car and "She's All Yours!".

const TEXT_COLOR := Color8(0x33, 0x4D, 0x66)
const GREY_TEXT := Color8(0x99, 0x99, 0x99)
const POPUP_TEXT := Color8(0x55, 0x55, 0x55)
const RED_TEXT := Color8(0x8C, 0x3A, 0x35)
const GLOW := Color8(0x23, 0x4F, 0x70)


## A button with the price: a coin (or Blue Coin) icon, the amount and a label.
static func price_button(label: String, cost: int, color: int) -> FrameButton:
	var holder := Node2D.new()
	var blue := Backend.query().docks_currency() == "blue"
	var icon := FlashUi.make("UIBlueCoinXL" if blue else "UIIconCoin")
	var x := 0.0
	if icon != null:
		var r := icon.local_bounds()
		var k := 26.0 / maxf(r.size.y, 1.0)
		icon.scale = Vector2(k, k)
		icon.position = -r.position * k + Vector2(0, -13)
		holder.add_child(icon)
		x = r.size.x * k + 6
	var text := FlashUi.styled_label("%s  %s" % [Format.number(cost), label], "casualA01", 22, Color.WHITE)
	text.position = Vector2(x, -text.get_minimum_size().y / 2.0)
	holder.add_child(text)
	var size := Vector2(x + text.get_minimum_size().x, 30)
	var inner := Node2D.new()
	holder.position = Vector2(0, 15)
	inner.add_child(holder)
	return FrameButton.with_content(inner, size, color)


## DocksNextShipPopup: Tony's boat, or both when his special boat is in.
static func open_next_ship(tree: SceneTree, special: bool, chosen: Callable) -> FlashPopup:
	var gfx := FlashUi.make("swcassets.docks.DocksNextShipPopupContent")
	if gfx == null:
		return null
	var root := Node2D.new()
	root.add_child(gfx)
	# The art's own text fields were moved around by code we don't have;
	# lay the words out plainly instead.
	_hide(gfx, ["messageField", "shipField1", "shipField2", "shipField3", "boatField1", "boatField2"])
	var title := FlashUi.styled_label("Which boat would you like to search?" if special else "Search the next boat?",
		"sansD01", 22, POPUP_TEXT)
	var middle := 288.0
	var panel := gfx.part("background") as FlashSymbol
	if panel != null:
		var pr := panel.local_bounds()
		middle = panel.position.x + pr.position.x + pr.size.x / 2.0
	title.position = Vector2(middle - title.get_minimum_size().x / 2.0, 22)
	root.add_child(title)
	var popup := FlashPopup.open_bare(tree, root)
	var add_boat := func(cls: String, x: float, boat_id: int, ship: String, which: String) -> void:
		var boat := FlashUi.make(cls)
		var centre := x + 103
		if boat != null:
			# Centred on the grey panel, by its drawn bounds.
			var r := boat.local_bounds()
			boat.position = Vector2(x, 63 + 150 * 0.5 - r.size.y * 0.5) - r.position
			root.add_child(boat)
			centre = boat.position.x + r.position.x + r.size.x / 2.0
		var name := FlashUi.styled_label(ship, "sansD01", 18, POPUP_TEXT)
		name.position = Vector2(centre - name.get_minimum_size().x / 2.0, 222)
		root.add_child(name)
		if which != "":
			var label := FlashUi.styled_label(which, "sansD01", 14, GREY_TEXT)
			label.position = Vector2(centre - label.get_minimum_size().x / 2.0, 246)
			root.add_child(label)
		var see := FrameButton.with_text("See Manifest", FrameButton.GREEN)
		see.position = Vector2(centre, 315)
		see.pressed.connect(func() -> void:
			popup.close()
			chosen.call(boat_id))
		root.add_child(see)
	if special:
		add_boat.call("swcassets.docks.Boat1Small", 127, 1, "SS AMEOWRICA", "1st Boat")
		add_boat.call("swcassets.docks.Boat2Small", 416, 2, "SS KITTYKAT", "2nd Boat")
	else:
		add_boat.call("swcassets.docks.Boat1Small", 273, 1, "SS AMEOWRICA", "")
	return popup


## DocksManifestPopup: the boat's eight cars (crossed out once passed over),
## and Search for the price, or Close while you're searching it.
static func open_manifest(tree: SceneTree, search: Callable, ask_for_car: Callable) -> FlashPopup:
	var gfx := FlashUi.make("ShippingManifestPopupContent")
	if gfx == null:
		return null
	var root := Node2D.new()
	root.add_child(gfx)
	gfx.styled_text("titleField", "Shipping Manifest", "casualA01")
	var boat: Dictionary = Backend.state()["docks"]["boat"]
	var passed := _passed_cars(boat)
	var cars: Array = boat.get("cars", [])
	for i in cars.size():
		var tile := _manifest_car(int(cars[i]), passed.has(int(cars[i])))
		tile.position = Vector2(40 + 195 * (i % 2), 185 + 90 * (i / 2))
		root.add_child(tile)
	var popup := FlashPopup.open_bare(tree, root)
	var button: FrameButton
	if boat.get("active", false):
		button = FrameButton.with_text("Close", FrameButton.RED)
		button.pressed.connect(popup.close)
	else:
		var cost := Backend.query().docks_search_price()
		button = price_button("Search Ship", cost, FrameButton.BLUE) if cost > 0 else FrameButton.with_text("Free Search!", FrameButton.BLUE)
		button.pressed.connect(func() -> void:
			popup.close()
			search.call())
		if Backend.state()["docks"]["first_done"]:
			# "Vinny here tells me you're lookin' for a rare car" (SHOW_CAR_PICKER).
			var ask := FlashUi.styled_label("Looking for a certain car?", "casualA01", 16, GLOW)
			var ask_button := FlashButton.wrap_node(_wrap(ask), Rect2(Vector2.ZERO, ask.get_minimum_size()))
			ask_button.position = Vector2(230 - ask.get_minimum_size().x / 2.0, 505)
			ask_button.pressed.connect(func() -> void:
				popup.close()
				ask_for_car.call())
			root.add_child(ask_button)
	button.position = Vector2(230, 565)
	root.add_child(button)
	return popup


## DocksManifestCarSprite: thumbnail, make and model, and its list price.
static func _manifest_car(car_id: int, passed: bool) -> Node2D:
	var root := Node2D.new()
	var bg := FlashUi.make("StoreItemNewIconBg")
	var thumb_at := Vector2(40, 40)
	if bg != null:
		root.add_child(bg)
		var r := bg.local_bounds()
		thumb_at = r.position + r.size / 2.0 + Vector2(3, 3)
	var tex := GameData.texture(GameData.car_art.get(str(car_id), {}).get("thumb", {}).get("file", ""))
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		var k := minf(1.0, 70.0 / maxf(tex.get_width(), tex.get_height()))
		s.scale = Vector2(k, k)
		s.position = thumb_at
		root.add_child(s)
	if passed:
		var x := FlashUi.make("BigRedX")
		if x != null:
			x.position = thumb_at
			root.add_child(x)
		else:
			var cross := FlashUi.styled_label("X", "casualA01", 48, RED_TEXT)
			cross.position = thumb_at - cross.get_minimum_size() / 2.0
			root.add_child(cross)
	var car: Dictionary = GameData.catalog.car(car_id)
	var make := FlashUi.styled_label(str(car.get("make", "")), "casualA01", 14, TEXT_COLOR)
	make.position = Vector2(83, 4)
	root.add_child(make)
	var model := FlashUi.styled_label(str(car.get("model", "")), "casualA01", 12, TEXT_COLOR)
	model.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	model.custom_minimum_size = Vector2(100, 0)
	model.size = Vector2(100, 0)
	model.position = Vector2(83, 22)
	root.add_child(model)
	var blue := Backend.query().docks_currency() == "blue"
	var price := int(car.get("blue_price" if blue else "price", 0))
	var msrp := FlashUi.styled_label("*MSRP Price: %s%s" % ["" if blue else "$", Format.number(price)], "casualA01", 11,
		GREY_TEXT if passed else RED_TEXT)
	msrp.position = Vector2(83, 58)
	root.add_child(msrp)
	return root


## DocksOpenedContainerPopup: "You found a" car, the manifest underneath, and
## Claim! or Search Again (unless it was the last crate).
static func open_found(tree: SceneTree, car_id: int, claim: Callable, search_again: Callable) -> FlashPopup:
	var gfx := FlashUi.make("swcassets.docks.DocksOpenedContainerPopupContent")
	if gfx == null:
		return null
	var root := Node2D.new()
	root.add_child(gfx)
	var boat: Dictionary = Backend.state()["docks"]["boat"]
	var states: Array = boat.get("states", [])
	var last := not states.has(GameLogic.CRATE_CLOSED)
	gfx.styled_text("titleField", "You found a", "sansD01")
	var name := GameData.car_name(car_id)
	gfx.styled_text("carField", name, "sansD01", 22 if name.length() <= 18 else 16)
	if last:
		gfx.styled_text("messageField", "You're the proud owner of a", "sansD01")
	else:
		gfx.styled_text("messageField", "Not the car you were lookin' for, but a beaut' nonetheless.\nYou can keep this one or keep searchin' for a little extra cash.", "sansD01")
	var bg := gfx.part("background") as Node2D
	var view := CarView.new()
	view.setup(CarView.stock_entry(car_id, 0), CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.45, 0.45)
	var bg_rect := Rect2(Vector2(164, 63), Vector2(250, 150))
	if bg is FlashSymbol:
		var r := (bg as FlashSymbol).local_bounds()
		bg_rect = Rect2(bg.position + r.position, r.size)
	view.position = Vector2(bg_rect.get_center().x, bg_rect.get_center().y + 10)
	root.add_child(view)
	# The rest of the manifest along the bottom (DocksManifestMiniCarSprite).
	var cars: Array = boat.get("cars", [])
	var passed := _passed_cars(boat)
	for i in cars.size():
		var id := int(cars[i])
		var tex := GameData.texture(GameData.car_art.get(str(id), {}).get("thumb", {}).get("file", ""))
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		var k := minf(1.0, 48.0 / maxf(tex.get_width(), tex.get_height()))
		s.scale = Vector2(k, k)
		s.position = Vector2(150 + 60 * i, 290)
		if id == car_id:
			s.scale *= 1.2
		elif passed.has(id):
			s.modulate = Color(0.4, 0.4, 0.4, 0.6)
		root.add_child(s)
	var popup := FlashPopup.open_bare(tree, root, false)
	var claim_button := FrameButton.with_text("Claim!", FrameButton.GREEN)
	claim_button.position = Vector2(360 if last else 445, 345)
	claim_button.pressed.connect(func() -> void:
		popup.close()
		claim.call())
	root.add_child(claim_button)
	if not last:
		var again := price_button("Search Again", Backend.query().docks_search_again_price(), FrameButton.BLUE)
		again.position = Vector2(265, 345)
		again.pressed.connect(func() -> void:
			popup.close()
			search_again.call())
		root.add_child(again)
	return popup


## "She's All Yours!" (DocksCarInStoragePopup).
static func open_claimed(tree: SceneTree, car_id: int) -> void:
	GenericPopup.message(tree, "She's All Yours!", "You're the proud owner of a\n%s!" % GameData.car_name(car_id))
	Sound.play("SuccessSound2")


## DocksSelectCarPopup: every retired car Tony can get, to ask for one.
static func open_select_car(tree: SceneTree, picked: Callable) -> GenericPopup:
	var root := Node2D.new()
	var message := FlashUi.styled_label("Vinny here tells me you're lookin' for a rare, outta stock car.\nTell me what you're lookin' for and I'll see what I can do.",
		"sansD01", 16, TEXT_COLOR)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(560, 0)
	message.size = Vector2(560, 0)
	root.add_child(message)
	var ids := Backend.query().docks_pool(1, Backend.now())
	var blue := Backend.query().docks_currency() == "blue"
	ids.sort_custom(func(a: int, b: int) -> bool:
		return GameData.car_name(a) < GameData.car_name(b))
	var box := ScrollContainer.new()
	box.position = Vector2(0, 60)
	box.custom_minimum_size = Vector2(580, 330)
	box.size = Vector2(580, 330)
	box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	root.add_child(box)
	var popup := GenericPopup.custom(tree, "Tony's Wish List", root, Vector2(580, 390), [])
	for id: int in ids:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(138, 96)
		var tile := Node2D.new()
		var tex := GameData.texture(GameData.car_art.get(str(id), {}).get("thumb", {}).get("file", ""))
		if tex != null:
			var s := Sprite2D.new()
			s.texture = tex
			var k := minf(1.0, 64.0 / maxf(tex.get_width(), tex.get_height()))
			s.scale = Vector2(k, k)
			s.position = Vector2(69, 34)
			tile.add_child(s)
		var name := FlashUi.styled_label(GameData.car_name(id), "casualA01", 12, TEXT_COLOR)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.clip_text = true
		name.custom_minimum_size = Vector2(136, 0)
		name.size = Vector2(136, 0)
		name.position = Vector2(1, 66)
		tile.add_child(name)
		var price := int(GameData.catalog.car(id).get("blue_price" if blue else "price", 0))
		var cost := FlashUi.styled_label("%s%s" % ["" if blue else "$", Format.number(price)], "casualA01", 12, RED_TEXT)
		cost.position = Vector2(69 - cost.get_minimum_size().x / 2.0, 80)
		tile.add_child(cost)
		var button := FlashButton.wrap_node(tile, Rect2(0, 0, 138, 96))
		button.pressed.connect(func() -> void:
			popup.close()
			picked.call(id))
		slot.add_child(button)
		grid.add_child(slot)
	return popup


## DocksBuyConfirmationPopup: "You got good taste kid!", the car, and what it
## costs to start searchin'.
static func open_buy_confirm(tree: SceneTree, car_id: int, cost: int, buy: Callable, back: Callable) -> FlashPopup:
	var gfx := FlashUi.make("swcassets.docks.DocksBuyConfirmPopupContent")
	if gfx == null:
		return null
	var root := Node2D.new()
	root.add_child(gfx)
	var car: Dictionary = GameData.catalog.car(car_id)
	gfx.styled_text("titleField", "You got good taste kid!", "sansD01")
	gfx.styled_text("messageField", "This %s is on the ship with seven other cars." % str(car.get("make", "")), "sansD01")
	var blue := Backend.query().docks_currency() == "blue"
	gfx.styled_text("costField1", "It'll cost %s%s to start Searchin'" % ["" if blue else "$", Format.number(cost)], "sansD01")
	_hide(gfx, ["costField2"])
	var view := CarView.new()
	view.setup(CarView.stock_entry(car_id, 0), CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.8, 0.8)
	view.position = Vector2(288, 160)
	root.add_child(view)
	var popup := FlashPopup.open_bare(tree, root)
	var buy_button := price_button("Buy", cost, FrameButton.BLUE)
	buy_button.position = Vector2(220, 345)
	buy_button.pressed.connect(func() -> void:
		popup.close()
		buy.call())
	root.add_child(buy_button)
	var back_button := FrameButton.with_text("Back", FrameButton.GREY)
	back_button.position = Vector2(390, 345)
	back_button.pressed.connect(func() -> void:
		popup.close()
		back.call())
	root.add_child(back_button)
	return popup


## Cars in crates already opened and passed over.
static func _passed_cars(boat: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var states: Array = boat.get("states", [])
	for i in states.size():
		if int(states[i]) == GameLogic.CRATE_PASSED:
			out.append(int(boat["crates"][i]))
	return out


static func _hide(gfx: FlashSymbol, parts: Array) -> void:
	for p: String in parts:
		var node := gfx.part(p) as CanvasItem
		if node != null:
			node.visible = false


static func _wrap(c: CanvasItem) -> Node2D:
	var n := Node2D.new()
	n.add_child(c)
	return n
