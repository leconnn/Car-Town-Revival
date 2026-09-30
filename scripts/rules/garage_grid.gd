class_name GarageGrid
extends RefCounted
## Tile occupancy for one garage floor, with the walls along tile edges and
## the posters on them (CarTownGrid). Built fresh from the save when needed.

const CAT_WORK_BAY := 5
const CAT_FLOOR_TILE := 6
const CAT_WALL := 7
const CAT_WALL_ART := 8
const CAT_DOOR := 10
const CAT_WINDOW := 11
const CAT_SIGNAGE := 13
## Categories that are never placed as floor objects.
const NON_FLOOR_CATEGORIES: Array[int] = [CAT_FLOOR_TILE, CAT_WALL, CAT_WALL_ART, CAT_DOOR, CAT_WINDOW, CAT_SIGNAGE]
## Things that hang on walls (WallObj): signs, posters, wall art.
const WALL_OBJECT_CATEGORIES: Array[int] = [CAT_WALL_ART, CAT_SIGNAGE]
## Wall rotations (StageWall): a vertical wall runs along v on the line
## h = x; a horizontal one runs along h on the line v = y.
const VERTICAL := 0
const HORIZONTAL := 1


## Floor objects block tiles. Wall-mounted items have a zero dimension.
static func is_floor_object(def: Dictionary) -> bool:
	return not NON_FLOOR_CATEGORIES.has(def.get("category", 0)) \
		and def.get("size_x", 0) > 0 and def.get("size_y", 0) > 0


static func is_wall(def: Dictionary) -> bool:
	return def.get("category", 0) == CAT_WALL


static func is_wall_object(def: Dictionary) -> bool:
	return WALL_OBJECT_CATEGORIES.has(def.get("category", 0))


## How many tile edges a wall covers (StageWall: yDim, at least 1).
static func wall_length(def: Dictionary) -> int:
	return maxi(1, def.get("size_y", 0))


## How many wall segments a poster covers (WallObj: xDim, at least 1).
static func wall_object_length(def: Dictionary) -> int:
	return maxi(1, def.get("size_x", 0))


## Half-height walls (the catalog's p1) can't hold posters.
static func is_half_wall(def: Dictionary) -> bool:
	return def.get("half_wall", false)

var width: int
var height: int
## "x,y" -> occupant key ("item:<uid>" or "car:<uid>").
var cells: Dictionary[String, String] = {}
## "x,y" -> wall uid on that tile's h = x edge (vertical) or v = y edge
## (horizontal).
var walls_v: Dictionary[String, int] = {}
var walls_h: Dictionary[String, int] = {}
## wall uid -> is it a half wall.
var half_walls: Dictionary[int, bool] = {}
## "V:x,y" / "H:x,y" -> poster uid hanging on that wall segment.
var posters: Dictionary[String, int] = {}


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
	for w: Dictionary in save["garage"].get("walls", []):
		var def: Dictionary = catalog.item(w["item_id"])
		grid.add_wall(w["x"], w["y"], wall_length(def), w["rot"] == HORIZONTAL, w["uid"], is_half_wall(def))
	for p: Dictionary in save["garage"].get("wall_items", []):
		var def: Dictionary = catalog.item(p["item_id"])
		grid.add_poster(p["x"], p["y"], wall_object_length(def), p["rot"] == HORIZONTAL, p["uid"])
	return grid


func occupy(x: int, y: int, size: Vector2i, key: String) -> void:
	for dx in size.x:
		for dy in size.y:
			cells["%d,%d" % [x + dx, y + dy]] = key


func release(key: String) -> void:
	for cell: String in cells.keys():
		if cells[cell] == key:
			cells.erase(cell)


## True if the footprint is inside the land, every tile is free, and no
## wall runs through it (tiles held by [param ignore_key] count as free).
func can_place(x: int, y: int, size: Vector2i, ignore_key: String = "") -> bool:
	if x < 0 or y < 0 or x + size.x > width or y + size.y > height:
		return false
	for dx in size.x:
		for dy in size.y:
			var cell := "%d,%d" % [x + dx, y + dy]
			var owner: String = cells.get(cell, "")
			if owner != "" and owner != ignore_key:
				return false
			# checkVacancyFloorObj: no wall inside the footprint.
			if dx > 0 and walls_v.has(cell):
				return false
			if dy > 0 and walls_h.has(cell):
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


# --- Walls ----------------------------------------------------------------------------

func add_wall(x: int, y: int, length: int, horizontal: bool, uid: int, half: bool) -> void:
	for i in length:
		if horizontal:
			walls_h["%d,%d" % [x + i, y]] = uid
		else:
			walls_v["%d,%d" % [x, y + i]] = uid
	half_walls[uid] = half


## The wall uid on an edge, or 0.
func wall_at(x: int, y: int, horizontal: bool) -> int:
	return (walls_h if horizontal else walls_v).get("%d,%d" % [x, y], 0)


## checkVacancyWall: inside the land, the edges are free, it doesn't cut
## through a floor object, and no wall crosses it.
func can_place_wall(x: int, y: int, length: int, horizontal: bool, ignore_uid: int = 0) -> bool:
	if x < 0 or y < 0:
		return false
	if horizontal and (x + length > width or y >= height):
		return false
	if not horizontal and (y + length > height or x >= width):
		return false
	for i in length:
		var cx := x + i if horizontal else x
		var cy := y if horizontal else y + i
		var here := wall_at(cx, cy, horizontal)
		if here != 0 and here != ignore_uid:
			return false
		# The tiles on both sides of the edge can't be the same object.
		var ox := cx if horizontal else cx - 1
		var oy := cy - 1 if horizontal else cy
		if ox >= 0 and oy >= 0:
			var a := occupant(ox, oy)
			if a != "" and a == occupant(cx, cy):
				return false
			# A wall running the other way can't pass through the middle.
			if i > 0:
				var cross := wall_at(cx, cy, not horizontal)
				if cross != 0 and cross != ignore_uid and cross == wall_at(ox, oy, not horizontal):
					return false
	return true


# --- Posters --------------------------------------------------------------------------

func add_poster(x: int, y: int, length: int, horizontal: bool, uid: int) -> void:
	for i in length:
		posters[_segment(x, y, i, horizontal)] = uid


static func _segment(x: int, y: int, i: int, horizontal: bool) -> String:
	return "H:%d,%d" % [x + i, y] if horizontal else "V:%d,%d" % [x, y + i]


## checkVacancyWallObj: a full-height wall under every segment and no other
## poster on them.
func can_place_poster(x: int, y: int, length: int, horizontal: bool, ignore_uid: int = 0) -> bool:
	for i in length:
		var cx := x + i if horizontal else x
		var cy := y if horizontal else y + i
		var wall := wall_at(cx, cy, horizontal)
		if wall == 0 or half_walls.get(wall, false):
			return false
		var other: int = posters.get(_segment(x, y, i, horizontal), 0)
		if other != 0 and other != ignore_uid:
			return false
	return true


## Posters hanging on wall [param uid].
func posters_on_wall(uid: int) -> Array[int]:
	var out: Array[int] = []
	for key: String in posters:
		var horizontal := key.begins_with("H:")
		var xy := key.substr(2).split(",")
		if wall_at(int(xy[0]), int(xy[1]), horizontal) == uid and not out.has(posters[key]):
			out.append(posters[key])
	return out
