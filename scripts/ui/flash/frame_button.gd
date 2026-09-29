class_name FrameButton
extends Node2D
## The original popup frame buttons (PopupNascarButtonDecorator and
## PopupNasacarGraphicButtonDecorator): a 48 px tall code-drawn pill in a
## CarTownColor with an outline at 60% brightness and a soft inner shadow,
## centred on its position. The label is white Dom Diagonal Bold 22 px, or
## any node (e.g. a coin icon with text).

signal pressed

const HEIGHT := 48.0
## CarTownColor values.
const GREEN := 0x637F47
const GREY := 0x757B82
const BLUE := 0x35648C
const LIGHT_BLUE := 0x5B828F
const YELLOW := 0xDAAC38
const RED := 0x8C3A35

var _body: Node2D
var _tween: Tween


static func with_text(text: String, color: int) -> FrameButton:
	var label := FlashUi.styled_label(text, "casualA01", 22, Color.WHITE)
	return with_content(label, label.get_minimum_size(), color)


static func with_content(content: CanvasItem, content_size: Vector2, color: int) -> FrameButton:
	var b := FrameButton.new()
	b._build(content, content_size, color)
	return b


func _build(content: CanvasItem, content_size: Vector2, color: int) -> void:
	var width := maxf(content_size.x * 1.25, 80.0)
	var c := Color.hex((color << 8) | 0xFF)
	_body = Node2D.new()
	add_child(_body)
	var pill := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = c
	style.border_color = Color(c.r * 0.6, c.g * 0.6, c.b * 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(HEIGHT / 2.0))
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	style.shadow_offset = Vector2(3, 5)
	pill.add_theme_stylebox_override("panel", style)
	pill.size = Vector2(width, HEIGHT)
	pill.position = -pill.size / 2.0
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(pill)
	# The inner shadow along the bottom.
	var shade := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0, 0, 0, 0.15)
	ss.set_corner_radius_all(int(HEIGHT / 2.0))
	shade.add_theme_stylebox_override("panel", ss)
	shade.size = Vector2(width - 4, HEIGHT / 2.0)
	shade.position = Vector2(-width / 2.0 + 2, 0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(shade)
	if content is Control:
		(content as Control).position = -content_size / 2.0
	elif content is Node2D:
		(content as Node2D).position = -content_size / 2.0
	_body.add_child(content)
	var hit := Control.new()
	hit.size = pill.size
	hit.position = pill.position
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.mouse_entered.connect(func() -> void:
		Sound.play("RollOverSound01")
		_scale_to(1.1))
	hit.mouse_exited.connect(func() -> void: _scale_to(1.0))
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sound.play("ClickSound01")
			pressed.emit()
			hit.accept_event())
	add_child(hit)


func _scale_to(s: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_body, "scale", Vector2(s, s), 0.1)
