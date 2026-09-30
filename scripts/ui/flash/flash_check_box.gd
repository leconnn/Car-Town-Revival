class_name FlashCheckBox
extends Control
## The original check box (UICarCityCheckBox, its "check" shown when on),
## drawn larger, with a label to its right. Click either to toggle.

signal toggled(on: bool)

const BOX_SCALE := 2.0

var on := false
var _box: FlashSymbol


static func create(text: String, start: bool, color: Color) -> FlashCheckBox:
	var c := FlashCheckBox.new()
	c.on = start
	c._build(text, color)
	return c


func _build(text: String, color: Color) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var holder := Node2D.new()
	add_child(holder)
	_box = FlashUi.make("UICarCityCheckBox")
	var box_size := Vector2(26, 26)
	if _box != null:
		var r := _box.local_bounds()
		_box.scale = Vector2(BOX_SCALE, BOX_SCALE)
		_box.position = -r.position * BOX_SCALE
		box_size = r.size * BOX_SCALE
		holder.add_child(_box)
	var label := FlashUi.styled_label(text, "casualA01", 22, color)
	label.position = Vector2(box_size.x + 10, (box_size.y - label.get_minimum_size().y) / 2.0)
	add_child(label)
	custom_minimum_size = Vector2(label.position.x + label.get_minimum_size().x, maxf(box_size.y, label.get_minimum_size().y))
	size = custom_minimum_size
	_show()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		on = not on
		_show()
		Sound.play("ClickSound01")
		toggled.emit(on)
		accept_event()


func _show() -> void:
	if _box == null:
		return
	var check := _box.part("check") as CanvasItem
	if check != null:
		check.visible = on
