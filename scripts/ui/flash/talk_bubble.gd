class_name TalkBubble
extends Node2D
## The original TextBubble (AbstractBubble): centred Dom Diagonal Bold text
## in #767676, in a white ellipse padded by the font size on every side, with
## a 4 px grey outline and a pointed tip running from the centre out past the
## ellipse towards the speaker (down-right, or down-left with tip_on_left).
## Pops in (0.2 s grow, then a 0.3 s bounce from 120%). Its origin is the
## ellipse's top-left corner, like the original.

const TEXT_COLOR := Color8(0x76, 0x76, 0x76)
const STROKE := 4.0
const TIP_STROKE := 3.0
const TIP_LENGTH := 15.0
const SEGMENTS := 64

## The ellipse's size (contentWidth / contentHeight).
var content_size := Vector2.ZERO
var _master: Node2D


static func create(text: String, max_width: float = 300.0, font_size: int = 20, tip_on_left: bool = false,
		animate: bool = true) -> TalkBubble:
	var b := TalkBubble.new()
	b._build(text, max_width, font_size, tip_on_left, animate)
	return b


func _build(text: String, max_width: float, font_size: int, tip_on_left: bool, animate: bool) -> void:
	var label := FlashUi.styled_label(text.replace("\r\n", "\n"), "casualA01", font_size, TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.label_settings.line_spacing = -6
	var size := label.get_minimum_size()
	if size.x > max_width:
		# checkText(): wrap at the maximum width. A wrapping Label only knows
		# its height once it has a width, so give it one before measuring.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(max_width, 0)
		label.size = Vector2(max_width, 0)
		size = Vector2(max_width, label.get_minimum_size().y)
	label.size = size
	var pad := float(font_size) * 2.0
	content_size = size + Vector2(pad, pad)
	_master = Node2D.new()
	_master.position = content_size / 2.0
	add_child(_master)
	var ellipse := _ellipse_points(content_size)
	var stroke := Line2D.new()
	stroke.points = ellipse
	stroke.closed = true
	stroke.width = STROKE
	stroke.default_color = TEXT_COLOR
	_master.add_child(stroke)
	# The tip: base half the ellipse's height, long enough to reach past it.
	var tip_height := sqrt(pow(size.x / 2.0, 2) + pow(size.y / 2.0, 2)) + TIP_LENGTH + pad / 2.0
	var tip_base := content_size.y / 2.0
	var tip_pts := PackedVector2Array([Vector2(-tip_base / 2.0, 0), Vector2(0, -tip_height), Vector2(tip_base / 2.0, 0)])
	var angle := rad_to_deg(atan((size.x / 2.0) / maxf(1.0, size.y / 2.0)))
	var tip := Node2D.new()
	tip.rotation_degrees = (180.0 + angle) if tip_on_left else (180.0 - angle)
	var tip_fill := Polygon2D.new()
	tip_fill.polygon = tip_pts
	tip_fill.color = Color.WHITE
	tip.add_child(tip_fill)
	var tip_line := Line2D.new()
	tip_line.points = tip_pts
	tip_line.width = TIP_STROKE
	tip_line.default_color = TEXT_COLOR
	tip.add_child(tip_line)
	_master.add_child(tip)
	var fill := Polygon2D.new()
	fill.polygon = ellipse
	fill.color = Color.WHITE
	_master.add_child(fill)
	label.position = -size / 2.0
	_master.add_child(label)
	if animate:
		_master.scale = Vector2.ZERO
		var tw := create_tween()
		tw.tween_property(_master, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(_master, "scale", Vector2(1.2, 1.2), 0.0)
		tw.tween_property(_master, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)


static func _ellipse_points(size: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		pts.append(Vector2(cos(a) * size.x / 2.0, sin(a) * size.y / 2.0))
	return pts
