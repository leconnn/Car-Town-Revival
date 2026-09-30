class_name Placement
extends Node2D
## Placing or moving something in the garage: a see-through ghost and a
## footprint that follow the mouse. R rotates, left click confirms,
## right click or Esc cancels. With [member hold_on_confirm] the ghost stays
## where it was dropped (e.g. while a buy box asks) until [method release].
##
## Kinds: "item" and "car" sit on tiles; "wall" snaps to the tile edge
## nearest the mouse (WallDragManager); "poster" hangs on the walls there
## (WallObjDragManager); "tile" paints one floor tile and keeps going, like
## dragging the flooring swatch again and again (FlooringDragManager).

signal confirmed(tile: Vector2i, rot: int)
signal cancelled

const OK_COLOR := Color(0.2, 0.9, 0.3, 0.35)
const BAD_COLOR := Color(0.95, 0.2, 0.2, 0.35)
## Half the thickness of the green/red strip under a wall being placed.
const EDGE_HALF := 5.0

var garage: GarageView
var size_x := 1
var size_y := 1
var rot := 0
## Key of the object being moved (its own tiles count as free).
var ignore_key := ""
## Uid of the wall or sign being moved.
var ignore_uid := 0
var _ghost: Node2D
var _footprint: Polygon2D
var _kind := ""
var _entry: Dictionary = {}
var _tile := Vector2i(-100, -100)
var hold_on_confirm := false
var _held := false


## [param kind] is "item", "car", "wall", "poster" or "tile"; [param entry]
## holds an item id or a car entry.
func start(view: GarageView, kind: String, entry: Dictionary, start_rot: int, ignore: String) -> void:
	garage = view
	_kind = kind
	_entry = entry
	rot = start_rot
	ignore_key = ignore
	if ignore.contains(":"):
		ignore_uid = int(ignore.get_slice(":", 1))
	if kind == "car":
		var car_size: Array = GameData.catalog.tune("garage.car_size", [4, 3])
		size_x = car_size[0]
		size_y = car_size[1]
	else:
		var def: Dictionary = GameData.catalog.item(entry["item_id"])
		size_x = def["size_x"]
		size_y = def["size_y"]
	_footprint = Polygon2D.new()
	add_child(_footprint)
	_rebuild_ghost()
	garage.interactive = false


func _rebuild_ghost() -> void:
	if _kind in ["wall", "poster", "tile"]:
		# Drawn in place at their spot: made in _update.
		_update(true)
		return
	if _ghost != null:
		_ghost.queue_free()
	match _kind:
		"item":
			var iv := ItemView.new()
			iv.setup(_entry["item_id"], rot)
			_ghost = iv
		"car":
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
	var def: Dictionary = GameData.catalog.item(_entry.get("item_id", 0))
	var horizontal := rot == GarageGrid.HORIZONTAL
	match _kind:
		"wall":
			return grid.can_place_wall(tile.x, tile.y, GarageGrid.wall_length(def), horizontal, ignore_uid)
		"poster":
			return grid.can_place_poster(tile.x, tile.y, GarageGrid.wall_object_length(def), horizontal, ignore_uid)
		"tile":
			return tile.x >= 0 and tile.y >= 0 and tile.x < grid.width and tile.y < grid.height
	return grid.can_place(tile.x, tile.y, _size(), ignore_key)


func _process(_delta: float) -> void:
	if not _held:
		_update(false)


func _update(force: bool) -> void:
	if garage == null:
		return
	var tile: Vector2i
	var new_rot := rot
	if _kind in ["wall", "poster"]:
		# The edge nearest the mouse: the tile's h side or its v side.
		var g := Iso.to_grid(garage.get_local_mouse_position())
		tile = Vector2i(floori(g.x), floori(g.y))
		new_rot = GarageGrid.VERTICAL if g.x - tile.x < g.y - tile.y else GarageGrid.HORIZONTAL
	elif _kind == "tile":
		tile = garage.tile_under_mouse()
	else:
		var size := _size()
		# Hold the object by its middle.
		tile = garage.tile_under_mouse() - Vector2i(size.x / 2, size.y / 2)
	if tile == _tile and new_rot == rot and not force:
		return
	_tile = tile
	rot = new_rot
	if _kind in ["wall", "poster", "tile"]:
		# These ghosts are drawn at their spot; make them again there.
		if _ghost != null:
			_ghost.queue_free()
		_rebuild_ghost_at_tile()
		_footprint.polygon = _edge_polygon(tile) if _kind != "tile" else Iso.area_polygon(tile.x, tile.y, 1, 1)
	else:
		var size := _size()
		_ghost.position = GarageView.object_position(tile.x, tile.y)
		_footprint.polygon = Iso.area_polygon(tile.x, tile.y, size.x, size.y)
	_footprint.color = OK_COLOR if _can_place(tile) else BAD_COLOR


func _rebuild_ghost_at_tile() -> void:
	match _kind:
		"wall":
			_ghost = WallArt.wall_node(_entry["item_id"], _tile.x, _tile.y, rot)
		"poster":
			_ghost = WallArt.poster_node(_entry["item_id"], _tile.x, _tile.y, rot)
		_:
			_ghost = WallArt.tile_node(_entry["item_id"], _tile.x, _tile.y)
	_ghost.modulate = Color(1, 1, 1, 0.75)
	add_child(_ghost)


## A strip along the edge(s) a wall or sign would cover.
func _edge_polygon(tile: Vector2i) -> PackedVector2Array:
	var def: Dictionary = GameData.catalog.item(_entry["item_id"])
	var length := GarageGrid.wall_length(def) if _kind == "wall" else GarageGrid.wall_object_length(def)
	var horizontal := rot == GarageGrid.HORIZONTAL
	var a := Iso.to_screen(tile.x, tile.y)
	var b := Iso.to_screen(tile.x + (length if horizontal else 0), tile.y + (0 if horizontal else length))
	var up := Vector2(0, -EDGE_HALF)
	return PackedVector2Array([a + up, b + up, b - up, a - up])


func _unhandled_input(event: InputEvent) -> void:
	if _held:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R and _kind in ["item", "car"]:
		rot = (rot + 1) % 4
		_rebuild_ghost()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if _can_place(_tile):
				if _kind == "tile":
					# Keep painting until right click or Esc.
					confirmed.emit(_tile, rot)
					return
				if hold_on_confirm:
					_held = true
				else:
					_finish()
				confirmed.emit(_tile, rot)
			else:
				Sound.play("ActionDeniedSound")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			cancel()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()


func rotate_once() -> void:
	rot = (rot + 1) % 4
	_rebuild_ghost()


## Removes a held ghost.
func release() -> void:
	_finish()


func cancel() -> void:
	_finish()
	cancelled.emit()


func _finish() -> void:
	garage.interactive = true
	queue_free()
