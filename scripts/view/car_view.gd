class_name CarView
extends Node2D
## Draws a car from its exported layers, the way the original did: body
## layers painted with the car's colour, parts swapped by asset id, wheels
## and tires composed and scaled by size, ride height moving the body.
##
## Views: "front" and "rear" (isometric, used in the garage) and "angle"
## (the big showroom view). Each can be mirrored.

const VIEW_FRONT := "front"
const VIEW_REAR := "rear"
const VIEW_ANGLE := "angle"

const ISO_TOP_LEFT := Vector2(-119, -170)
const ISO_WRAP_WIDTH := 272.0
const ANGLE_TOP_LEFT := Vector2(-243, -449)
const ANGLE_WRAP_WIDTH := 516.0
const RIDE_HEIGHT_STEP := 3.0
const REAR_WHEEL_SCALE_X := 0.9
const DEFAULT_WHEEL_SIZE := 22.0
const TIRE_HEIGHT_OFFSET_ISO: Array[int] = [7, 5, 3, 0]
const TIRE_HEIGHT_OFFSET_ANGLE: Array[int] = [17, 11, 8, 0]
const TIRE_MASK_OFFSET := 17.0
const WHEEL_DARKEN := 50.0 / 255.0

const CAT_WHEELS := 1
const CAT_TIRES := 2
const CAT_BODY_KIT := 4
const CAT_WING := 5
const CAT_HOOD := 6
const CAT_HOOD_ACCESSORY := 11
const CAT_NEON := 10
const CAT_TINT := 12
## Neon part id -> glow colour (from the original's StaticData).
const NEON_COLORS: Dictionary[int, Color] = {
	956: Color8(255, 255, 0), 957: Color8(0, 255, 255), 958: Color8(255, 0, 255),
	2965: Color8(0, 48, 255), 2966: Color8(255, 68, 0), 2967: Color8(255, 0, 60),
	2968: Color8(90, 255, 0), 2969: Color8(168, 0, 255),
}
## Window tint part id -> colour.
const TINT_COLORS: Dictionary[int, Color] = {
	959: Color8(0, 0, 0), 960: Color8(58, 58, 58), 961: Color8(0, 0, 255), 962: Color8(255, 0, 0),
}

static var _shader: Shader
static var _tire_cache: Dictionary[String, ImageTexture] = {}

var car: Dictionary = {}
var view: String = VIEW_FRONT
var reversed: bool = false
## False if this car has no exported art (a placeholder is drawn instead).
var has_art: bool = false

var _canvas: Node2D
var _coords: Dictionary = {}
var _layers: Dictionary = {}
var _paint := Color.RED
var _materials: Array[ShaderMaterial] = []


## A factory car as the dealer shows it: stock parts, no upgrades.
static func stock_entry(car_id: int, color_id: int) -> Dictionary:
	var entry := {"car_id": car_id, "color_id": color_id, "parts": {}, "ride_height": 0}
	var defaults: Dictionary = GameData.catalog.car(car_id).get("defaults", {})
	for key: String in defaults:
		var p: Dictionary = GameData.catalog.part(defaults[key])
		if not p.is_empty():
			entry["parts"][str(p["category_id"])] = p["id"]
	return entry


## Builds the drawing. [param car_entry] is a save car (or customer) entry.
func setup(car_entry: Dictionary, view_name: String, mirror: bool) -> void:
	car = car_entry
	view = view_name
	reversed = mirror
	for child in get_children():
		child.queue_free()
	_materials.clear()
	var art: Dictionary = GameData.car_art.get(str(car.get("car_id", 0)), {})
	_coords = art.get("coords", {}).get(view, {})
	_layers = art.get("views", {}).get(view, {}).get("layers", {})
	has_art = not _layers.is_empty() and not _coords.is_empty()
	if not has_art:
		_draw_placeholder()
		return
	_paint = _paint_color()
	_build(art.get("coords", {}))


## Hover highlight; a transparent colour restores each layer's own tint.
func set_highlight(color: Color) -> void:
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter("highlight", color if color.a > 0.0 else m.get_meta("base", Color(0, 0, 0, 0)))


