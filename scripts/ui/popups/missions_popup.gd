class_name MissionsPopup
extends Node2D
## The original Missions popup (integrations/missionsystem/views/
## MissionStatusPopup_v2 on MissionStatusPopupContentV2): today's daily
## mission and the other missions down the left, and for the one you pick,
## its steps with progress, the daily timer, the reward and OK.

## Frame margins around the content's bg (PopupHelper.getBoundsForInnerDisplayObject).
const MARGIN := Rect2(20, 40, 20, 20)
const ICON_SIZE := 66.0
## The list's visible area inside the content (its scroll mask).
const LIST_RECT := Rect2(20, 150, 142, 262)
const STEP_GAP := 12.0
const SELECTED_GLOW := Color(1.0, 1.0, 0.4)

## A mission was looked at (it's no longer a "NEW GOAL!").
signal viewed

var _content: FlashSymbol
var _mission_id := -1
var _list: Node2D
var _icons: Dictionary[int, Node2D] = {}
var _timer_field: FlashText
var _daily_ends := 0
var _popup: FlashPopup


## Opens the popup on [param mission_id] (or the daily / first mission).
static func open(tree: SceneTree, mission_id: int = -1) -> MissionsPopup:
	var p := MissionsPopup.new()
	p._mission_id = mission_id
	p._build()
	var bg := p._content.part("bg") as FlashSymbol if p._content != null else null
	var bg_rect := Rect2(bg.position, bg.local_bounds().size) if bg != null else Rect2(0, 0, 664, 461)
	var holder := Node2D.new()
	p.position = Vector2(MARGIN.position.x, MARGIN.position.y) - bg_rect.position
	holder.add_child(p)
	var size := bg_rect.size + Vector2(MARGIN.position.x + MARGIN.size.x, MARGIN.position.y + MARGIN.size.y)
	p._popup = FlashPopup.open(tree, holder, true, false, size)
	return p


func close() -> void:
	if _popup != null:
		_popup.close()


func _build() -> void:
	_content = FlashUi.make("MissionStatusPopupContentV2")
	if _content == null:
		return
	add_child(_content)
	_content.styled_text("fldPopupTitle", "Missions", "casualA01")
	_content.styled_text("fldDailyMissionTitle", "Daily Mission", "casualA01")
	_content.styled_text("fldDailyMissionCompleted", "Completed", "casualA01")
	_content.styled_text("fldReward", "Your Reward:", "casualA01")
	_build_list()
	_show(_mission_id)


func _missions() -> Array[int]:
	var ids := Backend.query().active_missions(Backend.now())
	ids.sort_custom(func(a: int, b: int) -> bool:
		return GameData.catalog.missions[a]["index"] < GameData.catalog.missions[b]["index"])
	return ids


static func _is_daily(mission_id: int) -> bool:
	return GameData.catalog.missions.get(mission_id, {}).get("category", "") == "daily"


func _build_list() -> void:
	var daily_holder := _content.part("dailyMissionIconContainer") as Node2D
	var clip := Control.new()
	clip.position = LIST_RECT.position
	clip.size = LIST_RECT.size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(clip)
	var list_origin := (_content.part("missionButtonsContainer") as Node2D).position if _content.part("missionButtonsContainer") != null else Vector2(91, 182)
	_list = Node2D.new()
	_list.position = list_origin - LIST_RECT.position - Vector2(0, ICON_SIZE / 2.0)
	clip.add_child(_list)
	var has_daily := false
	var y := 0.0
	for mid: int in _missions():
		var icon := _mission_icon(mid)
		if _is_daily(mid) and daily_holder != null and not has_daily:
			daily_holder.add_child(icon)
			has_daily = true
		else:
			icon.position.y = y + ICON_SIZE / 2.0
			_list.add_child(icon)
			y += ICON_SIZE + 4
		_icons[mid] = icon
	var done := _content.part("fldDailyMissionCompleted") as CanvasItem
	if done != null:
		done.visible = not has_daily
	# The scroll arrows only show when there's more than fits.
	for part: String in ["scrollUpButton", "scrollDownButton"]:
		var arrow := _content.part(part) as Node2D
		if arrow == null:
			continue
		arrow.visible = y > LIST_RECT.size.y
		var btn := FlashButton.wrap_node(arrow.duplicate())
		btn.position = arrow.position
		btn.body.position = Vector2.ZERO
		btn.body.scale = arrow.scale
		btn.visible = arrow.visible
		arrow.visible = false
		var dir := -1.0 if part == "scrollUpButton" else 1.0
		btn.pressed.connect(func() -> void: _scroll(dir, y))
		_content.add_child(btn)


func _scroll(dir: float, total: float) -> void:
	var top := LIST_RECT.position.y
	var min_y := -(total - LIST_RECT.size.y)
	var base := (_content.part("missionButtonsContainer") as Node2D).position.y - top - ICON_SIZE / 2.0 if _content.part("missionButtonsContainer") != null else 0.0
	var target := clampf(_list.position.y - dir * LIST_RECT.size.y, base + min_y, base)
	var tw := create_tween()
	tw.tween_property(_list, "position:y", target, 0.5)


