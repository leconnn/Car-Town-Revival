class_name Iso
extends RefCounted
## Isometric math for the garage. Matches the original, which drew the floor
## as 50-unit squares rotated 45 degrees and tilted 60 degrees: tiles are
## about 70.7 x 35.4 px diamonds; grid (h, v) maps to the tile's top corner.

const TILE_W := 70.71068
const TILE_H := 35.35534
const HALF_W := TILE_W / 2.0
const HALF_H := TILE_H / 2.0


## Screen position of the top corner of tile (h, v). Fractions allowed.
static func to_screen(h: float, v: float) -> Vector2:
	return Vector2((h - v) * HALF_W, (h + v) * HALF_H)


## Grid coordinates (fractional) under a screen point.
static func to_grid(p: Vector2) -> Vector2:
	var a := p.x / HALF_W
	var b := p.y / HALF_H
	return Vector2((a + b) / 2.0, (b - a) / 2.0)


## Integer tile under a screen point.
static func tile_at(p: Vector2) -> Vector2i:
	var g := to_grid(p)
	return Vector2i(floori(g.x), floori(g.y))


## Diamond outline of a w x h tile area starting at (h, v).
static func area_polygon(h: int, v: int, w: int, d: int) -> PackedVector2Array:
	return PackedVector2Array([
		to_screen(h, v), to_screen(h + w, v), to_screen(h + w, v + d), to_screen(h, v + d),
	])


## Draw order key: things further forward (larger h + v of their front
## corner) draw later.
static func depth(h: int, v: int, w: int, d: int) -> int:
	return (h + w - 1 + v + d - 1) * 1000 + (h + w - 1) * 2
