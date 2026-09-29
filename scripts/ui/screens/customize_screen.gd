class_name CustomizeScreen
extends StageUi
## The original Customize screen (views/editcar/EditCar + EditCarPanel): the
## car on the showroom floor with its make, model, class and performance,
## and the tray: sub-tabs for paint, wheels, tires, body, performance,
## suspension, tint and lights, a scroller of parts, and a buy box that
## previews each part on the car before you pay.

signal closed

const PLAY_HEIGHT := BuyCarScreen.PLAY_HEIGHT
const GLOW := BuyCarScreen.GLOW
const BUY_TEXT := Color8(0x5B, 0x5B, 0x5B)
const BUY_NAME := Color8(0x38, 0x78, 0x99)
const BUY_STROKE := Color8(0x5F, 0x77, 0x91)
## Part category ids (CarPartCategory).
const WHEELS := 1
const TIRES := 2
const BODY_KITS := 4
const WINGS := 5
const HOODS := 6
const HEADLIGHTS := 7
const NEON := 10
const TINTS := 12
const PAINT := 14
## Sub-tabs: icon symbol and what they list.
const SUB_TABS: Array[Array] = [
	["BtnPartPaint", "paint"], ["BtnPartWheels", "wheels"], ["BtnPartTires", "tires"],
	["BtnPartBody", "body"], ["BtnPartPerformance", "performance"], ["BtnPartSuspension", "suspension"],
	["BtnPartTint", "tint"], ["BtnPartLights", "lights"],
]
const TIRE_LABELS := {0: "Low", 1: "Medium", 2: "Tall", 3: "Monster"}
const TINT_LABELS := {959: "Full Black", 960: "50% Black", 961: "Full Blue", 962: "Full Red"}
const NEON_LABELS := {956: "Neon Yellow", 957: "Neon Aqua", 958: "Neon Pink", 2965: "Neon Blue",
	2966: "Neon Orange", 2967: "Neon Red", 2968: "Neon Green", 2969: "Neon Purple"}
const UPGRADE_NAMES := ["Engine Upgrade %d", "Handling Upgrade %d", "Aerodynamics Upgrade %d", "Weight Savings %d"]
const SUSPENSION_LABELS := ["Low", "Medium", "High"]
## Screen positions (EditCar.init).
const CAR_POS := Vector2(200, 390)
const WHEEL_THUMB_H := 62.0

var car_uid: int
var _stage: Node2D
var _preview: Dictionary = {}
var _car_view: CarView
var _info: Node2D
var _sub: TabTray
var _scroller: ItemScroller
var _tray: TabTray
var _buy_box: Node2D
var _picker: PaintPicker
var _tab := "paint"
var _tiles: Array[Dictionary] = []


static func create(uid: int) -> CustomizeScreen:
	var s := CustomizeScreen.new()
	s.car_uid = uid
	return s


func _ready() -> void:
	super()
	var bg := TextureRect.new()
	bg.texture = GameData.main_texture("swcassets.img.BuyCarBG")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	move_child(bg, 0)
	var fit := func() -> void: bg.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(fit)
	fit.call()
	_stage = Node2D.new()
	bottom.add_child(_stage)
	# EditBG is the 760 px wide showroom floor; stretch it across wider windows.
	var edit_bg := FlashUi.make("EditBG")
	if edit_bg != null:
		_stage.add_child(edit_bg)
		var stretch := func() -> void:
			var w := get_viewport().get_visible_rect().size.x / stage_scale()
			edit_bg.scale.x = w / STAGE.x
			edit_bg.position.x = -(w - STAGE.x) / 2.0
		get_viewport().size_changed.connect(stretch)
		stretch.call()
	var halo := Sprite2D.new()
	halo.texture = GameData.main_texture("swcassets.img.BuyCarGroundHalo")
	halo.centered = false
	halo.position = Vector2(0, 332)
	_stage.add_child(halo)
	_info = Node2D.new()
	_stage.add_child(_info)
	_preview = Backend.query().get_car(car_uid).duplicate(true)
	_build_tray()
	_refresh_car()
	Backend.state_changed.connect(_on_state_changed)


