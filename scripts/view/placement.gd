class_name Placement
extends Node2D
## Placing or moving something in the garage: a see-through ghost and a
## footprint that follow the mouse. R rotates, left click confirms,
## right click or Esc cancels.

signal confirmed(tile: Vector2i, rot: int)
signal cancelled

var garage: GarageView
var size_x := 1
var size_y := 1
var rot := 0
## Key of the object being moved (its own tiles count as free).
var ignore_key := ""
var _ghost: Node2D
var _footprint: Polygon2D
var _kind := ""
var _entry: Dictionary = {}
var _tile := Vector2i(-100, -100)


## [param kind] is "item" or "car"; [param entry] an item id or car entry.
func start(view: GarageView, kind: String, entry: Dictionary, start_rot: int, ignore: String) -> void:
	garage = view
	_kind = kind
	_entry = entry
	rot = start_rot
	ignore_key = ignore
	if kind == "item":
		var def: Dictionary = GameData.catalog.item(entry["item_id"])
		size_x = def["size_x"]
		size_y = def["size_y"]
	else:
		var car_size: Array = GameData.catalog.tune("garage.car_size", [4, 3])
		size_x = car_size[0]
		size_y = car_size[1]
	_footprint = Polygon2D.new()
	add_child(_footprint)
	_rebuild_ghost()
	garage.interactive = false


func _rebuild_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
	if _kind == "item":
		var iv := ItemView.new()
		iv.setup(_entry["item_id"], rot)
		_ghost = iv
	else:
		var cv := CarView.new()
		var vm := CarView.iso_view_for_rotation(rot)
		cv.setup(_entry, vm[0], vm[1])
		_ghost = cv
	_ghost.modulate = Color(1, 1, 1, 0.75)
	add_child(_ghost)
	_update(true)


func _size() -> Vector2i:
	return GarageGrid.rotated_size(size_x, size_y, rot)


func _can_place(tile: Vector2i) -> bool:
	var grid := GarageGrid.build(GameData.catalog, Backend.state())
	return grid.can_place(tile.x, tile.y, _size(), ignore_key)


func _process(_delta: float) -> void:
	_update(false)


func _update(force: bool) -> void:
	if garage == null:
		return
	var size := _size()
	var mouse_tile := garage.tile_under_mouse()
	# Hold the object by its middle.
	var tile := mouse_tile - Vector2i(size.x / 2, size.y / 2)
	if tile == _tile and not force:
		return
	_tile = tile
	_ghost.position = GarageView.object_position(tile.x, tile.y)
	_footprint.polygon = Iso.area_polygon(tile.x, tile.y, size.x, size.y)
	_footprint.color = Color(0.2, 0.9, 0.3, 0.35) if _can_place(tile) else Color(0.95, 0.2, 0.2, 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		rot = (rot + 1) % 4
		_rebuild_ghost()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if _can_place(_tile):
				_finish()
				confirmed.emit(_tile, rot)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			cancel()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()


func rotate_once() -> void:
	rot = (rot + 1) % 4
	_rebuild_ghost()


func cancel() -> void:
	_finish()
	cancelled.emit()


func _finish() -> void:
	garage.interactive = true
	queue_free()
