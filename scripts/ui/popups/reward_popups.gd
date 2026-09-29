class_name RewardPopups
extends Node
## The original celebration popups, shown one at a time as rule notices come
## in (the original queued them in AdvancedPopupManager):
##   level_up         LevelUpPopup / XPAchievePopup: "You reached Level 5!"
##                    with the level-up animation and your new perks.
##   mission_complete MissionStatusPopup in its completed state: Roxy, the
##                    mission's steps all ticked, "Goal Complete!", the reward.
##   mastery          TaskMasteryLevelUp: the job's five mastery stars, what
##                    each level earns and rewards.

const MISSION_TEXT_COLOR := Color8(0x96, 0xC4, 0x6B)
const MARGIN := Rect2(20, 40, 20, 20)

var _queue: Array[Dictionary] = []
var _showing := false


func push(n: Dictionary) -> void:
	if not n.get("kind", "") in ["level_up", "mission_complete", "mastery"]:
		return
	_queue.append(n)
	if not _showing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var n: Dictionary = _queue.pop_front()
	var popup: FlashPopup
	match n["kind"]:
		"level_up":
			popup = _level_up(n)
		"mission_complete":
			popup = _mission_complete(n)
		"mastery":
			popup = _mastery(n)
	if popup == null:
		_next()
		return
	popup.closed.connect(_next)


# --- Level up -------------------------------------------------------------------------

func _level_up(n: Dictionary) -> FlashPopup:
	var assets := FlashUi.make("XPAchievePopupAssets")
	if assets == null:
		return null
	assets.styled_text("fldHeader", "Your New Perks!", "casualA01")
	var anim := assets.part("levelUpAnimation") as FlashSymbol
	if anim != null:
		anim.styled_text("header/fld", "You reached:", "casualA01")
		anim.styled_text("levelNumber/fldLevel", "Level", "casualA01")
		anim.styled_text("levelNumber/levelText", str(n["level"]), "casualA01")
		anim.goto(0)
		anim.play(30.0, false)
	# PerkSetDisplay: up to three perks, 10 px apart, centred on perksGuide.
	var guide := assets.part("perksGuide") as Node2D
	var perks := Node2D.new()
	if guide != null:
		perks.position = guide.position
	assets.add_child(perks)
	var list: Array[Node2D] = []
	list.append(_perk(_money_icon(n.get("coins", 0), n.get("blue", 0)), "Car Town Points"))
	var before: Dictionary = GameData.catalog.level_info(n["level"] - 1)
	var after: Dictionary = GameData.catalog.level_info(n["level"])
	if after.get("max_workers", 0) > before.get("max_workers", 0):
		list.append(_perk(FlashUi.make("PerkIconAvatar"), "Hire up to %d Workers" % after["max_workers"]))
	for land_id: int in GameData.catalog.lands:
		if GameData.catalog.lands[land_id].get("min_level", 0) == n["level"]:
			list.append(_perk(FlashUi.make("PerkIconGarage"), "Unlock land expansion"))
			break
	var x := 0.0
	for p in list.slice(0, 3):
		p.position.x = x
		perks.add_child(p)
		x += p.get_meta("width", 150.0) + 10
	perks.position.x -= (x - 10) / 2.0
	var skip := FrameButton.with_text("Skip", FrameButton.GREY)
	var popup := FlashPopup.open_framed(get_tree(), assets, [33, 20, 58, 20], [skip])
	skip.pressed.connect(popup.close)
	return popup


## XPPerkDisplayInstance: an icon over a caption.
func _perk(icon: Node2D, caption: String) -> Node2D:
	var holder := FlashUi.make("XPPerkDisplayInstance")
	if holder == null:
		return Node2D.new()
	holder.styled_text("captionText", caption, "casualA01")
	var guide := holder.part("iconGuide") as Node2D
	if guide != null and icon != null:
		guide.add_child(icon)
	holder.set_meta("width", holder.local_bounds().size.x)
	return holder


## MoneyPerkIcons: coins, and blue coins when there are any.
func _money_icon(coins: int, blue: int) -> Node2D:
	var icons := FlashUi.make("MoneyPerkIcons")
	if icons == null:
		return Node2D.new()
	icons.styled_text("fldCoin", Format.number(coins), "casualA01")
	icons.styled_text("fldCredits", Format.number(blue), "casualA01")
	if blue == 0:
		for part: String in ["icnCredits", "fldCredits"]:
			var p := icons.part(part) as CanvasItem
			if p != null:
				p.visible = false
		for part: String in ["icnCoin", "fldCoin"]:
			var p := icons.part(part) as Node2D
			if p != null:
				p.position.y -= 10
	return icons


