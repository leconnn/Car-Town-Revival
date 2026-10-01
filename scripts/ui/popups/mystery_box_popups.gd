class_name MysteryBoxPopups
extends Node2D
## Mystery boxes (views/mysterybox): the slot machine you spin to see the car
## inside (MysteryBoxSpinWheelPopup on MysteryBoxPopupContent), and Claim Car
## or Respin afterwards (MysteryBoxClaimOrRespinPopup).

signal spun

## The reel's three slots (MysteryBoxSpinWheelPopup TOP_Y / MIDDLE_Y / BOTTOM_Y).
const TOP_Y := -71.0
const BOTTOM_Y := 71.0
const SQUISH := 0.3
const THUMB_WIDTH := 120.0
const WHEEL_CARS := 6
const TITLE_COLOR := Color.WHITE
const TITLE_GLOW := Color8(0x23, 0x4F, 0x70)
## Backdrops exist for the first seven boxes; the rest borrow Gold's.
const FALLBACK_BG := 3

var uid := 0
var level := 1
var car_id := 0
var _gfx: FlashSymbol
var _popup: FlashPopup
## The reel: index 0 is the car inside, then five others from the box.
var _wheel: Array[int] = []
var _index := 3
var _delay := 0.1
var _slowing := false
var _spinning := false
var _slots: Array[Node2D] = []
var _start_hit: Control
var _stop_hit: Control


## The slot machine for box [param box_uid]. [signal spun] fires once the
## reel stops (and the rules have recorded it).
static func open_spin(tree: SceneTree, box_uid: int) -> MysteryBoxPopups:
	var box: Dictionary = Backend.state()["mystery_boxes"].get(str(box_uid), {})
	if box.is_empty():
		return null
	var p := MysteryBoxPopups.new()
	p.uid = box_uid
	p.level = int(box["level"])
	p.car_id = int(box["car_id"])
	if not p._build_spin():
		return null
	p._popup = FlashPopup.open_bare(tree, p)
	return p


func _build_spin() -> bool:
	_gfx = FlashUi.make("MysteryBoxPopupContent")
	if _gfx == null:
		return false
	add_child(_gfx)
	var holder := _gfx.part("backgroundContainer") as Node2D
	var bg := art_sprite("MysteryBoxBG_%d" % level)
	if bg == null:
		bg = art_sprite("MysteryBoxBG_%d" % FALLBACK_BG)
	if holder != null and bg != null:
		holder.add_child(bg)
	_gfx.styled_text("titleField", box_name(level), "casualA01")
	_gfx.outline("titleField", TITLE_GLOW, 5)
	_gfx.styled_text("messageFld", "Click the 'Start' button\nto spin the wheel!", "casualA01")
	_gfx.styled_text("youWonField", "", "sansD01")
	# Set on the buttons themselves so the labels survive their frame changes.
	_button("startButton").styled_text("buttonField", "Start", "casualA01")
	_button("stopButton").styled_text("buttonField", "Stop", "casualA01")
	var lights := _gfx.part("pointerLights") as FlashSymbol
	if lights != null:
		lights.visible = false
	_button("stopButton").goto(2)
	# The reel: the car inside first, then five others from the same box.
	_wheel = [car_id]
	var pool := Backend.query().mystery_pool(level)
	pool.erase(car_id)
	pool.shuffle()
	for id: int in pool.slice(0, WHEEL_CARS - 1):
		_wheel.append(id)
	while _wheel.size() < WHEEL_CARS:
		_wheel.append(car_id)
	# The reel shows through a window (the original masked carContainer).
	var reel := _gfx.part("carContainer") as Node2D
	var window := Polygon2D.new()
	window.polygon = PackedVector2Array([Vector2(-60, -82), Vector2(60, -82), Vector2(60, 82), Vector2(-60, 82)])
	window.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	if reel != null:
		reel.add_child(window)
	for i in 3:
		var slot := _gfx.part("carContainer/imageContainer%d" % i) as Node2D
		if slot != null:
			slot.reparent(window, false)
			_slots.append(slot)
	_show_reel(_index)
	_start_hit = _hotspot("startButton", _on_start)
	_stop_hit = _hotspot("stopButton", _on_stop)
	_stop_hit.visible = false
	return true