# --- The car and its details -----------------------------------------------------------

func _refresh_car() -> void:
	if _car_view != null:
		_car_view.queue_free()
	_car_view = CarView.new()
	_car_view.setup(_preview, CarView.VIEW_ANGLE, false)
	_car_view.position = CAR_POS
	_stage.add_child(_car_view)
	_stage.move_child(_car_view, _info.get_index())
	for c in _info.get_children():
		c.queue_free()
	var def: Dictionary = GameData.catalog.car(_preview["car_id"])
	var make := FlashUi.styled_label("'%02d %s" % [int(def["year"]) % 100, def["make"]], "casualA01", 31, Color.WHITE, GLOW, 10)
	make.position = Vector2(456, 101)
	_info.add_child(make)
	var model := FlashUi.styled_label(def["model"], "casualA01", 57, Color.WHITE, GLOW, 12)
	model.position = Vector2(451, 132)
	var mw := model.get_minimum_size().x
	if mw > 290:
		model.scale = Vector2(290 / mw, 290 / mw)
	_info.add_child(model)
	var class_label := FlashUi.styled_label("Class:", "sansA03", 10, BuyCarScreen.SMALL_LABEL)
	class_label.position = Vector2(463, 200)
	_info.add_child(class_label)
	var class_icon := FlashUi.make("CarClassRating%d" % def["class_id"])
	if class_icon != null:
		class_icon.position = Vector2(451, 220) - class_icon.local_bounds().position
		_info.add_child(class_icon)
	var perf_icon := FlashUi.make("UIPerformanceRatingIconBig")
	if perf_icon != null:
		var r := perf_icon.local_bounds()
		perf_icon.position = Vector2(521, 225) - r.position
		_info.add_child(perf_icon)
		var perf := FlashUi.styled_label(str(_preview_score()), "sansD04", 35, BuyCarScreen.PERFORMANCE_COLOR)
		perf.position = Vector2(521 + r.size.x, 225)
		_info.add_child(perf)


## Performance with the previewed upgrades (UserCar.hp).
func _preview_score() -> int:
	var score: int = GameData.catalog.car(_preview["car_id"]).get("score", 0)
	for stage: int in _preview.get("upgrades", []):
		score += stage * int(GameData.catalog.consts.get("upgrade_score_per_stage", 20))
	return score


# --- The tray -----------------------------------------------------------------------------

func _build_tray() -> void:
	_tray = TabTray.create(STAGE.x, 233)
	_tray.position.y = PLAY_HEIGHT
	_stage.add_child(_tray)
	var shop := FlashUi.make("BtnShop2")
	if shop != null:
		shop.styled_text("fldLabel", "Shop", "casualA01")
		_tray.add_tab(shop)
	# Storage (parts you own but took off) isn't in our rules: bought parts
	# go straight on the car, so only the Shop tab shows.
	_tray.select(0)

	_sub = TabTray.create_sub(708, 144)
	_sub.position = Vector2(26, 58)
	_tray.add_child(_sub)
	for t: Array in SUB_TABS:
		var icon := FlashUi.make(t[0])
		if icon != null:
			_sub.add_tab(icon)
	_sub.tab_selected.connect(func(i: int) -> void: _show_tab(SUB_TABS[i][1]))

	_scroller = ItemScroller.create(650, 117, 92)
	_scroller.position = Vector2(54, 74)
	_scroller.position_arrows(25, 61)
	_tray.add_child(_scroller)

	# Done: a popup-frame button on the tray's top edge at x 695.
	var done := EllipseButton.create("Done", EllipseButton.GREEN)
	done.position = Vector2(695, 0)
	done.pressed.connect(close)
	_tray.add_child(done)
	_sub.select(0)


