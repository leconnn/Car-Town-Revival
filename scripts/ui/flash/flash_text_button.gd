class_name FlashTextButton
extends Node2D
## The original TextButton: a coloured pill (UIIconButtonBody*) stretched to
## size, with a white Dom Diagonal Bold label. Grows 20% on hover.

signal pressed

enum Kind { GREEN, YELLOW, RED, BLUE, GRAY }

const BODIES := ["UIIconButtonBodyGreen", "UIIconButtonBodyYellow", "UIIconButtonBodyRed",
	"UIIconButtonBodyBlue", "UIIconButtonBodyGray"]
const SQUARE_BODIES := ["UIIconSquareButtonBodyGreen", "UIIconSquareButtonBodyYellow",
	"UIIconSquareButtonBodyRed", "UIIconSquareButtonBodyBlue", "UIIconSquareButtonBodyGray"]
const OFFSET := 5.0
const OVERSCALE := 1.2
const ANIM := 0.1

var kind: Kind
var _body: Node2D
var _size := Vector2.ZERO
var _tween: Tween
var _label: Label
var _disabled := false


## Like the original constructor: label, colour, width, height, font size,
## and an optional icon drawn left of the label.
static func create(text: String, color: Kind, w: float, h: float, font_size: int = 22,
		square: bool = false, icon: Node2D = null) -> FlashTextButton:
	var b := FlashTextButton.new()
	b.kind = color
	b._build(text, w, h, font_size, square, icon)
	return b


func _build(text: String, w: float, h: float, font_size: int, square: bool, icon: Node2D = null) -> void:
	_body = Node2D.new()
	add_child(_body)
	var pill := FlashUi.make((SQUARE_BODIES if square else BODIES)[kind])
	_label = FlashUi.styled_label(text, "casualA01", font_size, Color.WHITE)
	var text_size := _label.get_minimum_size()
	var icon_w := 0.0
	if icon != null:
		var ib := FlashNine.bounds(icon)
		icon_w = ib.size.x + 1
		icon.position = Vector2(-ib.position.x, int((text_size.y - ib.size.y) * 0.5) - ib.position.y)
	text_size.x += icon_w
	var width := maxf(w, text_size.x + OFFSET * 2)
	var height := maxf(h, text_size.y + OFFSET * 2)
	_size = Vector2(width, height)
	if pill != null:
		var r := pill.local_bounds()
		pill.scale = Vector2(width / maxf(r.size.x, 1.0), height / maxf(r.size.y, 1.0))
		pill.position = -r.position * pill.scale
		_body.add_child(pill)
	else:
		var fallback := Panel.new()
		fallback.size = _size
		_body.add_child(fallback)
	var content := Node2D.new()
	content.position = ((_size - text_size) / 2.0).floor()
	_body.add_child(content)
	if icon != null:
		content.add_child(icon)
	_label.position = Vector2(icon_w, 0)
	content.add_child(_label)
	var hit := Control.new()
	hit.size = _size
	hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.mouse_entered.connect(_over)
	hit.mouse_exited.connect(_out)
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if not _disabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			Sound.play("ClickSound02" if kind == Kind.RED else "ClickSound01")
			pressed.emit()
			hit.accept_event())
	add_child(hit)


func size() -> Vector2:
	return _size


func set_disabled(on: bool) -> void:
	_disabled = on
	modulate = Color(0.6, 0.6, 0.6) if on else Color.WHITE


func set_text(text: String) -> void:
	_label.text = text


func _over() -> void:
	if _disabled:
		return
	Sound.play("RollOverSound01")
	_animate(OVERSCALE)


func _out() -> void:
	_animate(1.0)


## The original scaled the body around its centre.
func _animate(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_body, "scale", Vector2(to, to), ANIM)
	_tween.tween_property(_body, "position", _size * (1.0 - to) / 2.0, ANIM)
