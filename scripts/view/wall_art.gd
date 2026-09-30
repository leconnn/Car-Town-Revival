class_name WallArt
extends RefCounted
## Drawing walls, the signs on them and painted floor tiles, for the garage
## and for the ghosts that follow the mouse while placing them.

## Wall height above the floor line (StageWall art, WallObj.applyRotation).
const WALL_HEIGHT := 118.0
## How high a sign's middle sits above the floor line.
const POSTER_MIDDLE := 58.0
## A sign 1-2 segments wide is 50 px across; wider ones fill the wall less
## 10 px (WallObj.applyRotation).
const SMALL_POSTER_WIDTH := 50.0
## Floor textures are top-down squares: 50 texture px per tile.
const FLOOR_TEXTURE_TILE := 50.0


## A wall segment on the edge at (x, y): its art for that direction.
static func wall_node(item_id: int, x: int, y: int, rot: int) -> Node2D:
	var frames: Array = GameData.item_art.get(str(item_id), {}).get("frames", [])
	var pos := Iso.to_screen(x, y)
	# Frame 0 runs along v (a vertical wall), frame 1 along h.
	var frame := 0 if rot == GarageGrid.VERTICAL else 1
	if frames.size() > frame:
		var info: Dictionary = frames[frame]
		var s := Sprite2D.new()
		s.texture = GameData.texture(info["file"])
		s.centered = false
		s.offset = -Vector2(info["o"][0], info["o"][1])
		s.position = pos
		return s
	# No art: a plain grey panel standing on the edge.
	var length := GarageGrid.wall_length(GameData.catalog.item(item_id))
	var end := Iso.to_screen(x + (length if rot == GarageGrid.HORIZONTAL else 0), y + (length if rot == GarageGrid.VERTICAL else 0))
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([pos, end, end + Vector2(0, -WALL_HEIGHT), pos + Vector2(0, -WALL_HEIGHT)])
	poly.color = Color(0.72, 0.72, 0.7)
	return poly


## A sign hanging on the walls from (x, y), skewed flat onto the wall like
## WallObj.applyRotation.
static func poster_node(item_id: int, x: int, y: int, rot: int) -> Node2D:
	var def: Dictionary = GameData.catalog.item(item_id)
	var length := GarageGrid.wall_object_length(def)
	var horizontal := rot == GarageGrid.HORIZONTAL
	var start := Iso.to_screen(x, y)
	var end := Iso.to_screen(x + (length if horizontal else 0), y + (0 if horizontal else length))
	var holder := Node2D.new()
	holder.position = (start + end) / 2.0 - Vector2(0, POSTER_MIDDLE)
	var art: Dictionary = GameData.poster_art.get(str(item_id), {})
	var tex := GameData.texture(art.get("file", ""))
	if tex == null:
		return holder
	var width := length * Iso.HALF_W
	var k := (width - 10.0) / tex.get_width() if length > 2 else SMALL_POSTER_WIDTH / tex.get_width()
	# Along a vertical wall the picture climbs to the right, along a
	# horizontal one it drops.
	var slope := 0.5 if horizontal else -0.5
	var skew := Node2D.new()
	skew.transform = Transform2D(Vector2(k, slope * k), Vector2(0, k), Vector2.ZERO)
	var s := Sprite2D.new()
	s.texture = tex
	skew.add_child(s)
	holder.add_child(skew)
	return holder


## One painted floor tile at (x, y).
static func tile_node(item_id: int, x: int, y: int) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = Iso.area_polygon(x, y, 1, 1)
	var tex := GameData.texture("floors/%d.jpg" % item_id)
	if tex != null:
		poly.texture = tex
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var t := FLOOR_TEXTURE_TILE
		poly.uv = PackedVector2Array([Vector2(0, 0), Vector2(t, 0), Vector2(t, t), Vector2(0, t)])
	else:
		poly.color = Color(0.96, 0.93, 0.87)
	return poly
