class_name ShellHud
extends StageUi
## The original game's HUD, bottom bar and controls, rebuilt from the
## original symbols at the original positions (views/shell/Hud,
## CarTownControls, views/hud/BottomNav). See docs/original-ui-map.md.

signal action(name: String)

const XPBAR_ANGLE_RANGE := 243.0
const COUNTER_DIGITS := 8
const COUNTER_STEP := 12.0
## HUD and controls sit 12 px down; the bottom bar 165 px up from the bottom.
const HUD_Y := 12.0
const NAV_Y := 700.0 - 165.0
## Rusty's garage value on the neighbour list.
const RUSTY_GARAGE_VALUE := 5000

var _gauge: FlashSymbol
var _xp_clip: Polygon2D
var _xp_radius := 40.0
var _digits: Array[FlashSymbol] = []
var _balance: FlashSymbol
var _gv_meter: FlashSymbol
var _location_label: FlashSymbol
var _friend_cards: Node2D
var _mission_dock: Node2D


func _ready() -> void:
	super()
	_build_left()
	_build_right()
	_build_bottom()
	Backend.state_changed.connect(refresh)
	refresh()


# --- Top left: level gauge, balance, garage value, missions ---------------------------

func _build_left() -> void:
	_gauge = FlashUi.make("UIXPGaugeGfx")
	if _gauge != null:
		_gauge.position = Vector2(4, -20 + HUD_Y)
		left.add_child(_gauge)
		_setup_xp_bar()
		var counter := Node2D.new()
		counter.position = _gauge.position + Vector2(13, 88.5)
		left.add_child(counter)
		# The original XPCounter: 8 odometer digits, the last one white.
		var offset := -((COUNTER_DIGITS - 1) * COUNTER_STEP - 6 * COUNTER_STEP) / 2.0
		for i in COUNTER_DIGITS:
			var d := FlashUi.make("UIXPCounterGfxWhite" if i == 0 else "UIXPCounterGfx")
			if d == null:
				continue
			d.position.x = offset + (COUNTER_DIGITS - 1) * COUNTER_STEP - i * COUNTER_STEP
			counter.add_child(d)
			_digits.append(d)
	_balance = FlashUi.make("BalanceLegacy")
	if _balance != null:
		var gw := _gauge.local_bounds().size.x if _gauge != null else 110.0
		_balance.position = Vector2(gw + 5, -5 + HUD_Y)
		# The "+" buy backgrounds only showed on hover, to open the store.
		for part: String in ["coinAddBG", "creditAddBG"]:
			var bg := _balance.part(part) as CanvasItem
			if bg != null:
				bg.visible = false
		left.add_child(_balance)
	_gv_meter = FlashUi.make("GarageValueTierMeterContent")
	if _gv_meter != null:
		_gv_meter.position = Vector2(0, 87 + HUD_Y)
		left.add_child(_gv_meter)
	_mission_dock = Node2D.new()
	_mission_dock.position = Vector2(40, 220 + HUD_Y)
	left.add_child(_mission_dock)
	var missions := FlashButton.of("LongTermMissionsIcon")
	if missions != null:
		missions.pressed.connect(func() -> void: action.emit("missions"))
		_mission_dock.add_child(missions)


## The coloured XP arc is revealed by a pie-shaped mask, like the original.
func _setup_xp_bar() -> void:
	var bar := _gauge.part("xpBar") as Node2D
	if bar == null:
		return
	var bounds := (bar as FlashSymbol).local_bounds() if bar is FlashSymbol else Rect2(0, 0, 80, 80)
	_xp_radius = bounds.size.x / 2.0
	_xp_clip = Polygon2D.new()
	_xp_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_xp_clip.position = bar.position + bounds.position + bounds.size / 2.0
	var parent := bar.get_parent()
	var index := bar.get_index()
	parent.remove_child(bar)
	bar.position -= _xp_clip.position
	_xp_clip.add_child(bar)
	parent.add_child(_xp_clip)
	parent.move_child(_xp_clip, index)


