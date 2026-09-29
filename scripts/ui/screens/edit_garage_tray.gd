class_name EditGarageTray
extends StageUi
## The original Edit Garage mode (views/editgarage/EditGaragePanel and
## GameBase's EditGarageFrame): the play area framed by a rounded window,
## and a tray at the bottom with Shop / Storage tabs, category sub-tabs,
## a scroller of items, Reset Floor and Done. Items are placed by dragging a
## ghost into the garage; a BuyConfirm box asks before you pay. In Storage,
## the cash register sells whatever you drop on it.

signal done
## Asks the game to place something: kind "buy", "stored" or "car".
signal place_requested(kind: String, id: int)
## The object being moved was dropped on the tray (store) or register (sell).
signal dropped_on_tray(sell: bool)

## Tray position and size (DisplayEditGaragePanelCommand, EditGaragePanel).
const TRAY_Y := 700.0 - 175.0
const TRAY_SIZE := Vector2(762, 177)
const FRAME_MARGINS := [40, 40, 40, 220]
## Sub-tabs in Shop mode: icon and the item categories they list.
const SHOP_TABS: Array[Array] = [
	["BtnWorkBays", [5]], ["BtnFurniture", [3]], ["BtnFunctional", [4]], ["BtnMisc", [9]],
	["BtnSeating", [2, 1]], ["BtnFlooring", [6]], ["BtnWall", [7]], ["BtnSignage", [13]],
	["BtnLand", ["land"]],
]
const STORAGE_TABS: Array[Array] = [["BtnAllStorageItems", ["storage"]], ["BtnCarStorage", ["cars"]]]
const THUMB_SIZE := 70.0

var _frame: NinePatchRect
var _tray: TabTray
var _sub: TabTray
var _scroller: ItemScroller
var _register: FlashButton
var _storage := false
var _tabs: Array[Array] = SHOP_TABS
var _tiles: Array[Dictionary] = []
var _buy_box: BuyConfirm
var _tray_hit: Control


func _ready() -> void:
	super()
	_frame = NinePatchRect.new()
	var frame_tex := FlashUi.layer_texture("main_2_0_0")
	if not frame_tex.is_empty():
		_frame.texture = frame_tex["texture"]
	_frame.patch_margin_left = FRAME_MARGINS[0]
	_frame.patch_margin_right = FRAME_MARGINS[1]
	_frame.patch_margin_top = FRAME_MARGINS[2]
	_frame.patch_margin_bottom = FRAME_MARGINS[3]
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	move_child(_frame, 0)
	get_viewport().size_changed.connect(_fit_frame)
	_fit_frame()

	_tray = TabTray.create(TRAY_SIZE.x, TRAY_SIZE.y, 10, 110)
	_tray.chrome.queue_free()
	_tray.chrome = FlashNine.make("RegularFrameWithBlueInnerFrame", TRAY_SIZE)
	_tray.add_child(_tray.chrome)
	_tray.move_child(_tray.chrome, 0)
	_tray.position = Vector2(-1, TRAY_Y)
	bottom.add_child(_tray)
	# Anything dropped on the tray while moving an object goes into storage.
	_tray_hit = _tray.chrome
	_tray_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_tray_hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			dropped_on_tray.emit(false))
	var shop := FlashUi.make("BtnShop2")
	if shop != null:
		shop.styled_text("fldLabel", "Shop", "casualA01")
		_tray.add_tab(shop)
	var storage := FlashUi.make("BtnStorage2")
	if storage != null:
		_tray.add_tab(storage, true)
	_tray.tab_selected.connect(_set_mode)

	_scroller = ItemScroller.create(650, 123, 92)
	_scroller.position = Vector2(54, 47)
	_scroller.position_arrows(25, 55)

	var reset := EllipseButton.create("Reset\nFloor", EllipseButton.RED)
	reset.position = Vector2(595, 0)
	reset.pressed.connect(_ask_reset_floor)
	_tray.add_child(reset)
	var done_btn := EllipseButton.create("Done", EllipseButton.GREEN)
	done_btn.position = Vector2(695, 0)
	done_btn.pressed.connect(func() -> void: done.emit())
	_tray.add_child(done_btn)
	Backend.state_changed.connect(_refresh)
	_tray.select(0)


func _fit_frame() -> void:
	var s := stage_scale()
	var vp := get_viewport().get_visible_rect().size
	# The frame is drawn in stage units, scaled like the rest of the UI.
	_frame.scale = Vector2(s, s)
	_frame.size = Vector2(vp.x / s, STAGE.y * 656.0 / 700.0)
	_frame.position = Vector2(0, vp.y - STAGE.y * s)


