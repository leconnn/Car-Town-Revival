extends Node2D
## The main game screen: garage, camera, HUD and all panels. Knows nothing
## about the game mode; everything goes through Backend.

const ZOOM_MIN := 0.35
const ZOOM_MAX := 1.6

var garage: GarageView
var camera: Camera2D
var hud: ShellHud
var toasts: Toasts
var notices: NoticePopup
var edit_mode := false

var _ui: CanvasLayer
var _panel_host: Control
var _panel: GamePanel
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
	_panel_host = Control.new()
	UiKit.place(_panel_host, Rect2(0, 0, 1, 1))
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_panel_host)
	toasts = Toasts.new()
	_ui.add_child(toasts)
	notices = NoticePopup.new()
	_ui.add_child(notices)
	Backend.notice.connect(notices.push)
	Backend.action_failed.connect(func(msg: String) -> void: toasts.show_message(msg, true))
	Backend.session_ended.connect(_on_session_ended)
	Backend.action_done.connect(_on_action_done)
	Backend.notice.connect(_on_notice_sound)
	Backend.action_failed.connect(func(_m: String) -> void: Sound.play("ActionDeniedSound"))
	Sound.music("mainLoop")
	Tutorial.attach(self)
	_dev_open.call_deferred()
	DevShot.maybe_capture(self)


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
	_ui.move_child(tut, _panel_host.get_index())


## Glides the camera to [param world_pos] (the tutorial's ScrollMapProcess).
func focus_camera(world_pos: Vector2, zoom: float = -1.0, seconds: float = 1.0) -> void:
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(camera, "position", world_pos, seconds)
	if zoom > 0:
		tw.tween_property(camera, "zoom", Vector2(zoom, zoom), seconds)
	await tw.finished


# --- Panels ----------------------------------------------------------------------

func open_panel(panel: GamePanel, side: bool = false) -> void:
	close_panel()
	_panel = panel
	if side:
		UiKit.place(panel, Rect2(1, 0, 1, 1), Rect2(-580, 80, -12, -84))
	else:
		UiKit.place(panel, Rect2(0, 0, 1, 1), Rect2(110, 80, -110, -84))
	_panel_host.add_child(panel)
	panel.closed.connect(func() -> void:
		if _panel == panel:
			_panel = null)


## Full-screen views like Buy Cars: drawn under the HUD, which shrinks to the
## gauge and balance while one is open.
var _screen: Node


func open_screen(screen: Node) -> void:
	close_panel()
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


func close_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


func _on_hud_action(name: String) -> void:
	if tutorial_filter.is_valid() and not TUTORIAL_FREE_ACTIONS.has(name):
		Sound.play("ActionDeniedSound")
		return
	cancel_placement()
	match name:
		"dealer": open_screen(BuyCarScreen.new())
		"shop": set_edit_mode(true)
		"edit": set_edit_mode(not edit_mode)
		"cars": open_panel(CarsPanel.new(self), true)
		"town": open_panel(TownPanel.new())
		"missions": open_panel(MissionsPanel.new(), true)
		"menu": open_panel(MenuPanel.new())
		"players": open_panel(PlayersPanel.new(self), true)
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
		var car := Backend.query().get_car(car_uid)
		var refund: int = floori(GameData.catalog.car(car["car_id"])["price"] * float(GameData.catalog.tune("economy.resell_fraction", 0.1)))
		ConfirmBox.ask(self, "Sell your %s for %s coins?" % [GameData.car_name(car["car_id"]), Format.number(refund)],
			func() -> void:
				var r: GameResult = await Backend.sell_car(car_uid)
				if r.ok:
					popup.close()
					toasts.show_message("Sold for %s coins." % Format.number(r.data["coins"]))))
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
		var r: GameResult = await Backend.collect_car_task(car_uid)
		if r.ok:
			toasts.show_message("+%s coins  +%d XP" % [Format.number(r.data["coins"]), r.data["xp"]])
		return
	var w := WorkPopup.open_car(get_tree(), car_uid)
	if w == null:
		return
	w.stop_pressed.connect(func() -> void:
		w.close()
		await Backend.stop_car_task(car_uid))
	w.finish_pressed.connect(func() -> void:
		var r: GameResult = await Backend.finish_car_task_now(car_uid)
		if not r.ok:
			toasts.show_message(r.error, true)
			Sound.play("ActionDeniedSound")
			return
		w.close()
		toasts.show_message("+%s coins  +%d XP" % [Format.number(r.data["coins"]), r.data["xp"]]))


func _free_bay() -> int:
	var q := Backend.query()
	for it: Dictionary in Backend.state()["garage"]["items"]:
		if GameData.catalog.item(it["item_id"]).get("category", 0) == GarageGrid.CAT_WORK_BAY 				and q.bay_occupant(it["uid"]).is_empty():
			return it["uid"]
	return 0


func _bay_clicked(bay_uid: int) -> void:
	var job: Dictionary = Backend.state()["jobs"].get(str(bay_uid), {})
	if not job.is_empty() and Backend.now() >= job["ends_at"]:
		var r: GameResult = await Backend.collect_job(bay_uid)
		if r.ok:
			toasts.show_message("+%s coins  +%d XP" % [Format.number(r.data["coins"]), r.data["xp"]])
		return
	if not job.is_empty():
		_open_work(bay_uid)
		return
	open_panel(BayPanel.new(bay_uid, self), true)


