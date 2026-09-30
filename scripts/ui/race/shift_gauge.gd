class_name ShiftGauge
extends Node2D
## The shift gauge (views/racing/shiftcontrol/ShiftGauge), drawn the way the
## original drew it in code: a grey ring, a dark dial with a green bonus
## wedge and a dark red redline, an orange needle and the round GO button in
## the middle. The needle's [member needle_degrees] runs clockwise from
## straight down, like the original's Sprite rotation.

## Fired when the button is pressed (on mouse down, like the original).
signal pressed

const DIAMETER := 153.0
const OUTER := DIAMETER / 2.0
const INNER := 145.0 / 2.0
const RING_COLOR := Color8(0xCB, 0xCB, 0xCB)
const DIAL_COLOR := Color8(0x3C, 0x3C, 0x3C)
const BONUS_COLOR := Color8(0x00, 0xFF, 0x00)
const REDLINE_COLOR := Color8(0x4E, 0x05, 0x05)
const NEEDLE_COLOR := Color8(0xFF, 0x7F, 0x29)
const HUB_COLOR := Color8(0xCC, 0xCC, 0xCC)
const HUB_CENTER := Color8(0x55, 0x00, 0x00)
const TEXT_GLOW := Color8(0x23, 0x4F, 0x70)
const OVER_BRIGHTEN := 35.0 / 255.0

var needle_degrees := 0.0:
	set(v):
		needle_degrees = v
		queue_redraw()
var _button: Node2D
var _label: Label
var _hit: Control
var _active := false


func _ready() -> void:
	var center := Vector2(OUTER, OUTER)
	_button = Node2D.new()
	_button.position = center
	_button.visible = false
	add_child(_button)
	var tex := GameData.main_texture("swcassets.race.BtnGo")
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		_button.add_child(s)
	_label = FlashUi.styled_label(" ", "casualA01", 30, Color.WHITE, TEXT_GLOW, 5)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(88, 40)
	_label.position = Vector2(-44, -22)
	_button.add_child(_label)
	_hit = Control.new()
	_hit.position = center - Vector2(44, 44)
	_hit.size = Vector2(88, 88)
	_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hit.gui_input.connect(_on_hit_input)
	_hit.mouse_entered.connect(func() -> void:
		_button.modulate = Color(1 + OVER_BRIGHTEN, 1 + OVER_BRIGHTEN, 1 + OVER_BRIGHTEN))
	_hit.mouse_exited.connect(func() -> void: _button.modulate = Color.WHITE)
	add_child(_hit)


func _draw() -> void:
	var c := Vector2(OUTER, OUTER)
	draw_circle(c + Vector2(1, 2), OUTER, Color(0, 0, 0, 0.35))
	draw_circle(c, OUTER, RING_COLOR)
	draw_circle(c, INNER, DIAL_COLOR)
	_wedge(c, RaceRules.BONUS_STARTS, RaceRules.BONUS_ENDS, BONUS_COLOR)
	_wedge(c, RaceRules.BONUS_ENDS, 360.0, REDLINE_COLOR)
	draw_set_transform(c, deg_to_rad(needle_degrees))
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -18), Vector2(3, -18), Vector2(0.5, 80), Vector2(-0.5, 80)]), NEEDLE_COLOR)
	draw_circle(Vector2.ZERO, 18, HUB_COLOR)
	draw_circle(Vector2.ZERO, 15, HUB_CENTER)
	draw_set_transform(Vector2.ZERO)


## A pie slice of the dial between two needle angles.
func _wedge(c: Vector2, from_deg: float, to_deg: float, color: Color) -> void:
	var pts := PackedVector2Array([c])
	var a := from_deg
	while a < to_deg:
		pts.append(c + _dial_point(a))
		a += 1.0
	pts.append(c + _dial_point(to_deg))
	if pts.size() > 2:
		draw_colored_polygon(pts, color)


static func _dial_point(deg: float) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(-INNER * sin(r), INNER * cos(r))


func set_text(text: String) -> void:
	_label.text = text


## Pops the button in.
func activate() -> void:
	_active = true
	_button.visible = true
	_button.scale = Vector2(0.2, 0.2)
	create_tween().tween_property(_button, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func deactivate() -> void:
	_active = false
	_button.visible = false


func _on_hit_input(event: InputEvent) -> void:
	if _active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		_hit.accept_event()


## Testing aid: a click without the mouse.
func simulate_click() -> void:
	if _active:
		pressed.emit()