func _set_mode(index: int) -> void:
	_storage = index == 1
	_close_buy_box()
	if _sub != null:
		_sub.queue_free()
	# Storage turns the tray brown and brings out the cash register.
	var chrome_name := "BrownFrameWithBrownGrayInnerFrame" if _storage else "RegularFrameWithBlueInnerFrame"
	var chrome := FlashNine.make(chrome_name, TRAY_SIZE)
	chrome.mouse_filter = Control.MOUSE_FILTER_STOP
	chrome.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			dropped_on_tray.emit(false))
	_tray.chrome.queue_free()
	_tray.chrome = chrome
	_tray.add_child(chrome)
	_tray.move_child(chrome, 0)
	_tabs = STORAGE_TABS if _storage else SHOP_TABS
	_sub = TabTray.create_sub(708, 123)
	_sub.chrome.queue_free()
	_sub.chrome = FlashNine.make("WhiteStrokedRoundedBackground2", Vector2(708, 123))
	_sub.add_child(_sub.chrome)
	_sub.move_child(_sub.chrome, 0)
	_sub._tabs_x = 30
	_sub._spacing = 50
	_sub.position = Vector2(26, 41)
	_tray.add_child(_sub)
	_tray.move_child(_sub, 1)
	for t: Array in _tabs:
		var icon := FlashUi.make(t[0])
		if icon != null:
			_sub.add_tab(icon)
	if _scroller.get_parent() != null:
		_scroller.get_parent().remove_child(_scroller)
	_tray.add_child(_scroller)
	_sub.tab_selected.connect(func(_i: int) -> void: _fill())
	if _register != null:
		_register.queue_free()
		_register = null
	if _storage:
		_register = FlashButton.of("BtnCashRegister")
		if _register != null:
			_register.position = Vector2(302, -15)
			_register.pressed.connect(func() -> void: dropped_on_tray.emit(true))
			_tray.add_child(_register)
			var label := FlashUi.styled_label("drop items here to recycle for $.", "casualA01", 16, Color.WHITE)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(115, 0)
			label.position = Vector2(302 + 30, -45)
			_tray.add_child(label)
			_register.tree_exiting.connect(label.queue_free)
	_sub.select(0)


func _refresh() -> void:
	if is_inside_tree() and _buy_box == null:
		_fill()


func _fill() -> void:
	if _sub == null or _sub.current() < 0:
		return
	var cats: Array = _tabs[_sub.current()][1]
	_tiles = _tiles_for(cats)
	var page := _scroller.first_index
	_scroller.set_items(_tiles.size(), func(i: int) -> Node2D: return _make_tile(_tiles[i]))
	if page > 0 and page < _tiles.size():
		_scroller.first_index = page
		_scroller.page_to(page)


## {kind, id, name, price, blue, locked, count, texture}
func _tiles_for(cats: Array) -> Array[Dictionary]:
	var q := Backend.query()
	var s := Backend.state()
	var level: int = s["player"]["level"]
	var out: Array[Dictionary] = []
	if cats.has("land"):
		var next := q.next_land_id()
		if next != 0:
			var land: Dictionary = GameData.catalog.land(next)
			var blue: bool = land.get("price", 0) <= 0
			out.append({"kind": "land", "id": next, "name": land.get("name", "Land"),
				"price": land.get("blue_price", 0) if blue else land.get("price", 0), "blue": blue,
				"locked": "Level %d" % land.get("min_level", 0) if land.get("min_level", 0) > level else "", "count": 0})
		return out
	if cats.has("cars"):
		for car: Dictionary in s["cars"]:
			if not car["placed"]:
				out.append({"kind": "car", "id": car["uid"], "car": car, "name": GameData.car_name(car["car_id"]),
					"price": -1, "blue": false, "locked": "", "count": 0})
		return out
	if cats.has("storage"):
		for key: String in s["storage"]:
			var it: Dictionary = GameData.catalog.item(int(key))
			out.append({"kind": "stored", "id": int(key), "name": it.get("name", ""), "price": -1,
				"blue": false, "locked": "", "count": s["storage"][key]})
		return out
	for id: int in q.shop_item_ids():
		var it: Dictionary = GameData.catalog.item(id)
		if not cats.has(it["category"]) or not _has_art(id, it):
			continue
		var blue: bool = not it["can_buy_with_coins"] and it["price"] <= 0
		out.append({"kind": "buy", "id": id, "name": it["name"],
			"price": it["blue_price"] if blue else it["price"], "blue": blue,
			"locked": "Level %d" % it["min_level"] if it["min_level"] > level else "",
			"count": s["storage"].get(str(id), 0)})
	return out


