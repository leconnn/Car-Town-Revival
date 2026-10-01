class_name ColorMatrix
extends RefCounted
## The avatar's colour adjustments: TweenMax's ColorMatrixFilterPlugin
## (brightness, contrast, hue, saturation) as a 4 x 5 Flash colour matrix,
## applied to images on the CPU (the textures involved are small).

const LUM_R := 0.212671
const LUM_G := 0.715160
const LUM_B := 0.072169
const IDENTITY: Array[float] = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]

static var _cache: Dictionary = {}


## The matrix for an adjustment {"c", "b", "s", "h"} (AvatarColors entries).
static func from_adjustment(adj: Dictionary) -> Array[float]:
	var m: Array[float] = IDENTITY.duplicate()
	var b := float(adj.get("b", 1.0))
	if b != 1.0:
		var n := b * 100.0 - 100.0
		m = _apply([1, 0, 0, 0, n, 0, 1, 0, 0, n, 0, 0, 1, 0, n, 0, 0, 0, 1, 0], m)
	var c := float(adj.get("c", 1.0))
	if c != 1.0:
		var k := c + 0.01
		var o := 128.0 * (1.0 - k)
		m = _apply([k, 0, 0, 0, o, 0, k, 0, 0, o, 0, 0, k, 0, o, 0, 0, 0, 1, 0], m)
	var h := float(adj.get("h", 0.0))
	if h != 0.0:
		var a := deg_to_rad(h)
		var co := cos(a)
		var si := sin(a)
		m = _apply([
			(LUM_R + co * (1 - LUM_R)) + si * (-LUM_R), (LUM_G + co * (-LUM_G)) + si * (-LUM_G), (LUM_B + co * (-LUM_B)) + si * (1 - LUM_B), 0, 0,
			(LUM_R + co * (-LUM_R)) + si * 0.143, (LUM_G + co * (1 - LUM_G)) + si * 0.14, (LUM_B + co * (-LUM_B)) + si * -0.283, 0, 0,
			(LUM_R + co * (-LUM_R)) + si * (-(1 - LUM_R)), (LUM_G + co * (-LUM_G)) + si * LUM_G, (LUM_B + co * (1 - LUM_B)) + si * LUM_B, 0, 0,
			0, 0, 0, 1, 0], m)
	var s := float(adj.get("s", 1.0))
	if s != 1.0:
		var inv := 1.0 - s
		var r := inv * LUM_R
		var g := inv * LUM_G
		var bl := inv * LUM_B
		m = _apply([r + s, g, bl, 0, 0, r, g + s, bl, 0, 0, r, g, bl + s, 0, 0, 0, 0, 0, 1, 0], m)
	return m


## [param a] applied after [param b] (Flash's applyMatrix).
static func _apply(a: Array, b: Array[float]) -> Array[float]:
	var out: Array[float] = []
	out.resize(20)
	for row in 4:
		for col in 5:
			var v := 0.0
			for k in 4:
				v += float(a[row * 5 + k]) * b[k * 5 + col]
			if col == 4:
				v += float(a[row * 5 + 4])
			out[row * 5 + col] = v
	return out


## A copy of [param image] through the matrix (offsets are in 0-255 units).
static func apply_to_image(image: Image, m: Array[float]) -> Image:
	var img := image.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var r := p.r * 255.0
			var g := p.g * 255.0
			var b := p.b * 255.0
			var a := p.a * 255.0
			img.set_pixel(x, y, Color(
				clampf(m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4], 0, 255) / 255.0,
				clampf(m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9], 0, 255) / 255.0,
				clampf(m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14], 0, 255) / 255.0,
				p.a))
	return img


## A texture tinted by an adjustment, cached by [param key].
static func tinted_texture(key: String, image: Image, adj: Dictionary) -> ImageTexture:
	var k := "%s|%s" % [key, str(adj)]
	if not _cache.has(k):
		_cache[k] = ImageTexture.create_from_image(apply_to_image(image, from_adjustment(adj)))
	return _cache[k]
