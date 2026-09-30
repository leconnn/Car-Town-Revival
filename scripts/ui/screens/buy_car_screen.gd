class_name BuyCarScreen
extends StageUi
## The original Buy Cars screen (views/buycar/BuyCar + BuyCarPanel), at the
## original stage coordinates: the showroom backdrop with the selected car
## on its halo, make and model, class and performance, colour swatches, the
## price and Buy button on the tray's edge, and the tray itself with the sort
## box, search box and a scroller of every car for sale.

signal closed

## Where the tray starts (GameBase.PLAY_HEIGHT).
const PLAY_HEIGHT := 467.0
const GLOW := Color8(0x53, 0x1A, 0x16)
const TITLE_OUTLINE := Color8(0x23, 0x3B, 0x57)
## Car thumbnails: the angle view shrunk to fit the tile (the car sits
## about 150 px above the view's origin at full size).
const THUMB_SCALE := 0.19
const SMALL_LABEL := Color8(0x51, 0x5F, 0x72)
const XP_COLOR := Color8(0x5C, 0x6E, 0x82)
const WARNING_COLOR := Color8(0xAE, 0x00, 0x00)
const PERFORMANCE_COLOR := Color8(0x55, 0xA5, 0xE0)
const SORTS: Array[Array] = [
	["Added: New to Old", "new"], ["Model Name: A-Z", "model"], ["Manufacturer Name: A-Z", "mfg"],
	["Price: Low to High", "pricelow"], ["Price: High to Low", "pricehigh"], ["Level Lock: 1-100", "levellock"],
]

var _bg: TextureRect
var _stage: Node2D
var _details: Node2D
## Buy buttons and prices sit on the tray's edge, above it.
var _buy_layer: Node2D
var _select_a_car: FlashSymbol
var _scroller: ItemScroller
var _sort: FlashComboBox
var _search: LineEdit
var _ids: Array[int] = []
var _selected := 0
var _color_id := 0


func _ready() -> void:
	super()
	# BuyCarBG is a 10 px wide vertical gradient, stretched across.
	_bg = TextureRect.new()
	_bg.texture = GameData.main_texture("swcassets.img.BuyCarBG")
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	move_child(_bg, 0)
	get_viewport().size_changed.connect(_fit_bg)
	_fit_bg()
	_stage = Node2D.new()
	bottom.add_child(_stage)
	var halo := Sprite2D.new()
	halo.texture = GameData.main_texture("swcassets.img.BuyCarGroundHalo")
	halo.centered = false
	halo.position = Vector2(0, 332)
	_stage.add_child(halo)
	_details = Node2D.new()
	_stage.add_child(_details)
	_select_a_car = FlashUi.make("SelectACar")
	if _select_a_car != null:
		_select_a_car.styled_text("fld", "Select a Car", "casualA01")
		_select_a_car.outline("fld", TITLE_OUTLINE, 8)
		_select_a_car.position = Vector2(380, 260)
		_select_a_car.play()
		_stage.add_child(_select_a_car)
	_build_panel()
	_buy_layer = Node2D.new()
	_stage.add_child(_buy_layer)
	Backend.state_changed.connect(_on_state_changed)
	Sound.play("PopUpSound01")


func _fit_bg() -> void:
	_bg.size = get_viewport().get_visible_rect().size


# --- The tray -------------------------------------------------------------------------

func _build_panel() -> void:
	var tray := TabTray.create(STAGE.x, 233, 128)
	tray.position.y = PLAY_HEIGHT
	_stage.add_child(tray)
	var shop := FlashUi.make("BtnShop2")
	if shop != null:
		shop.styled_text("fldLabel", "Shop", "casualA01")
		tray.add_tab(shop)
	tray.select(0)

	var list_bg := FlashNine.make("UIWhiteStrokedRoundedBg", Vector2(704, 143))
	list_bg.position = Vector2(28, 60)
	tray.add_child(list_bg)
	_scroller = ItemScroller.create(650, 117, 92)
	_scroller.position = Vector2(54, 74)
	_scroller.position_arrows(25, 61)
	tray.add_child(_scroller)

	var sort_label := FlashUi.styled_label("Sort by:", "casualA01", 17, Color8(0x62, 0x65, 0x64))
	sort_label.position = Vector2(40 + 4, 40)
	sort_label.scale = Vector2(0.75, 0.75)
	tray.add_child(sort_label)
	var names := PackedStringArray()
	for s: Array in SORTS:
		names.append(s[0])
	_sort = FlashComboBox.create(names)
	_sort.position = Vector2(40 + 56 + 4, 40)
	_sort.selected.connect(func(_i: int) -> void: _fill_list())
	tray.add_child(_sort)
	var search := FlashUi.make("UISearchBox")
	if search != null:
		search.position = Vector2(maxf(330, _sort.position.x + 185 + 26), 40)
		var field := search.part("searchField") as FlashText
		_search = LineEdit.new()
		_search.flat = true
		_search.add_theme_font_override("font", FlashUi.style_font("casualA01"))
		_search.add_theme_font_size_override("font_size", 14)
		_search.add_theme_color_override("font_color", Color8(0x33, 0x33, 0x33))
		if field != null:
			var box := field.box()
			field.visible = false
			_search.position = field.position + box.position
			_search.size = box.size
		search.add_child(_search)
		_search.text_changed.connect(func(_t: String) -> void: _fill_list())
		tray.add_child(search)

	var back := FlashTextButton.create("Back", FlashTextButton.Kind.RED, 88, 47, 24, false, _back_arrow())
	back.position = Vector2(32, -30)
	back.pressed.connect(close)
	tray.add_child(back)
	_fill_list()


