class_name GpsPopup
extends Node2D
## The original GPS (views/hud/gps/GPSMain in a 720 x 550 frame): the big GPS
## icon, five tabs (What's New, Hot Spots, Racing, Car Shopping, Friends
## List) over a street-map panel, and location buttons laid out five to a
## page (corners and centre) with arrows between pages. A "My Garage" button
## sits on the panel's bottom edge when you're away from home.

signal location_chosen(location_id: int)
signal home_pressed
signal buy_cars_pressed

const FRAME_SIZE := Vector2(720, 550)
const PANEL_RECT := Rect2(30, 60, 664, 462)
const TABS_X := 80.0
const TABS_Y := 70.0
const TABS_SPACING := 113.0
const TAB_ICON_Y := 8.0
## GPSLocationScroller: a 620 x 370 page at (50, 107), buttons 220 x 180.
const PAGE_POS := Vector2(50, 107)
const PAGE_SIZE := Vector2(620, 370)
const BUTTON_SIZE := Vector2(220, 180)
const TABS: Array[Array] = [
	["GPSButWhatsNewGfx", "What's new!"], ["GPSButHotSpotsGfx", "Hot Spots"], ["GPSButRacingGfx", "Racing"],
	["GPSButBuyCarGfx", "Car Shopping"], ["GPSButFriendsGfx", "Friends List"],
]
## Location types in the catalog: 1 = hangouts (Hot Spots), 0 = racing.
const TYPE_HOT_SPOT := 1
const TYPE_RACING := 0
const TITLE_OUTLINE := Color8(0x33, 0x33, 0x33)

var _away := false
var _page := 0
var _tab := 0
var _content: Node2D
var _tab_bgs: Array[Node2D] = []


static func create(away_from_home: bool) -> GpsPopup:
	var g := GpsPopup.new()
	g._away = away_from_home
	g._build()
	return g


func _build() -> void:
	var bg := FlashNine.make("NewBlueBg", PANEL_RECT.size)
	bg.position = PANEL_RECT.position
	add_child(bg)
	var big := FlashUi.make("BigGPSIconGfx")
	if big != null:
		big.styled_text("fld", "GPS", "casualA01")
		big.position = Vector2(-20, -50)
		add_child(big)
	for i in TABS.size():
		var tab := Node2D.new()
		tab.position = Vector2(TABS_X + TABS_SPACING * i, TABS_Y)
		var tab_bg := FlashUi.make("GPSTabBg")
		var w := 110.0
		if tab_bg != null:
			tab_bg.visible = false
			w = tab_bg.local_bounds().end.x
			tab.add_child(tab_bg)
		_tab_bgs.append(tab_bg)
		var icon := FlashUi.make(TABS[i][0])
		if icon != null:
			icon.styled_text("fld", TABS[i][1], "casualA01")
			var btn := FlashButton.wrap_node(icon)
			btn.set_base_scale(1.0, 1.1)
			btn.position = Vector2(w / 2.0, TAB_ICON_Y)
			var index := i
			btn.pressed.connect(func() -> void: _select(index))
			tab.add_child(btn)
		add_child(tab)
	_content = Node2D.new()
	add_child(_content)
	if _away:
		var home := FlashButton.of("GPSHomeButtonGfx")
		if home != null:
			(home.body as FlashSymbol).styled_text("fld", "My Garage", "casualA01")
			home.position = Vector2(PANEL_RECT.position.x + PANEL_RECT.size.x / 2.0, PANEL_RECT.end.y)
			home.pressed.connect(func() -> void: home_pressed.emit())
			add_child(home)
	_select(1 if _locations(0).is_empty() else 0)


func _select(index: int) -> void:
	_tab = index
	_page = 0
	for i in _tab_bgs.size():
		if _tab_bgs[i] != null:
			_tab_bgs[i].visible = i == index
	_fill()


## What's New lists places flagged new; the others by type.
func _locations(tab: int) -> Array[int]:
	var out: Array[int] = []
	var ids := Backend.query().town_location_ids()
	for later: Variant in GameData.catalog.tune("town.coming_later", []):
		ids.append(int(later))
	for id: int in ids:
		var loc: Dictionary = GameData.catalog.locations.get(id, {})
		if loc.is_empty() or out.has(id):
			continue
		var is_new: bool = str(loc.get("raw", {}).get("in", "0")) == "1"
		match tab:
			0:
				if is_new:
					out.append(id)
			1:
				if loc["type"] != TYPE_RACING:
					out.append(id)
			2:
				if loc["type"] == TYPE_RACING:
					out.append(id)
	out.sort_custom(func(a: int, b: int) -> bool:
		return GameData.catalog.locations[a]["sort"] < GameData.catalog.locations[b]["sort"])
	return out


