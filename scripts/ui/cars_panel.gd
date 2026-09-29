class_name CarsPanel
extends GamePanel
## All the player's cars, including stored ones.

var game: Node


func _init(game_node: Node) -> void:
	game = game_node
	title = "My Cars"


func _build() -> void:
	var list := UiKit.vbox(6)
	for c: Dictionary in Backend.state()["cars"]:
		var row := UiKit.hbox(8)
		var thumb: Dictionary = GameData.car_art.get(str(c["car_id"]), {}).get("thumb", {})
		row.add_child(UiKit.texture_rect(GameData.texture(thumb.get("file", "")), Vector2(80, 44)))
		var info := UiKit.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label(GameData.car_name(c["car_id"]), 15))
		var where := "Parked"
		if c["bay_uid"] != 0:
			where = "On a work bay"
		elif not c["placed"]:
			where = "In storage"
		info.add_child(UiKit.label(where, 13, Color(0.85, 0.9, 1)))
		row.add_child(info)
		row.add_child(UiKit.button("Customize", func() -> void: game.open_panel(CarPanel.new(c["uid"], game), true), 14))
		if c["bay_uid"] == 0:
			row.add_child(UiKit.button("Place" if not c["placed"] else "Move", func() -> void: game.move_car(c["uid"]), 14))
		list.add_child(row)
	body.add_child(UiKit.scroll(list, Vector2(0, 500)))
