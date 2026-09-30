extends Node2D
## The main game screen: garage, camera, HUD and all panels. Knows nothing
## about the game mode; everything goes through Backend.

const ZOOM_MIN := 0.35
const ZOOM_MAX := 1.6

var garage: GarageView
## A place in town while you're visiting one (else hidden).
var location_view: LocationView
var camera: Camera2D
var hud: ShellHud
var toasts: Toasts
var notices: RewardPopups
var edit_mode := false

var _ui: CanvasLayer
var _placement: Placement
var _edit_tray: EditGarageTray
var _moving: Dictionary = {}
var _dragging := false
var _drag_moved := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(GarageView.TOWN_FILL)
	garage = GarageView.new()
	add_child(garage)
	garage.object_clicked.connect(_on_object_clicked)
	garage.rotate_clicked.connect(_rotate_object)
	location_view = LocationView.new()
	location_view.visible = false
	add_child(location_view)
	camera = Camera2D.new()
	# Framed like the original: the garage's front half and the crossroads.
	camera.position = garage.center_screen_position() + Vector2(0, 90)
	camera.zoom = Vector2(1.0, 1.0)
	add_child(camera)

	_ui = CanvasLayer.new()
	add_child(_ui)
	hud = ShellHud.new()
	hud.action.connect(_on_hud_action)
	_ui.add_child(hud)
	toasts = Toasts.new()
	_ui.add_child(toasts)
	notices = RewardPopups.new()
	_ui.add_child(notices)
	Backend.notice.connect(notices.push)
	Backend.action_failed.connect(func(msg: String) -> void: toasts.show_message(msg, true))
	Backend.session_ended.connect(_on_session_ended)
	Lan.garage_received.connect(_on_garage_received)
	Backend.action_done.connect(_on_action_done)
	Backend.notice.connect(_on_notice_sound)
	Backend.action_failed.connect(func(_m: String) -> void: Sound.play("ActionDeniedSound"))
	Sound.music("mainLoop")
	Tutorial.attach(self)
	_dev_open.call_deferred()
	DevShot.maybe_capture(self)


## The asphalt around a town location's lot.
const LOCATION_FILL := Color8(0xA1, 0x9C, 0x96)

## A popup opened ("customer", "car_options") with its content node.
signal popup_opened(kind: String, content: Node)
## The Customize button was pressed in the car options popup.
signal customize_opened

## While the tutorial is in its restrictive phase: func(kind, uid) -> bool
## says whether a click on a garage object may go through.
var tutorial_filter: Callable
## HUD buttons that still work during the tutorial (the original's
## "message generating" controls).
const TUTORIAL_FREE_ACTIONS := ["zoom_in", "zoom_out", "sound", "music", "fullscreen", "quality"]


func add_tutorial(tut: Node) -> void:
	_ui.add_child(tut)
	_ui.move_child(tut, toasts.get_index())


## Glides the camera to [param world_pos] (the tutorial's ScrollMapProcess).
func focus_camera(world_pos: Vector2, zoom: float = -1.0, seconds: float = 1.0) -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(camera, "position", world_pos, seconds)
	if zoom > 0:
		tw.tween_property(camera, "zoom", Vector2(zoom, zoom), seconds)
	await tw.finished


# --- Screens ---------------------------------------------------------------------

## Full-screen views like Buy Cars: drawn under the HUD, which shrinks to the
## gauge and balance while one is open.
var _screen: Node


func open_screen(screen: Node) -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = screen
	_ui.add_child(screen)
	_ui.move_child(screen, 0)
	hud.set_screen_mode(true)
	screen.tree_exited.connect(func() -> void:
		if _screen == screen:
			_screen = null
			hud.set_screen_mode(false))