static func _set_base_highlight(m: ShaderMaterial, color: Color) -> void:
	m.set_meta("base", color)
	m.set_shader_parameter("highlight", color)


## Maps a garage rotation (0-3) to the original's view and mirroring.
static func iso_view_for_rotation(rot: int) -> Array:
	match posmod(rot, 4):
		0: return [VIEW_FRONT, true]
		1: return [VIEW_FRONT, false]
		2: return [VIEW_REAR, true]
		_: return [VIEW_REAR, false]


func _paint_color() -> Color:
	if car.has("paint"):
		return Color.hex((int(car["paint"]) << 8) | 0xFF)
	for c: Dictionary in GameData.catalog.colors_for_car(car.get("car_id", 0)):
		if c["id"] == car.get("color_id", 0):
			return Color.html(c["hex"])
	return Color.html("cc2222")


func _coord(label: String) -> Dictionary:
	return _coords.get(label, {})


func _coord_pos(label: String) -> Vector2:
	var c := _coord(label)
	return Vector2(float(c.get("x", 0)), float(c.get("y", 0)))


func _coord_scale(label: String) -> float:
	# The original only read per-wheel scale for the angle view.
	if view != VIEW_ANGLE:
		return 1.0
	return float(_coord(label).get("scale", 1))


func _under_body(label: String) -> bool:
	return str(_coord(label).get("under_body", "false")) == "true"


func _part_asset(category: int) -> int:
	var part_id: int = car.get("parts", {}).get(str(category), 0)
	return GameData.catalog.part(part_id).get("asset_id", 0) if part_id > 0 else 0


func _part_size(category: int) -> int:
	var part_id: int = car.get("parts", {}).get(str(category), 0)
	if part_id == 0:
		part_id = GameData.catalog.car(car.get("car_id", 0)).get("defaults", {}).get(
			"wheels" if category == CAT_WHEELS else "tires", 0)
	return GameData.catalog.part(part_id).get("size", 22 if category == CAT_WHEELS else 0)


func _build(all_coords: Dictionary) -> void:
	var is_angle := view == VIEW_ANGLE
	var top_left := ANGLE_TOP_LEFT if is_angle else ISO_TOP_LEFT
	var wrap_width := ANGLE_WRAP_WIDTH if is_angle else ISO_WRAP_WIDTH

	_canvas = Node2D.new()
	_canvas.position = top_left
	if reversed:
		_canvas.scale.x = -1
		_canvas.position.x += wrap_width + (0.0 if is_angle else 28.0)

	# Wheel size, tire profile and ride height decide how high the body sits.
	var wheel_size := _part_size(CAT_WHEELS)
	var tire := _tire_details(_part_size(CAT_TIRES))
	var size_scale := wheel_size / DEFAULT_WHEEL_SIZE
	var clearance: Dictionary = all_coords.get("ground_clearance", {}).get("clearance_%d" % wheel_size, {})
	var offset_clearance := -float(clearance.get("y", 0)) - float(clearance.get("p%d" % tire["profile"], 0))
	var offset_ride := -float(car.get("ride_height", 0)) * RIDE_HEIGHT_STEP
	var height_map := TIRE_HEIGHT_OFFSET_ANGLE if is_angle else TIRE_HEIGHT_OFFSET_ISO
	var offset_tire := size_scale * height_map[tire["profile"]]
	var height_offset: float
	if is_angle:
		height_offset = (offset_clearance * 1.5 + offset_ride + offset_tire) * 1.35
	else:
		height_offset = offset_clearance + offset_ride + offset_tire
	var body_dy := floorf(height_offset)

	# Shadow: separate sprite in the iso views, part of the car in angle view.
	if _layers.has("shadow"):
		var shadow := _layer_sprite("shadow", false)
		var neon: int = car.get("parts", {}).get(str(CAT_NEON), 0)
		if NEON_COLORS.has(neon):
			# The original tinted the shadow and gave it an inner glow.
			_set_base_highlight(shadow.material, Color(NEON_COLORS[neon], 0.7))
			shadow.self_modulate = Color(1.3, 1.3, 1.3)
		if is_angle:
			shadow.position += _coord_pos("shadow")
			_canvas.add_child(shadow)
		else:
			var holder := Node2D.new()
			holder.position = top_left + _coord_pos("shadow")
			if reversed:
				holder.scale.x = -1
				var tex_w: float = _layers["shadow"]["size"][0]
				holder.position.x += tex_w + 28.0
			holder.add_child(shadow)
			add_child(holder)
	add_child(_canvas)

	var body_kit := _part_asset(CAT_BODY_KIT)
	var hood := _part_asset(CAT_HOOD)
	var wing := _part_asset(CAT_WING)
	var hood_acc := _part_asset(CAT_HOOD_ACCESSORY)

	_add_part("bodykit_under_%d" % body_kit, body_dy)
	var strip_draws := _draw_wheels(size_scale, tire, is_angle)
	_add_part("body", body_dy)
	_add_part("bodykit_%d" % body_kit, body_dy)
	if not (reversed and _add_part("body_np_f", body_dy)):
		_add_part("body_np", body_dy)
	if not (reversed and _add_part("windshields_np_f", body_dy)):
		_add_part("windshields_np", body_dy)
	_add_part("wing_%d" % wing, body_dy)
	_add_part("wing_np_%d" % wing, body_dy)
	_add_part("hood_%d" % hood, body_dy)
	if not (reversed and _add_part("hood_np_f_%d" % hood, body_dy)):
		_add_part("hood_np_%d" % hood, body_dy)
	_add_part("hood_accessory_%d" % hood_acc, body_dy)
	_add_part("hood_accessory_np_%d" % hood_acc, body_dy)
	_add_part("bodykit_np_%d" % body_kit, body_dy)
	# The visible edge of each wheel in front of the wheel arch.
	for d: Callable in strip_draws:
		d.call()