## The white arrow the original drew in code next to "Back".
static func _back_arrow() -> Node2D:
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, 7), Vector2(10, 0), Vector2(7, 13)])
	arrow.color = Color.WHITE
	return arrow


func _fill_list() -> void:
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	_ids.clear()
	for id: int in Backend.query().dealer_car_ids():
		if query == "" or GameData.car_name(id).to_lower().contains(query):
			_ids.append(id)
	var cars := GameData.catalog
	var sort: String = SORTS[_sort.index][1] if _sort != null else "new"
	_ids.sort_custom(func(a: int, b: int) -> bool:
		var ca: Dictionary = cars.car(a)
		var cb: Dictionary = cars.car(b)
		match sort:
			"model":
				return str(ca["model"]).naturalnocasecmp_to(cb["model"]) < 0
			"mfg":
				return str(ca["make"]).naturalnocasecmp_to(cb["make"]) < 0
			"pricelow":
				return ca["price"] < cb["price"]
			"pricehigh":
				return ca["price"] > cb["price"]
			"levellock":
				return ca["min_level"] < cb["min_level"]
		return ca["date_added"] > cb["date_added"] if ca["date_added"] != cb["date_added"] else a > b)
	_scroller.set_items(_ids.size(), _make_tile)


func _make_tile(i: int) -> Node2D:
	var id := _ids[i]
	var c: Dictionary = GameData.catalog.car(id)
	var p: Dictionary = Backend.state()["player"]
	var locked: bool = c["min_level"] > p["level"]
	var blue_only: bool = not c["can_buy_with_coins"]
	var price: int = c["blue_price"] if blue_only else c["price"]
	var thumb := CarView.new()
	thumb.setup(CarView.stock_entry(id, _first_color(id)), CarView.VIEW_ANGLE, false)
	thumb.scale = Vector2(THUMB_SCALE, THUMB_SCALE)
	thumb.position = Vector2(0, 150 * THUMB_SCALE - 6)
	# BuyCarItem turns StoreItem's red "can't afford" background off.
	var tile := StoreTile.create(thumb, price, blue_only, "Level %d" % c["min_level"] if locked else "", false, c["limited"], false)
	tile.pressed.connect(show_car.bind(id))
	return tile


static func _first_color(car_id: int) -> int:
	var colors := GameData.catalog.colors_for_car(car_id)
	return colors[0]["id"] if not colors.is_empty() else 0


# --- The selected car ---------------------------------------------------------------