## MissionIcon: the mission's picture in a 66 x 66 square, a GameButton
## growing 12%.
func _mission_icon(mid: int) -> Node2D:
	var holder := Node2D.new()
	var glow := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 32:
		pts.append(Vector2(cos(TAU * i / 32.0), sin(TAU * i / 32.0)) * (ICON_SIZE / 2.0 + 2))
	glow.polygon = pts
	glow.color = Color(SELECTED_GLOW, 0.7)
	glow.visible = false
	glow.name = "Glow"
	holder.add_child(glow)
	var tex := GameData.mission_picture(mid)
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		var k := minf(1.0, ICON_SIZE / maxf(tex.get_width(), tex.get_height()))
		s.scale = Vector2(k, k)
		s.position = Vector2(3, 3)
		holder.add_child(s)
	var btn := FlashButton.wrap_node(holder, Rect2(-ICON_SIZE / 2.0, -ICON_SIZE / 2.0, ICON_SIZE, ICON_SIZE))
	btn.set_base_scale(1.0, 1.12)
	btn.pressed.connect(func() -> void: _show(mid))
	return btn


func _show(mid: int) -> void:
	var ids := _missions()
	if not ids.has(mid):
		mid = -1
		for id: int in ids:
			if _is_daily(id):
				mid = id
		if mid < 0 and not ids.is_empty():
			mid = ids[0]
	_mission_id = mid
	for id: int in _icons:
		var glow := _icons[id].body.get_node_or_null("Glow") as CanvasItem
		if glow != null:
			glow.visible = id == mid
	for part: String in ["stepsContainer", "rewardContainer", "buttonContainer", "hintContainer"]:
		var c := _content.part(part) as Node2D
		if c != null:
			for child in c.get_children():
				child.queue_free()
	_timer_field = null
	if mid < 0:
		_content.styled_text("fldTitle", "No missions right now!", "casualA01")
		_add_ok()
		return
	var m: Dictionary = GameData.catalog.missions[mid]
	_content.styled_text("fldTitle", m["title"], "casualA01")
	if not Settings.missions_seen.has(mid):
		Settings.missions_seen.append(mid)
		Settings.save()
		viewed.emit.call_deferred()
	var steps := _content.part("stepsContainer") as Node2D
	var y := 0.0
	var q := Backend.query()
	for step: Dictionary in GameData.catalog.steps_by_mission.get(mid, []):
		var done := mini(q.missions.step_progress(Backend.state(), mid, step["id"]), step["count"])
		var complete: bool = done >= step["count"]
		var gfx := FlashUi.make("TaskStepCompleteGraphic" if complete else "TaskStepPendingGraphic")
		if gfx == null:
			continue
		gfx.styled_text("titleText", step["title"], "casualA01")
		gfx.styled_text("descriptionText", step["description"], "sansD01")
		if not complete:
			gfx.styled_text("tasksText", "%d/%d" % [done, step["count"]], "casualA01")
		var tex := GameData.texture("missions/step_%d.png" % step.get("icon_id", 0))
		if tex != null:
			var s := Sprite2D.new()
			s.texture = tex
			s.position = Vector2(42, 36)
			var k := minf(1.0, 56.0 / maxf(tex.get_width(), tex.get_height()))
			s.scale = Vector2(k, k)
			gfx.add_child(s)
		gfx.position.y = y
		steps.add_child(gfx)
		y += gfx.local_bounds().end.y + STEP_GAP
	if _is_daily(mid):
		var expiry := FlashUi.make("DailyMissionExpiration")
		if expiry != null:
			expiry.styled_text("fldTitle", "This Daily Mission Expires in:", "sansD01")
			expiry.position.y = y
			steps.add_child(expiry)
			_timer_field = expiry.part("fldTimer") as FlashText
			_daily_ends = (Backend.now() / 86400 + 1) * 86400
			y += expiry.local_bounds().end.y + STEP_GAP
	var step_bg := _content.part("stepBackground") as Node2D
	if step_bg != null:
		var h := (step_bg as FlashSymbol).local_bounds().size.y
		step_bg.scale.y = clampf(y + 80, 150, 330) / maxf(1.0, h)
		var hint := _content.part("hintContainer") as Node2D
		if hint != null:
			hint.position.y = step_bg.position.y + clampf(y + 80, 150, 330) + 8
	_show_reward(m)
	_add_ok()


## The coins, blue coins and XP, centred under "Your Reward:", greyed until
## the mission's done.
func _show_reward(m: Dictionary) -> void:
	var reward := _content.part("rewardContainer") as Node2D
	if reward == null:
		return
	var x := 0.0
	for entry: Array in [["CreditRewardFieldGraphic", m.get("blue", 0), false],
			["MoneyRewardFieldGraphic", m.get("coins", 0), false], ["XpRewardFieldGraphic", m.get("xp", 0), true]]:
		if entry[1] <= 0:
			continue
		var gfx := FlashUi.make(entry[0])
		if gfx == null:
			continue
		var text: String = ("%d XP" % entry[1]) if entry[2] else Format.number(entry[1])
		gfx.styled_text("amountText", text, "sansD01" if entry[2] else "casualA01")
		var r := gfx.local_bounds()
		gfx.position.x = x - r.position.x
		reward.add_child(gfx)
		x += r.size.x + 12
	var step_bg := _content.part("stepBackground") as FlashSymbol
	if step_bg != null:
		reward.position.x = step_bg.position.x + step_bg.local_bounds().size.x * 0.5 - x * 0.5
	reward.modulate = Color(0.75, 0.75, 0.75)


func _add_ok() -> void:
	var buttons := _content.part("buttonContainer") as Node2D
	if buttons == null:
		return
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	ok.pressed.connect(close)
	buttons.add_child(ok)


func _process(_delta: float) -> void:
	if _timer_field != null:
		var left := maxi(0, _daily_ends - Backend.now())
		_timer_field.set_style("sansD01")
		_timer_field.set_text("%02d:%02d:%02d" % [left / 3600, (left % 3600) / 60, left % 60])