## Selects a sub-tab by name ("wheels", "performance", ...).
func select_tab(tab: String) -> void:
	for i in SUB_TABS.size():
		if SUB_TABS[i][1] == tab:
			_sub.select(i)


## Clicks the first tile of the current tab (testing aid).
func click_first_tile() -> void:
	for t: Dictionary in _tiles:
		if not t["installed"] and t["locked"] == "":
			_on_tile(t)
			return


func _show_tab(tab: String) -> void:
	_tab = tab
	_close_buy_box()
	if _picker != null:
		_picker.queue_free()
		_picker = null
	_sub.visible = true
	_scroller.visible = true
	_tiles = _tiles_for(tab)
	_scroller.set_items(_tiles.size(), func(i: int) -> Node2D: return _make_tile(_tiles[i]))


## What a tab lists: {kind, id, name, price, blue, picture, installed, locked}.
func _tiles_for(tab: String) -> Array[Dictionary]:
	var q := Backend.query()
	var car := q.get_car(car_uid)
	var out: Array[Dictionary] = []
	match tab:
		"paint":
			var p: Dictionary = GameData.catalog.part(GameData.catalog.tune("parts.paint_part_id", 0))
			out.append(_part_tile(p, car, "paint"))
		"wheels":
			# One tile per rim design (joinCarPartsByAssetID), in the car's size.
			var by_asset: Dictionary = {}
			var size: int = GameData.catalog.part(car["parts"].get(str(WHEELS), 0)).get("size", 0)
			for pid: int in q.parts_for_car(car["car_id"], WHEELS):
				var p: Dictionary = GameData.catalog.part(pid)
				var key: int = p["asset_id"]
				if not by_asset.has(key) or p["size"] == size:
					by_asset[key] = p
			for key: int in by_asset:
				out.append(_part_tile(by_asset[key], car, "wheel"))
		"tires":
			for pid: int in q.parts_for_car(car["car_id"], TIRES):
				out.append(_part_tile(GameData.catalog.part(pid), car, "tire"))
		"body":
			for cat: int in [BODY_KITS, WINGS, HOODS]:
				for pid: int in q.parts_for_car(car["car_id"], cat):
					out.append(_part_tile(GameData.catalog.part(pid), car, "body"))
		"performance":
			for track in 4:
				var current: int = car["upgrades"][track]
				for stage in range(1, 6):
					var price := q.upgrade_stage_price(car["car_id"], stage)
					out.append({"kind": "upgrade", "track": track + 1, "stage": stage,
						"name": UPGRADE_NAMES[track] % stage, "price": price[0] if price[0] > 0 else price[1],
						"blue": price[0] == 0, "installed": stage <= current,
						"locked": "" if stage <= current + 1 else "Req. Upgrade %d" % (stage - 1)})
		"suspension":
			for h in 3:
				out.append({"kind": "suspension", "height": h, "name": SUSPENSION_LABELS[h] + " Suspension",
					"price": int(GameData.catalog.consts.get("ride_height_price", 100)), "blue": false,
					"installed": car.get("ride_height", 0) == h, "locked": ""})
		"tint":
			for pid: int in q.parts_for_car(car["car_id"], TINTS):
				out.append(_part_tile(GameData.catalog.part(pid), car, "tint"))
		"lights":
			for cat: int in [HEADLIGHTS, NEON]:
				for pid: int in q.parts_for_car(car["car_id"], cat):
					out.append(_part_tile(GameData.catalog.part(pid), car, "neon" if cat == NEON else "part"))
	return out


func _part_tile(p: Dictionary, car: Dictionary, kind: String) -> Dictionary:
	var level: int = Backend.state()["player"]["level"]
	var blue: bool = not p.get("can_buy_with_coins", true)
	return {"kind": kind, "id": p.get("id", 0), "part": p, "name": p.get("name", ""),
		"price": p.get("blue_price", 0) if blue else p.get("price", 0), "blue": blue,
		"installed": kind != "paint" and car["parts"].get(str(p.get("category_id", 0)), 0) == p.get("id", 0),
		"locked": "Level %d" % p["min_level"] if p.get("min_level", 0) > level else ""}