# --- Mission complete -----------------------------------------------------------------

func _mission_complete(n: Dictionary) -> FlashPopup:
	var mid: int = n["mission_id"]
	var root := Node2D.new()
	var bg := FlashUi.make("MissionCompletedBackgroundGraphic")
	var title := FlashUi.make("MissionCompletedPopupTitleField")
	var mission_title := FlashUi.make("MissionCompletedPopupTitle")
	var steps_bg := FlashUi.make("MissionCompletedWhiteBackgroundGraphic")
	var bubble := FlashUi.make("MissionCompletedTalkBubbleGraphic")
	var portrait := FlashUi.make("MissionCompletedRoxyMissionPortraitGraphic")
	if bg == null or title == null or steps_bg == null:
		return null
	title.styled_text("titleText", "Mission Complete", "casualA01")
	if mission_title != null:
		mission_title.styled_text("fldTitle", n.get("title", ""), "casualA01")
	# The steps, all complete now.
	var steps := Node2D.new()
	var y := 0.0
	for step: Dictionary in GameData.catalog.steps_by_mission.get(mid, []):
		var gfx := FlashUi.make("MissionCompletedTaskStepCompleteGraphic")
		if gfx == null:
			continue
		gfx.styled_text("titleText", step["title"], "casualA01")
		gfx.styled_text("descriptionText", step["description"], "sansD01")
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
		y += gfx.local_bounds().end.y + 12
	var steps_h := y - 12
	var title_h := title.local_bounds().end.y
	var bg_h := bg.local_bounds().size.y
	bg.scale.y = maxf(450, steps_h + 50) / maxf(1.0, bg_h)
	bg.position.y = title_h - 30
	var sbh := steps_bg.local_bounds().size.y
	steps_bg.scale.y = maxf(steps_h + 40, 200) / maxf(1.0, sbh)
	steps_bg.position = Vector2(170, title_h)
	var sb := Rect2(steps_bg.position, Vector2(steps_bg.local_bounds().size.x, maxf(steps_h + 40, 200)))
	title.position.x = (bg.local_bounds().size.x - title.local_bounds().size.x) / 2.0
	var steps_w := FlashNine.bounds(steps).size.x
	steps.position = Vector2(sb.position.x + (sb.size.x - steps_w) / 1.8, sb.position.y + (sb.size.y - steps_h) / 2.0)
	root.add_child(bg)
	root.add_child(steps_bg)
	root.add_child(steps)
	if mission_title != null:
		mission_title.position = Vector2(sb.position.x + sb.size.x / 2.0, sb.position.y)
		root.add_child(mission_title)
	root.add_child(title)
	var bg_bottom := bg.position.y + maxf(450, steps_h + 50)
	if portrait != null:
		var ph := portrait.local_bounds().size.y
		portrait.position = Vector2(-42, bg_bottom - ph * 0.97) - Vector2(0, portrait.local_bounds().position.y)
		root.add_child(portrait)
		if bubble != null:
			var text: String = n.get("text", "")
			bubble.styled_text("descriptionText", text if text != "" else "Goal Complete!", "casualA01", 36)
			var field := bubble.part("descriptionText") as FlashText
			if field != null:
				field.set_color(MISSION_TEXT_COLOR)
				field.fit_to_box()
			bubble.position = Vector2(50, bg_bottom - ph * 0.97 + ph * 0.14)
			root.add_child(bubble)
	# "Your Reward:" and the reward, under the steps.
	var reward_text := FlashUi.make("MissionCompletedYourRewardTextGraphic")
	var reward := Node2D.new()
	var rx := 0.0
	for entry: Array in [["MissionCompletedCreditRewardFieldGraphic", n.get("blue", 0), false],
			["MissionCompletedMoneyRewardFieldGraphic", n.get("coins", 0), false],
			["MissionCompletedXpRewardFieldGraphic", n.get("xp", 0), true]]:
		if entry[1] <= 0:
			continue
		var gfx := FlashUi.make(entry[0])
		if gfx == null:
			continue
		gfx.styled_text("amountText", ("%d XP" % entry[1]) if entry[2] else Format.number(entry[1]), "sansD01" if entry[2] else "casualA01")
		var r := gfx.local_bounds()
		gfx.position.x = rx - r.position.x
		reward.add_child(gfx)
		rx += r.size.x + 12
	if reward_text != null:
		reward_text.styled_text("fldText", "Your Reward:", "casualA01")
		var rw := reward_text.local_bounds()
		reward_text.position = Vector2(sb.position.x + sb.size.x * 0.5 - rw.size.x * 0.5 - rw.position.x, sb.end.y + 4)
		root.add_child(reward_text)
		reward.position = Vector2(sb.position.x + sb.size.x * 0.5 - (rx - 12) * 0.5, reward_text.position.y + rw.end.y - 12)
	root.add_child(reward)
	var item: Dictionary = n.get("reward", {})
	if not item.is_empty():
		var extra := FlashUi.styled_label("Bonus: %s" % (GameData.car_name(item["id"]) if item["type"] == "car" else GameData.catalog.item(item["id"]).get("name", "")),
			"casualA01", 18, Color.WHITE, Color8(0x23, 0x4F, 0x70), 5)
		extra.position = Vector2(sb.position.x + 10, reward.position.y + 40)
		root.add_child(extra)
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(get_tree(), root, [MARGIN.position.y, MARGIN.size.x, MARGIN.size.y, MARGIN.position.x], [ok])
	ok.pressed.connect(popup.close)
	return popup