func _on_hud_action(name: String) -> void:
	if tutorial_filter.is_valid() and not TUTORIAL_FREE_ACTIONS.has(name):
		Sound.play("ActionDeniedSound")
		return
	if name.begins_with("missions:"):
		_open_missions(int(name.trim_prefix("missions:")))
		return
	if name.begins_with("visit:"):
		Lan.request_garage(name.trim_prefix("visit:"))
		return
	cancel_placement()
	# Shopping and decorating happen at home.
	if name in ["dealer", "shop", "edit"] and is_away():
		leave_location()
		go_home()
	match name:
		"dealer": open_screen(BuyCarScreen.new())
		"shop": set_edit_mode(true)
		"edit": set_edit_mode(not edit_mode)
		"town": _open_gps()
		"missions": _open_missions(-1)
		"menu": MenuPopup.open(get_tree())
		"docks", "glovebox": toasts.show_message("That arrives in a later update.")
		"zoom_in": _zoom_step(1)
		"zoom_out": _zoom_step(-1)
		"fullscreen":
			Settings.fullscreen = not Settings.fullscreen
			Settings.apply()
			Settings.save()
		"sound":
			Settings.sfx_volume = 0.0 if Settings.sfx_volume > 0.0 else 0.8
			Settings.apply()
			Settings.save()
		"music":
			Settings.music_volume = 0.0 if Settings.music_volume > 0.0 else 0.7
			Settings.apply()
			Settings.save()
		"quality": pass
		"picture": _take_picture()


## The original's fixed zoom steps.
const ZOOM_STEPS: Array[float] = [0.4, 2.0 / 3.0, 1.0, 1.4]


func _zoom_step(dir: int) -> void:
	var idx := 0
	for i in ZOOM_STEPS.size():
		if absf(ZOOM_STEPS[i] - camera.zoom.x) < absf(ZOOM_STEPS[idx] - camera.zoom.x):
			idx = i
	idx = clampi(idx + dir, 0, ZOOM_STEPS.size() - 1)
	create_tween().tween_property(camera, "zoom", Vector2(ZOOM_STEPS[idx], ZOOM_STEPS[idx]), 0.25)


