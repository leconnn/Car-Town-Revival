class_name EllipseButton
extends Node2D
## The original StyledTextButton with PanelFrameButtonStyle (CarTownButtonFactory
## .createPanelFrameButton): an ellipse in the button's outer colour, a
## smaller ellipse in its main colour towards the top-left, and a stroke,
## with a white Dom Diagonal Bold label. Centred on its position. Used for
## Buy, Done, etc. on the edge of the bottom panels.

signal pressed

## [main, outer, stroke] per CarTownColor (createTextButtonStyle).
const GREEN := [0x587C48, 0x445E38, 0x194F2A]
const BLUE := [0x3F688F, 0x3D5267, 0x18263A]
const RED := [0x8C3A35, 0x6E3B3C, 0x000000]
const YELLOW := [0xD7AD39, 0xC77C2E, 0x654B22]
const GREY := [0x777E83, 0x62676D, 0x3D413F]

const HEIGHT := 52.0
const MIN_WIDTH := 68.0
const FONT_SIZE := 24
const STROKE := 3.0
const SEGMENTS := 48

var _body: Node2D
var _tween: Tween
var _size := Vector2.ZERO
var _disabled := false


## Panel-frame style by default (24 px, at least 68 wide); popup-frame
## buttons use 22 px and 78. Two-line labels (like Reset Floor) are drawn
## tighter and 10 px wider, like the multiline style.
static func create(text: String, colors: Array, font_size: int = FONT_SIZE, min_width: float = MIN_WIDTH) -> EllipseButton:
	var b := EllipseButton.new()
	b._build(text, colors, font_size, min_width)
	return b


func size() -> Vector2:
	return _size


## The original greyed out (desaturated) Buy buttons you couldn't afford.
func set_disabled(on: bool) -> void:
	_disabled = on
	modulate = Color(0.75, 0.75, 0.75) if on else Color.WHITE


func _build(text: String, colors: Array, font_size: int, min_width: float) -> void:
	var label := FlashUi.styled_label(text, "casualA01", font_size, Color.WHITE)
	var multiline := text.contains("\n")
	if multiline:
		label.label_settings.line_spacing = -8
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var text_size := label.get_minimum_size()
	var w := maxf(min_width, text_size.x + 6) + (10.0 if multiline else 0.0)
	_size = Vector2(w, HEIGHT)
	_body = Node2D.new()
	add_child(_body)
	var origin := -_size / 2.0
	var shadow := _ellipse(Rect2(origin + Vector2(3, 4), _size), Color(0, 0, 0, 0.3))
	_body.add_child(shadow)
	_body.add_child(_ellipse(Rect2(origin, _size), _color(colors[1])))
	_body.add_child(_ellipse(Rect2(origin + Vector2(w * 4.0 / 84.0, HEIGHT / 100.0), _size * 0.83), _color(colors[0])))
	var stroke := Line2D.new()
	stroke.width = STROKE
	stroke.default_color = _color(colors[2])
	stroke.closed = true
	stroke.antialiased = true
	stroke.points = _ellipse_points(Rect2(origin, _size))
	_body.add_child(stroke)
	label.position = Vector2(-text_size.x / 2.0, -floorf(text_size.y / 2.0) - 2)
	_body.add_child(label)
	var hit := Control.new()
	hit.position = origin
	hit.size = _size
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.mouse_entered.connect(func() -> void:
		Sound.play("RollOverSound01")
		_scale_to(1.1))
	hit.mouse_exited.connect(func() -> void: _scale_to(1.0))
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sound.play("ClickSound02" if colors == RED else "ClickSound01")
			pressed.emit()
			hit.accept_event())
	add_child(hit)


static func _color(rgb: int) -> Color:
	return Color.hex((rgb << 8) | 0xFF)


static func _ellipse_points(r: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c := r.get_center()
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		pts.append(c + Vector2(cos(a) * r.size.x / 2.0, sin(a) * r.size.y / 2.0))
	return pts


static func _ellipse(r: Rect2, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = _ellipse_points(r)
	p.color = color
	p.antialiased = true
	return p


func _scale_to(s: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_body, "scale", Vector2(s, s), 0.1)
