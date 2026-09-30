class_name GenericPopup
extends Node2D
## The original GenericPopup (views/GenericPopup): a big white title glowing
## blue over a white rounded panel, the content centred on the panel, and
## frame buttons on the panel's bottom edge. Used for questions ("Sell your
## car?") and short messages.

const TITLE_SIZE := 40
const TITLE_GLOW := Color8(0x23, 0x4F, 0x70)
const TEXT_COLOR := Color8(0x33, 0x4D, 0x66)
const PANEL_POS := Vector2(25, 60)
const MESSAGE_WIDTH := 420.0
const BUTTON_GAP := 10.0

var popup: FlashPopup


## A message with OK.
static func message(tree: SceneTree, title: String, text: String) -> GenericPopup:
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var p := _open(tree, title, _message_label(text), [ok])
	ok.pressed.connect(p.close)
	return p


## A yes/no question; [param on_yes] runs after the popup closes.
static func ask(tree: SceneTree, title: String, text: String, yes_text: String, on_yes: Callable,
		no_text: String = "Cancel") -> GenericPopup:
	var yes := FrameButton.with_text(yes_text, FrameButton.GREEN)
	var no := FrameButton.with_text(no_text, FrameButton.GREY)
	var p := _open(tree, title, _message_label(text), [yes, no])
	yes.pressed.connect(func() -> void:
		p.close()
		on_yes.call())
	no.pressed.connect(p.close)
	return p


## Any content, [param content_size] big, on a panel that fits it.
static func custom(tree: SceneTree, title: String, content: CanvasItem, content_size: Vector2,
		buttons: Array = []) -> GenericPopup:
	var holder := Node2D.new()
	holder.add_child(content)
	holder.set_meta("size", content_size)
	return _open(tree, title, holder, buttons)


func close() -> void:
	if popup != null:
		popup.close()


static func _message_label(text: String) -> Node2D:
	var label := FlashUi.styled_label(text, "casualA01", 22, TEXT_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(MESSAGE_WIDTH, 0)
	label.size = Vector2(MESSAGE_WIDTH, 0)
	var holder := Node2D.new()
	holder.add_child(label)
	holder.set_meta("size", Vector2(MESSAGE_WIDTH, label.get_minimum_size().y))
	return holder


static func _open(tree: SceneTree, title: String, content: Node2D, buttons: Array) -> GenericPopup:
	var g := GenericPopup.new()
	var content_size: Vector2 = content.get_meta("size", Vector2(MESSAGE_WIDTH, 100))
	var panel_size := Vector2(maxf(476.0, content_size.x + 56), content_size.y + 84)
	var panel := FlashNine.make("UIWhiteStrokedRoundedBg", panel_size)
	panel.position = PANEL_POS
	g.add_child(panel)
	var head := FlashUi.styled_label(title, "casualA01", TITLE_SIZE, Color.WHITE, TITLE_GLOW, 6)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.size = Vector2(panel_size.x, 50)
	head.position = Vector2(PANEL_POS.x, 4)
	g.add_child(head)
	content.position = PANEL_POS + ((panel_size - content_size) / 2.0).floor() + Vector2(0, -12)
	g.add_child(content)
	# The buttons straddle the panel's bottom edge, side by side.
	var total := 0.0
	for b: Node2D in buttons:
		total += FlashNine.bounds(b).size.x
	total += BUTTON_GAP * maxf(0, buttons.size() - 1)
	var x := PANEL_POS.x + (panel_size.x - total) / 2.0
	for b: Node2D in buttons:
		var w := FlashNine.bounds(b).size.x
		b.position = Vector2(x + w / 2.0, PANEL_POS.y + panel_size.y)
		g.add_child(b)
		x += w + BUTTON_GAP
	var frame := Vector2(PANEL_POS.x * 2 + panel_size.x, PANEL_POS.y + panel_size.y + 45)
	g.popup = FlashPopup.open(tree, g, true, false, frame)
	return g