## The original posted a garage picture to Facebook; we save it to Pictures.
func _take_picture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES).path_join("Car Town Revival")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("garage_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	img.save_png(path)
	Sound.play("ApprovalSound")
	toasts.show_message("Picture saved to %s" % path)


func _on_object_clicked(kind: String, uid: int) -> void:
	if tutorial_filter.is_valid() and not tutorial_filter.call(kind, uid):
		return
	if edit_mode:
		_edit_object(kind, uid)
		return
	match kind:
		"car":
			var bay_uid: int = Backend.query().get_car(uid).get("bay_uid", 0)
			if bay_uid != 0 and Backend.state()["jobs"].has(str(bay_uid)):
				# A car on a busy lift is part of the work bay.
				await _bay_clicked(bay_uid)
			elif Backend.state()["car_tasks"].has(str(uid)):
				await _car_task_clicked(uid)
			else:
				_open_car_options(uid)
		"car_task":
			await _car_task_clicked(uid)
		"customer":
			_open_customer(uid)
		"showroom":
			open_screen(BuyCarScreen.new())
		"bay":
			await _bay_clicked(uid)
		"item":
			var entry := _item_entry(uid)
			if GameData.catalog.item(entry.get("item_id", 0)).get("category", 0) == GarageGrid.CAT_WORK_BAY:
				await _bay_clicked(uid)


func _open_customer(uid: int) -> void:
	var cust := Backend.query().get_customer(uid)
	if cust.is_empty():
		return
	if cust.get("bay_uid", 0) != 0:
		await _bay_clicked(cust["bay_uid"])
		return
	var content := CustomerPopup.create(cust)
	var popup := FlashPopup.open(get_tree(), content, true, false, CustomerPopup.POPUP_SIZE)
	popup_opened.emit("customer", content)
	content.close_pressed.connect(popup.close)
	content.start_pressed.connect(func() -> void:
		popup.close()
		var bay := _free_bay()
		if bay == 0:
			toasts.show_message("All your work bays are busy. Buy another one in Edit Garage!", true)
			Sound.play("ActionDeniedSound")
			return
		var r: GameResult = await Backend.accept_customer(uid, bay)
		if r.ok:
			await Backend.start_job(bay, cust["job_id"]))


## The original CarOptions popup: customize, sell, or send the car out on a job.
func _open_car_options(car_uid: int) -> void:
	var content := CarOptionsPopup.create(car_uid)
	var popup := FlashPopup.open(get_tree(), content, true, false, CarOptionsPopup.POPUP_SIZE)
	popup_opened.emit("car_options", content)
	content.customize_pressed.connect(func() -> void:
		popup.close()
		customize_opened.emit()
		open_screen(CustomizeScreen.create(car_uid)))
	content.sell_pressed.connect(func() -> void:
		_ask_sell_car(car_uid, func() -> void: popup.close()))
	content.start_task.connect(func(job_id: int) -> void:
		var r: GameResult = await Backend.start_car_task(car_uid, job_id)
		if r.ok:
			popup.close())
	content.stop_task.connect(func() -> void:
		popup.close()
		await Backend.stop_car_task(car_uid))


## A car out on a car task: collect it when it's back, else Work in Progress.
func _car_task_clicked(car_uid: int) -> void:
	var task: Dictionary = Backend.state()["car_tasks"].get(str(car_uid), {})
	if task.is_empty():
		return
	if Backend.now() >= task["ends_at"]:
		var at: Variant = garage.callout_position(car_uid)
		_show_collected(at, await Backend.collect_car_task(car_uid))
		return
	var w := WorkPopup.open_car(get_tree(), car_uid)
	if w == null:
		return
	w.stop_pressed.connect(func() -> void:
		w.close()
		await Backend.stop_car_task(car_uid))
	w.finish_pressed.connect(func() -> void:
		var at: Variant = garage.callout_position(car_uid)
		var r: GameResult = await Backend.finish_car_task_now(car_uid)
		if r.ok:
			w.close()
			_show_collected(at, r))


func _open_missions(mission_id: int) -> void:
	var popup := MissionsPopup.open(get_tree(), mission_id)
	popup.viewed.connect(hud.refresh)


## The GPS: pick a place in town, or drive home.
func _open_gps() -> void:
	Backend.open_gps()
	var gps := GpsPopup.create(is_away())
	var popup := FlashPopup.open(get_tree(), gps, true, false, GpsPopup.FRAME_SIZE)
	gps.location_chosen.connect(func(loc_id: int) -> void:
		popup.close()
		var r: GameResult = await Backend.visit_location(loc_id)
		if r.ok:
			show_location(loc_id))
	gps.home_pressed.connect(func() -> void:
		popup.close()
		leave_location()
		go_home())
	gps.buy_cars_pressed.connect(func() -> void:
		popup.close()
		open_screen(BuyCarScreen.new()))


## Drives to a place in town (TownRacingEvent.VISIT_TOWN_LOCATION).
func show_location(loc_id: int) -> void:
	go_home()
	cancel_placement()
	set_edit_mode(false)
	location_view.show_location(loc_id)
	location_view.visible = true
	garage.visible = false
	garage.interactive = false
	hud.set_location(GameData.catalog.locations[loc_id]["name"], false)
	# The original showed town at its 0.4 zoom step, the place's point of
	# interest a little above the middle; the view stays on the scene.
	var area := location_view.bounds()
	var vp := get_viewport().get_visible_rect().size
	var z := maxf(0.4, maxf(vp.x / maxf(1.0, area.size.x), vp.y / maxf(1.0, area.size.y)))
	camera.zoom = Vector2(z, z)
	camera.limit_left = int(area.position.x)
	camera.limit_top = int(area.position.y)
	camera.limit_right = int(area.end.x)
	camera.limit_bottom = int(area.end.y)
	camera.position = location_view.to_global(location_view.focus_point() + Vector2(0, 250))
	RenderingServer.set_default_clear_color(LOCATION_FILL)


## Back to the garage (the GPS's My Garage button).
func leave_location() -> void:
	if not location_view.visible:
		return
	location_view.visible = false
	garage.visible = true
	garage.interactive = true
	hud.set_location("My Garage", true)
	camera.limit_left = -10000000
	camera.limit_top = -10000000
	camera.limit_right = 10000000
	camera.limit_bottom = 10000000
	camera.position = garage.center_screen_position() + Vector2(0, 90)
	camera.zoom = Vector2(1.0, 1.0)
	RenderingServer.set_default_clear_color(GarageView.TOWN_FILL)


func _free_bay() -> int:
	var q := Backend.query()
	for it: Dictionary in Backend.state()["garage"]["items"]:
		if GameData.catalog.item(it["item_id"]).get("category", 0) == GarageGrid.CAT_WORK_BAY 				and q.bay_occupant(it["uid"]).is_empty():
			return it["uid"]
	return 0


func _bay_clicked(bay_uid: int) -> void:
	var job: Dictionary = Backend.state()["jobs"].get(str(bay_uid), {})
	if not job.is_empty() and Backend.now() >= job["ends_at"]:
		var at: Variant = garage.callout_position(bay_uid)
		_show_collected(at, await Backend.collect_job(bay_uid))
		return
	if not job.is_empty():
		_open_work(bay_uid)
		return
	_open_work_bay(bay_uid)


## The work bay menu on an empty lift: pick a job to start.
func _open_work_bay(bay_uid: int) -> void:
	var content := WorkBayPopup.create(bay_uid)
	var popup := FlashPopup.open(get_tree(), content, true, false, WorkBayPopup.POPUP_SIZE)
	popup_opened.emit("work_bay", content)
	content.start_task.connect(func(job_id: int) -> void:
		var r: GameResult = await Backend.start_job(bay_uid, job_id)
		if r.ok:
			popup.close())


## The Work in Progress popup for a busy bay.
func _open_work(bay_uid: int) -> void:
	var w := WorkPopup.open(get_tree(), bay_uid)
	if w == null:
		return
	w.stop_pressed.connect(func() -> void:
		w.close()
		await Backend.stop_job(bay_uid))
	w.finish_pressed.connect(func() -> void:
		var at: Variant = garage.callout_position(bay_uid)
		var r: GameResult = await Backend.finish_job_now(bay_uid)
		if r.ok:
			w.close()
			_show_collected(at, r))


## What a collected job paid, floating up from where its callout was.
func _show_collected(at: Variant, r: GameResult) -> void:
	if r.ok and at != null:
		CollectMoney.spawn(garage.effects_layer(), at, r.data.get("coins", 0), r.data.get("xp", 0))


## A garage item, wall or sign by uid.
func _item_entry(uid: int) -> Dictionary:
	for list: String in ["items", "walls", "wall_items"]:
		for it: Dictionary in Backend.state()["garage"].get(list, []):
			if it["uid"] == uid:
				return it
	return {}


## How an item is placed: "item" (on the floor), "wall", "poster" or "tile".
static func _placement_kind(item_id: int) -> String:
	var def: Dictionary = GameData.catalog.item(item_id)
	if GarageGrid.is_wall(def):
		return "wall"
	if GarageGrid.is_wall_object(def):
		return "poster"
	if def.get("category", 0) == GarageGrid.CAT_FLOOR_TILE:
		return "tile"
	return "item"


# --- Placement and edit mode ---------------------------------------------------------

func place_new_item(item_id: int, use_blue: bool) -> void:
	_start_placement("item", {"item_id": item_id}, 0, "", func(tile: Vector2i, rot: int) -> void:
		var r: GameResult = await Backend.buy_item(item_id, tile.x, tile.y, rot, use_blue)
		if r.ok:
			toasts.show_message("Bought %s!" % GameData.catalog.item(item_id)["name"]))


func place_stored_item(item_id: int) -> void:
	_start_placement(_placement_kind(item_id), {"item_id": item_id}, 0, "", func(tile: Vector2i, rot: int) -> void:
		await Backend.place_stored_item(item_id, tile.x, tile.y, rot))


## Paints floor tiles one click at a time until cancelled: from storage
## while there are any, then bought (FlooringDragManager.onSwatchRelease).
func paint_floor(item_id: int, use_blue: bool) -> void:
	_start_placement("tile", {"item_id": item_id}, 0, "", func(tile: Vector2i, _rot: int) -> void:
		if Backend.state()["storage"].get(str(item_id), 0) > 0:
			await Backend.place_stored_item(item_id, tile.x, tile.y, 0)
		else:
			await Backend.buy_item(item_id, tile.x, tile.y, 0, use_blue))


func move_car(car_uid: int) -> void:
	var car: Dictionary = Backend.query().get_car(car_uid)
	_start_placement("car", car, car.get("rot", 0), "car:%d" % car_uid, func(tile: Vector2i, rot: int) -> void:
		await Backend.move_car(car_uid, tile.x, tile.y, rot))


func move_item(item_uid: int) -> void:
	var entry := _item_entry(item_uid)
	var kind := _placement_kind(entry["item_id"])
	var ignore := ("item:%d" if kind == "item" else "wall:%d") % item_uid
	_start_placement(kind, entry, entry["rot"], ignore, func(tile: Vector2i, rot: int) -> void:
		await Backend.move_item(item_uid, tile.x, tile.y, rot))


func _start_placement(kind: String, entry: Dictionary, rot: int, ignore: String, on_confirm: Callable, hold: bool = false) -> void:
	cancel_placement()
	var placement := Placement.new()
	_placement = placement
	placement.hold_on_confirm = hold
	garage.add_child(placement)
	placement.start(garage, kind, entry, rot, ignore)
	placement.confirmed.connect(func(tile: Vector2i, r: int) -> void:
		# Floor painting keeps going; everything else is placed once.
		if not hold and kind != "tile":
			_placement = null
		_moving = {}
		on_confirm.call(tile, r))
	placement.cancelled.connect(func() -> void:
		if _placement == placement:
			_placement = null
		_moving = {})
	match kind:
		"tile":
			toasts.show_message("Click tiles to paint them  ·  Right-click when you're done")
		"wall", "poster":
			toasts.show_message("Click an edge to place  ·  Right-click to cancel")
		_:
			toasts.show_message("Click to place  ·  R to rotate  ·  Right-click to cancel")


func cancel_placement() -> void:
	if _placement != null and is_instance_valid(_placement):
		_placement.cancel()
	_placement = null


func set_edit_mode(on: bool) -> void:
	if on == edit_mode:
		return
	edit_mode = on
	cancel_placement()
	Sound.music("editLoop" if on else "mainLoop")
	if _edit_tray != null:
		_edit_tray.queue_free()
		_edit_tray = null
	hud.set_screen_mode(on)
	garage.show_grid(on)
	if not on:
		return
	_edit_tray = EditGarageTray.new()
	_ui.add_child(_edit_tray)
	_ui.move_child(_edit_tray, 0)
	_edit_tray.done.connect(func() -> void: set_edit_mode(false))
	_edit_tray.place_requested.connect(_on_edit_place)
	_edit_tray.dropped_on_tray.connect(_on_dropped_on_tray)


func _on_edit_place(kind: String, id: int) -> void:
	match kind:
		"buy":
			var it: Dictionary = GameData.catalog.item(id)
			var blue: bool = not it["can_buy_with_coins"] and it["price"] <= 0
			var place_kind := _placement_kind(id)
			if place_kind == "tile":
				paint_floor(id, blue)
				return
			_start_placement(place_kind, {"item_id": id}, 0, "", func(tile: Vector2i, rot: int) -> void:
				var held := _placement
				_edit_tray.show_buy_confirm(it["name"], it["blue_price"] if blue else it["price"], blue,
					func() -> void:
						_release(held)
						await Backend.buy_item(id, tile.x, tile.y, rot, blue),
					func() -> void: _release(held)), true)
		"stored":
			place_stored_item(id)
		"car":
			move_car(id)


func _release(p: Placement) -> void:
	if p != null and is_instance_valid(p):
		p.release()
	if _placement == p:
		_placement = null


## In edit mode, clicking something picks it up to move it.
func _edit_object(kind: String, uid: int) -> void:
	match kind:
		"item", "wall", "wall_item":
			_moving = {"kind": "item", "uid": uid}
			move_item(uid)
		"car":
			if Backend.state()["car_tasks"].has(str(uid)):
				toasts.show_message("This car is out on a job.", true)
				return
			_moving = {"kind": "car", "uid": uid}
			move_car(uid)


## Edit mode's rotate button: turns the object where it stands, if it fits.
func _rotate_object(kind: String, uid: int) -> void:
	var r: GameResult
	if kind == "item":
		var entry := _item_entry(uid)
		r = await Backend.move_item(uid, entry["x"], entry["y"], (int(entry["rot"]) + 1) % 4)
	else:
		if Backend.state()["car_tasks"].has(str(uid)):
			toasts.show_message("This car is out on a job.", true)
			return
		var car := Backend.query().get_car(uid)
		r = await Backend.move_car(uid, car["x"], car["y"], (int(car.get("rot", 0)) + 1) % 4)
	if not r.ok:
		garage.shake_rotate()


## Something being moved was dropped on the tray: into storage, or onto the
## cash register to sell it.
func _on_dropped_on_tray(sell: bool) -> void:
	if _placement == null or _moving.is_empty():
		return
	var moving := _moving
	cancel_placement()
	if not sell:
		if moving["kind"] == "item":
			await Backend.store_item(moving["uid"])
		else:
			await Backend.store_car(moving["uid"])
		return
	if moving["kind"] == "item":
		var entry := _item_entry(moving["uid"])
		var it: Dictionary = GameData.catalog.item(entry.get("item_id", 0))
		var refund: int = floori(it.get("price", 0) * float(GameData.catalog.tune("economy.item_resell_fraction", 0.5)))
		GenericPopup.ask(get_tree(), "Sell Item", "Sell your %s for %s coins?" % [it.get("name", "item"), Format.number(refund)],
			"Sell", func() -> void: await Backend.sell_item(moving["uid"]))
	else:
		_ask_sell_car(moving["uid"], func() -> void: pass)


## "Sell your car for N coins?"; [param after] runs once it's sold.
func _ask_sell_car(car_uid: int, after: Callable) -> void:
	var car := Backend.query().get_car(car_uid)
	var refund: int = floori(GameData.catalog.car(car["car_id"])["price"] * float(GameData.catalog.tune("economy.resell_fraction", 0.1)))
	GenericPopup.ask(get_tree(), "Sell Car", "Sell your %s for %s coins?" % [GameData.car_name(car["car_id"]), Format.number(refund)],
		"Sell", func() -> void:
			var r: GameResult = await Backend.sell_car(car_uid)
			if r.ok:
				after.call())


# --- Camera ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / 1.1, event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_dragging = event.pressed
			_drag_moved = 0.0
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= event.relative / camera.zoom
		_drag_moved += event.relative.length()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, event.position)
	elif event is InputEventPanGesture:
		camera.position += event.delta * 20.0 / camera.zoom


