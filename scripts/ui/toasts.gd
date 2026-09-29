class_name Toasts
extends VBoxContainer
## Short messages that fade out (errors, "Bought!", ...).


func _ready() -> void:
	add_to_group("toasts")
	UiKit.place(self, Rect2(0.5, 0, 0.5, 0), Rect2(0, 90, 0, 90))
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN


func show_message(text: String, is_error: bool = false) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 20, Color(1, 0.75, 0.7) if is_error else Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	add_child(panel)
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)


## Shows a message from anywhere (panels use this).
static func say(tree: SceneTree, text: String, is_error: bool = false) -> void:
	var t := tree.get_first_node_in_group("toasts") as Toasts
	if t != null:
		t.show_message(text, is_error)
