extends Node2D
## Developer preview: one car in all garage rotations plus the showroom view.
## Run with:  godot --path . res://scenes/dev/car_preview.tscn -- car=1 shot=user://car.png
## Keys: Left/Right change car, C changes colour, W changes wheels.

var _car_ids: Array[int] = []
var _index := 0
var _color_index := 0
var _wheel_index := 0
var _label: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.55, 0.62, 0.68))
	for key: String in GameData.car_art:
		_car_ids.append(int(key))
	_car_ids.sort()
	var args := _args()
	if args.has("car"):
		_index = maxi(0, _car_ids.find(int(args["car"])))
	_label = Label.new()
	_label.position = Vector2(20, 20)
	add_child(_label)
	_show()
	if args.has("shot"):
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(args["shot"])
		get_tree().quit()


func _args() -> Dictionary:
	var out := {}
	for a: String in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_RIGHT: _index = (_index + 1) % _car_ids.size()
			KEY_LEFT: _index = posmod(_index - 1, _car_ids.size())
			KEY_C: _color_index += 1
			KEY_W: _wheel_index += 1
			_: return
		_show()


func _show() -> void:
	for c in get_children():
		if c is CarView or c is Line2D:
			c.queue_free()
	if _car_ids.is_empty():
		_label.text = "No car art exported yet."
		return
	var car_id := _car_ids[_index]
	var colors := GameData.catalog.colors_for_car(car_id)
	var entry := {"car_id": car_id, "color_id": colors[_color_index % colors.size()]["id"] if not colors.is_empty() else 0,
		"parts": {}, "ride_height": 0}
	var defaults: Dictionary = GameData.catalog.car(car_id).get("defaults", {})
	for key: String in defaults:
		var p: Dictionary = GameData.catalog.part(defaults[key])
		if not p.is_empty():
			entry["parts"][str(p["category_id"])] = p["id"]
	var logic := GameLogic.new(GameData.catalog, {"player": {"level": 999}, "cars": [], "garage": {"items": []}})
	var wheels := logic.parts_for_car(car_id, 1)
	if _wheel_index > 0 and not wheels.is_empty():
		entry["parts"]["1"] = wheels[_wheel_index % wheels.size()]
	_label.text = "%s  (id %d)   [<-/-> car, C colour, W wheels]" % [GameData.car_name(car_id), car_id]
	for rot in 4:
		var origin := Vector2(200 + rot * 300, 320)
		_add_tile_marker(origin)
		var v := CarView.new()
		var vm := CarView.iso_view_for_rotation(rot)
		v.setup(entry, vm[0], vm[1])
		v.position = origin
		add_child(v)
	var big := CarView.new()
	big.setup(entry, CarView.VIEW_ANGLE, false)
	big.position = Vector2(700, 860)
	add_child(big)


func _add_tile_marker(origin: Vector2) -> void:
	var line := Line2D.new()
	line.width = 1
	line.default_color = Color(1, 1, 0, 0.8)
	for p: Vector2 in Iso.area_polygon(0, 0, 4, 3):
		line.add_point(origin + p)
	line.add_point(origin)
	add_child(line)
