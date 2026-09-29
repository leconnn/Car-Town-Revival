class_name FlashButton
extends Node2D
## The original GameButton: wraps a symbol, grows 20% on hover (0.1 s,
## ease out) around its origin, and clicks.

signal pressed

const OVERSCALE := 1.2
const ANIM := 0.1

var body: Node2D
var base_scale := 1.0
var over_scale := OVERSCALE
var _hit: Control
var _tween: Tween


## Wraps a FlashSymbol (or any Node2D with a known hit rect).
static func wrap_node(node: Node2D, hit_rect: Rect2 = Rect2()) -> FlashButton:
	var b := FlashButton.new()
	b.body = node
	b.add_child(node)
	var rect := hit_rect
	if rect.size == Vector2.ZERO and node is FlashSymbol:
		rect = (node as FlashSymbol).local_bounds()
	b._make_hit(rect)
	return b


## A GameButton around a library symbol, with an optional label for its "fld".
static func of(class_name_: String, label: String = "", field: String = "fld") -> FlashButton:
	var s := FlashUi.make(class_name_)
	if s == null:
		return null
	if label != "":
		s.text(field, label)
	return wrap_node(s)


func _make_hit(rect: Rect2) -> void:
	_hit = Control.new()
	_hit.position = rect.position
	_hit.size = rect.size
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hit.mouse_entered.connect(_over)
	_hit.mouse_exited.connect(_out)
	_hit.gui_input.connect(_on_input)
	add_child(_hit)


func set_base_scale(s: float, over: float = OVERSCALE) -> void:
	base_scale = s
	over_scale = over
	scale = Vector2(s, s)


func _over() -> void:
	Sound.play("RollOverSound01")
	_animate(over_scale)


func _out() -> void:
	_animate(base_scale)


func _animate(to: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "scale", Vector2(to, to), ANIM)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Sound.play("ClickSound01")
		pressed.emit()
		_hit.accept_event()
