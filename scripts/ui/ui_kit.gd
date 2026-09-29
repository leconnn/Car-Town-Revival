class_name UiKit
extends RefCounted
## Small helpers for building UI in code.


static func label(text: String, size: int = 18, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable = Callable(), size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func texture_rect(tex: Texture2D, max_size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = max_size
	return t


static func scroll(child: Control, min_size: Vector2) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.custom_minimum_size = min_size
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Sets anchors (0..1) and pixel offsets in one go.
static func place(c: Control, anchors: Rect2, offsets: Rect2 = Rect2()) -> void:
	c.anchor_left = anchors.position.x
	c.anchor_top = anchors.position.y
	c.anchor_right = anchors.size.x
	c.anchor_bottom = anchors.size.y
	c.offset_left = offsets.position.x
	c.offset_top = offsets.position.y
	c.offset_right = offsets.size.x
	c.offset_bottom = offsets.size.y


static func clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()


## Coin/blue price label: "1,200" with a coloured prefix.
static func price_label(coins: int, blue: int, use_blue: bool, size: int = 16) -> Label:
	if use_blue:
		return label("◆ %s" % Format.number(blue), size, Color(0.55, 0.85, 1.0))
	return label("● %s" % Format.number(coins), size, Color(1.0, 0.85, 0.3))
