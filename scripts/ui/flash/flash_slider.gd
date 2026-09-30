class_name FlashSlider
extends Control
## A 0..1 slider in the game's look: a rounded groove with the original
## yellow slider knob (swcassets.btn.BtnSlider). Drag or click to set.

signal value_changed(value: float)

const GROOVE := Color8(0x9A, 0xAE, 0xC0)
const FILL := Color8(0x35, 0x64, 0x8C)
const GROOVE_HEIGHT := 8.0
const KNOB_SCALE := 1.3

var value := 0.0
var _knob: Node2D
var _dragging := false


static func create(width: float, start: float) -> FlashSlider:
	var s := FlashSlider.new()
	s.custom_minimum_size = Vector2(width, 28)
	s.size = s.custom_minimum_size
	s.value = clampf(start, 0.0, 1.0)
	return s


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var knob := FlashUi.make("swcassets.btn.BtnSlider")
	if knob != null:
		var r := knob.local_bounds()
		knob.position = -Vector2(r.position.x + r.size.x / 2.0, r.position.y) * KNOB_SCALE
		knob.scale = Vector2(KNOB_SCALE, KNOB_SCALE)
		_knob = Node2D.new()
		_knob.add_child(knob)
		add_child(_knob)
	_place_knob()


func _draw() -> void:
	var y := (size.y - GROOVE_HEIGHT) / 2.0 - 4
	var groove := StyleBoxFlat.new()
	groove.bg_color = GROOVE
	groove.set_corner_radius_all(int(GROOVE_HEIGHT / 2))
	draw_style_box(groove, Rect2(0, y, size.x, GROOVE_HEIGHT))
	var fill := groove.duplicate() as StyleBoxFlat
	fill.bg_color = FILL
	draw_style_box(fill, Rect2(0, y, maxf(GROOVE_HEIGHT, size.x * value), GROOVE_HEIGHT))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_set_from(event.position.x)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from(event.position.x)
		accept_event()


func _set_from(x: float) -> void:
	var v := clampf(x / maxf(1.0, size.x), 0.0, 1.0)
	if is_equal_approx(v, value):
		return
	value = v
	_place_knob()
	value_changed.emit(value)


func _place_knob() -> void:
	if _knob != null:
		_knob.position = Vector2(size.x * value, size.y / 2.0 - 2)
	queue_redraw()