## The Work in Progress popup for a busy bay.
func _open_work(bay_uid: int) -> void:
	var w := WorkPopup.open(get_tree(), bay_uid)
	if w == null:
		return
	w.stop_pressed.connect(func() -> void:
		w.close()
		await Backend.stop_job(bay_uid))
	w.finish_pressed.connect(func() -> void:
		var r: GameResult = await Backend.finish_job_now(bay_uid)
		if not r.ok:
			toasts.show_message(r.error, true)
			Sound.play("ActionDeniedSound")
			return
		w.close()
		toasts.show_message("+%s coins  +%d XP" % [Format.number(r.data["coins"]), r.data["xp"]]))


func _item_entry(uid: int) -> Dictionary:
	for it: Dictionary in Backend.state()["garage"]["items"]:
		if it["uid"] == uid:
			return it
	return {}


# --- Placement and edit mode ---------------------------------------------------------

func place_new_item(item_id: int, use_blue: bool) -> void:
	_start_placement("item", {"item_id": item_id}, 0, "", func(tile: Vector2i, rot: int) -> void:
		var r: GameResult = await Backend.buy_item(item_id, tile.x, tile.y, rot, use_blue)
		if r.ok:
			toasts.show_message("Bought %s!" % GameData.catalog.item(item_id)["name"]))


func place_stored_item(item_id: int) -> void:
	_start_placement("item", {"item_id": item_id}, 0, "", func(tile: Vector2i, rot: int) -> void:
		await Backend.place_stored_item(item_id, tile.x, tile.y, rot))


func move_car(car_uid: int) -> void:
	var car: Dictionary = Backend.query().get_car(car_uid)
	_start_placement("car", car, car.get("rot", 0), "car:%d" % car_uid, func(tile: Vector2i, rot: int) -> void:
		await Backend.move_car(car_uid, tile.x, tile.y, rot))


func move_item(item_uid: int) -> void:
	var entry := _item_entry(item_uid)
	_start_placement("item", entry, entry["rot"], "item:%d" % item_uid, func(tile: Vector2i, rot: int) -> void:
		await Backend.move_item(item_uid, tile.x, tile.y, rot))


func _start_placement(kind: String, entry: Dictionary, rot: int, ignore: String, on_confirm: Callable, hold: bool = false) -> void:
	cancel_placement()
	close_panel()
	var placement := Placement.new()
	_placement = placement
	placement.hold_on_confirm = hold
	garage.add_child(placement)
	placement.start(garage, kind, entry, rot, ignore)
	placement.confirmed.connect(func(tile: Vector2i, r: int) -> void:
		if not hold:
			_placement = null
		_moving = {}
		on_confirm.call(tile, r))
	placement.cancelled.connect(func() -> void:
		if _placement == placement:
			_placement = null
		_moving = {})
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
	close_panel()
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
			_start_placement("item", {"item_id": id}, 0, "", func(tile: Vector2i, rot: int) -> void:
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
		"item":
			_moving = {"kind": "item", "uid": uid}
			move_item(uid)
		"car":
			if Backend.state()["car_tasks"].has(str(uid)):
				toasts.show_message("This car is out on a job.", true)
				return
			_moving = {"kind": "car", "uid": uid}
			move_car(uid)


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
		ConfirmBox.ask(self, "Sell your %s?" % it.get("name", "item"), func() -> void:
			await Backend.sell_item(moving["uid"]))
	else:
		var car := Backend.query().get_car(moving["uid"])
		ConfirmBox.ask(self, "Sell your %s?" % GameData.car_name(car.get("car_id", 0)), func() -> void:
			await Backend.sell_car(moving["uid"]))


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


func _on_action_done(action: String, result: GameResult) -> void:
	if action == "tick" and result.data.get("arrived", 0) > 0:
		Sound.play("CarHornSound03")
	elif ACTION_SOUNDS.has(action):
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

var _visit_bar: Control


func visit_garage(player_state: Dictionary) -> void:
	close_panel()
	garage.visit(player_state)
	hud.visible = false
	if _visit_bar != null:
		_visit_bar.queue_free()
	var panel := PanelContainer.new()
	UiKit.place(panel, Rect2(0.5, 0, 0.5, 0), Rect2(0, 12, 0, 12))
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var row := UiKit.hbox(14)
	row.add_child(UiKit.label("Visiting %s's garage (level %d)" % [player_state["player"]["name"], player_state["player"]["level"]], 20))
	row.add_child(UiKit.button("Back to my garage", go_home))
	panel.add_child(row)
	_ui.add_child(panel)
	_visit_bar = panel


func go_home() -> void:
	garage.go_home()
	hud.visible = true
	if _visit_bar != null:
		_visit_bar.queue_free()
		_visit_bar = null


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
			"car": open_panel(CarPanel.new(s["cars"][0]["uid"], self), true)
			"bay": open_panel(BayPanel.new(bay, self), true)
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
			"edit_storage":
				set_edit_mode(true)
				_edit_tray._tray.select(1)
			"customize":
				open_screen(CustomizeScreen.create(s["cars"][0]["uid"]))
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