func _button(name: String) -> FlashSymbol:
	var b := _gfx.part(name) as FlashSymbol
	return b if b != null else FlashSymbol.new()


## A click area over one of the art's buttons.
func _hotspot(name: String, action: Callable) -> Control:
	var hit := Control.new()
	var b := _gfx.part(name) as FlashSymbol
	if b != null:
		var r := b.local_bounds()
		hit.position = b.position + r.position
		hit.size = r.size
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			action.call())
	add_child(hit)
	return hit


func _on_start() -> void:
	_start_hit.visible = false
	_button("startButton").goto(2)
	_button("stopButton").goto(0)
	_stop_hit.visible = true
	_gfx.styled_text("messageFld", "Click the 'Stop' button\nto select a car!", "casualA01")
	Sound.play("SlotClick")
	Sound.play("SlotLoop")
	_spinning = true
	_tick()


func _on_stop() -> void:
	_stop_hit.visible = false
	_button("stopButton").goto(2)
	_slowing = true
	Sound.play("SlotDrumroll")
	Sound.play("SlotClick")
	# UpdateMysteryBoxSpinStateRequest: the spin counts once Stop is hit.
	await Backend.mystery_box_spun(uid)


## One step of the reel: the next car drops into the middle slot. After
## Stop each step takes longer, until it lands on the car inside.
func _tick() -> void:
	while _spinning and is_inside_tree():
		_index -= 1
		if _slowing:
			_delay += 0.1
		if _index < 0:
			_index = _wheel.size() - 1
		var landing := _delay >= 0.5 and _index == 0
		_show_reel(_index)
		var lights := _gfx.part("pointerLights") as CanvasItem
		if lights != null:
			lights.visible = _index % 2 == 1
		if _slots.size() == 3:
			_slots[0].position.y = TOP_Y
			_slots[0].scale.y = SQUISH
			_slots[1].position.y = 0.0
			_slots[1].scale.y = 1.0
			var t := create_tween().set_parallel()
			t.tween_property(_slots[0], "position:y", 0.0, _delay).set_trans(
				Tween.TRANS_BOUNCE if landing else Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)
			t.tween_property(_slots[0], "scale:y", 1.0, _delay)
			t.tween_property(_slots[1], "position:y", BOTTOM_Y, _delay)
			t.tween_property(_slots[1], "scale:y", SQUISH, _delay / 2.0).set_delay(_delay / 2.0)
			await t.finished
		else:
			await get_tree().create_timer(_delay).timeout
		if landing:
			_spinning = false
			_finish()


## Three cars in view from [param start]: the middle one is the pick.
func _show_reel(start: int) -> void:
	for i in _slots.size():
		for c in _slots[i].get_children():
			c.queue_free()
		var id: int = _wheel[(start + i) % _wheel.size()]
		var thumb := car_thumb(id, THUMB_WIDTH)
		if thumb != null:
			_slots[i].add_child(thumb)
	if _slots.size() == 3:
		_slots[2].modulate.a = 0.0


