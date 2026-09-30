class_name LocationView
extends Node2D
## A place in town (views/townracing/location/*TownLocation): the lot and
## building ("bg"), cars parked in the lot's marked spots, and whatever
## stands in front of them ("fg"). Cars fill the spots closest to the place's
## point of interest first (ParkCloseToPOISolver). The Drive-In is at night:
## the lot is shaded and only its movie screen is lit.

## Per location: environment, point of interest, parked car count, and the
## marker rows with how many spots each holds (from each *TownLocation).
const PLACES: Dictionary[int, Dictionary] = {
	9: {"env": "environment_diner", "poi": Vector2(2050, 550), "cars": 20, "rows": [
		["row1", 3], ["row2", 3], ["row3", 3], ["row4", 3], ["row5", 3], ["row7", 3],
		["row8", 3], ["row9", 3], ["row10", 3], ["row11", 11]]},
	7: {"env": "environment_coffee_place", "poi": Vector2(1700, 925), "cars": 20, "rows": [
		["row1", 5], ["row2", 9], ["row3", 5], ["row4", 5], ["row5", 5], ["row6", 5], ["row7", 3]]},
	6: {"env": "environment_pizza_place", "poi": Vector2(1963, 536), "cars": 20, "rows": [
		["rowA", 5], ["rowB", 2], ["rowC", 3], ["rowD", 4], ["rowE", 6], ["rowF", 6], ["rowG", 9]]},
	8: {"env": "environment_drive_in_v3", "poi": Vector2(2263, 825), "cars": 14, "night": true, "rows": [
		["rowA", 4], ["rowB", 4], ["rowC", 4], ["rowD", 4]]},
}
## ParkingSpotHelper.parkingSpotOffsets: from the marker line to the car, by rotation.
const SPOT_OFFSETS: Array[Vector2] = [Vector2(-35, -15), Vector2(35, -19), Vector2(36, 3), Vector2(-35, 13)]
const NIGHT_SHADE := Color(0, 0, 0, 0.4)

## Clicked one of the cars waiting to race (the nearest spots to the place's
## point of interest hold the opponents).
signal opponent_clicked(opponent: Dictionary)

var location_id := 0
var _bg: Sprite2D
## The racing cars: {"opponent", "view"}.
var _opponents: Array[Dictionary] = []
var _press := Vector2(-1, -1)
var _hover := -1


static func has_scene(loc_id: int) -> bool:
	return PLACES.has(loc_id)


func show_location(loc_id: int) -> void:
	for c in get_children():
		c.queue_free()
	_opponents.clear()
	_hover = -1
	location_id = loc_id
	var place: Dictionary = PLACES.get(loc_id, {})
	var env: Dictionary = GameData.town_art.get(place.get("env", ""), {})
	if env.is_empty():
		return
	_bg = _layer(env.get("bg", {}))
	if _bg == null:
		return
	add_child(_bg)
	if place.get("night", false):
		var shade := Polygon2D.new()
		var size: Vector2 = _bg.texture.get_size()
		shade.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
		shade.color = NIGHT_SHADE
		add_child(shade)
		var movie := _layer(env.get("movie", {}))
		if movie != null:
			add_child(movie)
	_park_cars(place, env.get("markers", {}))
	var fg := _layer(env.get("fg", {}))
	if fg != null:
		add_child(fg)


## The scene's extent in this view's coordinates (for camera limits).
func bounds() -> Rect2:
	if _bg == null or _bg.texture == null:
		return Rect2()
	return Rect2(_bg.position, _bg.texture.get_size())


## The point the camera looks at when you arrive.
func focus_point() -> Vector2:
	return PLACES.get(location_id, {}).get("poi", Vector2.ZERO)


static func _layer(info: Dictionary) -> Sprite2D:
	var tex := GameData.texture(info.get("file", ""))
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	var o: Array = info.get("o", [0, 0])
	var pos: Array = info.get("pos", [0, 0])
	s.position = Vector2(pos[0], pos[1]) - Vector2(o[0], o[1])
	return s


