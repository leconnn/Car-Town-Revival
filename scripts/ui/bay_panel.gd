class_name BayPanel
extends GamePanel
## A work bay: put a car on it, pick a job, watch the timer, collect.

var bay_uid: int
var game: Node
var _time_label: Label
var _bar: ProgressBar


func _init(uid: int, game_node: Node) -> void:
	bay_uid = uid
	game = game_node
	title = "Work Bay"


func _build() -> void:
	var q := Backend.query()
	var s := Backend.state()
	var occ := q.bay_occupant(bay_uid)
	var job: Dictionary = s["jobs"].get(str(bay_uid), {})
	if occ.is_empty():
		_build_empty()
		return
	var entry: Dictionary = occ["entry"]
	var who := "Customer's " if occ["kind"] == "customer" else "Your "
	body.add_child(UiKit.label(who + GameData.car_name(entry["car_id"]), 20, Color(1, 0.95, 0.7)))
	var preview := CarPreviewBox.new(Vector2(500, 190), 0.45)
	body.add_child(preview)
	preview.show_car(entry)
	if job.is_empty():
		_build_job_list(occ)
	else:
		_build_running(job)


func _build_empty() -> void:
	var s := Backend.state()
	body.add_child(UiKit.label("This work bay is empty. Put a car on it to start a job.", 16))
	var waiting: Array = s["customers"].filter(func(c: Dictionary) -> bool: return c.get("bay_uid", 0) == 0)
	if not waiting.is_empty():
		body.add_child(UiKit.label("Customers waiting", 18, Color(1, 0.9, 0.5)))
		for c: Dictionary in waiting:
			var row := UiKit.hbox()
			var l := UiKit.label(GameData.car_name(c["car_id"]), 15)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			row.add_child(UiKit.button("Bring in", func() -> void: await Backend.accept_customer(c["uid"], bay_uid), 14))
			body.add_child(row)
	var own: Array = s["cars"].filter(func(c: Dictionary) -> bool: return c["bay_uid"] == 0)
	if not own.is_empty():
		body.add_child(UiKit.label("Your cars", 18, Color(1, 0.9, 0.5)))
		var list := UiKit.vbox(4)
		for c: Dictionary in own:
			var row := UiKit.hbox()
			var l := UiKit.label(GameData.car_name(c["car_id"]), 15)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			row.add_child(UiKit.button("Put on bay", func() -> void: await Backend.put_car_on_bay(c["uid"], bay_uid), 14))
			list.add_child(row)
		body.add_child(UiKit.scroll(list, Vector2(0, 200)))


func _build_job_list(occ: Dictionary) -> void:
	var q := Backend.query()
	var s := Backend.state()
	var level: int = s["player"]["level"]
	var busy: int = s["jobs"].size()
	body.add_child(UiKit.label("Choose a job  (workers busy: %d/%d)" % [busy, q.max_workers()], 17))
	var list := UiKit.vbox(4)
	for job_id: int in q.available_job_ids():
		var j: Dictionary = GameData.catalog.job(job_id)
		var pay := q.job_payout(job_id)
		var row := UiKit.hbox(8)
		var name := UiKit.label(j["name"], 15)
		name.custom_minimum_size = Vector2(170, 0)
		row.add_child(name)
		row.add_child(UiKit.label(Format.minutes(j["minutes"]), 14, Color(0.85, 0.9, 1)))
		var gain := UiKit.label("● %s  +%d XP" % [Format.number(pay["coins"]), pay["xp"]], 14, Color(1, 0.85, 0.3))
		gain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(gain)
		if j["min_level"] > level:
			row.add_child(UiKit.label("Level %d" % j["min_level"], 14, Color(1, 0.6, 0.55)))
		else:
			var start := UiKit.button("Start (%s)" % Format.number(j["price"]), func() -> void:
				var r: GameResult = await Backend.start_job(bay_uid, job_id)
				if r.ok:
					close(), 13)
			start.disabled = busy >= q.max_workers()
			row.add_child(start)
		list.add_child(row)
	body.add_child(UiKit.scroll(list, Vector2(0, 260)))
	if occ["kind"] == "car":
		body.add_child(UiKit.button("Take car off the bay", func() -> void: await Backend.take_car_off_bay(occ["entry"]["uid"]), 15))
	else:
		body.add_child(UiKit.button("Send customer away", func() -> void: await Backend.dismiss_customer(occ["entry"]["uid"]), 15))


func _build_running(job: Dictionary) -> void:
	var q := Backend.query()
	var j: Dictionary = GameData.catalog.job(job["job_id"])
	var pay := q.job_payout(job["job_id"])
	body.add_child(UiKit.label("%s  ·  pays ● %s and %d XP" % [j["name"], Format.number(pay["coins"]), pay["xp"]], 17))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(400, 20)
	_bar.show_percentage = false
	body.add_child(_bar)
	_time_label = UiKit.label("", 18)
	body.add_child(_time_label)
	var row := UiKit.hbox()
	if Backend.now() >= job["ends_at"]:
		row.add_child(UiKit.button("Collect!", _collect))
	else:
		var price := q.finish_now_price(bay_uid, Backend.now())
		row.add_child(UiKit.button("Finish now  ◆ %d" % price, func() -> void:
			var r: GameResult = await Backend.finish_job_now(bay_uid)
			if r.ok:
				toast("+%s coins  +%d XP" % [Format.number(r.data["coins"]), r.data["xp"]])))
	body.add_child(row)
	body.add_child(UiKit.label("Mastery: %s done, level %d" % [
		Format.number(Backend.state()["job_mastery"].get(str(job["job_id"]), 0)), q.mastery_level(job["job_id"])], 14, Color(0.85, 0.9, 1)))
	_process(0)


func _collect() -> void:
	var r: GameResult = await Backend.collect_job(bay_uid)
	if r.ok:
		toast("+%s coins  +%d XP" % [Format.number(r.data["coins"]), r.data["xp"]])


func _process(_delta: float) -> void:
	if _bar == null or not is_instance_valid(_bar):
		return
	var job: Dictionary = Backend.state()["jobs"].get(str(bay_uid), {})
	if job.is_empty():
		return
	var left: int = job["ends_at"] - Backend.now()
	var total: int = maxi(1, job["ends_at"] - job["started_at"])
	_bar.value = 100.0 * (1.0 - float(maxi(0, left)) / total)
	_time_label.text = "Ready to collect!" if left <= 0 else "Done in %s" % Format.duration(left)
	if left <= 0 and not has_meta("rebuilt"):
		set_meta("rebuilt", true)
		_on_state_changed()