## spinningComplete: lights, "You Won!", the car's name and OK.
func _finish() -> void:
	Sound.play("SlotReveal")
	var lights := _gfx.part("pointerLights") as FlashSymbol
	if lights != null:
		lights.visible = true
		lights.play(30.0)
	_button("startButton").goto(3)
	_button("stopButton").goto(3)
	_gfx.styled_text("youWonField", "You Won!", "sansD01")
	_gfx.styled_text("messageFld", GameData.car_name(car_id), "casualA01")
	var ok := FlashTextButton.create("OK", FlashTextButton.Kind.GREEN, 65, 40, 22, true)
	ok.position = Vector2(168, 497)
	ok.scale = Vector2(0.2, 0.2)
	ok.pressed.connect(func() -> void:
		_popup.close()
		spun.emit())
	add_child(ok)
	var grow := create_tween()
	grow.tween_property(ok, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# --- Claim or respin -------------------------------------------------------------------

## MysteryBoxClaimOrRespinPopup: the car you won on the box's backdrop, Claim
## Car, and Respin for the price if you haven't yet.
static func open_claim(tree: SceneTree, box_uid: int, claim: Callable, respin: Callable) -> FlashPopup:
	var box: Dictionary = Backend.state()["mystery_boxes"].get(str(box_uid), {})
	var gfx := FlashUi.make("MysteryBoxClaimOrRespinPopupContent")
	if box.is_empty() or gfx == null:
		return null
	var lvl := int(box["level"])
	var won := int(box["car_id"])
	var can_respin: bool = int(box["spin"]) == GameLogic.BOX_SPUN
	var root := Node2D.new()
	root.add_child(gfx)
	var holder := gfx.part("backgroundContainer") as Node2D
	var bg := art_sprite("MysteryBoxClaimBG_%d" % lvl)
	if bg == null:
		bg = art_sprite("MysteryBoxClaimBG_%d" % FALLBACK_BG)
	if holder != null and bg != null:
		holder.add_child(bg)
	gfx.styled_text("titleField", box_name(lvl), "casualA01", 28)
	gfx.styled_text("carField", GameData.car_name(won), "sansD03")
	gfx.styled_text("messageField", "Claim this car or respin\nfor a chance to win\nsomething better!" if can_respin
		else "Congratulations!\nPlease claim\nyour new car.", "casualA01")
	var view := CarView.new()
	view.setup(CarView.stock_entry(won, 0), CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.6, 0.6)
	view.position = Vector2(150, 175)
	root.add_child(view)
	var buttons: Array = []
	var claim_button := FrameButton.with_text("Claim Car", FrameButton.GREEN)
	buttons.append(claim_button)
	var respin_button: FrameButton = null
	if can_respin:
		var cost := Backend.query().mystery_box_respin_price(lvl)
		respin_button = DocksPopups.price_button("Respin", cost, FrameButton.LIGHT_BLUE)
		buttons.append(respin_button)
	var popup := FlashPopup.open_framed(tree, root, [10, 12, 12, 12], buttons)
	claim_button.pressed.connect(func() -> void:
		popup.close()
		claim.call())
	if respin_button != null:
		respin_button.pressed.connect(func() -> void:
			popup.close()
			respin.call())
	return popup


# --- Shared ---------------------------------------------------------------------------

## "Silver Mystery Box": the box's item name from the catalog.
static func box_name(lvl: int) -> String:
	var b: Dictionary = GameData.catalog.mystery_boxes.get(lvl, {})
	var item: Dictionary = GameData.catalog.item(int(b.get("item_id", 0)))
	return str(item.get("name", "Mystery Box"))


## Art rendered from the mystery box movies (see export_art.py).
static func art_sprite(key: String) -> Sprite2D:
	var info: Dictionary = GameData.mysterybox_art.get(key, {})
	var tex := GameData.texture(info.get("file", ""))
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	var o: Array = info.get("o", [0, 0])
	s.offset = -Vector2(o[0], o[1])
	return s


## The same art centred on its origin and shrunk to fit [param fit].
static func art_fitted(key: String, fit: Vector2) -> Sprite2D:
	var s := art_sprite(key)
	if s == null:
		return null
	s.centered = true
	s.offset = Vector2.ZERO
	var size := s.texture.get_size()
	var k := minf(1.0, minf(fit.x / size.x, fit.y / size.y))
	s.scale = Vector2(k, k)
	return s


## A car's store thumbnail (TrimmedCarThumbnail), centred, [param width] wide.
static func car_thumb(id: int, width: float) -> Sprite2D:
	var tex := GameData.texture(GameData.car_art.get(str(id), {}).get("thumb", {}).get("file", ""))
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	var k := width / maxf(tex.get_width(), 1.0)
	s.scale = Vector2(k, k)
	return s
