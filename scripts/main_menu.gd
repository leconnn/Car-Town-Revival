extends Control
## Title screen: pick a mode and a save slot.
##
## Command line (for testing): -- autostart=<slot> [newgame=<name>]

const SAVE_FOLDER := "user://saves/single"

var _store: SaveStore
var _content: VBoxContainer


func _ready() -> void:
	Settings.load_and_apply()
	Sound.music("mainLoop")
	UiKit.place(self, Rect2(0, 0, 1, 1))
	_store = SaveStore.new(SAVE_FOLDER)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.36, 0.62)
	UiKit.place(bg, Rect2(0, 0, 1, 1))
	add_child(bg)
	var center := CenterContainer.new()
	UiKit.place(center, Rect2(0, 0, 1, 1))
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	_content = UiKit.vbox(14)
	panel.add_child(_content)
	var toasts := Toasts.new()
	add_child(toasts)
	if Engine.has_meta("title_message"):
		toasts.show_message.call_deferred(str(Engine.get_meta("title_message")), true)
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
	_show_modes()


func _args() -> Dictionary:
	var out := {}
	for a: String in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			out[parts[0]] = parts[1]
	return out


func _header() -> void:
	UiKit.clear(_content)
	var t := UiKit.label("Car Town Revival", 44, Color(1, 0.88, 0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(t)
	var sub := UiKit.label("An unofficial fan remake · v%s" % ProjectSettings.get_setting("application/config/version"), 15, Color(0.85, 0.9, 1))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(sub)


func _show_error(message: String) -> void:
	_header()
	var l := UiKit.label(message, 16, Color(1, 0.75, 0.7))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	_content.add_child(l)


func _show_modes() -> void:
	_header()
	_content.add_child(UiKit.button("Single-player", _show_slots, 24))
	_content.add_child(UiKit.button("LAN", _show_lan, 24))
	var online := UiKit.button("Online" if Online.is_configured() else "Online (not set up yet)", _show_online, 24)
	online.disabled = not Online.is_configured()
	_content.add_child(online)
	var row := UiKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UiKit.button("Settings", _show_settings))
	row.add_child(UiKit.button("Credits", _show_credits))
	row.add_child(UiKit.button("Quit", func() -> void: get_tree().quit()))
	_content.add_child(row)


func _show_slots() -> void:
	_header()
	_content.add_child(UiKit.label("Choose a save slot", 22))
	for slot in SaveStore.SLOT_COUNT:
		var row := UiKit.hbox(10)
		var summary := _store.summary(slot)
		var text: String
		if summary.is_empty():
			text = "Slot %d: empty" % (slot + 1)
		else:
			text = "Slot %d: %s  ·  Level %d  ·  %s coins" % [slot + 1, summary["name"], summary["level"], Format.number(summary["coins"])]
		var l := UiKit.label(text, 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if summary.is_empty():
			row.add_child(UiKit.button("New game", _ask_name.bind(slot)))
		else:
			row.add_child(UiKit.button("Continue", _continue.bind(slot)))
			row.add_child(UiKit.button("Delete", func() -> void:
				ConfirmBox.ask(self, "Delete %s's garage in slot %d? This can't be undone." % [summary["name"], slot + 1], func() -> void:
					_store.delete_slot(slot)
					_show_slots())))
		_content.add_child(row)
	_content.add_child(UiKit.button("Back", _show_modes))


func _ask_name(slot: int) -> void:
	_header()
	_content.add_child(UiKit.label("What's your name?", 22))
	var edit := LineEdit.new()
	edit.max_length = 20
	edit.placeholder_text = "Your name"
	_content.add_child(edit)
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Start", func() -> void:
		var n := edit.text.strip_edges()
		if n.is_empty():
			Toasts.say(get_tree(), "Please type a name.", true)
			return
		_start_new(slot, n)))
	row.add_child(UiKit.button("Back", _show_slots))
	_content.add_child(row)
	edit.grab_focus()


func _start_new(slot: int, player_name: String) -> void:
	var backend := LocalBackend.new(GameData.catalog, _store)
	if not backend.new_game(slot, player_name):
		Toasts.say(get_tree(), "Couldn't create the save file.", true)
		return
	await Backend.use(backend)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _continue(slot: int) -> void:
	var backend := LocalBackend.new(GameData.catalog, _store)
	var errors: Array[String] = []
	if not backend.load_game(slot, errors):
		Toasts.say(get_tree(), "\n".join(errors), true)
		return
	await Backend.use(backend)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# --- LAN -------------------------------------------------------------------------