func _set_xp_arc(fraction: float) -> void:
	if _xp_clip == null:
		return
	var pts := PackedVector2Array([Vector2.ZERO])
	var end := int(fraction * XPBAR_ANGLE_RANGE)
	for a in range(0, end + 1):
		var rad := deg_to_rad(-210.0 + a)
		pts.append(Vector2(cos(rad), sin(rad)) * (_xp_radius + 1))
	if pts.size() < 3:
		pts = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	_xp_clip.polygon = pts


# --- Top right: picture and the six control buttons ---------------------------------------

func _build_right() -> void:
	var box := Panel.new()
	var style := StyleBoxFlat.new()
	# Original: 83 x 52 rounded rect, grey gradient, 2 px dark outline.
	style.bg_color = Color8(0xB9, 0xBA, 0xC0)
	style.border_color = Color8(0x68, 0x68, 0x66)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	box.add_theme_stylebox_override("panel", style)
	box.position = Vector2(670 - 120, HUD_Y)
	box.size = Vector2(83, 52)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(box)
	var buttons: Array[Array] = [
		["BtnSound", "sound"], ["BtnQuality", "quality"], ["BtnZoomIn", "zoom_in"],
		["BtnMusic", "music"], ["BtnFullScreen", "fullscreen"], ["BtnZoomOut", "zoom_out"],
	]
	var x := 0.0
	var y := 0.0
	for i in buttons.size():
		var b := FlashButton.of(buttons[i][0])
		if b == null:
			continue
		var r := (b.body as FlashSymbol).local_bounds()
		if i == 0:
			x = r.size.x / 2.0 + 7
			y = r.size.y / 2.0 + 5
		b.position = box.position + Vector2(x, y)
		var name: String = buttons[i][1]
		b.pressed.connect(func() -> void: action.emit(name))
		right.add_child(b)
		x += r.size.x + 5
		if i == 2:
			x = r.size.x / 2.0 + 7
			y += r.size.y + 3
	var photo := FlashButton.of("BtnPhoto", "Picture")
	if photo != null:
		photo.position = Vector2(643 - 130, 27 + HUD_Y)
		photo.pressed.connect(func() -> void: action.emit("picture"))
		right.add_child(photo)
	var menu := FlashTextButton.create("Menu", FlashTextButton.Kind.GRAY, 70, 30, 16)
	menu.position = Vector2(670 - 120 + 7, HUD_Y + 58)
	menu.pressed.connect(func() -> void: action.emit("menu"))
	right.add_child(menu)


# --- Bottom bar: chrome, location tabs, GPS, label, friends ------------------------------

func _build_bottom() -> void:
	var nav := Node2D.new()
	nav.position = Vector2(0, NAV_Y)
	bottom.add_child(nav)
	var chrome := FlashUi.make("BottomNavChrome")
	if chrome != null:
		nav.add_child(chrome)
	# Location tabs for your own garage (LocationButtons.setSelfLocation).
	var tabs := Node2D.new()
	tabs.position.y = 1
	nav.add_child(tabs)
	var x := 0.0
	for entry: Array in [
		["LocButtonDocksGfx", "The Docks", "docks"], ["LocButtonEditGarageGfx", "Edit Garage", "edit"],
		["LocButtonCarShoppingGfx", "Buy Cars", "dealer"], ["LocButtonGloveboxGfx", "Glove Box", "glovebox"],
	]:
		var b := FlashButton.of(entry[0], entry[1])
		if b == null:
			continue
		var r := (b.body as FlashSymbol).local_bounds()
		b.position = Vector2(x - r.position.x, 0)
		var name: String = entry[2]
		b.pressed.connect(func() -> void: action.emit(name))
		tabs.add_child(b)
		x += r.size.x + 5
	tabs.position.x = 510 - x
	_location_label = FlashUi.make("LocationLabelGfx")
	if _location_label != null:
		_location_label.position = Vector2(137, -16)
		_location_label.text("nameField", "My Garage")
		# No profile picture: LocationLabel hides it and moves the name left.
		for part: String in ["picture", "floorButtonsContainer"]:
			var p := _location_label.part(part) as CanvasItem
			if p != null:
				p.visible = false
		var name_field := _location_label.part("nameField") as Node2D
		if name_field != null:
			name_field.position.x = 0
		nav.add_child(_location_label)
	var gps := FlashButton.of("GPSButtonGfx")
	if gps != null:
		var r := (gps.body as FlashSymbol).local_bounds()
		gps.body.position = -r.position - r.size / 2.0
		gps._hit.position = -r.size / 2.0
		gps.position = Vector2(10 + r.size.x / 2.0, -50 + r.size.y / 2.0)
		gps.pressed.connect(func() -> void: action.emit("town"))
		nav.add_child(gps)
	_build_friend_list(nav)