static func _has_art(id: int, it: Dictionary) -> bool:
	if it["category"] == GarageGrid.CAT_FLOOR_TILE:
		return GameData.texture("floors/%d.jpg" % id) != null
	return GameData.item_art.has(str(id))


func _make_tile(t: Dictionary) -> Node2D:
	var p: Dictionary = Backend.state()["player"]
	var affordable: bool = t["price"] <= (p["blue"] if t["blue"] else p["coins"])
	var tile := StoreTile.create(_picture(t), t["price"], t["blue"], t["locked"],
		t["kind"] == "buy" and t["locked"] == "" and not affordable)
	if t["count"] > 0:
		tile.set_quantity(t["count"])
	tile.position.y = 5
	tile.pressed.connect(_on_tile.bind(t))
	return tile


func _picture(t: Dictionary) -> Node2D:
	match t["kind"]:
		"land":
			var icon := FlashUi.make("LandStoreIcon")
			if icon != null:
				icon.styled_text("label", t["name"], "casualA01")
				return CustomizeScreen._centered(icon)
		"car":
			var view := CarView.new()
			view.setup(t["car"], CarView.VIEW_ANGLE, false)
			view.scale = Vector2(0.19, 0.19)
			view.position = Vector2(0, 150 * 0.19 - 6)
			return view
	var tex: Texture2D
	var it: Dictionary = GameData.catalog.item(t["id"])
	if it.get("category", 0) == GarageGrid.CAT_FLOOR_TILE:
		tex = GameData.texture("floors/%d.jpg" % t["id"])
	else:
		tex = GameData.texture(GameData.item_art.get(str(t["id"]), {}).get("thumb", {}).get("file", ""))
	var sprite := Sprite2D.new()
	sprite.texture = tex
	if tex != null:
		var k := minf(THUMB_SIZE / tex.get_width(), THUMB_SIZE / tex.get_height())
		sprite.scale = Vector2(k, k)
	return sprite


func _on_tile(t: Dictionary) -> void:
	if t["locked"] != "":
		return
	_close_buy_box()
	match t["kind"]:
		"buy":
			var cat: int = GameData.catalog.item(t["id"]).get("category", 0)
			if cat == GarageGrid.CAT_FLOOR_TILE or cat == GarageGrid.CAT_WALL:
				# Floors and walls cover the whole garage: just confirm.
				show_buy_confirm(t["name"], t["price"], t["blue"], func() -> void:
					await Backend.set_surface(t["id"], t["blue"]))
			else:
				place_requested.emit("buy", t["id"])
		"land":
			show_buy_confirm(t["name"], t["price"], t["blue"], func() -> void:
				await Backend.expand_land(t["blue"]))
		"stored":
			place_requested.emit("stored", t["id"])
		"car":
			place_requested.emit("car", t["id"])


## BuyConfirm on the tray; [param on_accept] runs if the player says yes,
## [param on_cancel] either way it closes without buying.
func show_buy_confirm(item_name: String, price: int, blue: bool, on_accept: Callable, on_cancel: Callable = Callable()) -> void:
	_close_buy_box()
	_buy_box = BuyConfirm.create(item_name, price, blue)
	_buy_box.position = Vector2(328, -65 - 20)
	_buy_box.accepted.connect(func() -> void:
		_close_buy_box()
		await on_accept.call())
	_buy_box.cancelled.connect(func() -> void:
		_close_buy_box()
		if on_cancel.is_valid():
			on_cancel.call())
	_tray.add_child(_buy_box)


func _close_buy_box() -> void:
	if _buy_box != null:
		_buy_box.queue_free()
		_buy_box = null


## The original ClearGarageFloorPopup: pick what goes into storage.
func _ask_reset_floor() -> void:
	var content := ResetFloorPopup.create()
	var popup := FlashPopup.open(get_tree(), content, true, false, ResetFloorPopup.SIZE, content.frame_buttons())
	content.confirmed.connect(func(cars: bool, items: bool, bays: bool) -> void:
		popup.close()
		await Backend.clear_floor(cars, items, bays))
	content.cancelled.connect(popup.close)
