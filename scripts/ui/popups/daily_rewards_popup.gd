class_name DailyRewardsPopup
extends Node2D
## The daily login bonus (integrations/dailyrewards/views/DailyRewardsPopup on
## DailyRewardsPopupContent): "Daily Bonus!", today's prize with a starburst,
## tomorrow's greyed out, the days after it as mystery boxes, and what was
## added to your inventory. Opening it takes the prize (the original claimed
## it when the popup closed).

const SLOTS := 8
## The pictures for a prize type are frames of the `images` clip.
const TYPE_LABELS := {"Coins": "Coins", "Point": "Point", "XP": "XP", "Item": "Item", "Car": "Car", "Petrol": "Petrol",
	"TournamentItem": "TournamentItem"}
const ADDED_TO := {"Coins": "coins", "Point": "points", "XP": "XP", "Petrol": "tank", "Item": "inventory", "Car": "inventory"}
const TITLE_GLOW := Color8(0x23, 0x4F, 0x70)


## Takes today's prize and shows it, if there is one to take.
static func open_if_due(tree: SceneTree) -> void:
	if not Backend.query().daily_reward_status(Backend.now()).get("available", false):
		return
	var r: GameResult = await Backend.claim_daily_reward()
	if r.ok:
		open(tree, r.data)


static func open(tree: SceneTree, claimed: Dictionary) -> FlashPopup:
	var p := DailyRewardsPopup.new()
	p._build(claimed)
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(tree, p, [10, 12, 12, 12], [ok])
	ok.pressed.connect(popup.close)
	Sound.play("SuccessSound1")
	return popup


func _build(claimed: Dictionary) -> void:
	var content := FlashUi.make("DailyRewardsPopupContent")
	if content == null:
		return
	add_child(content)
	var streak: int = claimed["streak"]
	var list := GameData.catalog.daily_rewards
	content.styled_text("titleFieldContainer/titleField", "Daily Bonus!", "casualA01")
	content.styled_text("messageField1", "Earn an extra bonus for each consecutive day!", "casualA01")
	content.styled_text("messageField2", "You have logged in %d %s in a row." % [streak, "Day" if streak == 1 else "Days"], "casualA01")
	for i in SLOTS:
		var slot := content.part("rewardContainer%d" % i) as FlashSymbol
		if slot == null:
			continue
		var reward: Dictionary = list[(streak - 1 + i) % list.size()]
		var burst := slot.part("starBurst") as CanvasItem
		if burst != null:
			burst.visible = i == 0
		var images := slot.part("images") as FlashSymbol
		if i == 0 or i == 1:
			_show_reward(images, reward, i == 1)
			slot.styled_text("dayField", "Today" if i == 0 else "Tomorrow", "casualA01")
		else:
			if images != null:
				images.goto("unknownCar" if reward["type"] == "Car" else "unknownItem")
			slot.styled_text("dayField", "Day %d" % (streak + i), "casualA01")
	var added := content.part("addToInventoryContainer") as FlashSymbol
	if added != null:
		var text := "%s has been added\nto your %s!" % [_reward_text(claimed), ADDED_TO.get(claimed["type"], "inventory")]
		added.styled_text("messageField3", text, "casualA01")
		var images := added.part("images") as FlashSymbol
		if images != null:
			images.goto(TYPE_LABELS.get(claimed["type"], "Coins"))
		added.position.x = 280.0 - added.local_bounds().size.x / 2.0


## The picture for a prize: its type's frame, plus the car or item's own art.
func _show_reward(images: FlashSymbol, reward: Dictionary, greyed: bool) -> void:
	if images == null:
		return
	images.goto(TYPE_LABELS.get(reward["type"], "Coins"))
	if greyed:
		images.modulate = Color(0.75, 0.75, 0.75, 0.7)
	var tex: Texture2D = null
	match reward["type"]:
		"Car":
			tex = GameData.texture(GameData.car_art.get(str(reward["id"]), {}).get("thumb", {}).get("file", ""))
		"Item":
			tex = GameData.texture(GameData.item_art.get(str(reward["id"]), {}).get("thumb", {}).get("file", ""))
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		var k := minf(1.0, 64.0 / maxf(tex.get_width(), tex.get_height()))
		s.scale = Vector2(k, k)
		images.add_child(s)


static func _reward_text(r: Dictionary) -> String:
	var amount: int = r["amount"]
	match r["type"]:
		"Coins": return "%s Gold Coins" % Format.number(amount)
		"Point": return "%d Blue Points" % amount
		"XP": return "%d XP" % amount
		"Petrol": return "%d Gallons of Fuel" % amount
		"Car": return "A %s" % GameData.car_name(int(r["id"]))
		"Item": return str(GameData.catalog.item(int(r["id"])).get("name", "An item"))
	return "A bonus"
