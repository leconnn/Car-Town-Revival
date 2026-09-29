class_name TownPanel
extends GamePanel
## The GPS map: pick a place in town to drive to.

## Location id -> town background exported from the original.
const ENVIRONMENTS: Dictionary[int, String] = {
	9: "environment_diner", 7: "environment_coffee_place",
	6: "environment_pizza_place", 8: "environment_drive_in_v3",
}
const BLURBS: Dictionary[int, String] = {
	9: "Lou's Diner is where street racers hang out.",
	7: "Grab a coffee and check out the cars in the lot.",
	6: "Tony's Pizza: good slices, fast cars.",
	8: "The Drive-In Movie Theatre, a classic Car Town hangout.",
	17: "The Junk Yard, full of old cars waiting to be restored.",
	4: "Casual Racing: friendly races around town.",
	1: "High Stakes: bet coins on pro races.",
}


func _init() -> void:
	title = "Town (GPS)"


func _ready() -> void:
	super()
	Backend.open_gps()


func _on_state_changed() -> void:
	pass


func _build() -> void:
	body.add_child(UiKit.label("Where do you want to drive?", 18))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var level: int = Backend.state()["player"]["level"]
	for loc_id: int in Backend.query().town_location_ids():
		var loc: Dictionary = GameData.catalog.locations[loc_id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 210)
		var box := UiKit.vbox(4)
		UiKit.place(box, Rect2(0, 0, 1, 1))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var icon: Dictionary = _town_art("icon_%d" % loc_id)
		var tr := UiKit.texture_rect(GameData.texture(icon.get("file", "")), Vector2(240, 150))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
		var name := UiKit.label(loc["name"], 17)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name)
		if loc["min_level"] > level:
			b.disabled = true
			var lock := UiKit.label("Level %d" % loc["min_level"], 14, Color(1, 0.6, 0.55))
			lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(lock)
		b.pressed.connect(_visit.bind(loc_id))
		grid.add_child(b)
	body.add_child(UiKit.scroll(grid, Vector2(0, 460)))


static func _town_art(key: String) -> Dictionary:
	var manifest: Variant = JsonUtil.read_file(GameData.EA_ART_DIR.path_join("town.json"))
	return manifest.get(key, {}) if typeof(manifest) == TYPE_DICTIONARY else {}


func _visit(loc_id: int) -> void:
	var r: GameResult = await Backend.visit_location(loc_id)
	if not r.ok:
		return
	var game := get_tree().current_scene
	game.open_panel(LocationPanel.new(loc_id))


class LocationPanel:
	extends GamePanel
	## A place in town. Street racing plugs in here in a later update.

	var location_id: int

	func _init(loc_id: int) -> void:
		location_id = loc_id
		title = GameData.catalog.locations[loc_id]["name"]

	func _on_state_changed() -> void:
		pass

	func _build() -> void:
		var env: String = TownPanel.ENVIRONMENTS.get(location_id, "")
		var stage := Control.new()
		stage.custom_minimum_size = Vector2(900, 430)
		stage.clip_contents = true
		stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(stage)
		if env != "":
			var art: Dictionary = TownPanel._town_art(env)
			var bg := TextureRect.new()
			bg.texture = GameData.texture(art.get("file", ""))
			bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			UiKit.place(bg, Rect2(0, 0, 1, 1))
			stage.add_child(bg)
			_park_cars(stage)
		else:
			var icon: Dictionary = TownPanel._town_art("icon_%d" % location_id)
			var tr := UiKit.texture_rect(GameData.texture(icon.get("file", "")), Vector2(300, 260))
			UiKit.place(tr, Rect2(0.5, 0.5, 0.5, 0.5), Rect2(-150, -130, 150, 130))
			stage.add_child(tr)
		var blurb := UiKit.label(TownPanel.BLURBS.get(location_id, ""), 18)
		body.add_child(blurb)
		body.add_child(UiKit.label("Racing and more here are coming in a future update.", 15, Color(0.85, 0.9, 1)))
		body.add_child(UiKit.button("Drive back to the garage", close))

	## A few cars from around town parked in the lot, just for looks.
	func _park_cars(stage: Control) -> void:
		var ids := Backend.query().dealer_car_ids()
		if ids.is_empty():
			return
		var state := location_id * 7919 + Backend.now() / 3600
		var spots: Array[Vector2] = [Vector2(250, 230), Vector2(470, 330), Vector2(700, 250)]
		for i in spots.size():
			state = SimpleRng.next(state)
			var car_id: int = ids[(state >> 8) % ids.size()]
			var colors := GameData.catalog.colors_for_car(car_id)
			var color_id: int = colors[(state >> 12) % colors.size()]["id"] if not colors.is_empty() else 0
			var v := CarView.new()
			v.setup(CarPreviewBox.stock_entry(car_id, color_id), CarView.VIEW_FRONT, i % 2 == 0)
			v.position = spots[i]
			stage.add_child(v)