## ParkingSpotHelper + ParkCloseToPOISolver: spots evenly along each row,
## the ones nearest the point of interest taken first.
func _park_cars(place: Dictionary, markers: Dictionary) -> void:
	var spots: Array[Dictionary] = []
	for row: Array in place["rows"]:
		var a: Array = markers.get(row[0] + "Start", [])
		var b: Array = markers.get(row[0] + "End", [])
		if a.is_empty() or b.is_empty():
			continue
		var n: int = row[1]
		var start := Vector2(a[0], a[1])
		var step := (Vector2(b[0], b[1]) - start) / maxf(1.0, n - 1)
		var rot: int = a[2]
		for i in n:
			spots.append({"pos": start + step * i + SPOT_OFFSETS[rot], "rot": rot})
	var poi: Vector2 = place["poi"]
	spots.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x["pos"].distance_squared_to(poi) < y["pos"].distance_squared_to(poi))
	var ids := Backend.query().dealer_car_ids()
	if ids.is_empty():
		return
	# The same cars for an hour at a time, different at each place.
	var state := location_id * 7919 + Backend.now() / 3600
	var racers: Array[Dictionary] = []
	if Backend.query().race_locations().has(location_id):
		racers = Backend.query().race_opponents(location_id, Backend.now())
	var parked: Array[Dictionary] = []
	for i in mini(place["cars"], spots.size()):
		state = SimpleRng.next(state)
		var car_id: int = ids[(state >> 8) % ids.size()]
		var colors := GameData.catalog.colors_for_car(car_id)
		var color_id: int = colors[(state >> 12) % colors.size()]["id"] if not colors.is_empty() else 0
		if i < racers.size():
			car_id = racers[i]["car_id"]
			color_id = racers[i]["color_id"]
		parked.append({"spot": spots[i], "car": CarView.stock_entry(car_id, color_id),
			"opponent": racers[i] if i < racers.size() else {}})
	# Back to front, so nearer cars draw over farther ones.
	parked.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["spot"]["pos"].y < y["spot"]["pos"].y)
	for p: Dictionary in parked:
		var view := CarView.new()
		var vm := CarView.iso_view_for_rotation(p["spot"]["rot"])
		view.setup(p["car"], vm[0], vm[1])
		view.position = p["spot"]["pos"]
		add_child(view)
		if not p["opponent"].is_empty():
			_opponents.append({"opponent": p["opponent"], "view": view})


# --- Clicking the racing cars ------------------------------------------------------------

func _opponent_at(global_point: Vector2) -> int:
	# Nearer cars are drawn later, so look from the front.
	for i in range(_opponents.size() - 1, -1, -1):
		if _node_hit(_opponents[i]["view"], global_point):
			return i
	return -1


static func _node_hit(node: Node, global_point: Vector2) -> bool:
	if node is Sprite2D:
		var sp := node as Sprite2D
		return sp.texture != null and sp.is_pixel_opaque(sp.to_local(global_point))
	for child in node.get_children():
		if _node_hit(child, global_point):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _opponents.is_empty():
		return
	if event is InputEventMouseMotion:
		var i := _opponent_at(get_global_mouse_position())
		if i != _hover:
			if _hover >= 0 and _hover < _opponents.size():
				(_opponents[_hover]["view"] as CarView).set_highlight(Color(0, 0, 0, 0))
			_hover = i
			if i >= 0:
				(_opponents[i]["view"] as CarView).set_highlight(Color(1, 1, 0.6, 0.25))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press = event.position
		elif _press.x >= 0 and event.position.distance_to(_press) < 6.0:
			var i := _opponent_at(get_global_mouse_position())
			_press = Vector2(-1, -1)
			if i >= 0:
				get_viewport().set_input_as_handled()
				opponent_clicked.emit(_opponents[i]["opponent"])
