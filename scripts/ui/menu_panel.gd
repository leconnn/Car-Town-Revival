class_name MenuPanel
extends GamePanel
## In-game menu: settings, credits, save and quit.


func _init() -> void:
	title = "Menu"


func _on_state_changed() -> void:
	pass


func _build() -> void:
	var s := Backend.state()
	body.add_child(UiKit.label("Playing as %s  ·  Your game saves automatically." % s["player"]["name"], 17))
	body.add_child(SettingsBox.new())
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Credits", func() -> void: get_tree().current_scene.open_panel(CreditsPanel.new())))
	row.add_child(UiKit.button("Save & quit to title", func() -> void: Backend.end_session("menu")))
	body.add_child(row)
	if Backend.mode() == "online":
		var account := UiKit.hbox()
		account.add_child(UiKit.button("Sign out", func() -> void:
			Online.sign_out()
			Backend.end_session("menu")))
		account.add_child(UiKit.button("Delete my account", func() -> void:
			ConfirmBox.ask(self, "Delete your online account and garage for good? This can't be undone.", func() -> void:
				var err: String = await Online.delete_account()
				if err != "":
					toast(err)
				else:
					Backend.end_session("Your account was deleted."))))
		body.add_child(account)



class SettingsBox:
	extends VBoxContainer

	func _ready() -> void:
		add_theme_constant_override("separation", 8)
		var fs := CheckBox.new()
		fs.text = "Fullscreen"
		fs.button_pressed = Settings.fullscreen
		fs.toggled.connect(func(on: bool) -> void:
			Settings.fullscreen = on
			Settings.apply()
			Settings.save())
		add_child(fs)
		add_child(_slider("Music volume", Settings.music_volume, func(v: float) -> void: Settings.music_volume = v))
		add_child(_slider("Sound effects", Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v))

	func _slider(text: String, value: float, setter: Callable) -> Control:
		var row := UiKit.hbox()
		var l := UiKit.label(text, 16)
		l.custom_minimum_size = Vector2(160, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 1
		s.step = 0.05
		s.value = value
		s.custom_minimum_size = Vector2(240, 20)
		s.value_changed.connect(func(v: float) -> void:
			setter.call(v)
			Settings.apply()
			Settings.save())
		row.add_child(s)
		return row


class CreditsPanel:
	extends GamePanel

	func _init() -> void:
		title = "Credits"

	func _on_state_changed() -> void:
		pass

	func _build() -> void:
		var text := FileAccess.get_file_as_string("res://CREDITS.md")
		var rt := RichTextLabel.new()
		rt.text = text
		rt.fit_content = false
		rt.scroll_active = true
		rt.custom_minimum_size = Vector2(700, 480)
		rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(rt)
