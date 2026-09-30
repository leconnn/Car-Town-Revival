class_name CollectionPopups
extends RefCounted
## Car collections: the "Collection Complete!" celebration
## (CarCollectionCompletePopupContent) and the list of sets in the Glove Box
## (CarCollectionsPopupContent): each set with how many of its cars you own,
## and for the selected one its cars and reward.

const TEXT_COLOR := Color8(0x33, 0x4D, 0x66)
const CAR_SCALE := 0.15
const LIST_STEP := 30.0
const LIST_TOP := 100.0
const LIST_X := 22.0
const LIST_HEIGHT := 340.0
const COIN_COLOR := Color8(0xF3, 0xCE, 0x23)
const GLOW := Color8(0x23, 0x4F, 0x70)


## The celebration for a notice from the rules ({collection_id, name, coins,
## xp, plaque_id}).
static func open_complete(tree: SceneTree, n: Dictionary) -> FlashPopup:
	var gfx := FlashUi.make("CarCollectionCompletePopupContent")
	if gfx == null:
		return null
	gfx.styled_text("titleFld", "Collection Complete!", "casualA01")
	gfx.styled_text("youCompletedFld", "You completed the", "sansD01")
	gfx.styled_text("collectionLabelFld", str(n["name"]), "casualA01")
	gfx.styled_text("yourRewardLabelFld", "Your Reward:", "casualA01")
	gfx.styled_text("moneyFld", Format.number(n["coins"]), "casualA01")
	gfx.styled_text("xpFld", "%d XP" % n["xp"], "casualA01")
	var ids: Array = GameData.catalog.car_collections.get(n["collection_id"], {}).get("car_ids", [])
	for i in 4:
		var holder := gfx.part("car%d" % i) as Node2D
		if holder != null and i < ids.size():
			var thumb := _car_thumb(int(ids[i]), false)
			thumb.scale = Vector2(0.12, 0.12)
			thumb.position = Vector2(34, 44)
			holder.add_child(thumb)
	var plaque := int(n.get("plaque_id", 0))
	var plaque_holder := gfx.part("plaqueHolder") as Node2D
	if plaque > 0 and plaque_holder != null:
		gfx.styled_text("storageFld", "Plaque added to your storage", "casualA01")
		var tex := GameData.texture(GameData.item_art.get(str(plaque), {}).get("thumb", {}).get("file", ""))
		if tex != null:
			var s := Sprite2D.new()
			s.texture = tex
			plaque_holder.add_child(s)
	else:
		gfx.styled_text("storageFld", "", "casualA01")
	var splash := gfx.part("splosion") as FlashSymbol
	if splash != null:
		splash.goto(0)
		splash.play(30.0, false)
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(tree, gfx, [10, 12, 12, 12], [ok])
	Sound.play("SuccessSound2")
	ok.pressed.connect(popup.close)
	return popup


## Every set, with your progress; click one for its cars.
static func open_list(tree: SceneTree) -> FlashPopup:
	var root := Node2D.new()
	var gfx := FlashUi.make("CarCollectionsPopupContent")
	if gfx != null:
		gfx.styled_text("titleFld", "Car Collections", "casualA01")
		root.add_child(gfx)
	var ids: Array = GameData.catalog.car_collections.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var da: bool = Backend.state()["collections_done"].has(a)
		var db: bool = Backend.state()["collections_done"].has(b)
		return (not da and db) or (da == db and a < b))
	var detail := Node2D.new()
	detail.position = Vector2(300, LIST_TOP)
	root.add_child(detail)
	var box := ScrollContainer.new()
	box.position = Vector2(LIST_X, LIST_TOP)
	box.custom_minimum_size = Vector2(270, LIST_HEIGHT)
	box.size = Vector2(270, LIST_HEIGHT)
	box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	box.add_child(column)
	root.add_child(box)
	var show := func(id: int) -> void:
		for c in detail.get_children():
			c.queue_free()
		detail.add_child(_detail(id))
	for id: int in ids:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(250, LIST_STEP - 2)
		var row := _row(id)
		row.position = Vector2(0, 0)
		row.pressed.connect(func() -> void: show.call(id))
		slot.add_child(row)
		column.add_child(slot)
	if not ids.is_empty():
		show.call(ids[0])
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(tree, root, [10, 12, 12, 12], [ok])
	ok.pressed.connect(popup.close)
	return popup


## One line of the list: a tick or "2/4", and the name.
static func _row(id: int) -> FlashButton:
	var c: Dictionary = GameData.catalog.car_collections[id]
	var progress := Backend.query().collection_progress(id)
	var done: bool = Backend.state()["collections_done"].has(id)
	var item := FlashUi.make("CarCollectionsListItemContent")
	if item != null:
		item.styled_text("titleFld", str(c["name"]), "casualA01", 16)
		item.styled_text("countFld", "%d/%d" % [progress[0], progress[1]], "casualA01", 14)
		var check := item.part("checkmark") as CanvasItem
		if check != null:
			check.visible = done
		var count := item.part("countFld") as CanvasItem
		if count != null:
			count.visible = not done
		var sel := item.part("selected") as CanvasItem
		if sel != null:
			sel.visible = false
	var holder := item if item != null else Node2D.new()
	var btn := FlashButton.wrap_node(holder, Rect2(0, 0, 250, 26))
	btn.set_base_scale(1.0, 1.04)
	return btn


## A set's cars (yours in colour, the rest greyed) and what it pays.
static func _detail(id: int) -> Node2D:
	var c: Dictionary = GameData.catalog.car_collections[id]
	var root := Node2D.new()
	var name_label := FlashUi.styled_label(str(c["name"]), "casualA01", 26, Color.WHITE, GLOW, 6)
	root.add_child(name_label)
	var ids: Array = c["car_ids"]
	for i in ids.size():
		var owned: bool = Backend.state()["cars"].any(func(car: Dictionary) -> bool: return car["car_id"] == int(ids[i]))
		var thumb := _car_thumb(int(ids[i]), not owned)
		thumb.position = Vector2(60 + (i % 2) * 150, 90 + (i / 2) * 90)
		root.add_child(thumb)
	var y := 90 + ((ids.size() + 1) / 2) * 90 + 10
	var bonus := FlashUi.styled_label("Completion Bonus:", "casualA01", 18, TEXT_COLOR)
	bonus.position = Vector2(0, y)
	root.add_child(bonus)
	var coins := FlashUi.styled_label("$ %s   %d XP" % [Format.number(c["coins"]), c["xp"]], "casualA01", 28, COIN_COLOR, GLOW, 5)
	coins.position = Vector2(0, y + 24)
	root.add_child(coins)
	return root


static func _car_thumb(car_id: int, greyed: bool) -> Node2D:
	var view := CarView.new()
	view.setup(CarView.stock_entry(car_id, 0), CarView.VIEW_ANGLE, false)
	view.scale = Vector2(CAR_SCALE, CAR_SCALE)
	if greyed:
		view.set_highlight(Color(0.15, 0.15, 0.15, 0.7))
	return view