# --- Job mastery ----------------------------------------------------------------------

func _mastery(n: Dictionary) -> FlashPopup:
	var job_id: int = n["job_id"]
	var def: Dictionary = GameData.catalog.job(job_id)
	var root := Node2D.new()
	var white := FlashNine.make("UIWhiteStrokedRoundedBg", Vector2(473, 327))
	white.position = Vector2(25, 70)
	root.add_child(white)
	var gfx := FlashUi.make("UITaskMasteryLevelUp")
	if gfx == null:
		return null
	gfx.position.x = 25
	root.add_child(gfx)
	gfx.styled_text("fldHead", "Congratulations!", "casualA01")
	gfx.styled_text("titleField", def.get("name", "").to_upper(), "sansD04")
	gfx.styled_text("nextStarsInHeader", "next star in:", "casualA01")
	gfx.styled_text("jobsCompletedHeader", "Jobs Completed:", "casualA01")
	gfx.styled_text("fldCol1", "Jobs Completed:", "casualA01")
	gfx.styled_text("fldCol2", "Mastery:", "casualA01")
	gfx.styled_text("fldCol3", "Earns per job:", "casualA01")
	gfx.styled_text("fldCol4", "Reward:", "casualA01")
	var icon := FlashUi.make("UITaskIcon%d" % job_id)
	var holder := gfx.part("icon") as Node2D
	if icon != null and holder != null:
		holder.add_child(icon)
	var level: int = n["level"]
	var done: int = Backend.state()["job_mastery"].get(str(job_id), 0)
	var thresholds: Array = def.get("mastery_thresholds", [0, 0, 0, 0, 0])
	var xp_list: Array = def.get("mastery_xp", [0, 0, 0, 0, 0])
	gfx.styled_text("jobsCompletedField", str(done), "casualA01")
	gfx.styled_text("currentLevelField", str(level), "casualA01")
	if level < 5 and level < thresholds.size():
		gfx.styled_text("nextStarsInField", str(maxi(0, int(thresholds[level]) - done)), "casualA01")
	else:
		for part: String in ["nextStarsInHeader", "nextStarsInField"]:
			var p := gfx.part(part) as CanvasItem
			if p != null:
				p.visible = false
	var stars := gfx.part("masteryLevels") as FlashSymbol
	for i in range(1, 6):
		if stars != null and i <= level:
			var star := stars.part("l%d" % i) as FlashSymbol
			if star != null:
				star.goto(1)
		var row := gfx.part("l%d" % i) as FlashSymbol
		if row == null:
			continue
		if i <= level:
			row.goto(1)
		row.styled_text("thresholdField", str(thresholds[i - 1] if i - 1 < thresholds.size() else 0), "casualA01")
		row.styled_text("earnsField", "%d XP" % (xp_list[i - 1] if i - 1 < xp_list.size() else 0), "casualA01")
		var row_stars := row.part("masteryStars") as FlashSymbol
		if row_stars != null:
			for k in range(1, 6):
				var st := row_stars.part("l%d" % k) as CanvasItem
				if st != null:
					st.visible = k <= i
		var bonus: Dictionary = {}
		for tm: Dictionary in GameData.catalog.task_mastery_levels:
			if tm["level"] == i:
				bonus = tm
		for entry: Array in [["pointsReward", "pointsReward/pointsField", bonus.get("blue_bonus", 0)],
				["moneyReward", "moneyReward/moneyField", bonus.get("coin_bonus", 0)]]:
			var p := row.part(entry[0]) as CanvasItem
			if p != null:
				p.visible = i > 1 and entry[2] > 0
			row.styled_text(entry[1], Format.number(entry[2]), "casualA01")
	return FlashPopup.open_framed(get_tree(), root, [5, 20, -14, 20])
