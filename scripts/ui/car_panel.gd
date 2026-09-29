class_name CarPanel
extends GamePanel
## One of the player's cars: customize it, work on it, move, store or sell.

const PART_TABS: Array[Array] = [
	["Wheels", 1], ["Tires", 2], ["Body Kits", 4], ["Wings", 5], ["Hoods", 6],
	["Hood Extras", 11], ["Neon", 10], ["Window Tint", 12],
]

var car_uid: int
var game: Node
var _tab := "Paint"
var _preview: CarPreviewBox
var _content: VBoxContainer
var _preview_parts: Dictionary = {}


func _init(uid: int, game_node: Node) -> void:
	car_uid = uid
	game = game_node


func _car() -> Dictionary:
	return Backend.query().get_car(car_uid)


func _build() -> void:
	var car := _car()
	if car.is_empty():
		close()
		return
	set_title(GameData.car_name(car["car_id"]))
	_preview = CarPreviewBox.new(Vector2(500, 230), 0.55)
	body.add_child(_preview)
	_refresh_preview()
	var status := UiKit.label(_status_text(car), 15, Color(0.85, 0.9, 1))
	body.add_child(status)
	body.add_child(_action_row(car))
	var tabs := HFlowContainer.new()
	for t: String in ["Paint"] + PART_TABS.map(func(a: Array) -> String: return a[0]) + ["Performance", "Ride Height", "Plate"]:
		var b := UiKit.button(t, _set_tab.bind(t), 14)
		b.disabled = t == _tab
		tabs.add_child(b)
	body.add_child(tabs)
	_content = UiKit.vbox(6)
	body.add_child(UiKit.scroll(_content, Vector2(0, 220)))
	_fill_tab(car)


func _status_text(car: Dictionary) -> String:
	var q := Backend.query()
	var where := "Parked in the garage"
	if car["bay_uid"] != 0:
		where = "On a work bay"
	elif not car["placed"]:
		where = "In storage"
	return "%s  ·  Performance %d" % [where, q.car_score(car_uid)]


func _action_row(car: Dictionary) -> Control:
	var row := HFlowContainer.new()
	if car["bay_uid"] == 0:
		row.add_child(UiKit.button("Move", func() -> void: game.move_car(car_uid), 15))
		var bay := _free_bay()
		if bay != 0:
			row.add_child(UiKit.button("Put on work bay", func() -> void:
				var r: GameResult = await Backend.put_car_on_bay(car_uid, bay)
				if r.ok:
					game.open_panel(BayPanel.new(bay, game), true), 15))
		if car["placed"]:
			row.add_child(UiKit.button("Store", func() -> void: await Backend.store_car(car_uid), 15))
	else:
		row.add_child(UiKit.button("Open work bay", func() -> void:
			game.open_panel(BayPanel.new(car["bay_uid"], game), true), 15))
		row.add_child(UiKit.button("Take off work bay", func() -> void: await Backend.take_car_off_bay(car_uid), 15))
	var refund: int = floori(GameData.catalog.car(car["car_id"])["price"] * float(GameData.catalog.tune("economy.resell_fraction", 0.1)))
	row.add_child(UiKit.button("Sell (%s)" % Format.number(refund), func() -> void:
		ConfirmBox.ask(self, "Sell your %s for %s coins?" % [GameData.car_name(car["car_id"]), Format.number(refund)],
			func() -> void:
				var r: GameResult = await Backend.sell_car(car_uid)
				if r.ok:
					toast("Sold for %s coins." % Format.number(r.data["coins"]))
					close()), 15))
	return row


func _free_bay() -> int:
	var q := Backend.query()
	for it: Dictionary in Backend.state()["garage"]["items"]:
		if GameData.catalog.item(it["item_id"]).get("category", 0) == GarageGrid.CAT_WORK_BAY \
				and q.bay_occupant(it["uid"]).is_empty():
			return it["uid"]
	return 0


func _set_tab(t: String) -> void:
	_tab = t
	_preview_parts.clear()
	UiKit.clear(body)
	_build()


func _refresh_preview() -> void:
	var entry := _car().duplicate(true)
	for k: String in _preview_parts:
		entry[k] = _preview_parts[k]
	_preview.show_car(entry)


func _fill_tab(car: Dictionary) -> void:
	match _tab:
		"Paint": _fill_paint(car)
		"Performance": _fill_performance(car)
		"Ride Height": _fill_ride_height(car)
		"Plate": _fill_plate(car)
		_:
			for t: Array in PART_TABS:
				if t[0] == _tab:
					_fill_parts(car, t[1])


func _fill_paint(car: Dictionary) -> void:
	var price: Dictionary = GameData.catalog.part(GameData.catalog.tune("parts.paint_part_id", 0))
	_content.add_child(UiKit.label("New paint costs ● %s or ◆ %d. Click a colour to preview." % [Format.number(price.get("price", 0)), price.get("blue_price", 0)], 15))
	var flow := HFlowContainer.new()
	var current := Backend.query().car_paint(car)
	var chosen: int = _preview_parts.get("paint", current)
	for col: Dictionary in GameData.catalog.colors_for_car(car["car_id"]):
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		var style := StyleBoxFlat.new()
		style.bg_color = Color.html(col["hex"])
		style.set_corner_radius_all(18)
		var rgb: int = str(col["hex"]).hex_to_int()
		style.set_border_width_all(3 if rgb == chosen else 1)
		style.border_color = Color.WHITE if rgb == chosen else Color(0, 0, 0, 0.4)
		for st: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, style)
		b.pressed.connect(func() -> void:
			_preview_parts["paint"] = rgb
			UiKit.clear(body)
			_build())
		flow.add_child(b)
	_content.add_child(flow)
	if chosen != current:
		var row := UiKit.hbox()
		row.add_child(UiKit.button("Paint  ● %s" % Format.number(price.get("price", 0)), _paint.bind(chosen, false)))
		row.add_child(UiKit.button("Paint  ◆ %d" % price.get("blue_price", 0), _paint.bind(chosen, true)))
		_content.add_child(row)


