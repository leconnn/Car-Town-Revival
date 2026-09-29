class_name FlashComboBox
extends Node2D
## The original CarTownComboBox (a Flash ComboBox with the game's skins):
## 185 x 28, Dom Diagonal Bold 16 px in #447FA2, a drop-down list of
## CellRenderer rows.

signal selected(index: int)

const TEXT_COLOR := Color8(0x44, 0x7F, 0xA2)
const ROW_H := 22.0

var items: PackedStringArray = []
var index := 0
var _size: Vector2
var _label: Label
var _list: Node2D


static func create(labels: PackedStringArray, w: float = 185.0, h: float = 28.0) -> FlashComboBox:
	var c := FlashComboBox.new()
	c.items = labels
	c._size = Vector2(w, h)
	c._build()
	return c


func _build() -> void:
	add_child(FlashNine.make("ComboBox_upSkin", _size))
	_label = FlashUi.styled_label("", "casualA01", 16, TEXT_COLOR)
	_label.position = Vector2(4 + 2, 3)
	add_child(_label)
	var hit := Control.new()
	hit.size = _size
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sound.play("ClickSound01")
			_toggle_list()
			hit.accept_event())
	add_child(hit)
	select(0, false)


func select(i: int, notify: bool = true) -> void:
	index = clampi(i, 0, items.size() - 1)
	_label.text = items[index] if not items.is_empty() else ""
	if notify:
		selected.emit(index)


func _toggle_list() -> void:
	if _list != null:
		_list.queue_free()
		_list = null
		return
	_list = Node2D.new()
	_list.position.y = _size.y
	_list.z_index = 10
	for i in items.size():
		var row := FlashNine.make("CellRenderer_upSkin", Vector2(_size.x, ROW_H))
		row.position.y = i * ROW_H
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var label := FlashUi.styled_label(items[i], "casualA01", 16, TEXT_COLOR)
		label.position = Vector2(6, 1)
		row.add_child(label)
		row.mouse_entered.connect(func() -> void: row.modulate = Color(0.85, 0.92, 1.0))
		row.mouse_exited.connect(func() -> void: row.modulate = Color.WHITE)
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Sound.play("ClickSound01")
				_list.queue_free()
				_list = null
				select(i)
				row.accept_event())
		_list.add_child(row)
	add_child(_list)
