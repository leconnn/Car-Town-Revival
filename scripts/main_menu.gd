extends Control
## Title screen: pick a mode and a save slot. Dressed like the original's
## loading screen (preloader.swf): the Car Town logo over the yellow
## sunburst, with the choices on a tan board below.
##
## Command line (for testing): -- autostart=<slot> [newgame=<name>] [title=<page>]

const SAVE_FOLDER := "user://saves/single"
const BOARD_WIDTH := 660.0
const LOGO_HEIGHT := 250.0
const TEXT_COLOR := Color8(0x4A, 0x36, 0x1E)
const NOTE_COLOR := Color8(0x7A, 0x5E, 0x3A)
const FOOTER_GLOW := Color8(0x8A, 0x5A, 0x10)

var _store: SaveStore
var _content: VBoxContainer
var _toasts: Toasts


func _ready() -> void:
	Settings.load_and_apply()
	Sound.music("mainLoop")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	_store = SaveStore.new(SAVE_FOLDER)
	_build_backdrop()
	_toasts = Toasts.new()
	add_child(_toasts)
	if Engine.has_meta("title_message"):
		_toasts.show_message.call_deferred(str(Engine.get_meta("title_message")), true)
		Engine.remove_meta("title_message")
	if not GameData.is_loaded():
		_show_error(GameData.load_error)
		return
	var args := _args()
	if args.has("autostart"):
		var slot := int(args["autostart"])
		if args.has("newgame") or not _store.exists(slot):
			_start_new.call_deferred(slot, args.get("newgame", "Tester"))
		else:
			_continue.call_deferred(slot)
		return
	match args.get("title", ""):
		"slots": _show_slots()
		"name": _ask_name(0)
		"lan": _show_lan()
		"host": _show_host()
		"new_world": _new_world(0)
		"join": _show_join()
		"settings": _show_settings()
		_: _show_modes()
	DevShot.maybe_capture(self)


func _args() -> Dictionary:
	var out := {}
	for a: String in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


# --- Look --------------------------------------------------------------------------

func _build_backdrop() -> void:
	var bg := TextureRect.new()
	bg.texture = GameData.texture(GameData.title_art.get("bg", {}).get("file", ""))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if bg.texture == null:
		var fill := ColorRect.new()
		fill.color = Color8(0xF2, 0xC6, 0x3A)
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(fill)
	else:
		add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -18)
	center.add_child(column)
	var logo_tex := GameData.texture(GameData.title_art.get("logo", {}).get("file", ""))
	if logo_tex != null:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(BOARD_WIDTH, LOGO_HEIGHT)
		column.add_child(logo)
	# The tan board: the original's stroked panel behind the choices.
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	board.custom_minimum_size = Vector2(BOARD_WIDTH, 0)
	column.add_child(board)
	var tan := FlashNine.make("UITanStrokedRoundedBg", Vector2(BOARD_WIDTH, 200))
	board.add_child(tan)
	var margin := MarginContainer.new()
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 34)
	board.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	margin.add_child(_content)
	var footer := FlashUi.styled_label("Car Town Revival v%s  ·  An unofficial, free fan remake. Car Town belongs to Electronic Arts (Cie Games)."
		% ProjectSettings.get_setting("application/config/version"), "casualA01", 18, Color.WHITE, FOOTER_GLOW, 6)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -40
	footer.offset_bottom = -12
	add_child(footer)