func _fill() -> void:
	for c in _content.get_children():
		c.queue_free()
	match _tab:
		3:
			_fill_car_shopping()
			return
		4:
			var note := FlashUi.styled_label("Your friends' garages show up here\nwhen you play on LAN or online.",
				"casualA01", 22, Color.WHITE, Color8(0x23, 0x4F, 0x70), 6)
			note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			note.position = Vector2(PANEL_RECT.get_center().x - 200, 250)
			note.custom_minimum_size = Vector2(400, 0)
			_content.add_child(note)
			return
	var ids := _locations(_tab)
	var pages := ceili(ids.size() / 5.0)
	var page_node := Node2D.new()
	page_node.position = PAGE_POS
	_content.add_child(page_node)
	for n in range(_page * 5, mini(ids.size(), _page * 5 + 5)):
		var slot := n % 5
		# Top-left, top-right, centre, bottom-left, bottom-right.
		var pos: Vector2 = [Vector2.ZERO, Vector2(PAGE_SIZE.x - BUTTON_SIZE.x, 0),
			(PAGE_SIZE - BUTTON_SIZE) / 2.0, Vector2(0, PAGE_SIZE.y - BUTTON_SIZE.y),
			PAGE_SIZE - BUTTON_SIZE][slot]
		var button := _location_button(ids[n])
		button.position = pos + BUTTON_SIZE / 2.0
		page_node.add_child(button)
	if pages > 1:
		for dir: int in [-1, 1]:
			if (dir < 0 and _page == 0) or (dir > 0 and _page >= pages - 1):
				continue
			var arrow := FlashButton.of("BtnScrollArrowLeft")
			if arrow == null:
				continue
			if dir > 0:
				arrow.body.rotation_degrees = 180
				arrow._hit.position = -arrow._hit.position - arrow._hit.size
			arrow.position = Vector2(PANEL_RECT.position.x + 8 if dir < 0 else PANEL_RECT.end.x - 8, PANEL_RECT.get_center().y)
			arrow.pressed.connect(func() -> void:
				_page += dir
				_fill())
			_content.add_child(arrow)


## GPSLocationButton: the place's icon (grey and padlocked when locked),
## growing 10% on hover.
func _location_button(loc_id: int) -> Node2D:
	var loc: Dictionary = GameData.catalog.locations[loc_id]
	var art: Dictionary = GameData.town_art.get("icon_%d" % loc_id, {})
	var holder := Node2D.new()
	var tex := GameData.texture(art.get("file", ""))
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		holder.add_child(s)
		# The name goes where the icon's fldTitle was (GPSLocationButton).
		var title: Array = art.get("title", [])
		if not title.is_empty():
			var o: Array = art.get("o", [0, 0])
			var shift := Vector2(o[0], o[1]) - tex.get_size() / 2.0
			var label := FlashUi.styled_label(loc["name"], "casualA01", int(title[4]), Color.WHITE, TITLE_OUTLINE, 5)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.position = Vector2(title[0], title[1]) + shift
			label.size = Vector2(title[2] - title[0], title[3] - title[1])
			holder.add_child(label)
	var locked := _locked_reason(loc_id) != ""
	if locked:
		holder.modulate = Color(1.25, 1.25, 1.25)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/desaturate.gdshader")
		for c in holder.get_children():
			(c as CanvasItem).material = mat
		var lock := FlashUi.make("UIIconLockLarge")
		if lock != null:
			var r := lock.local_bounds()
			lock.position = Vector2(0, -r.size.y / 2.0) - r.position
			holder.add_child(lock)
	var btn := FlashButton.wrap_node(holder, Rect2(-BUTTON_SIZE / 2.0, BUTTON_SIZE))
	btn.set_base_scale(1.0, 1.1)
	btn.pressed.connect(func() -> void:
		if locked:
			_access_denied(loc_id)
		else:
			location_chosen.emit(loc_id))
	return btn


## "" if the place can be visited, else why not.
func _locked_reason(loc_id: int) -> String:
	var loc: Dictionary = GameData.catalog.locations[loc_id]
	if not Backend.query().town_location_ids().has(loc_id) or not LocationView.has_scene(loc_id):
		return "later"
	if loc.get("min_level", 0) > Backend.state()["player"]["level"]:
		return "level"
	return ""


func _access_denied(loc_id: int) -> void:
	var loc: Dictionary = GameData.catalog.locations[loc_id]
	var graphic := FlashUi.make("AccessDeniedPopupGraphic")
	if graphic == null:
		return
	graphic.styled_text("fldTitle", "Access Denied", "casualA01")
	graphic.styled_text("fldSubtitle", "%s is locked!" % loc["name"], "casualA01")
	if _locked_reason(loc_id) == "level":
		graphic.styled_text("fldMinLevel", "Sorry, but you have to be level %d to enter!" % loc["min_level"], "casualA01")
		graphic.styled_text("fldHowToLevel", "To level up, do jobs in your garage, buy cars, and race!", "casualA01")
	else:
		graphic.styled_text("fldMinLevel", "This place opens in a later update.", "casualA01")
		graphic.styled_text("fldHowToLevel", "", "casualA01")
	var holder := graphic.part("imageHolder") as Node2D
	var tex := GameData.texture(GameData.town_art.get("icon_%d" % loc_id, {}).get("file", ""))
	if holder != null and tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.scale = Vector2(0.75, 0.75)
		holder.add_child(s)
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(get_tree(), graphic, [10, 20, 28, 20], [ok])
	ok.pressed.connect(popup.close)


## GPSCarShopping: a shortcut to Buy Cars.
func _fill_car_shopping() -> void:
	var btn := FlashButton.of("GPSButBuyCarGfx")
	if btn == null:
		return
	(btn.body as FlashSymbol).styled_text("fld", "Buy Cars", "casualA01")
	btn.set_base_scale(2.0, 2.2)
	btn.position = PANEL_RECT.get_center() + Vector2(0, 20)
	btn.pressed.connect(func() -> void: buy_cars_pressed.emit())
	_content.add_child(btn)
