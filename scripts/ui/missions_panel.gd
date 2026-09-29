class_name MissionsPanel
extends GamePanel
## Current goals: story/tutorial missions and today's daily missions.


func _init() -> void:
	title = "Missions"


func _build() -> void:
	var s := Backend.state()
	var q := Backend.query()
	var ids := q.active_missions(Backend.now())
	var list := UiKit.vbox(10)
	var daily_ids: Array = s["missions"]["daily"].get("ids", [])
	var shown := 0
	for section: String in ["Missions", "Daily Missions"]:
		var header_added := false
		for mid: int in ids:
			var is_daily := daily_ids.has(mid)
			if is_daily != (section == "Daily Missions"):
				continue
			if not header_added:
				list.add_child(UiKit.label(section, 22, Color(1, 0.9, 0.45)))
				header_added = true
			list.add_child(_mission_card(mid, q))
			shown += 1
	if shown == 0:
		list.add_child(UiKit.label("No missions right now. Check back as you level up!", 16))
	body.add_child(UiKit.scroll(list, Vector2(0, 560)))


func _mission_card(mid: int, q: GameLogic) -> Control:
	var m: Dictionary = GameData.catalog.missions[mid]
	var panel := PanelContainer.new()
	var box := UiKit.vbox(4)
	panel.add_child(box)
	box.add_child(UiKit.label(m["title"] if m["title"] != "" else "Mission %d" % mid, 18, Color(1, 0.95, 0.75)))
	if m["description"] != "":
		var d := UiKit.label(m["description"], 14, Color(0.88, 0.92, 1))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(460, 0)
		box.add_child(d)
	for step: Dictionary in GameData.catalog.steps_by_mission.get(mid, []):
		var done := q.missions.step_progress(Backend.state(), mid, step["id"])
		var text: String = step["title"] if step["title"] != "" else step["event"].capitalize()
		var mark := "✔" if done >= step["count"] else "•"
		box.add_child(UiKit.label("%s %s  (%d/%d)" % [mark, text, mini(done, step["count"]), step["count"]], 15,
			Color(0.6, 1, 0.6) if done >= step["count"] else Color.WHITE))
	var reward: Array[String] = []
	if m["coins"] > 0:
		reward.append("● %s" % Format.number(m["coins"]))
	if m["blue"] > 0:
		reward.append("◆ %d" % m["blue"])
	if m["xp"] > 0:
		reward.append("%d XP" % m["xp"])
	if not reward.is_empty():
		box.add_child(UiKit.label("Reward: " + "  ".join(reward), 14, Color(1, 0.85, 0.3)))
	return panel