func show_car(car_id: int, color_id: int = -1) -> void:
	_selected = car_id
	_color_id = _first_color(car_id) if color_id < 0 else color_id
	if _select_a_car != null:
		_select_a_car.visible = false
	for layer: Node2D in [_details, _buy_layer]:
		for c in layer.get_children():
			c.queue_free()
	var c: Dictionary = GameData.catalog.car(car_id)
	var p: Dictionary = Backend.state()["player"]

	var view := CarView.new()
	view.setup(CarView.stock_entry(car_id, _color_id), CarView.VIEW_ANGLE, false)
	view.position = Vector2(200, 390)
	_details.add_child(view)

	var make := FlashUi.styled_label("'%02d %s" % [int(c["year"]) % 100, c["make"]], "casualA01", 31, Color.WHITE, GLOW, 10)
	make.position = Vector2(436, 61)
	_details.add_child(make)
	var model := FlashUi.styled_label(c["model"], "casualA01", 47, Color.WHITE, GLOW, 12)
	model.position = Vector2(431, 92)
	var mw := model.get_minimum_size().x
	if mw > 320:
		model.scale = Vector2(320 / mw, 320 / mw)
	_details.add_child(model)

	var class_label := FlashUi.styled_label("Class:", "sansA03", 10, SMALL_LABEL)
	class_label.position = Vector2(442, 157)
	_details.add_child(class_label)
	var class_icon := FlashUi.make("CarClassRating%d" % c["class_id"])
	if class_icon != null:
		class_icon.position = Vector2(431, 175) - class_icon.local_bounds().position
		_details.add_child(class_icon)
	var perf_icon := FlashUi.make("UIPerformanceRatingIconBig")
	if perf_icon != null:
		var r := perf_icon.local_bounds()
		perf_icon.position = Vector2(501, 179) - r.position
		_details.add_child(perf_icon)
		var perf := FlashUi.styled_label(str(c["score"]), "sansD04", 35, PERFORMANCE_COLOR)
		perf.position = Vector2(501 + r.size.x, 179)
		_details.add_child(perf)

	var swatches := Node2D.new()
	swatches.position = Vector2(431, 260)
	_details.add_child(swatches)
	var x := 0.0
	for col: Dictionary in GameData.catalog.colors_for_car(car_id):
		var bubble := _swatch(Color.html(col["hex"]))
		var btn := FlashButton.wrap_node(bubble)
		var w := bubble.local_bounds().size.x
		btn.position.x = x
		var cid: int = col["id"]
		btn.pressed.connect(func() -> void: show_car(car_id, cid))
		swatches.add_child(btn)
		x += w + 4

	var xp := FlashUi.styled_label("XP Gain: %d" % c["xp"], "casualA01", 26, XP_COLOR)
	xp.position = Vector2(437, 298)
	_details.add_child(xp)
	if c["description"] != "":
		var warn := FlashUi.styled_label(c["description"], "casualA01", 14, WARNING_COLOR)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(342 - 17, 0)
		warn.position = Vector2(433, 332)
		_details.add_child(warn)

	# Buy with coins at 660 - 178, with blue coins at 660, on the tray's edge.
	var locked: bool = c["min_level"] > p["level"]
	if c["can_buy_with_coins"]:
		var buy := EllipseButton.create("Buy", EllipseButton.GREEN)
		buy.position = Vector2(660 - 178 + buy.size().x / 2.0, PLAY_HEIGHT)
		buy.visible = not locked
		buy.set_disabled(c["price"] > p["coins"])
		buy.pressed.connect(_buy.bind(false))
		_buy_layer.add_child(buy)
		if locked:
			_unlocks_at(c["min_level"], buy.position.x)
		else:
			_buy_layer.add_child(_price(c["price"], false, buy.position.x))
	if c["can_buy_with_blue"] and c["blue_price"] > 0:
		var buy_blue := EllipseButton.create("Buy", EllipseButton.GREEN)
		buy_blue.position = Vector2(660 + buy_blue.size().x / 2.0, PLAY_HEIGHT)
		buy_blue.set_disabled(c["blue_price"] > p["blue"])
		buy_blue.pressed.connect(_buy.bind(true))
		_buy_layer.add_child(buy_blue)
		_buy_layer.add_child(_price(c["blue_price"], true, buy_blue.position.x))


## UIColorPickerBubble with the colour drawn in its 37 x 31 ellipse.
func _swatch(color: Color) -> FlashSymbol:
	var bubble := FlashUi.make("UIColorPickerBubble")
	if bubble == null:
		return FlashSymbol.new()
	var holder := bubble.part("colorSprite") as Node2D
	if holder != null:
		var e := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			pts.append(Vector2(18.5 + cos(a) * 18.5, 15.5 + sin(a) * 15.5))
		e.polygon = pts
		e.color = color
		holder.add_child(e)
	return bubble


## BuyCarPrice: coin (or blue coin) and the price, 45 px left of the button.
func _price(amount: int, blue: bool, button_x: float) -> Node2D:
	var price := FlashUi.make("BuyCarPrice")
	if price == null:
		return Node2D.new()
	var coin := price.part("coinIcon") as CanvasItem
	var credit := price.part("creditIcon") as CanvasItem
	if coin != null:
		coin.visible = not blue
	if credit != null:
		credit.visible = blue
	price.styled_text("fld", Format.number(amount), "sansA02")
	price.outline("fld", StoreTile.PRICE_GLOW, 5)
	var fld := price.part("fld") as FlashText
	if fld != null:
		fld.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var w := 34.0 + (fld.label.get_minimum_size().x if fld != null else 60.0)
	price.position = Vector2(button_x - w - 45, PLAY_HEIGHT - 45)
	return price


## BuyCarLockedText: "Unlocks at level 12" to the left of the Buy button.
func _unlocks_at(level: int, button_x: float) -> void:
	var msg := FlashUi.make("BuyCarLockedText")
	if msg == null:
		return
	msg.styled_text("fld", "Unlocks at level %d" % level, "casualA01", 18)
	var fld := msg.part("fld") as FlashText
	var text_w := fld.label.get_minimum_size().x if fld != null else 150.0
	var w := 57.3 + text_w
	var h := msg.local_bounds().size.y
	msg.position = Vector2(maxf(button_x - w, 215), PLAY_HEIGHT - 3 - h)
	_buy_layer.add_child(msg)


func _buy(use_blue: bool) -> void:
	var r: GameResult = await Backend.buy_car(_selected, _color_id, use_blue)
	if r.ok:
		close()


func _on_state_changed() -> void:
	if _selected != 0 and is_inside_tree():
		show_car(_selected, _color_id)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