## Zooms while keeping the world point under the cursor in place.
func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var from_center := screen_point - get_viewport().get_visible_rect().size / 2.0
	var old_zoom := camera.zoom.x
	var z := clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.position += from_center / old_zoom - from_center / z


const ACTION_SOUNDS: Dictionary[String, String] = {
	"collect_job": "MoneyCollectSound01", "finish_job_now": "MoneyCollectSound01",
	"start_job": "NewJobSound", "buy_car": "CarStartSound", "buy_item": "ApprovalSound",
	"install_part": "ApprovalSound", "paint_car": "ApprovalSound", "upgrade_car": "CarRevSound",
	"sell_car": "MoneyCollectSound02", "sell_item": "MoneyCollectSound02", "expand_land": "SuccessSound2",
	"accept_customer": "CarHornSound03",
}


func _on_action_done(action: String, _result: GameResult) -> void:
	# New customers honk when they pull up (GarageView), not on arrival.
	if ACTION_SOUNDS.has(action):
		Sound.play(ACTION_SOUNDS[action])


func _on_notice_sound(n: Dictionary) -> void:
	match n.get("kind", ""):
		"level_up": Sound.play("SuccessSound1")
		"mission_complete": Sound.play("SuccessSound2")
		"mastery": Sound.play("ApprovalSound")


