class_name FuelStorePopup
extends RefCounted
## The fuel store (views/townracing/store/BuyFuelStore, a MiniStore of fuel
## cans): "Fill up your tank..." and a tile per can, bought with blue coins.
## Also the "out of fuel" popup that opens it.

const TILE_STEP := 96.0
const TILE_HEIGHT := 125.0
const LABEL_COLOR := Color8(0x33, 0x4D, 0x66)


## The store itself.
static func open(tree: SceneTree) -> GenericPopup:
	var ids: Array = GameData.catalog.tune("racing.fuel_can_ids", [])
	var row := Node2D.new()
	var x := 0.0
	for id: int in ids:
		var def := GameData.catalog.consumable(id)
		if def.is_empty():
			continue
		var tile := StoreTile.create(_picture(def), def.get("blue_price", 0), true)
		tile.position.x = x
		tile.pressed.connect(func() -> void: _ask(tree, id))
		row.add_child(tile)
		x += TILE_STEP
	var ok := FrameButton.with_text("Close", FrameButton.GREY)
	var p := GenericPopup.custom(tree, "Fill up your tank...", row, Vector2(maxf(x, 100.0), TILE_HEIGHT), [ok])
	ok.pressed.connect(p.close)
	return p


## "You're out of fuel!" with a way to the store.
static func open_out_of_fuel(tree: SceneTree) -> GenericPopup:
	var q := Backend.query()
	var per := q.fuel_refill_seconds()
	var text := "You're out of fuel!\nA gallon comes back every %d minutes, or you can fill up in the store." % maxi(1, per / 60)
	var label := FlashUi.styled_label(text, "casualA01", 22, LABEL_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	label.size = Vector2(420, 0)
	var holder := Node2D.new()
	holder.add_child(label)
	var buy := FrameButton.with_text("Buy Fuel", FrameButton.GREEN)
	var later := FrameButton.with_text("Not now", FrameButton.GREY)
	var p := GenericPopup.custom(tree, "Refuel and keep racing!", holder, Vector2(420, label.get_minimum_size().y), [buy, later])
	buy.pressed.connect(func() -> void:
		p.close()
		open(tree))
	later.pressed.connect(p.close)
	return p


static func _picture(def: Dictionary) -> Node2D:
	var holder := Node2D.new()
	var icon := FlashUi.make("UIEnergyFuelStoreIconAsset")
	if icon != null:
		var r := icon.local_bounds()
		var k := minf(1.0, 44.0 / maxf(r.size.x, r.size.y))
		icon.scale = Vector2(k, k)
		icon.position = -(r.position + r.size / 2.0) * k + Vector2(0, -8)
		holder.add_child(icon)
	var amount: int = def.get("amount", 1)
	var text := "Full tank" if def.get("kind", 1) == 2 else ("%d gal" % amount)
	var label := FlashUi.styled_label(text, "casualA01", 16, LABEL_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(70, 20)
	label.position = Vector2(-35, 14)
	holder.add_child(label)
	return holder


static func _ask(tree: SceneTree, id: int) -> void:
	var def := GameData.catalog.consumable(id)
	var text := "Buy %s for %d blue coins?" % [
		"a full tank" if def.get("kind", 1) == 2 else "%d gallons" % int(def.get("amount", 1)), int(def.get("blue_price", 0))]
	GenericPopup.ask(tree, "Buy Fuel", text, "Buy", func() -> void:
		var r: GameResult = await Backend.buy_fuel(id)
		if r.ok:
			Sound.play("MoneyCollectSound01"))