func _paint(rgb: int, use_blue: bool) -> void:
	var r: GameResult = await Backend.paint_car(car_uid, rgb, use_blue)
	if r.ok:
		_preview_parts.clear()
		toast("Fresh paint!")


func _fill_parts(car: Dictionary, category: int) -> void:
	var q := Backend.query()
	var level: int = Backend.state()["player"]["level"]
	var installed: int = car["parts"].get(str(category), 0)
	var ids := q.parts_for_car(car["car_id"], category)
	if ids.is_empty():
		_content.add_child(UiKit.label("No parts of this kind fit this car.", 15))
		return
	for pid: int in ids:
		var p: Dictionary = GameData.catalog.part(pid)
		var row := UiKit.hbox(8)
		var stock := GameData.catalog.stock_part(car["car_id"], category) == pid
		var name := UiKit.label(("%s (stock)" % p["name"]) if stock else p["name"], 15)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true
		row.add_child(name)
		if pid == installed:
			row.add_child(UiKit.label("Installed", 14, Color(0.6, 1, 0.6)))
		else:
			if category != 10 and category != 12:
				row.add_child(UiKit.button("Preview", func() -> void:
					var parts: Dictionary = car["parts"].duplicate()
					parts[str(category)] = pid
					_preview_parts["parts"] = parts
					_refresh_preview(), 13))
			if stock:
				row.add_child(UiKit.button("Install (free)", _install.bind(pid, false), 13))
			elif p["min_level"] > level:
				row.add_child(UiKit.label("Level %d" % p["min_level"], 14, Color(1, 0.6, 0.55)))
			else:
				if p["can_buy_with_coins"] or p["price"] > 0:
					row.add_child(UiKit.button("● %s" % Format.number(p["price"]), _install.bind(pid, false), 13))
				if p["can_buy_with_blue"] and p["blue_price"] > 0:
					row.add_child(UiKit.button("◆ %d" % p["blue_price"], _install.bind(pid, true), 13))
		_content.add_child(row)


func _install(pid: int, use_blue: bool) -> void:
	var r: GameResult = await Backend.install_part(car_uid, pid, use_blue)
	if r.ok:
		_preview_parts.clear()
		toast("Installed %s." % GameData.catalog.part(pid)["name"])


func _fill_performance(car: Dictionary) -> void:
	var q := Backend.query()
	_content.add_child(UiKit.label("Performance upgrades make your car faster in races.", 15))
	for track in 4:
		var stage: int = car["upgrades"][track]
		var row := UiKit.hbox()
		row.add_child(UiKit.label("%s: stage %d of 5" % [["Engine", "Handling", "Aerodynamics", "Weight"][track], stage], 15))
		if stage < 5:
			var price := q.upgrade_stage_price(car["car_id"], stage + 1)
			var label := "● %s" % Format.number(price[0]) if price[0] > 0 else "◆ %d" % price[1]
			row.add_child(UiKit.button("Upgrade  %s" % label, _upgrade.bind(track + 1)))
		_content.add_child(row)


func _upgrade(track: int) -> void:
	var r: GameResult = await Backend.upgrade_car(car_uid, track)
	if r.ok:
		toast("Upgraded to stage %d!" % r.data["stage"])


func _fill_ride_height(car: Dictionary) -> void:
	var price: Dictionary = GameData.catalog.part(GameData.catalog.tune("parts.ride_height_part_id", 0))
	var max_h: int = GameData.catalog.tune("parts.max_ride_height", 4)
	_content.add_child(UiKit.label("Raise or lower your car. Each change costs ● %s." % Format.number(price.get("price", 0)), 15))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = max_h
	slider.step = 1
	slider.value = _preview_parts.get("ride_height", car["ride_height"])
	slider.custom_minimum_size = Vector2(300, 24)
	slider.value_changed.connect(func(v: float) -> void:
		_preview_parts["ride_height"] = int(v)
		_refresh_preview())
	_content.add_child(slider)
	_content.add_child(UiKit.button("Apply", func() -> void:
		var h: int = _preview_parts.get("ride_height", car["ride_height"])
		var r: GameResult = await Backend.set_ride_height(car_uid, h, false)
		if r.ok:
			_preview_parts.clear()
			toast("Ride height set.")))


func _fill_plate(car: Dictionary) -> void:
	var price: Dictionary = GameData.catalog.part(GameData.catalog.tune("parts.vanity_plate_part_id", 0))
	var max_len: int = GameData.catalog.tune("parts.plate_max_length", 7)
	_content.add_child(UiKit.label("Current plate: %s" % (car["plate"] if car["plate"] != "" else "(none)"), 16))
	var edit := LineEdit.new()
	edit.max_length = max_len
	edit.placeholder_text = "Up to %d letters or numbers" % max_len
	edit.custom_minimum_size = Vector2(260, 0)
	_content.add_child(edit)
	_content.add_child(UiKit.button("Buy plate  ● %s" % Format.number(price.get("price", 0)), func() -> void:
		var r: GameResult = await Backend.set_plate(car_uid, edit.text, false)
		if r.ok:
			toast("New plate: %s" % edit.text.to_upper())))
