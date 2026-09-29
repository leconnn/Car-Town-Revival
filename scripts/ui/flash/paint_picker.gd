class_name PaintPicker
extends Node2D
## The original paint ColorPicker (views/panels/colorpicker): a 68 x 20 grid
## of 5 px swatches (hue across, saturation down) on the ColorPickerPanel,
## a brightness slider that darkens towards black or lightens towards
## white, a preview swatch and the RGB / hex readouts.

signal color_changed(rgb: int)

const COLUMNS := 67
const ROWS := 19
const CELL := 5.0
const GRID_POS := Vector2(8, 12)
const SLIDER_TRAVEL := 70.0
const PREVIEW_POS := Vector2(606, 55)
const PREVIEW_SIZE := Vector2(58, 40)

var _panel: FlashSymbol
var _grid: Sprite2D
var _highlight: Line2D
var _handle: Node2D
var _handle_top := 0.0
var _preview: ColorRect
var _cell := Vector2i.ZERO
## 0 = black, 1 = pure colour, 2 = white (the original's value range).
var _brightness := 1.0
var _dragging := false


static func create(rgb: int) -> PaintPicker:
	var p := PaintPicker.new()
	p._build()
	p.select_closest(rgb)
	return p


func _build() -> void:
	_panel = FlashUi.make("ColorPickerPanel")
	if _panel == null:
		return
	add_child(_panel)
	var check := _panel.part("checkmark_btn") as CanvasItem
	if check != null:
		check.visible = false # hideCloseButton()
	var img := Image.create((COLUMNS + 1) * int(CELL) + 1, (ROWS + 1) * int(CELL) + 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	for row in ROWS + 1:
		for col in COLUMNS + 1:
			var c := _cell_color(col, row)
			img.fill_rect(Rect2i(col * int(CELL) + 1, row * int(CELL) + 1, int(CELL) - 1, int(CELL) - 1), c)
	_grid = Sprite2D.new()
	_grid.texture = ImageTexture.create_from_image(img)
	_grid.centered = false
	_grid.position = GRID_POS
	add_child(_grid)
	_highlight = Line2D.new()
	_highlight.width = 1.0
	_highlight.default_color = Color.WHITE
	_highlight.closed = true
	_highlight.points = PackedVector2Array([Vector2.ZERO, Vector2(CELL, 0), Vector2(CELL, CELL), Vector2(0, CELL)])
	add_child(_highlight)
	_handle = _panel.part("brightness_btn") as Node2D
	if _handle != null:
		_handle_top = _handle.position.y
	_preview = ColorRect.new()
	_preview.position = PREVIEW_POS
	_preview.size = PREVIEW_SIZE
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_preview)
	var hit := Control.new()
	hit.position = GRID_POS
	hit.size = Vector2((COLUMNS + 1) * CELL, (ROWS + 1) * CELL)
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(_on_grid_input)
	add_child(hit)
	if _handle != null:
		var slider := Control.new()
		slider.position = Vector2(_handle.position.x - 20, _handle_top - 10)
		slider.size = Vector2(40, SLIDER_TRAVEL + 20)
		slider.mouse_default_cursor_shape = Control.CURSOR_VSIZE
		slider.gui_input.connect(_on_slider_input)
		add_child(slider)


static func _cell_color(col: int, row: int) -> Color:
	return Color.from_hsv(float(col) / COLUMNS, 1.0 - float(row) / ROWS, 1.0)


func _on_grid_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT \
			or e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var p: Vector2 = e.position
		_cell = Vector2i(clampi(int(p.x / CELL), 0, COLUMNS), clampi(int(p.y / CELL), 0, ROWS))
		_changed()


func _on_slider_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
	if _dragging and (e is InputEventMouseButton or e is InputEventMouseMotion):
		var y: float = clampf(e.position.y - 10, 0, SLIDER_TRAVEL)
		_brightness = 2.0 - 2.0 * y / SLIDER_TRAVEL
		_changed()


## Picks the swatch nearest [param rgb] and the brightness that matches it.
func select_closest(rgb: int) -> void:
	var c := Color.hex((rgb << 8) | 0xFF)
	_cell = Vector2i(roundi(c.h * COLUMNS) % (COLUMNS + 1), roundi((1.0 - c.s) * ROWS))
	_brightness = c.v
	_changed(false)


func color() -> int:
	var c := _cell_color(_cell.x, _cell.y)
	if _brightness < 1.0:
		c = Color(c.r * _brightness, c.g * _brightness, c.b * _brightness)
	else:
		var add := _brightness - 1.0
		c = Color(minf(c.r + add, 1.0), minf(c.g + add, 1.0), minf(c.b + add, 1.0))
	return (c.r8 << 16) | (c.g8 << 8) | c.b8


func _changed(notify: bool = true) -> void:
	if _highlight != null:
		_highlight.position = GRID_POS + Vector2(_cell) * CELL
	if _grid != null:
		# The original tinted the whole grid with the brightness.
		_grid.modulate = Color(minf(_brightness, 1.0), minf(_brightness, 1.0), minf(_brightness, 1.0))
		_grid.self_modulate = Color.WHITE
	if _handle != null:
		_handle.position.y = _handle_top + (2.0 - _brightness) / 2.0 * SLIDER_TRAVEL
	var rgb := color()
	if _preview != null:
		_preview.color = Color.hex((rgb << 8) | 0xFF)
	if _panel != null:
		_panel.text("red_txt", str((rgb >> 16) & 0xFF))
		_panel.text("green_txt", str((rgb >> 8) & 0xFF))
		_panel.text("blue_txt", str(rgb & 0xFF))
		_panel.text("hex_txt", "%06X" % rgb)
	if notify:
		color_changed.emit(rgb)