## Text boxes and drop-downs in the game's white rounded style.
func _make_theme() -> Theme:
	var t := Theme.new()
	var font := FlashUi.style_font("casualA01")
	t.default_font = font
	t.default_font_size = 22
	var box := StyleBoxFlat.new()
	box.bg_color = Color.WHITE
	box.border_color = Color8(0x9A, 0xAE, 0xC0)
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_color = Color8(0x35, 0x64, 0x8C)
	for type: String in ["LineEdit", "OptionButton"]:
		t.set_stylebox("normal", type, box)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("hover", type, focus)
		t.set_stylebox("pressed", type, focus)
		t.set_color("font_color", type, TEXT_COLOR)
		t.set_color("font_hover_color", type, TEXT_COLOR)
		t.set_color("font_focus_color", type, TEXT_COLOR)
		t.set_color("font_pressed_color", type, TEXT_COLOR)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_COLOR, 0.45))
	t.set_color("caret_color", "LineEdit", TEXT_COLOR)
	var menu := box.duplicate() as StyleBoxFlat
	t.set_stylebox("panel", "PopupMenu", menu)
	t.set_color("font_color", "PopupMenu", TEXT_COLOR)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color8(0x35, 0x64, 0x8C)
	hover.set_corner_radius_all(6)
	t.set_stylebox("hover", "PopupMenu", hover)
	return t


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _title(text: String) -> void:
	_clear()
	var l := FlashUi.styled_label(text, "casualA01", 34, Color.WHITE, GenericPopup.TITLE_GLOW, 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(l)


func _label(text: String, size: int = 22, color: Color = TEXT_COLOR) -> Label:
	var l := FlashUi.styled_label(text, "casualA01", size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	return l


func _note(text: String) -> Label:
	var l := _label(text, 17, NOTE_COLOR)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## One of the game's oval buttons, as a Control so containers can place it.
func _button(text: String, on_press: Callable, colors: Array = EllipseButton.GREEN, font_size: int = 24) -> Control:
	var b := EllipseButton.create(text, colors, font_size, 90)
	var slot := Control.new()
	slot.custom_minimum_size = b.size() + Vector2(6, 8)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.position = slot.custom_minimum_size / 2.0
	slot.add_child(b)
	b.pressed.connect(func() -> void: on_press.call())
	return slot


func _row(items: Array, align := BoxContainer.ALIGNMENT_CENTER) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = align
	row.add_theme_constant_override("separation", 12)
	for it: Control in items:
		row.add_child(it)
	return row


func _field(text: String, placeholder: String, max_length: int, secret: bool = false) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.max_length = max_length
	e.secret = secret
	e.custom_minimum_size = Vector2(360, 0)
	e.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return e


## A white row card (a save slot, a world): text on the left, buttons right.
func _card(text: String, buttons: Array) -> Control:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.75)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _label(text, 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	row.add_child(l)
	for b: Control in buttons:
		row.add_child(b)
	card.add_child(row)
	return card


func _say(text: String, is_error: bool = false) -> void:
	_toasts.show_message(text, is_error)


func _ask(title: String, text: String, yes: String, on_yes: Callable) -> void:
	GenericPopup.ask(get_tree(), title, text, yes, on_yes)


# --- Pages -------------------------------------------------------------------------

func _show_error(message: String) -> void:
	_title("Can't start")
	var l := _label(message, 18)
	l.custom_minimum_size = Vector2(BOARD_WIDTH - 90, 0)
	_content.add_child(l)


func _show_modes() -> void:
	_title("Welcome to Car Town!")
	var online_ready := Online.is_configured()
	var online := _show_online
	if not online_ready:
		online = func() -> void: _say("Online play comes in a later update.")
	_content.add_child(_row([_button("Single Player", _show_slots, EllipseButton.GREEN, 28)]))
	_content.add_child(_row([_button("LAN", _show_lan, EllipseButton.BLUE, 28),
		_button("Online", online, EllipseButton.BLUE if online_ready else EllipseButton.GREY, 28)]))
	_content.add_child(_row([_button("Settings", _show_settings, EllipseButton.YELLOW, 22),
		_button("Credits", func() -> void: MenuPopup.open_credits(get_tree()), EllipseButton.YELLOW, 22),
		_button("Quit", func() -> void: get_tree().quit(), EllipseButton.RED, 22)]))


func _show_slots() -> void:
	_title("Choose a Garage")
	for slot in SaveStore.SLOT_COUNT:
		var summary := _store.summary(slot)
		if summary.is_empty():
			_content.add_child(_card("Garage %d: empty" % (slot + 1), [_button("New Game", _ask_name.bind(slot), EllipseButton.GREEN, 20)]))
			continue
		var text := "%s  ·  Level %d  ·  %s coins" % [summary["name"], summary["level"], Format.number(summary["coins"])]
		_content.add_child(_card(text, [
			_button("Play", _continue.bind(slot), EllipseButton.GREEN, 20),
			_button("Delete", func() -> void:
				_ask("Delete Garage", "Delete %s's garage? This can't be undone." % summary["name"], "Delete", func() -> void:
					_store.delete_slot(slot)
					_show_slots()), EllipseButton.GREY, 20)]))
	_content.add_child(_row([_button("Back", _show_modes, EllipseButton.GREY, 22)]))


func _ask_name(slot: int) -> void:
	_title("What's your name?")
	var edit := _field("", "Your name", 20)
	_content.add_child(_row([edit]))
	var start := func() -> void:
		var n := edit.text.strip_edges()
		if n.is_empty():
			_say("Please type a name.", true)
			return
		_start_new(slot, n)
	edit.text_submitted.connect(func(_t: String) -> void: start.call())
	_content.add_child(_row([_button("Start", start, EllipseButton.GREEN), _button("Back", _show_slots, EllipseButton.GREY)]))
	edit.grab_focus.call_deferred()


func _start_new(slot: int, player_name: String) -> void:
	var backend := LocalBackend.new(GameData.catalog, _store)
	if not backend.new_game(slot, player_name):
		_say("Couldn't create the save file.", true)
		return
	await Backend.use(backend)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _continue(slot: int) -> void:
	var backend := LocalBackend.new(GameData.catalog, _store)
	var errors: Array[String] = []
	if not backend.load_game(slot, errors):
		_say("\n".join(errors), true)
		return
	await Backend.use(backend)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# --- LAN -------------------------------------------------------------------------

const LAN_FOLDER := "user://saves/lan"


func _show_lan() -> void:
	_title("LAN")
	_content.add_child(_note("Play with friends on the same network."))
	_content.add_child(_row([_button("Host a World", _show_host, EllipseButton.GREEN), _button("Join a World", _show_join, EllipseButton.BLUE)]))
	_content.add_child(_row([_button("Back", _show_modes, EllipseButton.GREY, 22)]))


func _show_host() -> void:
	_title("Your LAN Worlds")
	_content.add_child(_note("Host one at a time. Friends' progress is kept in your world."))
	var worlds := LanWorld.new(LAN_FOLDER)
	for slot in LanWorld.SLOT_COUNT:
		var summary := worlds.summary(slot)
		if summary.is_empty():
			_content.add_child(_card("World %d: empty" % (slot + 1), [_button("Create", _new_world.bind(slot), EllipseButton.GREEN, 20)]))
			continue
		_content.add_child(_card("%s  ·  %d players" % [summary["name"], summary["players"]], [
			_button("Host", _host_world.bind(slot, "", {}), EllipseButton.GREEN, 20),
			_button("Delete", func() -> void:
				_ask("Delete World", "Delete \"%s\" and everyone's progress in it?" % summary["name"], "Delete", func() -> void:
					worlds.delete_slot(slot)
					_show_host()), EllipseButton.GREY, 20)]))
	_content.add_child(_row([_button("Back", _show_lan, EllipseButton.GREY, 22)]))


func _new_world(slot: int) -> void:
	_title("New World")
	var world_name := _field("My Car Town", "World name", 24)
	var player_name := _field(PlayerIdentity.get_name(), "Your name", 20)
	var from := OptionButton.new()
	from.custom_minimum_size = Vector2(360, 0)
	from.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	from.add_item("A new garage", -1)
	for s in SaveStore.SLOT_COUNT:
		var summary := _store.summary(s)
		if not summary.is_empty():
			from.add_item("%s (level %d)" % [summary["name"], summary["level"]], s)
	for pair: Array in [["World name", world_name], ["Your name", player_name], ["Start from", from]]:
		var l := _label(pair[0], 20)
		l.custom_minimum_size = Vector2(150, 0)
		_content.add_child(_row([l, pair[1]]))
	_content.add_child(_row([_button("Create and Host", func() -> void:
		if player_name.text.strip_edges().is_empty():
			_say("Please type your name.", true)
			return
		PlayerIdentity.set_name(player_name.text.strip_edges())
		var import_save: Dictionary = {}
		var src := from.get_selected_id()
		if src >= 0:
			import_save = _store.load_slot(src)
		_host_world(slot, world_name.text.strip_edges(), import_save), EllipseButton.GREEN, 20),
		_button("Back", _show_host, EllipseButton.GREY)]))


func _host_world(slot: int, world_name: String, import_save: Dictionary) -> void:
	var err: String = Lan.host(LanWorld.new(LAN_FOLDER), slot, world_name if world_name != "" else "My Car Town",
		PlayerIdentity.get_name() if PlayerIdentity.get_name() != "" else "Host", import_save)
	if err != "":
		_say(err, true)
		return
	await Backend.use(Lan.host_backend())
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_join() -> void:
	_title("Join a World")
	var player_name := _field(PlayerIdentity.get_name(), "Your name", 20)
	var name_label := _label("Your name", 20)
	name_label.custom_minimum_size = Vector2(150, 0)
	_content.add_child(_row([name_label, player_name]))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	_content.add_child(list)
	var join_to := func(address: String, port: int) -> void:
		var n := player_name.text.strip_edges()
		if n.is_empty():
			_say("Please type your name.", true)
			return
		PlayerIdentity.set_name(n)
		_say("Joining %s..." % address)
		Lan.join(address, port, n)
	var refresh := func() -> void:
		for c in list.get_children():
			c.queue_free()
		if Lan.found_hosts.is_empty():
			list.add_child(_note("Looking for worlds on your network..."))
		for key: String in Lan.found_hosts:
			var h: Dictionary = Lan.found_hosts[key]
			var same: bool = h.get("version", "") == Lan.game_version()
			var text := "%s  ·  %s  ·  %d playing%s" % [h.get("world", "?"), h.get("host", "?"), h.get("players", 1),
				"" if same else "  ·  v%s" % h.get("version", "?")]
			list.add_child(_card(text, [_button("Join", join_to.bind(h["ip"], h["port"]), EllipseButton.GREEN, 20)]))
	Lan.hosts_changed.connect(refresh)
	Lan.start_discovery()
	refresh.call()
	var ip := _field("", "Host's IP, like 192.168.1.20", 45)
	ip.custom_minimum_size = Vector2(300, 0)
	_content.add_child(_row([ip, _button("Join", func() -> void: join_to.call(ip.text.strip_edges(), Lan.PORT), EllipseButton.BLUE, 20)]))
	_content.add_child(_row([_button("Back", func() -> void:
		Lan.hosts_changed.disconnect(refresh)
		Lan.stop_discovery()
		_show_lan(), EllipseButton.GREY, 22)]))
	if not Lan.join_finished.is_connected(_on_join_finished):
		Lan.join_finished.connect(_on_join_finished)


func _on_join_finished(ok: bool, message: String) -> void:
	if not ok:
		_say(message, true)
		return
	Lan.stop_discovery()
	for c: Dictionary in Lan.hosts_changed.get_connections():
		Lan.hosts_changed.disconnect(c["callable"])
	await Backend.use(Lan.guest_backend())
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# --- Online ------------------------------------------------------------------------

func _show_online() -> void:
	if Online.has_saved_session():
		_say("Signing in...")
		if await Online.resume_session() == "":
			_enter_online()
			return
	_title("Online")
	_content.add_child(_note("Your garage is saved on our server."))
	var email := _field("", "Email", 120)
	var password := _field("", "Password", 120, true)
	_content.add_child(_row([email]))
	_content.add_child(_row([password]))
	_content.add_child(_row([_button("Sign In", func() -> void:
		var err: String = await Online.sign_in(email.text.strip_edges(), password.text)
		if err != "":
			_say(err, true)
			return
		_enter_online(), EllipseButton.GREEN, 22),
		_button("Create Account", func() -> void:
			if password.text.length() < 8:
				_say("Use a password of at least 8 characters.", true)
				return
			var err: String = await Online.sign_up(email.text.strip_edges(), password.text)
			if err == "confirm_email":
				_say("Check your email to confirm your account, then sign in.")
			elif err != "":
				_say(err, true)
			else:
				_enter_online(), EllipseButton.BLUE, 22)]))
	_content.add_child(_note("We only store your email and the display name you choose. You can delete your account at any time from the in-game menu."))
	_content.add_child(_row([_button("Back", _show_modes, EllipseButton.GREY, 22)]))


func _enter_online() -> void:
	var backend := OnlineBackend.new(Online)
	var err: String = await backend.load_state()
	if err == "no_save":
		_ask_display_name(backend)
		return
	if err != "":
		_say(err, true)
		return
	await Backend.use(backend)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _ask_display_name(backend: OnlineBackend) -> void:
	_title("Pick a Display Name")
	_content.add_child(_note("Not your real name: this is what other players see."))
	var edit := _field("", "Display name", 20)
	_content.add_child(_row([edit]))
	_content.add_child(_row([_button("Start My Garage", func() -> void:
		var err: String = await backend.start(edit.text.strip_edges())
		if err != "":
			_say(err, true)
			return
		await Backend.use(backend)
		get_tree().change_scene_to_file("res://scenes/game.tscn"), EllipseButton.GREEN)]))


func _show_settings() -> void:
	_title("Settings")
	var box := MenuPopup.settings_content()
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(box)
	_content.add_child(_row([_button("Back", _show_modes, EllipseButton.GREY, 22)]))