## GarageFriendList in its default garage-value mode: the tan tab with the
## garage-value and XP tab icons on the left and a card per neighbour.
func _build_friend_list(nav: Node2D) -> void:
	var list := Node2D.new()
	list.position = Vector2(18, 38)
	nav.add_child(list)
	var tab := FlashUi.make("GarageValueTab")
	if tab == null:
		return
	list.add_child(tab)
	for arrow: String in ["leftArrow", "rightArrow"]:
		var a := tab.part(arrow) as CanvasItem
		if a != null:
			a.visible = false
	var tab_h := tab.local_bounds().end.y
	var gv := FlashUi.make("GVTabIcon")
	if gv != null:
		gv.position = Vector2(15, 11) - gv.local_bounds().position
		tab.add_child(gv)
	var xp := FlashUi.make("XPTabIcon")
	if xp != null:
		var r := xp.local_bounds()
		xp.position = Vector2(13, tab_h - r.size.y - 15) - r.position
		tab.add_child(xp)
	_friend_cards = tab.part("userHolder") as Node2D


## Neighbours by garage value, 82 px apart (GarageFriendListSprite).
func _refresh_friends(s: Dictionary) -> void:
	if _friend_cards == null:
		return
	for c in _friend_cards.get_children():
		c.queue_free()
	var people: Array = [[s["player"]["name"], Backend.query().garage_value()], ["Rusty", RUSTY_GARAGE_VALUE]]
	people.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	for i in people.size():
		var card := FlashUi.make("FriendListSpriteGarageValueGfx")
		if card == null:
			return
		card.text("nameField", people[i][0])
		card.text("gvFld", "$" + Format.abbreviated(people[i][1]))
		card.position.x = i * 82 + 7
		_friend_cards.add_child(card)


## Full-screen screens (Buy Cars, Customize) keep only the level gauge and
## balance; the controls, garage value, missions and bottom bar go away.
func set_screen_mode(on: bool) -> void:
	right.visible = not on
	bottom.visible = not on
	if _gv_meter != null:
		_gv_meter.visible = not on
	if _mission_dock != null:
		_mission_dock.visible = not on and _missions_allowed


var _missions_allowed := true


## The missions dock only appears once the tutorial is over.
func set_mission_dock_visible(on: bool) -> void:
	_missions_allowed = on
	if _mission_dock != null:
		_mission_dock.visible = on and bottom.visible


# --- Values -------------------------------------------------------------------------------

func refresh() -> void:
	var s := Backend.state()
	if s.is_empty():
		return
	var p: Dictionary = s["player"]
	var cat := GameData.catalog
	if _gauge != null:
		var cur: int = cat.level_info(p["level"])["xp"]
		var next: int = cat.level_info(p["level"] + 1)["xp"] if p["level"] < cat.max_level() else cur + 1
		var frac := clampf(float(p["xp"] - cur) / maxf(1.0, next - cur), 0.0, 1.0)
		_gauge.text("levelField", str(p["level"]))
		_gauge.text("levelNameField", "LEVEL")
		var needle := _gauge.part("needle") as Node2D
		if needle != null:
			needle.rotation_degrees = frac * XPBAR_ANGLE_RANGE
		_set_xp_arc(frac)
	var xp_text := str(p["xp"]).lpad(COUNTER_DIGITS, "0").right(COUNTER_DIGITS)
	for i in _digits.size():
		_digits[i].text("digitField", xp_text[COUNTER_DIGITS - 1 - i])
	if _balance != null:
		_balance.text("moneyField", Format.number(p["coins"]))
		_balance.text("pointsField", Format.number(p["blue"]))
	if _gv_meter != null:
		_gv_meter.text("tierField", str(Backend.query().garage_value_tier()))
	_refresh_friends(s)
