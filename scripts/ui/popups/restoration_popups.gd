class_name RestorationPopups
extends RefCounted
## Car restoration (views/carrestoration/popups): the junkers you can restore,
## restoring one, what you found in a junk pile, a restoration in progress on
## a work bay, and "Restoration Complete!".

const TEXT_COLOR := Color8(0x33, 0x4D, 0x66)
const GREY_TEXT := Color8(0x88, 0x88, 0x88)
const GREEN_TEXT := Color8(0x3C, 0x7A, 0x2E)
const GLOW := Color8(0x23, 0x4F, 0x70)
const PART_ICON := 44.0


## A build part's picture (carbuild/parts/part_<id>), [param size] across.
static func part_icon(part_id: int, size: float = PART_ICON) -> Sprite2D:
	var info: Dictionary = GameData.restoration_art.get("part_%d" % part_id, {})
	var tex := GameData.texture(info.get("file", ""))
	if tex == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex
	var k := size / maxf(tex.get_width(), tex.get_height())
	s.scale = Vector2(k, k)
	return s


static func part_name(part_id: int) -> String:
	return str(GameData.catalog.car_build_parts.get(part_id, {}).get("name", "Part")).replace("\n", " ").replace("\r", "")


static func build_car(build_id: int) -> int:
	return int(GameData.catalog.car_builds.get(build_id, {}).get("car_id", 0))


static func _price_text(cost: int) -> String:
	return ("%s Blue" % Format.number(cost)) if Backend.query().restoration_currency() == "blue" else "$%s" % Format.number(cost)


## CarRestorationPilePopup: what was in the junk pile you searched.
## [param kind] is "found", "notFound" or "alreadyCollected".
static func open_pile(tree: SceneTree, kind: String, part_id: int = 0) -> void:
	var gfx := FlashUi.make("CarRestorationPilePopupContent")
	if gfx == null:
		return
	for k: String in ["found", "notFound", "alreadyCollected"]:
		var p := gfx.part(k) as CanvasItem
		if p != null:
			p.visible = k == kind
	match kind:
		"found":
			gfx.styled_text("fldTitle", "Junk pile contents...", "casualA01")
			gfx.styled_text("found/fldFound", "You found a car part!", "casualA01")
			gfx.styled_text("found/fldPartName", part_name(part_id), "casualA01")
			var holder := gfx.part("found/thumbcontainer") as Node2D
			var icon := part_icon(part_id, 70)
			if holder != null and icon != null:
				holder.add_child(icon)
			Sound.play("SuccessSound1")
		"notFound":
			gfx.styled_text("fldTitle", "Junk pile contents...", "casualA01")
			gfx.styled_text("notFound/fldNotFound", "No car part found.", "casualA01")
			gfx.styled_text("notFound/fldChance", "Search junk piles for a chance\nto get free parts for your car build", "casualA01")
		_:
			gfx.styled_text("fldTitle", "Junk piles empty!", "casualA01")
			gfx.styled_text("alreadyCollected/fldOnlyOne", "Only one car part can be salvaged per day.", "casualA01")
			gfx.styled_text("alreadyCollected/fldComeBack", "Come back tomorrow!", "casualA01")
	var ok := FrameButton.with_text("OK", FrameButton.GREY)
	var popup := FlashPopup.open_framed(tree, gfx, [10, 20, 20, 20], [ok])
	ok.pressed.connect(popup.close)


