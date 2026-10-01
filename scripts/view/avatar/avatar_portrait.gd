class_name AvatarPortrait
extends Node2D
## An avatar drawn in 2D (Avatar2D): body, clothes, head and face features
## from data/6/avatar/<id>_l, each centred on its spot and adjusted by its
## setting digits (colour, position, scale, distance, rotation).
## With face_only it draws just the features the original copied onto the
## 3D head (eyes, brows, nose, mouth, facial hair, freckles).

## Outfit keys (AvatarData categories) and the default look.
const DEFAULT_OUTFIT := {
	"head": 68, "eyes": 1, "mouth": 12, "brows": 20, "facial_hair": 0, "hair": 33, "misc": 0, "hat": 0,
	"top": 53, "bottom": 57, "nose": 60,
	"settings": {"head": 20000, "eyes": 5425, "mouth": 5300, "brows": 7226, "facial_hair": 0, "hair": 0, "misc": 0, "nose": 6200},
}
const NO_HAT := 77

var outfit: Dictionary = DEFAULT_OUTFIT
var face_only := false


static func create(look: Dictionary, faces_only: bool = false) -> AvatarPortrait:
	var p := AvatarPortrait.new()
	p.outfit = look
	p.face_only = faces_only
	p._build()
	return p


## One setting digit: colour 10000s, position 1000s, scale 100s, distance 10s, rotation 1s.
static func digit(setting: int, place: int) -> int:
	return (setting / place) % 10


## Conversion(0, from, 9, to).
static func conv(key: int, from: float, to: float) -> float:
	return from + (to - from) * key / 9.0


func _setting(part: String) -> int:
	return int(outfit.get("settings", {}).get(part, DEFAULT_OUTFIT["settings"].get(part, 0)))


func _id(part: String) -> int:
	return int(outfit.get(part, DEFAULT_OUTFIT.get(part, 0)))


func _build() -> void:
	var holder := Node2D.new()
	holder.position.y = -15
	add_child(holder)
	var skin: Dictionary = AvatarColors.SKIN[mini(digit(_setting("head"), 10000), AvatarColors.SKIN.size() - 1)]
	var hair_color: Dictionary = AvatarColors.HAIR[mini(digit(_setting("hair"), 10000), AvatarColors.HAIR.size() - 1)]
	if not face_only:
		_piece(holder, "0_l", Vector2(5, 157), skin)
		_piece(holder, "%d_lb" % _id("hair"), Vector2(0, -20), hair_color)
		_piece(holder, "%d_l" % _id("bottom"), Vector2(3, 173))
		_piece(holder, "%d_l" % _id("top"), Vector2(5, 115))
		_piece(holder, "%d_l" % _id("head"), Vector2.ZERO, skin)
	if _id("misc") > 0:
		_piece(holder, "%d_l" % _id("misc"), Vector2(0, 20))
	var mouth := _setting("mouth")
	var m := _piece(holder, "%d_l" % _id("mouth"), Vector2(0, 50 + conv(digit(mouth, 1000), -6, 6)), skin)
	if m != null:
		m.scale *= conv(digit(mouth, 100), 0.6, 1.0)
	var nose := _setting("nose")
	var n := _piece(holder, "%d_l" % _id("nose"), Vector2(0, 10 + conv(digit(nose, 1000), -6, 6)), skin)
	if n != null:
		n.scale *= conv(digit(nose, 100), 0.4, 0.8)
	if _id("facial_hair") > 0:
		_piece(holder, "%d_l" % _id("facial_hair"), Vector2(0, 35), hair_color)
	var eyes := _setting("eyes")
	_pair_texture(holder, _eye_texture(_id("eyes"), digit(eyes, 10000)), Vector2(0, -20), conv(digit(eyes, 1000), 10, 20), conv(digit(eyes, 100), 0.4, 0.9),
		conv(digit(eyes, 10), -25, -45), conv(digit(eyes, 1), -30, 30))
	var brows := _setting("brows")
	_pair(holder, "%d_l" % _id("brows"), Vector2(0, -30), conv(digit(brows, 1000), -15, 10), conv(digit(brows, 100), 0.5, 1.3),
		conv(digit(brows, 10), -25, -45), conv(digit(brows, 1), -30, 30), hair_color)
	if not face_only:
		_piece(holder, "%d_l" % _id("hair"), Vector2(0, -20), hair_color)
		var hat := _id("hat")
		if hat > 0 and hat != NO_HAT:
			_piece(holder, "%d_l" % hat, Vector2(0, -80))


