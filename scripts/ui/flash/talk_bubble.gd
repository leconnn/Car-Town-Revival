class_name TalkBubble
extends Node2D
## The original TextBubble: centred Dom Diagonal Bold text (#767676, 20 px)
## in a white speech bubble, wrapping at a maximum width. Centred on its
## position, with the tail pointing down-right towards the speaker.

const TEXT_COLOR := Color8(0x76, 0x76, 0x76)


static func create(text: String, max_width: float = 300.0, size: int = 20) -> TalkBubble:
	var b := TalkBubble.new()
	b._build(text, max_width, size)
	return b


func _build(text: String, max_width: float, font_size: int) -> void:
	var label := FlashUi.styled_label(text, "casualA01", font_size, TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.label_settings.line_spacing = -6
	var size := label.get_minimum_size()
	if size.x > max_width:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(max_width, 0)
		size = label.get_minimum_size()
	label.size = size
	label.position = -size / 2.0
	var pad := Vector2(24, 20)
	var r := maxf(size.x, size.y) / 2.0 + pad.x
	var bubble := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		pts.append(Vector2(cos(a) * (size.x / 2.0 + pad.x), sin(a) * (size.y / 2.0 + pad.y)))
	bubble.polygon = pts
	bubble.color = Color.WHITE
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(r * 0.25, size.y / 2.0 + pad.y - 8),
		Vector2(r * 0.7, size.y / 2.0 + pad.y + 26), Vector2(r * 0.55, size.y / 2.0 + pad.y - 14)])
	tail.color = Color.WHITE
	var outline := Line2D.new()
	outline.width = 2.0
	outline.default_color = Color(0.2, 0.2, 0.2)
	outline.closed = true
	outline.points = pts
	add_child(outline)
	add_child(tail)
	add_child(bubble)
	add_child(label)