## CarRestorationCarListPopup: every junker you can restore, with what it
## needs; pick one to restore. The Master Mechanic meter counts restorations.
static func open_list(tree: SceneTree, restore: Callable) -> GenericPopup:
	var q := Backend.query()
	var root := Node2D.new()
	var sub := FlashUi.styled_label("Restore these cars in your garage!\nNew car builds are brought in daily.", "sansD01", 16, TEXT_COLOR)
	root.add_child(sub)
	var mm := q.restorations_done()
	var need := int(GameData.catalog.consts.get("restorations_to_master_mechanic", 10))
	var meter := FlashUi.styled_label("Master Mechanic: %d/%d restored" % [mini(mm, need), need] if mm < need else "Master Mechanic!",
		"casualA01", 16, GREEN_TEXT if mm >= need else GREY_TEXT)
	meter.position = Vector2(400, 4)
	root.add_child(meter)
	var box := ScrollContainer.new()
	box.position = Vector2(0, 50)
	box.custom_minimum_size = Vector2(600, 330)
	box.size = Vector2(600, 330)
	box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	box.add_child(column)
	root.add_child(box)
	var popup := GenericPopup.custom(tree, "Vehicle Restoration", root, Vector2(600, 380), [])
	var level: int = Backend.state()["player"]["level"]
	var restored: Array = Backend.state()["restoration"]["restored"]
	for id: int in q.restoration_build_ids():
		var b: Dictionary = GameData.catalog.car_builds[id]
		var car: Dictionary = GameData.catalog.car(int(b["car_id"]))
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(580, 74)
		var row := Node2D.new()
		var thumb := MysteryBoxPopups.car_thumb(int(b["car_id"]), 90)
		if thumb != null:
			thumb.position = Vector2(50, 36)
			row.add_child(thumb)
		var title := FlashUi.styled_label(GameData.car_name(int(b["car_id"])), "casualA01", 18, TEXT_COLOR)
		title.position = Vector2(105, 2)
		row.add_child(title)
		if int(b["task_id"]) == GameLogic.BUILD_MASTER_MECHANIC:
			var tag := FlashUi.styled_label("Master Mechanic", "casualA01", 13, GREEN_TEXT)
			tag.position = Vector2(105 + title.get_minimum_size().x + 10, 6)
			row.add_child(tag)
		var x := 105.0
		for p: Dictionary in b["parts"]:
			var icon := part_icon(int(p["part_id"]), 26)
			if icon != null:
				icon.position = Vector2(x + 13, 44)
				row.add_child(icon)
			var n := FlashUi.styled_label("x%d" % int(p["quantity"]), "casualA01", 13, TEXT_COLOR)
			n.position = Vector2(x + 27, 36)
			row.add_child(n)
			x += 60
		var lvl := int(car.get("min_level", 0))
		if lvl > level:
			var lock := FlashUi.styled_label("Level %d" % lvl, "casualA01", 16, GREY_TEXT)
			lock.position = Vector2(500, 24)
			row.add_child(lock)
		else:
			var go := FlashTextButton.create("Restore", FlashTextButton.Kind.GREEN, 86, 34, 17, true)
			go.position = Vector2(486, 18)
			go.pressed.connect(func() -> void:
				popup.close()
				restore.call(id))
			row.add_child(go)
		if restored.has(id):
			var done := FlashUi.styled_label("Restored", "casualA01", 12, GREEN_TEXT)
			done.position = Vector2(498, 54)
			row.add_child(done)
		slot.add_child(row)
		column.add_child(slot)
	return popup


## A restoration on a work bay (CarRestorationBuildConstructionPopup): the
## junker, how far along it is, and a row per part: install the ones you
## have, buy the ones you don't. Finish once every part is in.
static func open_construction(tree: SceneTree, bay_uid: int, changed: Callable) -> GenericPopup:
	var q := Backend.query()
	var build := q.bay_build(bay_uid)
	if build.is_empty():
		return null
	var b: Dictionary = GameData.catalog.car_builds[int(build["build_id"])]
	var root := Node2D.new()
	var head := FlashUi.styled_label("Restore this car to mint condition!", "sansD01", 16, TEXT_COLOR)
	root.add_child(head)
	var view := CarView.new()
	view.setup(CarView.stock_entry(int(b["primer_car_id"]), 0), CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.5, 0.5)
	view.position = Vector2(110, 150)
	root.add_child(view)
	var goal := FlashUi.styled_label("Becomes a %s" % GameData.car_name(int(b["car_id"])), "casualA01", 15, GREY_TEXT)
	goal.position = Vector2(10, 190)
	root.add_child(goal)
	var total := 0
	var have_total := 0
	for p: Dictionary in b["parts"]:
		total += int(p["quantity"])
		have_total += mini(int(p["quantity"]), int(build["parts"].get(str(p["part_id"]), 0)))
	var progress := FlashUi.styled_label("Progress: %d%%" % (100 * have_total / maxi(1, total)), "casualA01", 18, GREEN_TEXT)
	progress.position = Vector2(10, 220)
	root.add_child(progress)
	var inventory: Dictionary = Backend.state()["restoration"]["inventory"]
	var popup: GenericPopup
	var refresh := func() -> void:
		popup.close()
		changed.call()
		open_construction(tree, bay_uid, changed)
	var y := 30.0
	for p: Dictionary in b["parts"]:
		var pid := int(p["part_id"])
		var need := int(p["quantity"])
		var put := int(build["parts"].get(str(pid), 0))
		var owned := int(inventory.get(str(pid), 0))
		var icon := part_icon(pid, 36)
		if icon != null:
			icon.position = Vector2(250, y + 18)
			root.add_child(icon)
		var label := FlashUi.styled_label("%s  %d/%d" % [part_name(pid), put, need], "casualA01", 16,
			GREEN_TEXT if put >= need else TEXT_COLOR)
		label.position = Vector2(275, y + 6)
		root.add_child(label)
		if put < need:
			var button: FlashTextButton
			if owned > 0:
				button = FlashTextButton.create("Install (%d)" % owned, FlashTextButton.Kind.GREEN, 110, 30, 15, true)
				button.pressed.connect(func() -> void:
					var r: GameResult = await Backend.install_build_part(bay_uid, pid)
					if r.ok:
						Sound.play("ClickSound01")
					refresh.call())
			else:
				button = FlashTextButton.create("Buy %s" % _price_text(q.build_part_price(pid)), FlashTextButton.Kind.BLUE, 110, 30, 15, true)
				button.pressed.connect(func() -> void:
					var r: GameResult = await Backend.buy_build_part(pid)
					if not r.ok:
						Sound.play("ActionDeniedSound")
						GenericPopup.message(tree, "Restoration", r.error)
						return
					refresh.call())
			button.position = Vector2(470, y + 4)
			root.add_child(button)
		y += 44.0
	var tip := FlashUi.styled_label("Townsfolk drop off parts now and then, and the Junk Yard\nhas a free part every day.", "casualA01", 13, GREY_TEXT)
	tip.position = Vector2(250, y + 6)
	root.add_child(tip)
	var buttons: Array = []
	var finish: FrameButton = null
	if q.build_parts_needed(bay_uid).is_empty():
		finish = FrameButton.with_text("Finish Restoration", FrameButton.GREEN)
		buttons.append(finish)
	var abandon := FrameButton.with_text("Give Up", FrameButton.RED)
	buttons.append(abandon)
	popup = GenericPopup.custom(tree, "Restoration", root, Vector2(590, maxf(260.0, y + 50)), buttons)
	if finish != null:
		finish.pressed.connect(func() -> void:
			popup.close()
			var r: GameResult = await Backend.finish_restoration(bay_uid)
			if r.ok:
				changed.call()
				open_complete(tree, int(r.data["car_id"]))
				for n: Dictionary in r.notices:
					if n.get("kind", "") == "master_mechanic":
						open_master_mechanic(tree))
	abandon.pressed.connect(func() -> void:
		GenericPopup.ask(tree, "Give Up?", "Stop restoring this car? The parts you put in go back to your inventory.", "Give Up",
			func() -> void:
				popup.close()
				await Backend.abandon_restoration(bay_uid)
				changed.call()))
	return popup