## Adds a layer if the car has it, at its coords plus the body height offset.
func _add_part(layer_name: String, dy: float) -> bool:
	if not _layers.has(layer_name) or _coord(layer_name).is_empty():
		return false
	var painted := layer_name.find("_np") == -1 and layer_name.find("_under") == -1
	var s := _layer_sprite(layer_name, painted)
	s.position += _coord_pos(layer_name) + Vector2(0, dy)
	if layer_name.begins_with("windshields_np"):
		var tint: int = car.get("parts", {}).get(str(CAT_TINT), 0)
		if TINT_COLORS.has(tint):
			_set_base_highlight(s.material, Color(TINT_COLORS[tint], 0.45))
	_canvas.add_child(s)
	return true


func _layer_sprite(layer_name: String, painted: bool) -> Sprite2D:
	var info: Dictionary = _layers[layer_name]
	var s := Sprite2D.new()
	s.texture = GameData.texture(info["file"])
	s.centered = false
	s.position = -Vector2(info["o"][0], info["o"][1])
	s.material = _material(painted, 0.0)
	return s


func _material(painted: bool, darken: float) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/car_layer.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("painted", painted)
	m.set_shader_parameter("paint_color", Vector3(_paint.r, _paint.g, _paint.b))
	m.set_shader_parameter("darken", darken)
	_materials.append(m)
	return m


# --- Wheels and tires ------------------------------------------------------------

static func _tire_details(raw_size: int) -> Dictionary:
	var asset := (raw_size % 100) / 10
	var d := {
		"asset": asset,
		"width": raw_size / 100,
		"profile": asset % 4,
		"sidewall": raw_size % 10,
	}
	if asset == 8:
		d["profile"] = 3
		d["sidewall"] = 0
	return d


