class_name GamePanel
extends PanelContainer
## Base for the game's windows: a title bar with a close button and a body.
## Subclasses fill [member body] in _build() and may rebuild on state change.

signal closed

var title: String = ""
var body: VBoxContainer
var _title_label: Label


func _ready() -> void:
	var outer := UiKit.vbox(10)
	add_child(outer)
	var bar := UiKit.hbox()
	_title_label = UiKit.label(title, 26, Color(1, 0.93, 0.6))
	bar.add_child(_title_label)
	bar.add_child(UiKit.spacer())
	bar.add_child(UiKit.button("✕", close, 18))
	outer.add_child(bar)
	body = UiKit.vbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	_build()
	Backend.state_changed.connect(_on_state_changed)


func set_title(text: String) -> void:
	title = text
	if _title_label != null:
		_title_label.text = text


func toast(text: String) -> void:
	Toasts.say(get_tree(), text)


func close() -> void:
	closed.emit()
	queue_free()


## Override: fill [member body].
func _build() -> void:
	pass


## Override to refresh when the save changes. Default rebuilds everything.
func _on_state_changed() -> void:
	UiKit.clear(body)
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
