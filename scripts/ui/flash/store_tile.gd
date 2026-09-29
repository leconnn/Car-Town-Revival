class_name StoreTile
extends Node2D
## The original StoreItem: a rounded icon background (normal, locked or
## red "can't afford"), the item's picture centred on it, a lock icon in the
## top-left corner, a clock for limited items, and underneath either the
## price (PriceFieldLegacy) or a red "Level 12" style label.

signal pressed

const BG_POS := Vector2(7, 6)
const PRICE_Y := 84.0
const PRICE_GLOW := Color8(0x5F, 0x77, 0x91)
const LOCKED_COLOR := Color8(0xAE, 0x00, 0x00)
const INSTALLED_TINT := Color(0.72, 0.93, 0.62)

var _bg_size := Vector2(80, 76)


## [param picture] is centred on the background. [param price] < 0 hides it.
## [param lock_art] false keeps the normal background and no lock icon on a
## locked item (BuyCarItem did that; only the red label shows).
static func create(picture: Node2D, price: int, blue: bool, locked_label: String = "",
		red: bool = false, limited: bool = false, lock_art: bool = true) -> StoreTile:
	var t := StoreTile.new()
	t._build(picture, price, blue, locked_label, red, limited, lock_art)
	return t


func _build(picture: Node2D, price: int, blue: bool, locked_label: String, red: bool, limited: bool, lock_art: bool) -> void:
	var locked := locked_label != ""
	var bg_name := "StoreItemNewIconLocked" if locked and lock_art else ("StoreItemNewIconRestricted" if red else "StoreItemNewIconBg")
	var bg := FlashUi.make(bg_name)
	if bg != null:
		bg.position = BG_POS
		_bg_size = bg.local_bounds().end
		add_child(bg)
	if picture != null:
		picture.position += BG_POS + _bg_size / 2.0 + Vector2(3, 3)
		add_child(picture)
	if locked:
		var lock := FlashUi.make("UIIconLock") if lock_art else null
		if lock != null:
			lock.position = Vector2(1, 1.5) - lock.local_bounds().position
			add_child(lock)
		var label := FlashUi.styled_label(locked_label, "casualA01", 14, LOCKED_COLOR)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(_bg_size.x, 0)
		label.position = Vector2(BG_POS.x, PRICE_Y)
		add_child(label)
	elif price >= 0:
		add_child(price_field(price, blue))
	if limited:
		var clock := FlashUi.make("UIIconClock")
		if clock != null:
			clock.position = Vector2(71, 3) - clock.local_bounds().position
			add_child(clock)
	var hit := Control.new()
	hit.position = BG_POS
	hit.size = _bg_size
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sound.play("ClickSound01")
			pressed.emit()
			hit.accept_event())
	add_child(hit)


## StoreItem.isInstalled: a check mark, a green tint on the icon background
## (the original multiplied UIItemGreenOverlay over it) and the price faded
## to 20%.
func set_installed() -> void:
	var bg := get_child(0) as CanvasItem
	if bg != null:
		bg.modulate = INSTALLED_TINT
	var check := FlashUi.make("UIIconCheckMark")
	if check != null:
		check.position = Vector2(8, 58) - check.local_bounds().position
		add_child(check)
	for c in get_children():
		if c is Node2D and (c as Node2D).position.y == PRICE_Y:
			(c as Node2D).modulate.a = 0.2


## StoreItem quantity: an open box for items you own, and a green bubble
## with the count when there's more than one.
func set_quantity(count: int) -> void:
	var box := FlashUi.make("UIIconOpenBox")
	if box != null:
		box.position = Vector2(32, 0)
		add_child(box)
	if count > 1:
		var bubble := Node2D.new()
		bubble.position = Vector2(48, 10)
		var circle := Polygon2D.new()
		var outline := Line2D.new()
		var pts := PackedVector2Array()
		for i in 24:
			pts.append(Vector2(cos(TAU * i / 24.0), sin(TAU * i / 24.0)) * 10.0)
		circle.polygon = pts
		circle.color = Color8(0x75, 0xA1, 0x42)
		outline.points = pts
		outline.closed = true
		outline.width = 2.0
		outline.default_color = Color8(0x3E, 0x3A, 0x33)
		bubble.add_child(circle)
		bubble.add_child(outline)
		var label := FlashUi.styled_label(str(count), "casualA01", 16, Color.WHITE)
		label.position = -label.get_minimum_size() / 2.0
		bubble.add_child(label)
		add_child(bubble)


## PriceFieldLegacy: a small coin (or blue coin) and the amount in white
## Arial Bold with a blue-grey glow, at y 84 under the tile.
static func price_field(price: int, blue: bool) -> Node2D:
	var root := Node2D.new()
	root.position.y = PRICE_Y
	var text := Format.number(price)
	var size := 15 if text.length() <= 7 else 12
	var label := FlashUi.styled_label(text, "sansA02", size, Color.WHITE, PRICE_GLOW, 4)
	label.position = Vector2(30, 0 if size >= 14 else 2)
	root.add_child(label)
	var icon := FlashUi.make("UIIconCoin")
	if icon != null:
		icon.position = Vector2(13, 2)
		var coin := icon.part("coinIcon") as CanvasItem
		var credit := icon.part("creditIcon") as CanvasItem
		if coin != null:
			coin.visible = not blue
		if credit != null:
			credit.visible = blue
		root.add_child(icon)
	return root