func _on_session_ended(reason: String) -> void:
	if reason != "" and reason != "menu" and reason != "quit":
		# Shown on the title screen after the change.
		Engine.set_meta("title_message", reason)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# --- Visiting (LAN) ---------------------------------------------------------------

## True while in town or in someone else's garage.
func is_away() -> bool:
	return location_view.visible or not garage.visiting.is_empty()


func _on_garage_received(_player_id: String, player_state: Dictionary) -> void:
	if player_state.is_empty():
		toasts.show_message("Couldn't load that garage.", true)
		return
	visit_garage(player_state)


## Looks around a friend's garage (the friend list); the GPS brings you home.
func visit_garage(player_state: Dictionary) -> void:
	cancel_placement()
	set_edit_mode(false)
	leave_location()
	garage.visit(player_state)
	hud.set_location("%s's Garage" % player_state["player"]["name"], false)
	camera.position = garage.center_screen_position() + Vector2(0, 90)


func go_home() -> void:
	if garage.visiting.is_empty():
		return
	garage.go_home()
	hud.set_location("My Garage", true)
	camera.position = garage.center_screen_position() + Vector2(0, 90)


## Testing aid: `-- open=<panel>` opens a panel on start (see DevShot).
func _dev_open() -> void:
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("open="):
			continue
		var s := Backend.state()
		var bay := 0
		for it: Dictionary in s["garage"]["items"]:
			if GameData.catalog.item(it["item_id"]).get("category", 0) == GarageGrid.CAT_WORK_BAY:
				bay = it["uid"]
				break
		match a.trim_prefix("open="):
			"bay": _open_work_bay(bay)
			"credits": MenuPopup.open_credits(get_tree())
			"place_wall", "place_poster", "place_tile":
				# A ghost following a mouse parked over a tile edge.
				set_edit_mode(true)
				var item: int = {"place_wall": 1357, "place_poster": 856, "place_tile": 40}[a.trim_prefix("open=")]
				if a.ends_with("poster"):
					for v in 4:
						await Backend.buy_item(1357, 0, v, GarageGrid.VERTICAL, false)
				_on_edit_place("buy", item)
				await get_tree().process_frame
				var at := Iso.to_screen(0.2, 1.5) if not a.ends_with("tile") else Iso.to_screen(3.5, 3.5)
				get_viewport().warp_mouse(garage.get_global_transform_with_canvas() * at)
			"decor", "decor_edit":
				# Back walls with signs on them, and some painted floor.
				for v in 8:
					await Backend.buy_item(1357, 0, v, GarageGrid.VERTICAL, false)
				for h in 10:
					await Backend.buy_item(1357, h, 0, GarageGrid.HORIZONTAL, false)
				await Backend.buy_item(1572, 0, 3, GarageGrid.VERTICAL, false)
				await Backend.buy_item(856, 0, 0, GarageGrid.VERTICAL, false)
				await Backend.buy_item(1129, 1, 0, GarageGrid.HORIZONTAL, false)
				await Backend.buy_item(857, 6, 0, GarageGrid.HORIZONTAL, false)
				for x in range(1, 9):
					for y in range(7, 10):
						await Backend.buy_item(40, x, y, 0, false)
				if a.ends_with("_edit"):
					set_edit_mode(true)
			"drive_in":
				# Pretend every waiting customer just arrived.
				garage._seen_customers = {}
				garage.rebuild()
			"collect": _bay_clicked(bay)
			"sell": _ask_sell_car(s["cars"][0]["uid"], func() -> void: pass)
			"bay_job":
				# The starter job collected and the car moved off: a new job
				# on the empty lift gets its own car.
				await Backend.collect_job(bay)
				await Backend.take_car_off_bay(s["cars"][0]["uid"])
				await Backend.start_job(bay, 4)
			"job":
				await Backend.put_car_on_bay(s["cars"][0]["uid"], bay)
				await Backend.start_job(bay, 13)
			"buycar":
				var screen := BuyCarScreen.new()
				open_screen(screen)
				screen.show_car(21)
			"buycar_locked":
				var screen := BuyCarScreen.new()
				open_screen(screen)
				screen.show_car(Backend.query().dealer_car_ids()[-1])
			"edit":
				set_edit_mode(true)
			"edit_rotate":
				# Hover the first item so its rotate button shows.
				set_edit_mode(true)
				await get_tree().process_frame
				for it: Dictionary in s["garage"]["items"]:
					var at: Variant = garage.object_anchor("item", it["uid"])
					if at != null:
						garage.set_hover({"kind": "item", "uid": it["uid"]})
						break
			"edit_storage":
				set_edit_mode(true)
				_edit_tray._tray.select(1)
			"customize":
				open_screen(CustomizeScreen.create(s["cars"][0]["uid"]))
			"customize_storage":
				# Some parts in storage: bought wheels and neon, then taken off.
				var uid: int = s["cars"][0]["uid"]
				for pid: int in Backend.query().parts_for_car(s["cars"][0]["car_id"], CustomizeScreen.WHEELS).slice(0, 3):
					await Backend.install_part(uid, pid, false)
				await Backend.remove_part(uid, CustomizeScreen.WHEELS)
				var screen := CustomizeScreen.create(uid)
				open_screen(screen)
				screen.select_tab("storage")
			"levelup":
				notices.push({"kind": "level_up", "level": 5, "coins": 250, "blue": 1})
			"mission_done":
				var mid: int = Backend.query().active_missions(Backend.now())[0]
				var m: Dictionary = GameData.catalog.missions[mid]
				notices.push({"kind": "mission_complete", "mission_id": mid, "title": m["title"],
					"text": m["complete_text"], "coins": m["coins"], "blue": m["blue"], "xp": m["xp"], "reward": {}})
			"mastery":
				notices.push({"kind": "mastery", "job_id": 4, "level": 2, "coins": 100, "blue": 0})
			"gps":
				_open_gps()
			var o when o.begins_with("location_"):
				await Backend.visit_location(int(o.trim_prefix("location_")))
				show_location(int(o.trim_prefix("location_")))
			var o when o.begins_with("customize_"):
				# customize_<tab>[_click]: a tab, optionally clicking its first tile.
				var screen := CustomizeScreen.create(s["cars"][0]["uid"])
				open_screen(screen)
				var bits := o.trim_prefix("customize_").split("_")
				screen.select_tab(bits[0])
				if bits.size() > 1:
					screen.click_first_tile()
			"caroptions":
				_open_car_options(s["cars"][0]["uid"])
			"work":
				await Backend.put_car_on_bay(s["cars"][0]["uid"], bay)
				await Backend.start_job(bay, 13)
				_open_work(bay)
			"customer":
				if not s["customers"].is_empty():
					_open_customer(s["customers"][0]["uid"])
			_: _on_hud_action(a.trim_prefix("open="))
