class_name DocksScreen
extends StageUi
## The Docks (integrations/docks/views/DocksView): Fat Tony on the pier, the
## boat with its eight crates, the water. Talk to Tony for a boat, search it,
## pick a crate, and claim the car inside or search again.

const WATER := Color8(0x1B, 0x1F, 0x22)
## DocksLightingContent's night tint, carried past the stage's edges.
const NIGHT := Color(13 / 255.0, 0, 74 / 255.0, 100 / 255.0)
const BOAT_START := Vector2(-610, -610)
const BOAT_DOCKED := Vector2(178, -38)
const BOAT_GONE := Vector2(1200, 540)
const SAIL_IN_SECONDS := 4.0
const SAIL_OUT_SECONDS := 6.0
## Where each crate sits on the boat (DocksView.populateCrates).
const CRATE_SPOTS: Array[Vector2] = [
	Vector2(250, 173), Vector2(314, 206), Vector2(377, 239), Vector2(444, 272),
	Vector2(166, 216), Vector2(230, 249), Vector2(293, 282), Vector2(360, 315),
]
## An opened crate lands on the pier here, then its car drives off.
const CRATE_LANDING := Vector2(-78, 323)
const CAR_DRIVE_AWAY := Vector2(-350, 430)
const TONY_AT := Vector2(405, 330)
const HIGHLIGHT := Color(1.25, 1.2, 0.8)

const SAY_WELCOME := "Hey kid, want to get in my van?"
const SAY_FIRST_TIME := "Hey Kid, welcome to The Docks.\nSince it's your first time here,\nyour first search is on me.\n\nClick me to get started."
const SAY_PICK_CRATE := "Take ya time, choose the right container..."
const SAY_NEXT_BOAT := "There's another ship coming in soon with\neven better cars. Click me to see the\nShipping Manifest."
const SAY_SECOND_BOAT := "Alright kid, I've got the manifest for a\nspecial boat only available to my dearest\ncustomers. Click me to take a look."

var _world: Node2D
var _boat: FlashSymbol
var _boat_cargo: Node2D
var _crates: Array[FlashSymbol] = []
var _crate_cars: Array[Node2D] = []
var _tony: FlashSymbol
var _tony_button: FlashButton
var _bubble: TalkBubble
var _confirm: Node2D
## While the boat moves or a crate flies, clicks wait.
var _busy := false


func _ready() -> void:
	super()
	var bg := ColorRect.new()
	bg.color = WATER.lerp(Color(NIGHT, 1.0), NIGHT.a)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	move_child(bg, 0)
	var fit := func() -> void: bg.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(fit)
	fit.call()
	_world = Node2D.new()
	center.add_child(_world)
	_build_scene()
	_show_state()


func _build_scene() -> void:
	var water := FlashUi.make("swcassets.docks.DocksBGContent")
	if water != null:
		water.position.y = -30
		_world.add_child(water)
		# Wider windows see past the stage's left edge: more water there.
		var more := FlashUi.make("swcassets.docks.DocksBGContent")
		more.position.y = -30
		more.scale.x = -1
		_world.add_child(more)
	_boat = FlashUi.make("swcassets.docks.DocksBoatContent")
	if _boat != null:
		_world.add_child(_boat)
	var foreground := FlashUi.make("swcassets.docks.DocksForegroundContent")
	if foreground != null:
		_world.add_child(foreground)
	_boat_cargo = Node2D.new()
	for i in CRATE_SPOTS.size():
		var crate := FlashUi.make("swcassets.docks.DocksContainerContent")
		if crate == null:
			continue
		crate.position = CRATE_SPOTS[i]
		# DockCrateObj.color picks the crate's paint; we vary it by slot.
		crate.goto(i % maxi(1, crate.frame_count - 1))
		var button := FlashButton.wrap_node(crate, Rect2(0, 0, 152, 125))
		button.set_base_scale(1.0, 1.0)
		button.pressed.connect(_on_crate_clicked.bind(i))
		_boat_cargo.add_child(button)
		_crates.append(crate)
		var car_holder := Node2D.new()
		car_holder.position = Vector2(50, 40)
		crate.add_child(car_holder)
		_crate_cars.append(car_holder)
	var hull := FlashUi.make("swcassets.docks.DocksHullContent")
	if hull != null:
		hull.position = Vector2(370, 409)
		_boat_cargo.add_child(hull)
	_world.add_child(_boat_cargo)
	var cleats := FlashUi.make("swcassets.docks.DocksCleatsContent")
	if cleats != null:
		_world.add_child(cleats)
	var dingy := FlashUi.make("swcassets.docks.DocksDingyContent")
	if dingy != null:
		dingy.position = Vector2(160, 468)
		dingy.rotation_degrees = -3
		_world.add_child(dingy)
		var rock := dingy.create_tween().set_loops()
		rock.tween_property(dingy, "rotation_degrees", 3.0, 5.0).set_trans(Tween.TRANS_SINE)
		rock.tween_property(dingy, "rotation_degrees", -3.0, 5.0).set_trans(Tween.TRANS_SINE)
	var shadow := FlashUi.make("swcassets.docks.FatTonyShadowsContent")
	if shadow != null:
		shadow.position = TONY_AT + Vector2(0, 1)
		_world.add_child(shadow)
	var lighting := FlashUi.make("swcassets.docks.DocksLightingContent")
	if lighting != null:
		_world.add_child(lighting)
	for side: float in [-1.0, 1.0]:
		var tint := ColorRect.new()
		tint.color = NIGHT
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tint.size = Vector2(2000, 1200)
		tint.position = Vector2(-2000 if side < 0 else STAGE.x, -250)
		_world.add_child(tint)
	_tony = FlashUi.make("swcassets.docks.FatTonyContent")
	if _tony != null:
		_tony_button = FlashButton.wrap_node(_tony, Rect2(-60, -90, 120, 110))
		_tony_button.set_base_scale(1.0, 1.0)
		_tony_button.position = TONY_AT
		_tony_button.pressed.connect(_on_tony_clicked)
		_world.add_child(_tony_button)
	_confirm = _build_confirm()
	_world.add_child(_confirm)