const LAN_FOLDER := "user://saves/lan"


func _show_lan() -> void:
	_header()
	_content.add_child(UiKit.label("Play with people on the same network", 20))
	_content.add_child(UiKit.button("Host a world", _show_host, 22))
	_content.add_child(UiKit.button("Join a world", _show_join, 22))
	_content.add_child(UiKit.button("Back", _show_modes))


func _show_host() -> void:
	_header()
	var worlds := LanWorld.new(LAN_FOLDER)
	_content.add_child(UiKit.label("Your LAN worlds (host one at a time)", 20))
	for slot in LanWorld.SLOT_COUNT:
		var row := UiKit.hbox(10)
		var summary := worlds.summary(slot)
		var text := "World %d: empty" % (slot + 1) if summary.is_empty() else 			"World %d: %s  ·  %d players" % [slot + 1, summary["name"], summary["players"]]
		var l := UiKit.label(text, 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if summary.is_empty():
			row.add_child(UiKit.button("Create", _new_world.bind(slot)))
		else:
			row.add_child(UiKit.button("Host", _host_world.bind(slot, "", {})))
			row.add_child(UiKit.button("Delete", func() -> void:
				ConfirmBox.ask(self, "Delete world \"%s\" and everyone's progress in it?" % summary["name"], func() -> void:
					worlds.delete_slot(slot)
					_show_host())))
		_content.add_child(row)
	_content.add_child(UiKit.button("Back", _show_lan))


func _new_world(slot: int) -> void:
	_header()
	_content.add_child(UiKit.label("Name your world", 20))
	var world_name := LineEdit.new()
	world_name.max_length = 24
	world_name.text = "My Car Town"
	_content.add_child(world_name)
	_content.add_child(UiKit.label("Your name", 18))
	var player_name := LineEdit.new()
	player_name.max_length = 20
	player_name.text = PlayerIdentity.get_name()
	_content.add_child(player_name)
	_content.add_child(UiKit.label("Start your player from:", 18))
	var from := OptionButton.new()
	from.add_item("A new garage", -1)
	for s in SaveStore.SLOT_COUNT:
		var summary := _store.summary(s)
		if not summary.is_empty():
			from.add_item("Single-player slot %d (%s, level %d)" % [s + 1, summary["name"], summary["level"]], s)
	_content.add_child(from)
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Create and host", func() -> void:
		if player_name.text.strip_edges().is_empty():
			Toasts.say(get_tree(), "Please type your name.", true)
			return
		PlayerIdentity.set_name(player_name.text.strip_edges())
		var import_save: Dictionary = {}
		var src := from.get_selected_id()
		if src >= 0:
			import_save = _store.load_slot(src)
		_host_world(slot, world_name.text.strip_edges(), import_save)))
	row.add_child(UiKit.button("Back", _show_host))
	_content.add_child(row)


func _host_world(slot: int, world_name: String, import_save: Dictionary) -> void:
	var err: String = Lan.host(LanWorld.new(LAN_FOLDER), slot, world_name if world_name != "" else "My Car Town",
		PlayerIdentity.get_name() if PlayerIdentity.get_name() != "" else "Host", import_save)
	if err != "":
		Toasts.say(get_tree(), err, true)
		return
	await Backend.use(Lan.host_backend())
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_join() -> void:
	_header()
	_content.add_child(UiKit.label("Your name", 18))
	var player_name := LineEdit.new()
	player_name.max_length = 20
	player_name.text = PlayerIdentity.get_name()
	_content.add_child(player_name)
	_content.add_child(UiKit.label("Worlds on your network", 20))
	var list := UiKit.vbox(6)
	_content.add_child(list)
	var join_to := func(address: String, port: int) -> void:
		var n := player_name.text.strip_edges()
		if n.is_empty():
			Toasts.say(get_tree(), "Please type your name.", true)
			return
		PlayerIdentity.set_name(n)
		Toasts.say(get_tree(), "Joining %s..." % address)
		Lan.join(address, port, n)
	var refresh := func() -> void:
		UiKit.clear(list)
		if Lan.found_hosts.is_empty():
			list.add_child(UiKit.label("Looking for worlds...", 16, Color(0.85, 0.9, 1)))
		for key: String in Lan.found_hosts:
			var h: Dictionary = Lan.found_hosts[key]
			var row := UiKit.hbox()
			var same: bool = h.get("version", "") == Lan.game_version()
			var l := UiKit.label("%s  (hosted by %s, %d playing)%s" % [h.get("world", "?"), h.get("host", "?"), h.get("players", 1),
				"" if same else "  · v%s" % h.get("version", "?")], 16)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			row.add_child(UiKit.button("Join", join_to.bind(h["ip"], h["port"])))
			list.add_child(row)
	Lan.hosts_changed.connect(refresh)
	Lan.start_discovery()
	refresh.call()
	_content.add_child(UiKit.label("Or type the host's IP address", 18))
	var ip_row := UiKit.hbox()
	var ip := LineEdit.new()
	ip.placeholder_text = "192.168.1.20"
	ip.custom_minimum_size = Vector2(240, 0)
	ip_row.add_child(ip)
	ip_row.add_child(UiKit.button("Join", func() -> void: join_to.call(ip.text.strip_edges(), Lan.PORT)))
	_content.add_child(ip_row)
	_content.add_child(UiKit.button("Back", func() -> void:
		Lan.hosts_changed.disconnect(refresh)
		Lan.stop_discovery()
		_show_lan()))
	if not Lan.join_finished.is_connected(_on_join_finished):
		Lan.join_finished.connect(_on_join_finished)