## Tire (+ shadow) image, and the full tire + sidewall + rim image.
func _tire_images(tire: Dictionary, is_angle: bool) -> Array[Image]:
	var a := "a" if is_angle else ""
	var name := "tire_%d%s_%d" % [tire["asset"], a, tire["width"]]
	if reversed and tire["asset"] == 8:
		name += "_f"
	var base := _main_image(name)
	if base == null:
		return []
	var with_shadow := base.duplicate() as Image
	if tire["asset"] < 8:
		var sh := _main_image("tire_%d%s_sh" % [tire["asset"], a])
		if sh != null:
			with_shadow.blend_rect(sh, Rect2i(Vector2i.ZERO, sh.get_size()), Vector2i.ZERO)
	var full := with_shadow.duplicate() as Image
	if tire["sidewall"] > 0:
		var sw := _main_image("tire_%d%s_w%d" % [tire["profile"], a, tire["sidewall"]])
		if sw != null:
			full.blend_rect(sw, Rect2i(Vector2i.ZERO, sw.get_size()), Vector2i.ZERO)
	var rim := _rim_image(is_angle)
	if rim.size() == 2:
		var img: Image = rim[0]
		var at: Vector2i = rim[1]
		full.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
	return [with_shadow, full]


func _main_image(name: String) -> Image:
	var tex := GameData.main_texture("swcassets.bmd.tire." + name)
	if tex == null:
		return null
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## The rim image and where its top-left sits relative to the tire's origin.
func _rim_image(is_angle: bool) -> Array:
	var asset := _part_asset(CAT_WHEELS)
	var entry: Dictionary = GameData.wheel_art.get(str(asset), {})
	var kind := "a_a" if is_angle else "i_a"
	if not is_angle and view == VIEW_REAR and _wheels_are_stock() and entry.has("i_b") \
			and str(GameData.car_art.get(str(car.get("car_id", 0)), {}).get("coords", {}).get("_attrs", {}).get("wheelsInvertible", "")) == "true":
		kind = "i_b"
	var frames: Array = entry.get(kind, [])
	if frames.is_empty():
		return []
	var info: Dictionary = frames[0]
	var tex := GameData.texture(info["file"])
	if tex == null:
		return []
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return [img, -Vector2i(info["o"][0], info["o"][1])]


func _wheels_are_stock() -> bool:
	var stock := GameData.catalog.stock_part(car.get("car_id", 0), CAT_WHEELS)
	return car.get("parts", {}).get(str(CAT_WHEELS), 0) == stock


func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


