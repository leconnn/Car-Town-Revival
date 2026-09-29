class_name ShopPanel
extends GamePanel
## Garage shop: work bays, furniture, decorations, floors and walls, plus
## the player's stored items.

const TABS: Array[Array] = [
	["Work Bays", [5]], ["Decor", [9]], ["Tables & Chairs", [1, 2]],
	["Tools", [3, 4]], ["Trophies & Signs", [12, 13]], ["Floors", [6]],
	["Walls", [7]], ["Storage", []],
]

var game: Node
var _grid: GridContainer
var _tab := 0
var _use_blue := false


func _init(game_node: Node) -> void:
	game = game_node
	title = "Garage Shop"


func _build() -> void:
	var tabs := UiKit.hbox(6)
	for i in TABS.size():
		var b := UiKit.button(TABS[i][0], _set_tab.bind(i), 16)
		b.disabled = i == _tab
		tabs.add_child(b)
	body.add_child(tabs)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	body.add_child(UiKit.scroll(_grid, Vector2(0, 400)))
	if TABS[_tab][0] == "Storage":
		_fill_storage()
	else:
		_fill_shop(TABS[_tab][1])


func _set_tab(i: int) -> void:
	_tab = i
	UiKit.clear(body)
	_build()


func _on_state_changed() -> void:
	# Rebuilding would lose scroll position; only storage changes shape.
	if TABS[_tab][0] == "Storage":
		UiKit.clear(body)
		_build()


func _fill_shop(categories: Array) -> void:
	var s := Backend.state()
	var level: int = s["player"]["level"]
	for id: int in Backend.query().shop_item_ids():
		var it: Dictionary = GameData.catalog.item(id)
		if not categories.has(it["category"]):
			continue
		if not GameData.item_art.has(str(id)) and it["category"] != GarageGrid.CAT_FLOOR_TILE:
			continue
		if it["category"] == GarageGrid.CAT_FLOOR_TILE and not ResourceLoader.exists("res://assets/ea/art/floors/%d.jpg" % id) \
				and not FileAccess.file_exists("res://assets/ea/art/floors/%d.jpg" % id):
			continue
		_grid.add_child(_tile(id, it, level))


func _tile(id: int, it: Dictionary, level: int) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 150)
	var box := UiKit.vbox(2)
	UiKit.place(box, Rect2(0, 0, 1, 1))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var tex: Texture2D
	if it["category"] == GarageGrid.CAT_FLOOR_TILE:
		tex = GameData.texture("floors/%d.jpg" % id)
	else:
		tex = GameData.texture(GameData.item_art.get(str(id), {}).get("thumb", {}).get("file", ""))
	var tr := UiKit.texture_rect(tex, Vector2(140, 80))
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var name := UiKit.label(it["name"] if it["name"] != "" else "Item %d" % id, 12)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.custom_minimum_size = Vector2(140, 0)
	box.add_child(name)
	var price: Label
	var cat: int = it["category"]
	var per_tile := cat == GarageGrid.CAT_FLOOR_TILE or cat == GarageGrid.CAT_WALL
	if it["min_level"] > level:
		price = UiKit.label("Level %d" % it["min_level"], 13, Color(1, 0.6, 0.55))
		b.disabled = true
	else:
		var blue_only: bool = not it["can_buy_with_coins"] and it["price"] <= 0
		price = UiKit.price_label(it["price"], it["blue_price"], blue_only, 13)
		if per_tile:
			price.text += " / tile"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(price)
	b.pressed.connect(_buy.bind(id))
	return b


func _buy(id: int) -> void:
	var it: Dictionary = GameData.catalog.item(id)
	var blue_only: bool = not it["can_buy_with_coins"] and it["price"] <= 0
	var cat: int = it["category"]
	if cat == GarageGrid.CAT_FLOOR_TILE or cat == GarageGrid.CAT_WALL:
		var r: GameResult = await Backend.set_surface(id, blue_only)
		if r.ok:
			toast("Your garage has a new %s!" % ("floor" if cat == GarageGrid.CAT_FLOOR_TILE else "wall"))
		return
	game.place_new_item(id, blue_only)


func _fill_storage() -> void:
	var storage: Dictionary = Backend.state()["storage"]
	if storage.is_empty():
		body.add_child(UiKit.label("Nothing in storage. Stored items and mission rewards show up here.", 16))
		return
	for key: String in storage:
		var id := int(key)
		var it: Dictionary = GameData.catalog.item(id)
		var box := UiKit.vbox(4)
		box.custom_minimum_size = Vector2(150, 0)
		var tex := GameData.texture(GameData.item_art.get(key, {}).get("thumb", {}).get("file", ""))
		box.add_child(UiKit.texture_rect(tex, Vector2(140, 70)))
		box.add_child(UiKit.label("%s  x%d" % [it.get("name", "Item"), storage[key]], 13))
		var row := UiKit.hbox(4)
		row.add_child(UiKit.button("Place", func() -> void: game.place_stored_item(id), 14))
		row.add_child(UiKit.button("Sell", func() -> void:
			var r: GameResult = await Backend.sell_stored_item(id)
			if r.ok:
				toast("Sold for %s coins" % Format.number(r.data["coins"])), 14))
		box.add_child(row)
		_grid.add_child(box)
