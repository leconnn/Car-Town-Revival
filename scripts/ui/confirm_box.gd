class_name ConfirmBox
extends ConfirmationDialog
## Yes/no question before something can't be undone.


static func ask(from: Node, question: String, on_yes: Callable) -> void:
	var d := ConfirmBox.new()
	d.dialog_text = question
	d.ok_button_text = "Yes"
	d.cancel_button_text = "No"
	d.confirmed.connect(on_yes)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	from.get_tree().root.add_child(d)
	d.popup_centered()