## The little "Open this container?" box over a crate (DocksContainerPopupContent).
func _build_confirm() -> Node2D:
	var root := Node2D.new()
	root.visible = false
	var gfx := FlashUi.make("swcassets.docks.DocksContainerPopupContent")
	if gfx != null:
		gfx.styled_text("messageField", "Open this container?", "sansD01")
		root.add_child(gfx)
	var ok := FlashTextButton.create("OK", FlashTextButton.Kind.GREEN, 54, 30, 16, true)
	ok.position = Vector2(20, 72)
	ok.pressed.connect(func() -> void:
		root.visible = false
		_open_crate(int(root.get_meta("crate", -1))))
	root.add_child(ok)
	var cancel := FlashTextButton.create("Cancel", FlashTextButton.Kind.RED, 64, 30, 16, true)
	cancel.position = Vector2(80, 72)
	cancel.pressed.connect(func() -> void:
		root.visible = false
		_say(SAY_PICK_CRATE))
	root.add_child(cancel)
	return root


func _boat_state() -> Dictionary:
	return Backend.state()["docks"]["boat"]


## Lays the scene out from the save: the boat in or out, crates opened or
## not, and what Tony says.
func _show_state() -> void:
	var boat := _boat_state()
	var docks: Dictionary = Backend.state()["docks"]
	if not boat.get("active", false):
		_set_boat_position(BOAT_START)
		if not docks["first_done"]:
			_say(SAY_WELCOME)
			await get_tree().create_timer(2.5).timeout
			if is_inside_tree() and not _boat_state().get("active", false):
				_say(SAY_FIRST_TIME)
		else:
			_say(SAY_SECOND_BOAT if Backend.query().docks_special_boat(Backend.now()) else SAY_NEXT_BOAT)
		return
	_set_boat_position(BOAT_DOCKED)
	_lay_out_crates()
	var open: int = (boat["states"] as Array).find(GameLogic.CRATE_OPEN)
	if open >= 0:
		_crates[open].position = CRATE_LANDING - _boat_cargo.position
		_show_car_in_crate(open)
		_offer_found(open)
	else:
		_say(SAY_PICK_CRATE)


func _lay_out_crates() -> void:
	var states: Array = _boat_state().get("states", [])
	for i in _crates.size():
		var crate := _crates[i]
		crate.get_parent().position = Vector2.ZERO
		crate.position = CRATE_SPOTS[i]
		crate.visible = i < states.size() and int(states[i]) != GameLogic.CRATE_PASSED
		for c in _crate_cars[i].get_children():
			c.queue_free()


func _set_boat_position(at: Vector2) -> void:
	if _boat != null:
		_boat.position = at
	_boat_cargo.position = at


func _sail_boat(to: Vector2, seconds: float, ease_in: bool) -> void:
	var t := create_tween().set_parallel()
	t.tween_property(_boat, "position", to, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN if ease_in else Tween.EASE_OUT)
	t.tween_property(_boat_cargo, "position", to, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN if ease_in else Tween.EASE_OUT)
	await t.finished


## Tony's speech bubble (ExpandingDialogueBubble, to his right).
func _say(text: String) -> void:
	if _bubble != null:
		_bubble.queue_free()
		_bubble = null
	if text.is_empty():
		return
	_bubble = TalkBubble.create(text, 330, 16, true)
	_bubble.position = TONY_AT + Vector2(20, -40 - _bubble.content_size.y)
	_world.add_child(_bubble)


