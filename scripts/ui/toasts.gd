class_name Toasts
extends VBoxContainer
## Short messages that float near the top and fade out ("Not enough coins.",
## "Picture saved"), in the game's white casual type with a dark glow.

const GLOW := Color8(0x23, 0x4F, 0x70)
const ERROR_GLOW := Color8(0x8C, 0x3A, 0x35)


func _ready() -> void:
	add_to_group("toasts")
	# Full width, 110 px down; each message is centred on its own line.
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_top = 110
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN


func show_message(text: String, is_error: bool = false) -> void:
	var l := FlashUi.styled_label(text, "casualA01", 26, Color.WHITE, ERROR_GLOW if is_error else GLOW, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


## Shows a message from anywhere.
static func say(tree: SceneTree, text: String, is_error: bool = false) -> void:
	var t := tree.get_first_node_in_group("toasts") as Toasts
	if t != null:
		t.show_message(text, is_error)