func _make_tile(t: Dictionary) -> Node2D:
	var tile := StoreTile.create(_picture(t), t["price"], t["blue"], t["locked"])
	if t["installed"]:
		tile.set_installed()
	tile.position.y = 5
	tile.pressed.connect(_on_tile.bind(t))
	return tile


## The tile's picture, like EditCarPanel.populateItemScroller.
func _picture(t: Dictionary) -> Node2D:
	var sym: FlashSymbol = null
	match t["kind"]:
		"paint":
			sym = FlashUi.make("CarPartPaintColor")
			if sym != null:
				sym.styled_text("fld", "Paint", "casualA01")
		"wheel":
			var art: Dictionary = GameData.wheel_art.get(str(t["part"]["asset_id"]), {})
			var frames: Array = art.get("a_a", [])
			if not frames.is_empty():
				var s := Sprite2D.new()
				s.texture = GameData.texture(frames[0]["file"])
				var k := WHEEL_THUMB_H / maxf(1.0, s.texture.get_height() if s.texture != null else 1.0)
				s.scale = Vector2(k, k)
				return s
		"tire":
			var asset: int = t["part"]["asset_id"]
			sym = FlashUi.make("CarPartTires%d" % asset)
			if sym != null:
				sym.styled_text("fld", TIRE_LABELS.get((asset - 20) % 4 if asset < 40 else asset - 40, ""), "casualA01")
		"body":
			sym = FlashUi.make("CarPartBody%d" % t["part"]["category_id"])
			if sym != null:
				sym.styled_text("label", t["name"], "casualA01")
				# A Flash text field without autoSize clips to its box.
				var field := sym.part("label") as FlashText
				if field != null:
					field.label.clip_text = true
		"upgrade":
			sym = FlashUi.make("CarPartUpgrade%d" % (100 + t["track"]))
			var hp := FlashUi.make("HpAmount")
			if sym != null and hp != null:
				var lab := sym.part("label") as CanvasItem
				if lab != null:
					lab.visible = false
				hp.styled_text("label", "+%d" % int(GameData.catalog.consts.get("upgrade_score_per_stage", 20)), "casualA01")
				var holder := Node2D.new()
				holder.add_child(_centered(sym))
				hp.position = Vector2(25, 56) - Vector2(45, 44)
				holder.add_child(hp)
				return holder
		"suspension":
			sym = FlashUi.make("CarPartSuspension%d" % (201 + t["height"]))
			if sym != null:
				sym.styled_text("fld", SUSPENSION_LABELS[t["height"]], "casualA01")
		"tint":
			sym = FlashUi.make("CarPart%d" % t["id"])
			if sym != null:
				sym.styled_text("fld", TINT_LABELS.get(t["id"], ""), "casualA01")
		"neon":
			sym = FlashUi.make("CarPart%d" % t["id"])
			if sym != null:
				sym.styled_text("fld", NEON_LABELS.get(t["id"], ""), "casualA01")
		_:
			sym = FlashUi.make("CarPart%d" % t["id"])
	if sym == null:
		var label := FlashUi.styled_label(t["name"], "casualA01", 12, BUY_TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(72, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(-36, -20)
		var n := Node2D.new()
		n.add_child(label)
		return n
	return _centered(sym)


## CenteredContainer: the symbol's bounds centred on the origin.
static func _centered(sym: FlashSymbol) -> Node2D:
	var holder := Node2D.new()
	var r := sym.local_bounds()
	sym.position = -r.position - r.size / 2.0
	holder.add_child(sym)
	return holder


# --- Previewing and buying ------------------------------------------------------------

func _on_tile(t: Dictionary) -> void:
	if t["installed"] or t["locked"] != "":
		return
	_preview = Backend.query().get_car(car_uid).duplicate(true)
	match t["kind"]:
		"paint":
			_open_paint(t)
			return
		"upgrade":
			_preview["upgrades"][t["track"] - 1] = t["stage"]
		"suspension":
			_preview["ride_height"] = t["height"]
		_:
			_preview["parts"][str(t["part"]["category_id"])] = t["id"]
	_refresh_car()
	_show_buy_box(t)


func _open_paint(t: Dictionary) -> void:
	# The picker takes the sub-tab panel's place (hideSubStack), at (29, 526).
	_sub.visible = false
	_scroller.visible = false
	_picker = PaintPicker.create(Backend.query().car_paint(Backend.query().get_car(car_uid)))
	_picker.position = Vector2(29, 526 - PLAY_HEIGHT)
	_tray.add_child(_picker)
	_picker.color_changed.connect(func(rgb: int) -> void:
		_preview["paint"] = rgb
		_refresh_car()
		t["rgb"] = rgb
		_show_buy_box(t))


## BuyConfirm: a white rounded box (404 x 93) above the tray at (328, -65)
## with "Buy <name> for <cost> coins?" and OK / close buttons.
func _show_buy_box(t: Dictionary) -> void:
	_close_buy_box()
	_buy_box = Node2D.new()
	_buy_box.position = Vector2(328, -65)
	_tray.add_child(_buy_box)
	var box := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = BUY_STROKE
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	box.add_theme_stylebox_override("panel", style)
	box.size = Vector2(404, 93)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	_buy_box.add_child(box)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("normal_font", FlashUi.style_font("casualA01"))
	text.add_theme_font_size_override("normal_font_size", 20)
	text.add_theme_color_override("default_color", BUY_TEXT)
	text.size = Vector2(240, 84)
	text.text = "Buy [color=#%s]%s[/color] for %s %s?" % [BUY_NAME.to_html(false), t["name"],
		Format.number(t["price"]), "blue coins" if t["blue"] else "coins"]
	text.position = Vector2(35, 0)
	_buy_box.add_child(text)
	# Centred once it has wrapped (content height is only known after layout).
	text.finished.connect(func() -> void:
		text.position.y = (93 - text.get_content_height()) / 2.0, CONNECT_ONE_SHOT)
	(func() -> void: text.position.y = (93 - text.get_content_height()) / 2.0).call_deferred()
	var ok := FlashTextButton.create("", FlashTextButton.Kind.GREEN, 34, 32, 18, false, _icon("UISymbolOk"))
	ok.position = Vector2(280, 31)
	ok.pressed.connect(_buy.bind(t))
	_buy_box.add_child(ok)
	var cancel := FlashPopup.close_button()
	cancel.position = Vector2(344, 31)
	cancel.pressed.connect(func() -> void:
		_close_buy_box()
		_preview = Backend.query().get_car(car_uid).duplicate(true)
		_refresh_car())
	_buy_box.add_child(cancel)


static func _icon(class_name_: String) -> Node2D:
	var sym := FlashUi.make(class_name_)
	return sym if sym != null else Node2D.new()


func _close_buy_box() -> void:
	if _buy_box != null:
		_buy_box.queue_free()
		_buy_box = null


func _buy(t: Dictionary) -> void:
	var r: GameResult
	match t["kind"]:
		"paint":
			r = await Backend.paint_car(car_uid, t.get("rgb", Backend.query().car_paint(Backend.query().get_car(car_uid))), t["blue"])
		"upgrade":
			r = await Backend.upgrade_car(car_uid, t["track"])
		"suspension":
			r = await Backend.set_ride_height(car_uid, t["height"], false)
		_:
			r = await Backend.install_part(car_uid, t["id"], t["blue"])
	if r.ok:
		_close_buy_box()
		_show_tab(_tab)


func _on_state_changed() -> void:
	if not is_inside_tree() or Backend.query().get_car(car_uid).is_empty():
		return
	if _buy_box == null and _picker == null:
		_preview = Backend.query().get_car(car_uid).duplicate(true)
		_refresh_car()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
