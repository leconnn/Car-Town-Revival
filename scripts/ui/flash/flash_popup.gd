class_name FlashPopup
extends CanvasLayer
## The original's popups: a 70% black cover over the whole screen and a
## UIBgFrame around the content, centred on the 760 x 700 stage, with a red
## close button 10 px in from the top-right.
##
## open():        the legacy AbstractPopup: frame = content + 20 px each side,
##                or a fixed size with the content at the frame's origin.
## open_framed(): the newer decorated popups (PopupSimpleFrameDecorator):
##                custom padding per side (negative lets content poke out of
##                the frame) and buttons centred on the frame's bottom edge.

signal closed

const OFFSET := 20.0
const COVER_ALPHA := 0.7
const BUTTON_SPACING := 25.0

var content: Node2D
var _stage: StageUi
var _body: Node2D
var _fixed_size := Vector2.ZERO


static func open(tree: SceneTree, node: Node2D, show_close: bool = true, red_frame: bool = false,
		fixed_size: Vector2 = Vector2.ZERO, buttons: Array = []) -> FlashPopup:
	var p := FlashPopup.new()
	p._fixed_size = fixed_size
	return _add(p, tree, node, [OFFSET, OFFSET, OFFSET, OFFSET], buttons, show_close, red_frame, true)


## [param pad] is [top, right, bottom, left] like the original decorator.
static func open_framed(tree: SceneTree, node: Node2D, pad: Array, buttons: Array = [], show_close: bool = true) -> FlashPopup:
	return _make(tree, node, pad, buttons, show_close, false, false)


static func _make(tree: SceneTree, node: Node2D, pad: Array, buttons: Array, show_close: bool, red_frame: bool, legacy: bool) -> FlashPopup:
	return _add(FlashPopup.new(), tree, node, pad, buttons, show_close, red_frame, legacy)


static func _add(p: FlashPopup, tree: SceneTree, node: Node2D, pad: Array, buttons: Array, show_close: bool, red_frame: bool, legacy: bool) -> FlashPopup:
	p.layer = 10
	p.content = node
	tree.current_scene.add_child(p)
	p._build(pad, buttons, show_close, red_frame, legacy)
	return p


func _build(pad: Array, buttons: Array, show_close: bool, red_frame: bool, legacy: bool) -> void:
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, COVER_ALPHA)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	_stage = StageUi.new()
	add_child(_stage)
	_body = Node2D.new()
	var top: float = pad[0]
	var right: float = pad[1]
	var bottom: float = pad[2]
	var left: float = pad[3]
	var b := FlashNine.bounds(content)
	var size := Vector2(b.size.x + left + right, b.size.y + top + bottom)
	# AbstractPopup with a width/height: content at the frame's origin.
	if _fixed_size.x > 0:
		size.x = _fixed_size.x
		left = 0
	if _fixed_size.y > 0:
		size.y = _fixed_size.y
		top = 0
	var frame := FlashNine.make("UIBgRedFrame" if red_frame else "UIBgFrame", size)
	_body.add_child(frame)
	# The legacy popup put the content's origin at (20, 20) whatever its
	# bounds (so e.g. a job icon at y -30 pokes out of the frame); the newer
	# decorators align the content's bounds with the padding.
	content.position = Vector2(left, top) if legacy else Vector2(left, top) - b.position
	_body.add_child(content)
	if show_close:
		var x := close_button()
		x.pressed.connect(close)
		x.position = Vector2(size.x - x.size().x - 10, 10)
		_body.add_child(x)
	if not buttons.is_empty():
		var widths: Array[float] = []
		var total := 0.0
		for btn: Node2D in buttons:
			var w := FlashNine.bounds(btn).size.x
			widths.append(w)
			total += w
		total += BUTTON_SPACING * (buttons.size() - 1)
		var x := (size.x - total) / 2.0
		for i in buttons.size():
			var btn: Node2D = buttons[i]
			btn.position = Vector2(x + widths[i] / 2.0, size.y)
			_body.add_child(btn)
			x += widths[i] + BUTTON_SPACING
	_stage.center.add_child(_body)
	_body.position = ((StageUi.STAGE - size) / 2.0).floor()
	_body.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_body, "modulate:a", 1.0, 0.15)
	Sound.play("PopUpSound01")


## The original IconButton.CLOSE_BUTTON: red pill with the close symbol.
static func close_button() -> FlashTextButton:
	var b := FlashTextButton.create("", FlashTextButton.Kind.RED, 34, 32, 18)
	var sym := FlashUi.make("UISymbolClose")
	if sym != null:
		var r := sym.local_bounds()
		sym.position = (b.size() - r.size) / 2.0 - r.position
		b.get_child(0).add_child(sym)
	return b


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