## Draws the wheels under the body. Returns callables that draw the strips
## of the near wheels that show in front of the body (drawn last).
func _draw_wheels(scale_f: float, tire: Dictionary, is_angle: bool) -> Array[Callable]:
	var images := _tire_images(tire, is_angle)
	if images.is_empty():
		return []
	var shadow_tex := _tex(images[0])
	var full: Image = images[1]
	var full_tex := _tex(full)
	var w := full.get_width()
	var h := full.get_height()
	var off_x: float
	var off_y: float
	var height_map := TIRE_HEIGHT_OFFSET_ANGLE if is_angle else TIRE_HEIGHT_OFFSET_ISO
	if is_angle:
		off_x = (1.0 - scale_f) * 53.0
		off_y = scale_f * height_map[tire["profile"]] + (1.0 - scale_f) * 140.0
	else:
		off_x = (1.0 - scale_f) * 48.0
		off_y = scale_f * height_map[tire["profile"]] + (1.0 - scale_f) * 76.0
	var strips: Array[Callable] = []

	if is_angle:
		var mask := floori(1.77 * scale_f * TIRE_MASK_OFFSET)
		if tire["asset"] < 8:
			_wheel_sprite(shadow_tex, Rect2(0, 0, w, h), _angle_wheel_xform("wheel_opposite_rear", scale_f, off_x, off_y, true), WHEEL_DARKEN)
			_wheel_sprite(shadow_tex, Rect2(0, 0, w, h), _angle_wheel_xform("wheel_opposite", scale_f, off_x, off_y, false), WHEEL_DARKEN)
		var rear_mask := 0 if _under_body("wheel_rear") else mask
		var front_mask := 0 if _under_body("wheel_front") else mask
		_wheel_sprite(full_tex, Rect2(rear_mask, 0, w - rear_mask, h), _angle_wheel_xform("wheel_rear", scale_f, off_x, off_y, true), 0.0)
		_wheel_sprite(full_tex, Rect2(front_mask, 0, w - front_mask, h), _angle_wheel_xform("wheel_front", scale_f, off_x, off_y, false), 0.0)
		var strip := Rect2(0, 0, mask + 1, h)
		for label: String in ["wheel_rear", "wheel_front"]:
			var xf := _angle_wheel_xform(label, scale_f, off_x, off_y, label == "wheel_rear")
			if _under_body(label):
				_wheel_sprite(full_tex, strip, xf, 0.0)
			else:
				strips.append(_wheel_sprite.bind(full_tex, strip, xf, 0.0))
		return strips

	var mask := floori(scale_f * TIRE_MASK_OFFSET)
	var off := Vector2(off_x, off_y)
	if tire["asset"] < 8:
		_wheel_sprite(shadow_tex, Rect2(0, 0, w, h), Transform2D(0, Vector2(scale_f, scale_f), 0, _coord_pos("wheel_opposite") + off), WHEEL_DARKEN)
	var rear_mask := 0 if _under_body("wheel_rear") else mask
	var front_mask := 0 if _under_body("wheel_front") else mask
	var front_pos := _coord_pos("wheel_front") + off
	var rear_pos := _coord_pos("wheel_rear") + off
	if view == VIEW_REAR:
		var t := rear_mask
		rear_mask = front_mask
		front_mask = t
		var p := rear_pos
		rear_pos = front_pos
		front_pos = p
	_wheel_sprite(full_tex, Rect2(0, 0, w - rear_mask, h), Transform2D(0, Vector2(scale_f, scale_f), 0, rear_pos), 0.0)
	_wheel_sprite(full_tex, Rect2(0, 0, w - front_mask, h), Transform2D(0, Vector2(scale_f, scale_f), 0, front_pos), 0.0)
	var strip_x := w - mask - 1
	var strip := Rect2(strip_x, 0, w - strip_x, h)
	for label: String in ["wheel_front", "wheel_rear"]:
		var xf := Transform2D(0, Vector2(scale_f, scale_f), 0, _coord_pos(label) + off)
		if _under_body(label):
			_wheel_sprite(full_tex, strip, xf, 0.0)
		else:
			strips.append(_wheel_sprite.bind(full_tex, strip, xf, 0.0))
	return strips


func _angle_wheel_xform(label: String, s: float, off_x: float, off_y: float, rear: bool) -> Transform2D:
	var ws := _coord_scale(label)
	var pos := _coord_pos(label)
	if label == "wheel_front":
		# The original applies the wheel scale to the size offsets here.
		return Transform2D(0, Vector2(s * ws, s * ws), 0, pos + Vector2(off_x * ws, off_y * ws))
	var sx := (REAR_WHEEL_SCALE_X if rear else 1.0) * s * ws
	var x := pos.x + off_x + (1.0 - ws) * 53.0 * (REAR_WHEEL_SCALE_X if rear else 1.0) * s
	var y := pos.y + off_y + (1.0 - ws) * 140.0 * s
	return Transform2D(0, Vector2(sx, s * ws), 0, Vector2(x, y))


## A sprite showing [param region] of the tire texture, placed as if the
## whole texture were drawn with [param xf].
func _wheel_sprite(tex: Texture2D, region: Rect2, xf: Transform2D, darken: float) -> void:
	if region.size.x <= 0 or region.size.y <= 0:
		return
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.region_enabled = true
	s.region_rect = region
	s.transform = xf * Transform2D(0, region.position)
	s.material = _material(false, darken)
	_canvas.add_child(s)


func _draw_placeholder() -> void:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-70, -10), Vector2(0, -45), Vector2(70, -10), Vector2(0, 25)])
	poly.color = Color(0.4, 0.4, 0.45, 0.8)
	add_child(poly)
	var label := Label.new()
	label.text = GameData.car_name(car.get("car_id", 0))
	label.position = Vector2(-70, -20)
	label.add_theme_font_size_override("font_size", 11)
	add_child(label)
