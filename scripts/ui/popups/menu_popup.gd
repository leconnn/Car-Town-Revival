class_name MenuPopup
extends RefCounted
## The in-game menu (the HUD's Menu button) and the settings and credits
## shared with the title screen, drawn as the original's GenericPopup.

const ROW_WIDTH := 420.0
const LABEL_WIDTH := 170.0
const ROW_GAP := 14.0


## Settings, and the buttons to see the credits or leave the game.
static func open(tree: SceneTree) -> GenericPopup:
	var s := Backend.state()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(ROW_GAP))
	var who := FlashUi.styled_label("Playing as %s. Your game saves by itself." % s["player"]["name"],
		"casualA01", 20, GenericPopup.TEXT_COLOR)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.custom_minimum_size = Vector2(ROW_WIDTH, 0)
	box.add_child(who)
	box.add_child(settings_content())
	var credits := FrameButton.with_text("Credits", FrameButton.BLUE)
	var quit := FrameButton.with_text("Quit to Title", FrameButton.RED)
	var buttons: Array = [credits, quit]
	var sign_out: FrameButton = null
	var delete: FrameButton = null
	if Backend.mode() == "online":
		sign_out = FrameButton.with_text("Sign Out", FrameButton.GREY)
		delete = FrameButton.with_text("Delete Account", FrameButton.GREY)
		buttons.append_array([sign_out, delete])
	var p := GenericPopup.custom(tree, "Menu", box, _size_of(box), buttons)
	credits.pressed.connect(func() -> void: open_credits(tree))
	quit.pressed.connect(func() -> void:
		p.close()
		Backend.end_session("menu"))
	if sign_out != null:
		sign_out.pressed.connect(func() -> void:
			p.close()
			Online.sign_out()
			Backend.end_session("menu"))
		delete.pressed.connect(func() -> void:
			GenericPopup.ask(tree, "Delete Account", "Delete your online account and garage for good? This can't be undone.",
				"Delete", func() -> void:
					var err: String = await Online.delete_account()
					if err != "":
						GenericPopup.message(tree, "Oops!", err)
					else:
						Backend.end_session("Your account was deleted.")))
	return p


## Music and sound volume, and fullscreen.
static func settings_content() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(ROW_GAP))
	box.add_child(_slider_row("Music", Settings.music_volume, func(v: float) -> void: Settings.music_volume = v))
	box.add_child(_slider_row("Sound Effects", Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v))
	var fs := FlashCheckBox.create("Fullscreen", Settings.fullscreen, GenericPopup.TEXT_COLOR)
	fs.toggled.connect(func(on: bool) -> void:
		Settings.fullscreen = on
		Settings.apply()
		Settings.save())
	box.add_child(fs)
	return box


static func _slider_row(text: String, value: float, setter: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := FlashUi.styled_label(text, "casualA01", 22, GenericPopup.TEXT_COLOR)
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(label)
	var slider := FlashSlider.create(ROW_WIDTH - LABEL_WIDTH - 20, value)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		Settings.apply()
		Settings.save())
	row.add_child(slider)
	return row


## CREDITS.md in a scrolling box.
static func open_credits(tree: SceneTree) -> GenericPopup:
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	# The popup's title stands in for the file's own "# Credits" heading.
	var md := FileAccess.get_file_as_string("res://CREDITS.md").strip_edges()
	if md.begins_with("# "):
		md = md.substr(md.find("
") + 1)
	text.text = _credits_bbcode(md)
	text.custom_minimum_size = Vector2(520, 330)
	text.size = text.custom_minimum_size
	text.scroll_active = true
	text.add_theme_font_override("normal_font", FlashUi.style_font("sansD01"))
	text.add_theme_font_override("bold_font", FlashUi.style_font("casualA01"))
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 22)
	text.add_theme_color_override("default_color", GenericPopup.TEXT_COLOR)
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var p := GenericPopup.custom(tree, "Credits", text, text.size, [ok])
	ok.pressed.connect(p.close)
	return p


## Just enough Markdown for the credits: headings, bullets, bold, links.
static func _credits_bbcode(md: String) -> String:
	var out: PackedStringArray = []
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var link := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	for line: String in md.split("\n"):
		var l := line.strip_edges(false, true)
		l = link.sub(l, "$1", true)
		l = bold.sub(l, "$1", true)
		if l.begins_with("#"):
			out.append("[b]%s[/b]" % l.lstrip("# "))
		elif l.begins_with("- ") or l.begins_with("* "):
			out.append("  •  " + l.substr(2))
		else:
			out.append(l)
	return "\n".join(out).strip_edges()


static func _size_of(c: Control) -> Vector2:
	return c.get_combined_minimum_size()