## A piece centred at [param at] (AbstractAvatarAsset.centerContent).
func _piece(parent: Node2D, key: String, at: Vector2, tint: Dictionary = {}) -> Sprite2D:
	var tex := _texture(key, tint)
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	s.position = at
	parent.add_child(s)
	return s


## A mirrored pair (eyes, brows): [param y] down from [param at], each
## [param x] out from the middle, scaled and tilted.
func _pair(parent: Node2D, key: String, at: Vector2, y: float, scale_f: float, x: float, degrees: float,
		tint: Dictionary = {}) -> void:
	_pair_texture(parent, _texture(key, tint), at, y, scale_f, x, degrees)


func _pair_texture(parent: Node2D, tex: Texture2D, at: Vector2, y: float, scale_f: float, x: float, degrees: float) -> void:
	if tex == null:
		return
	for side: float in [1.0, -1.0]:
		var s := Sprite2D.new()
		s.texture = tex
		s.position = at + Vector2(x * side, y)
		s.scale = Vector2(scale_f * side, scale_f)
		s.rotation_degrees = degrees * side
		parent.add_child(s)


static var _eye_cache: Dictionary = {}


## An eye with its iris: the original swapped an iris clip (a frame per eye
## colour) into the eye; ours is painted onto the eye's white, centred on it,
## so the lids stay on top.
static func _eye_texture(eye_id: int, color: int) -> Texture2D:
	var key := "%d|%d" % [eye_id, color]
	if _eye_cache.has(key):
		return _eye_cache[key]
	var eye_tex := _texture("%d_l" % eye_id, {})
	var iris_tex := GameData.texture("avatar/iris_%d.png" % clampi(color, 0, 8))
	if eye_tex == null or iris_tex == null:
		return eye_tex
	var eye := eye_tex.get_image().duplicate() as Image
	if eye.is_compressed():
		eye.decompress()
	eye.convert(Image.FORMAT_RGBA8)
	var iris := iris_tex.get_image().duplicate() as Image
	if iris.is_compressed():
		iris.decompress()
	iris.convert(Image.FORMAT_RGBA8)
	var lo := Vector2i(eye.get_width(), eye.get_height())
	var hi := Vector2i(-1, -1)
	for py in eye.get_height():
		for px in eye.get_width():
			if _is_white(eye.get_pixel(px, py)):
				lo = Vector2i(mini(lo.x, px), mini(lo.y, py))
				hi = Vector2i(maxi(hi.x, px), maxi(hi.y, py))
	if hi.x >= 0:
		var centre := (lo + hi) / 2
		var origin := centre - Vector2i(iris.get_width(), iris.get_height()) / 2
		for iy in iris.get_height():
			for ix in iris.get_width():
				var px := origin.x + ix
				var py := origin.y + iy
				if px < 0 or py < 0 or px >= eye.get_width() or py >= eye.get_height():
					continue
				var under := eye.get_pixel(px, py)
				if not _is_white(under):
					continue
				var ic := iris.get_pixel(ix, iy)
				eye.set_pixel(px, py, under.lerp(Color(ic.r, ic.g, ic.b, under.a), ic.a))
	_eye_cache[key] = ImageTexture.create_from_image(eye)
	return _eye_cache[key]


static func _is_white(c: Color) -> bool:
	return c.a > 0.9 and c.r > 0.85 and c.g > 0.85 and c.b > 0.85


static func _texture(key: String, tint: Dictionary) -> Texture2D:
	var info: Dictionary = GameData.avatar_art.get(key, {})
	var tex := GameData.texture(info.get("file", ""))
	if tex == null or tint.is_empty():
		return tex
	return ColorMatrix.tinted_texture(key, tex.get_image(), tint)
