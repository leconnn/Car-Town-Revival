class_name GarageGrid
extends RefCounted
## Tile occupancy for one garage floor. Built fresh from the save when needed.

const CAT_WORK_BAY := 5
const CAT_FLOOR_TILE := 6
const CAT_WALL := 7
const CAT_DOOR := 10
const CAT_WINDOW := 11
## Categories that are never placed as floor objects.
const NON_FLOOR_CATEGORIES: Array[int] = [CAT_FLOOR_TILE, CAT_WALL, CAT_DOOR, CAT_WINDOW]


## Floor objects block tiles. Wall-mounted items have a zero dimension.
static func is_floor_object(def: Dictionary) -> bool:
	return not NON_FLOOR_CATEGORIES.has(def.get("category", 0)) \
		and def.get("size_x", 0) > 0 and def.get("size_y", 0) > 0

var width: int
var height: int
## "x,y" -> occupant key ("item:<uid>" or "car:<uid>").
var cells: Dictionary[String, String] = {}


func _init(w: int, h: int) -> void:
	width = w
	height = h


## Size of a footprint after rotation (odd rotations swap the axes).
static func rotated_size(size_x: int, size_y: int, rot: int) -> Vector2i:
	return Vector2i(size_y, size_x) if rot % 2 == 1 else Vector2i(size_x, size_y)


static func build(catalog: Catalog, save: Dictionary) -> GarageGrid:
	var land: Dictionary = catalog.land(save["garage"]["land_id"])
	var grid := GarageGrid.new(land.get("size_x", 10), land.get("size_y", 10))
	for it: Dictionary in save["garage"]["items"]:
		var def: Dictionary = catalog.item(it["item_id"])
		if not is_floor_object(def):
			continue
		var size := rotated_size(def["size_x"], def["size_y"], it["rot"])
		grid.occupy(it["x"], it["y"], size, "item:%d" % it["uid"])
	var car_size: Array = catalog.tune("garage.car_size", [4, 3])
	for c: Dictionary in save["cars"]:
		if c.get("placed", false) and c.get("bay_uid", 0) == 0:
			var size := rotated_size(car_size[0], car_size[1], c["rot"])
			grid.occupy(c["x"], c["y"], size, "car:%d" % c["uid"])
	return grid


func occupy(x: int, y: int, size: Vector2i, key: String) -> void:
	for dx in size.x:
		for dy in size.y:
			cells["%d,%d" % [x + dx, y + dy]] = key


func release(key: String) -> void:
	for cell: String in cells.keys():
		if cells[cell] == key:
			cells.erase(cell)


## True if the footprint is inside the land and every tile is free
## (tiles held by [param ignore_key] count as free, for moves).
func can_place(x: int, y: int, size: Vector2i, ignore_key: String = "") -> bool:
	if x < 0 or y < 0 or x + size.x > width or y + size.y > height:
		return false
	for dx in size.x:
		for dy in size.y:
			var owner: String = cells.get("%d,%d" % [x + dx, y + dy], "")
			if owner != "" and owner != ignore_key:
				return false
	return true


## First free spot for the footprint, scanning rows from the back corner.
## Returns (-1, -1) if none.
func find_free(size: Vector2i) -> Vector2i:
	for y in height - size.y + 1:
		for x in width - size.x + 1:
			if can_place(x, y, size):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func occupant(x: int, y: int) -> String:
	return cells.get("%d,%d" % [x, y], "")