func _on_tony_clicked() -> void:
	if _busy or _boat_state().get("active", false):
		return
	_say("")
	if not Backend.state()["docks"]["first_done"]:
		_bring_boat(1, 0)
		return
	var special := Backend.query().docks_special_boat(Backend.now())
	DocksPopups.open_next_ship(get_tree(), special, func(boat_id: int) -> void: _bring_boat(boat_id, 0))


## Gets a boat's manifest and shows it.
func _bring_boat(boat_id: int, wanted: int) -> void:
	var r: GameResult = await Backend.docks_manifest(boat_id, wanted)
	if not r.ok:
		_fail(r.error)
		return
	_show_manifest()


func _show_manifest() -> void:
	DocksPopups.open_manifest(get_tree(), _search, _ask_for_car)


func _ask_for_car() -> void:
	DocksPopups.open_select_car(get_tree(), func(car_id: int) -> void:
		var r: GameResult = await Backend.docks_manifest(1, car_id)
		if not r.ok:
			_fail(r.error)
			return
		DocksPopups.open_buy_confirm(get_tree(), car_id, Backend.query().docks_search_price(), _search, _show_manifest))


## Pays for the boat; it sails in and the crates can be picked.
func _search() -> void:
	var r: GameResult = await Backend.docks_search()
	if not r.ok:
		_fail(r.error)
		return
	_busy = true
	_lay_out_crates()
	_set_boat_position(BOAT_START)
	Sound.play("CarHornSound1")
	await _sail_boat(BOAT_DOCKED, SAIL_IN_SECONDS, false)
	_busy = false
	_say(SAY_PICK_CRATE)


func _on_crate_clicked(index: int) -> void:
	var boat := _boat_state()
	if _busy or not boat.get("active", false) or (boat["states"] as Array).has(GameLogic.CRATE_OPEN):
		return
	if int(boat["states"][index]) != GameLogic.CRATE_CLOSED:
		return
	_say("")
	_confirm.set_meta("crate", index)
	_confirm.position = _boat_cargo.position + CRATE_SPOTS[index] + Vector2(-10, -90)
	_confirm.visible = true


## selectCrate: the crate flies over to the pier and opens.
func _open_crate(index: int) -> void:
	if index < 0:
		return
	_busy = true
	var crate := _crates[index]
	var target := CRATE_LANDING - _boat_cargo.position
	var start := crate.position
	var peak := Vector2(292, -300) - _boat_cargo.position
	var t := create_tween()
	t.tween_method(func(k: float) -> void:
		# A quadratic bezier through the original's control point.
		crate.position = start.lerp(peak, k).lerp(peak.lerp(target, k), k), 0.0, 1.0, 1.0)
	await t.finished
	var r: GameResult = await Backend.docks_open_crate(index)
	_busy = false
	if not r.ok:
		_fail(r.error)
		_lay_out_crates()
		return
	_show_car_in_crate(index)
	Sound.play("SuccessSound1")
	_offer_found(index)


## revealCar: the car's front view standing in the open crate.
func _show_car_in_crate(index: int) -> void:
	var car_id: int = _boat_state()["crates"][index]
	var crate := _crates[index]
	crate.goto(crate.frame_count - 1)
	var view := CarView.new()
	view.setup(CarView.stock_entry(car_id, 0), CarView.VIEW_FRONT, false)
	view.scale = Vector2(0.7, 0.7)
	_crate_cars[index].add_child(view)


func _offer_found(index: int) -> void:
	var car_id: int = _boat_state()["crates"][index]
	DocksPopups.open_found(get_tree(), car_id, _claim.bind(index), _search_again.bind(index))


func _claim(index: int) -> void:
	var r: GameResult = await Backend.docks_claim()
	if not r.ok:
		_fail(r.error)
		return
	_crates[index].visible = false
	DocksPopups.open_claimed(get_tree(), int(r.data["car_id"]))
	_busy = true
	await _sail_boat(BOAT_GONE, SAIL_OUT_SECONDS, true)
	_busy = false
	_say(SAY_SECOND_BOAT if Backend.query().docks_special_boat(Backend.now()) else SAY_NEXT_BOAT)


## Passes over the car: it drives off the pier and the search goes on.
func _search_again(index: int) -> void:
	var r: GameResult = await Backend.docks_search_again()
	if not r.ok:
		_fail(r.error)
		_offer_found(index)
		return
	_busy = true
	var crate := _crates[index]
	var t := create_tween()
	t.tween_property(crate, "position", CAR_DRIVE_AWAY - _boat_cargo.position, 2.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await t.finished
	crate.visible = false
	_busy = false
	_say(SAY_PICK_CRATE)


func _fail(message: String) -> void:
	Sound.play("ActionDeniedSound")
	GenericPopup.message(get_tree(), "The Docks", message)