func _on_join_finished(ok: bool, message: String) -> void:
	if not ok:
		Toasts.say(get_tree(), message, true)
		return
	Lan.stop_discovery()
	for c: Dictionary in Lan.hosts_changed.get_connections():
		Lan.hosts_changed.disconnect(c["callable"])
	await Backend.use(Lan.guest_backend())
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# --- Online ------------------------------------------------------------------------

func _show_online() -> void:
	if Online.has_saved_session():
		Toasts.say(get_tree(), "Signing in...")
		if await Online.resume_session() == "":
			_enter_online()
			return
	_header()
	_content.add_child(UiKit.label("Online: your garage is saved on our server", 20))
	_content.add_child(UiKit.label("Email", 16))
	var email := LineEdit.new()
	email.placeholder_text = "you@example.com"
	_content.add_child(email)
	_content.add_child(UiKit.label("Password", 16))
	var password := LineEdit.new()
	password.secret = true
	_content.add_child(password)
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Sign in", func() -> void:
		var err: String = await Online.sign_in(email.text.strip_edges(), password.text)
		if err != "":
			Toasts.say(get_tree(), err, true)
			return
		_enter_online()))
	row.add_child(UiKit.button("Create account", func() -> void:
		if password.text.length() < 8:
			Toasts.say(get_tree(), "Use a password of at least 8 characters.", true)
			return
		var err: String = await Online.sign_up(email.text.strip_edges(), password.text)
		if err == "confirm_email":
			Toasts.say(get_tree(), "Check your email to confirm your account, then sign in.")
		elif err != "":
			Toasts.say(get_tree(), err, true)
		else:
			_enter_online()))
	_content.add_child(row)
	var note := UiKit.label("We only store your email and the display name you choose. You can delete your account at any time from the in-game menu.", 13, Color(0.85, 0.9, 1))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(600, 0)
	_content.add_child(note)
	_content.add_child(UiKit.button("Back", _show_modes))


func _enter_online() -> void:
	var backend := OnlineBackend.new(Online)
	var err: String = await backend.load_state()
	if err == "no_save":
		_ask_display_name(backend)
		return
	if err != "":
		Toasts.say(get_tree(), err, true)
		return
	await Backend.use(backend)
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _ask_display_name(backend: OnlineBackend) -> void:
	_header()
	_content.add_child(UiKit.label("Pick a display name (not your real name)", 20))
	var edit := LineEdit.new()
	edit.max_length = 20
	_content.add_child(edit)
	_content.add_child(UiKit.button("Start my garage", func() -> void:
		var err: String = await backend.start(edit.text.strip_edges())
		if err != "":
			Toasts.say(get_tree(), err, true)
			return
		await Backend.use(backend)
		get_tree().change_scene_to_file("res://scenes/game.tscn")))


func _show_settings() -> void:
	_header()
	_content.add_child(MenuPanel.SettingsBox.new())
	_content.add_child(UiKit.button("Back", _show_modes))


func _show_credits() -> void:
	_header()
	var rt := RichTextLabel.new()
	rt.text = FileAccess.get_file_as_string("res://CREDITS.md")
	rt.custom_minimum_size = Vector2(600, 400)
	_content.add_child(rt)
	_content.add_child(UiKit.button("Back", _show_modes))
