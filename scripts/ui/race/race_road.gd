class_name RaceRoad
extends Node2D
## The street a race is run on (views/racing/raceview/track/Track): a
## diagonal road running down and to the right at the isometric 1:2 slope
## with a dashed line between the two lanes, sidewalks along both sides, and
## the walls beyond them. It scrolls up and to the left as the cars go.

## Down the road, in stage pixels per step.
const FORWARD := Vector2(2, 1)
## Across the road (from the far lane to the near one).
const ACROSS := Vector2(-2, 1)
const ROAD_HALF := 270.0
const SIDEWALK := 60.0
const LENGTH := 1500.0
const LINE_STEP := 200.0
const ROAD_COLOR := Color8(0x5B, 0x5B, 0x5F)
const SIDEWALK_COLOR := Color8(0xB4, 0xB0, 0xA6)
const CURB_COLOR := Color8(0x8C, 0x88, 0x80)
const WALL_STEP := 150.0

## Where the road's centre line passes.
var center := Vector2(256, 60)
var _scroll := 0.0
var _line_tex: Texture2D
var _wall_tex: Texture2D


func _ready() -> void:
	_line_tex = GameData.main_texture("swcassets.scrollTile.RoadLine")
	_wall_tex = GameData.main_texture("swcassets.scrolltile.RaceWall")


## Moves the road [param pixels] along its direction (a car driving).
func advance(pixels: float) -> void:
	_scroll = fposmod(_scroll + pixels, LINE_STEP)
	queue_redraw()


func _forward() -> Vector2:
	return FORWARD.normalized()


func _across() -> Vector2:
	return (Vector2(2, -1)).normalized()


func _draw() -> void:
	var f := _forward()
	var n := _across()
	_band(0.0, ROAD_HALF, ROAD_COLOR)
	_band(ROAD_HALF, ROAD_HALF + SIDEWALK, SIDEWALK_COLOR)
	_band(-ROAD_HALF - SIDEWALK, -ROAD_HALF, SIDEWALK_COLOR)
	for side: float in [-1.0, 1.0]:
		var a: Vector2 = center + n * side * ROAD_HALF - f * LENGTH
		var b: Vector2 = center + n * side * ROAD_HALF + f * LENGTH
		draw_line(a, b, CURB_COLOR, 3.0)
	# The dashed line down the middle.
	if _line_tex != null:
		var size := _line_tex.get_size()
		var i := -int(LENGTH / LINE_STEP)
		while i <= int(LENGTH / LINE_STEP):
			var pos := center + f * (i * LINE_STEP - _scroll)
			draw_texture(_line_tex, pos - size / 2.0)
			i += 1
	# Walls beyond the sidewalks.
	if _wall_tex != null:
		var size := _wall_tex.get_size()
		for side: float in [-1.0, 1.0]:
			var base: Vector2 = center + n * side * (ROAD_HALF + SIDEWALK)
			var i := -int(LENGTH / WALL_STEP)
			while i <= int(LENGTH / WALL_STEP):
				var pos := base + f * (i * WALL_STEP - fposmod(_scroll, WALL_STEP))
				draw_texture(_wall_tex, pos - Vector2(size.x / 2.0, size.y - 20))
				i += 1


## A strip of the road between two distances from the centre line.
func _band(from: float, to: float, color: Color) -> void:
	var f := _forward() * LENGTH
	var n := _across()
	var a := center + n * from
	var b := center + n * to
	draw_colored_polygon(PackedVector2Array([a - f, a + f, b + f, b - f]), color)
	if from == 0.0:
		var c := center - n * to
		draw_colored_polygon(PackedVector2Array([a - f, a + f, c + f, c - f]), color)
