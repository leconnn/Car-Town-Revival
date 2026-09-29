class_name NoticePopup
extends CenterContainer
## Queue of celebratory popups: level up, mission complete, job mastery.

var _queue: Array[Dictionary] = []
var _showing := false


func _ready() -> void:
	UiKit.place(self, Rect2(0, 0, 1, 1))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push(n: Dictionary) -> void:
	_queue.append(n)
	if not _showing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_showing = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	_showing = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var n: Dictionary = _queue.pop_front()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	var box := UiKit.vbox(12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var head: String
	var lines: Array[String] = []
	match n.get("kind", ""):
		"level_up":
			head = "Level Up!"
			lines.append("You're now level %d" % n["level"])
			if n.get("title", "") != "" and n["title"] != "n/a":
				lines.append("\"%s\"" % n["title"])
			lines.append(_reward_text(n))
		"mission_complete":
			head = "Mission Complete!"
			lines.append(n.get("title", ""))
			if n.get("text", "") != "":
				lines.append(n["text"])
			lines.append(_reward_text(n))
			var reward: Dictionary = n.get("reward", {})
			if reward.get("type", "") == "item":
				lines.append("Bonus: %s (in storage)" % GameData.catalog.item(reward["id"]).get("name", "item"))
			elif reward.get("type", "") == "car":
				lines.append("Bonus car: %s" % GameData.car_name(reward["id"]))
		"mastery":
			head = "Job Mastery!"
			lines.append("%s is now mastery level %d" % [GameData.catalog.job(n["job_id"]).get("name", "Job"), n["level"]])
			lines.append(_reward_text(n))
		_:
			head = "Notice"
	var title := UiKit.label(head, 34, Color(1, 0.9, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for line: String in lines:
		if line == "":
			continue
		var l := UiKit.label(line, 20)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
		box.add_child(l)
	var ok := UiKit.button("Great!", func() -> void:
		panel.queue_free()
		_next())
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(ok)
	add_child(panel)
	panel.scale = Vector2(0.85, 0.85)
	panel.pivot_offset = panel.size / 2
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.15)


func _reward_text(n: Dictionary) -> String:
	var parts: Array[String] = []
	if n.get("coins", 0) > 0:
		parts.append("+%s coins" % Format.number(n["coins"]))
	if n.get("blue", 0) > 0:
		parts.append("+%d blue" % n["blue"])
	if n.get("xp", 0) > 0:
		parts.append("+%s XP" % Format.number(n["xp"]))
	return "   ".join(parts)
