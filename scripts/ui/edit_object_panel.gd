class_name EditObjectPanel
extends GamePanel
## Edit mode actions for one item or car: move, rotate, store, sell.

var kind: String
var uid: int
var game: Node


func _init(object_kind: String, object_uid: int, game_node: Node) -> void:
	kind = object_kind
	uid = object_uid
	game = game_node


func _build() -> void:
	if kind == "car":
		var car := Backend.query().get_car(uid)
		if car.is_empty():
			close()
			return
		set_title(GameData.car_name(car["car_id"]))
		var row := UiKit.hbox()
		row.add_child(UiKit.button("Move", func() -> void: game.move_car(uid)))
		row.add_child(UiKit.button("Rotate", func() -> void:
			await Backend.move_car(uid, car["x"], car["y"], car["rot"] + 1)))
		row.add_child(UiKit.button("Store", func() -> void:
			await Backend.store_car(uid)
			close()))
		body.add_child(row)
		return
	var entry: Dictionary = {}
	for it: Dictionary in Backend.state()["garage"]["items"]:
		if it["uid"] == uid:
			entry = it
	if entry.is_empty():
		close()
		return
	var def: Dictionary = GameData.catalog.item(entry["item_id"])
	set_title(def.get("name", "Item"))
	var refund: int = floori(def.get("price", 0) * float(GameData.catalog.tune("economy.item_resell_fraction", 0.5)))
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Move", func() -> void: game.move_item(uid)))
	row.add_child(UiKit.button("Rotate", func() -> void:
		await Backend.move_item(uid, entry["x"], entry["y"], entry["rot"] + 1)))
	row.add_child(UiKit.button("Store", func() -> void:
		var r: GameResult = await Backend.store_item(uid)
		if r.ok:
			close()))
	row.add_child(UiKit.button("Sell (%s)" % Format.number(refund), func() -> void:
		var r: GameResult = await Backend.sell_item(uid)
		if r.ok:
			toast("Sold for %s coins." % Format.number(r.data["coins"]))
			close()))
	body.add_child(row)