## CarRestorationRestorationCompletePopup.
static func open_complete(tree: SceneTree, car_id: int) -> void:
	var gfx := FlashUi.make("CarRestorationRestorationCompletePopupContent")
	if gfx == null:
		GenericPopup.message(tree, "Restoration Complete!", "Your %s is good as new!" % GameData.car_name(car_id))
		return
	var car: Dictionary = GameData.catalog.car(car_id)
	gfx.styled_text("fldTitle", "Restoration Complete!", "casualA01")
	gfx.styled_text("fldMake", str(car.get("make", "")), "casualA01")
	gfx.styled_text("fldModel", str(car.get("model", "")), "casualA01")
	gfx.styled_text("placedInStorage/fldLabel", "Placed in your garage", "casualA01")
	var root := Node2D.new()
	root.add_child(gfx)
	var view := CarView.new()
	view.setup(CarView.stock_entry(car_id, 0), CarView.VIEW_ANGLE, false)
	view.scale = Vector2(0.6, 0.6)
	view.position = Vector2(200, 230)
	root.add_child(view)
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(tree, root, [10, 20, 20, 20], [ok])
	ok.pressed.connect(popup.close)
	Sound.play("SuccessSound2")


## MasterMechanicAchievedPopup.
static func open_master_mechanic(tree: SceneTree) -> void:
	var gfx := FlashUi.make("MasterMechanicAchievedPopupGfx")
	var need := int(GameData.catalog.consts.get("restorations_to_master_mechanic", 10))
	if gfx == null:
		return
	gfx.styled_text("titleFld", "Master Mechanic Level Achieved!", "casualA01")
	gfx.styled_text("descriptionFld", "You've completed %d unique car restorations and are now a master mechanic!" % need, "casualA01")
	gfx.styled_text("footerFld", "Master mechanic tier cars can now be restored in the junkyard!", "casualA01")
	var ok := FrameButton.with_text("OK", FrameButton.GREEN)
	var popup := FlashPopup.open_framed(tree, gfx, [10, 20, 20, 20], [ok])
	ok.pressed.connect(popup.close)


## MasterMechanicInfoPopup: how to become one.
static func open_master_mechanic_info(tree: SceneTree) -> void:
	var need := int(GameData.catalog.consts.get("restorations_to_master_mechanic", 10))
	var done := Backend.query().restorations_done()
	GenericPopup.message(tree, "Become a Master Mechanic!",
		"Restore %d DIFFERENT cars in the Junk Yard to reach the master mechanic status and unlock special car restorations!\n\nRestored so far: %d" % [need, mini(done, need)])
