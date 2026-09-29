class_name GarageView
extends Node2D
## Draws the player's garage from the save: floor, walls, items, cars,
## customer cars on the street and job status bubbles. Rebuilt whenever the
## state changes; the garage is small enough that this stays cheap.

signal object_clicked(kind: String, uid: int)
signal empty_tile_clicked(tile: Vector2i)

## The town around the garage, positioned like the original Floor and
## ShowRoomContainer: everything hangs off the backdrop's anchor, which moves
## down 35 px per tile of land so the crossroads stays at the front corner.
const TOWN_FILL := Color8(0x6C, 0xB2, 0x4F)
const BG_ORIGIN_Y := -1854.0
const BG_ANCHOR_X := -1500.0
## Waiting customers park on the street along the garage's front-left side.
const CUSTOMER_STREET_OFFSET := 3
const CUSTOMER_SPACING := 5

var land_size := Vector2i(10, 10)
## When false, clicks are ignored (e.g. while a panel handles placement).
var interactive := true
## Another player's garage being visited (read-only), or {} for our own.
var visiting: Dictionary = {}

var _floor_layer: Node2D
var _wall_layer: Node2D
var _object_layer: Node2D
var _town_front_layer: Node2D
var _overlay_layer: Node2D
## Drawn objects for hit testing, in draw order: {"kind", "uid", "node"}.
var _pickables: Array[Dictionary] = []
var _job_bubbles: Dictionary[int, JobStatus] = {}
var _hover_key := ""
var _grid_on := false


func _ready() -> void:
	_floor_layer = Node2D.new()
	_wall_layer = Node2D.new()
	_object_layer = Node2D.new()
	_town_front_layer = Node2D.new()
	_overlay_layer = Node2D.new()
	for layer in [_floor_layer, _wall_layer, _object_layer, _town_front_layer, _overlay_layer]:
		add_child(layer)
	Backend.state_changed.connect(rebuild)
	rebuild()


func _process(_delta: float) -> void:
	if not visiting.is_empty():
		return
	for bay_uid: int in _job_bubbles:
		_job_bubbles[bay_uid].refresh(Backend.now())


func visit(player_state: Dictionary) -> void:
	visiting = player_state
	rebuild()


func go_home() -> void:
	visiting = {}
	rebuild()


func rebuild() -> void:
	var s := visiting if not visiting.is_empty() else Backend.state()
	if s.is_empty():
		return
	var land: Dictionary = GameData.catalog.land(s["garage"]["land_id"])
	land_size = Vector2i(land.get("size_x", 10), land.get("size_y", 10))
	for layer in [_floor_layer, _wall_layer, _object_layer, _town_front_layer, _overlay_layer]:
		for c in layer.get_children():
			c.queue_free()
	_pickables.clear()
	_job_bubbles.clear()
	_build_town()
	_build_floor(s["garage"]["floor_item_id"])
	if _grid_on:
		_build_grid()
	_build_walls(s["garage"]["wall_item_id"])
	_build_objects(s)


## Screen position where a floor object at tile (h, v) is anchored.
static func object_position(h: int, v: int) -> Vector2:
	return Iso.to_screen(h + 0.5, v + 0.5) + Vector2(-35, -17.5)


func tile_under_mouse() -> Vector2i:
	return Iso.tile_at(get_local_mouse_position())


func center_screen_position() -> Vector2:
	return Iso.to_screen(land_size.x / 2.0, land_size.y / 2.0)


# --- Floor, walls, town ---------------------------------------------------------------

func _build_floor(floor_item_id: int) -> void:
	var poly := Polygon2D.new()
	poly.polygon = Iso.area_polygon(0, 0, land_size.x, land_size.y)
	var tex: Texture2D = GameData.texture("floors/%d.jpg" % floor_item_id)
	var size := Vector2(land_size) * 50.0
	if tex != null:
		# Floor tile textures are top-down squares: 50 texture px per tile.
		poly.texture = tex
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		poly.uv = PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), size, Vector2(0, size.y)])
	else:
		# The original default floor: one soft cream gradient stretched over the lot.
		tex = GameData.main_texture("swcassets.img.activeAreaBG")
		if tex != null:
			var ts := tex.get_size()
			poly.texture = tex
			poly.uv = PackedVector2Array([Vector2(0, 0), Vector2(ts.x, 0), ts, Vector2(0, ts.y)])
		else:
			poly.color = Color(0.96, 0.93, 0.87)
	_floor_layer.add_child(poly)


## Edit mode's floor grid (Floor.showGrid): a 1 px line along every tile
## edge. The original inverted what was under the lines; a dark translucent
## line reads the same on the default floor.
func show_grid(on: bool) -> void:
	_grid_on = on
	rebuild()


func _build_grid() -> void:
	var grid := Node2D.new()
	grid.name = "Grid"
	for i in land_size.y + 1:
		grid.add_child(_grid_line(Iso.to_screen(0, i), Iso.to_screen(land_size.x, i)))
	for i in land_size.x + 1:
		grid.add_child(_grid_line(Iso.to_screen(i, 0), Iso.to_screen(i, land_size.y)))
	_floor_layer.add_child(grid)


static func _grid_line(a: Vector2, b: Vector2) -> Line2D:
	var l := Line2D.new()
	l.points = PackedVector2Array([a, b])
	l.width = 1.0
	l.default_color = Color(0.1, 0.1, 0.25, 0.35)
	return l


## Walls are only drawn if the player picked a wall style.
func _build_walls(wall_item_id: int) -> void:
	var frames: Array = GameData.item_art.get(str(wall_item_id), {}).get("frames", [])
	if wall_item_id == 0 or frames.size() < 2:
		return
	# Frame 0 runs along the h = 0 edge, frame 1 along the v = 0 edge.
	for v in land_size.y:
		_wall_layer.add_child(_wall_sprite(frames[0], Iso.to_screen(0, v)))
	for h in land_size.x:
		_wall_layer.add_child(_wall_sprite(frames[1], Iso.to_screen(h, 0)))


func _wall_sprite(info: Dictionary, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = GameData.texture(info["file"])
	s.centered = false
	s.offset = -Vector2(info["o"][0], info["o"][1])
	s.position = pos
	return s


func _town_sprite(tex: Texture2D, pos: Vector2, scale_f: float = 1.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.position = pos
	s.scale = Vector2(scale_f, scale_f)
	return s


## Roads, grass and the dealership, at the original's offsets.
func _build_town() -> void:
	var anchor_y := BG_ORIGIN_Y + 35.0 * maxi(land_size.x, land_size.y)
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([Vector2(-6000, anchor_y - 6000), Vector2(6000, anchor_y - 6000),
		Vector2(6000, anchor_y + 8000), Vector2(-6000, anchor_y + 8000)])
	fill.color = TOWN_FILL
	_floor_layer.add_child(fill)
	var bg := GameData.main_texture("swcassets.img.defaultBG")
	if bg != null:
		_floor_layer.add_child(_town_sprite(bg, Vector2(BG_ANCHOR_X, anchor_y + floorf(1655.0 * 2.0 / 3.0))))
	var lot := GameData.main_texture("swcassets.img.ShowroomGround")
	if lot != null:
		_floor_layer.add_child(_town_sprite(lot, Vector2(BG_ANCHOR_X + 2008, anchor_y + 1381 + 178)))
	var showroom := GameData.main_texture("swcassets.img.Showroom")
	if showroom != null:
		var s := _town_sprite(showroom, Vector2(BG_ANCHOR_X + 2484, anchor_y + 1381), 2.0 / 3.0)
		_town_front_layer.add_child(s)
		_pickables.append({"kind": "showroom", "uid": 0, "node": s})


# --- Objects ---------------------------------------------------------------------------

func _build_objects(s: Dictionary) -> void:
	var entries: Array[Dictionary] = []
	var car_size: Array = GameData.catalog.tune("garage.car_size", [4, 3])
	var bays: Dictionary[int, Dictionary] = {}
	for it: Dictionary in s["garage"]["items"]:
		var def: Dictionary = GameData.catalog.item(it["item_id"])
		if not GarageGrid.is_floor_object(def):
			continue
		var size := GarageGrid.rotated_size(def["size_x"], def["size_y"], it["rot"])
		entries.append({"kind": "item", "entry": it, "h": it["x"], "v": it["y"], "size": size})
		if def["category"] == GarageGrid.CAT_WORK_BAY:
			bays[it["uid"]] = {"item": it, "size": size}
	for c: Dictionary in s["cars"]:
		if not c["placed"]:
			continue
		if c["bay_uid"] != 0 and bays.has(c["bay_uid"]):
			entries.append(_on_bay_entry("car", c, bays[c["bay_uid"]], car_size))
		elif c["bay_uid"] == 0:
			var size := GarageGrid.rotated_size(car_size[0], car_size[1], c["rot"])
			entries.append({"kind": "car", "entry": c, "h": c["x"], "v": c["y"], "size": size})
	var waiting := 0
	for cust: Dictionary in s["customers"]:
		if cust.get("bay_uid", 0) != 0 and bays.has(cust["bay_uid"]):
			entries.append(_on_bay_entry("customer", cust, bays[cust["bay_uid"]], car_size))
		elif cust.get("bay_uid", 0) == 0:
			# Waiting customers line up on the street, nose to tail.
			var h := land_size.x - 5 - waiting * CUSTOMER_SPACING
			var v := land_size.y + CUSTOMER_STREET_OFFSET
			entries.append({"kind": "customer", "entry": cust, "h": h, "v": v,
				"size": Vector2i(4, 3), "rot": 0})
			waiting += 1
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _depth(a) < _depth(b))
	for e: Dictionary in entries:
		var node := _make_node(e)
		_object_layer.add_child(node)
		_pickables.append({"kind": e["kind"], "uid": e["entry"]["uid"], "node": node})
	# Job bubbles float above each busy bay.
	for bay_uid: int in bays:
		var job: Dictionary = s["jobs"].get(str(bay_uid), {})
		if job.is_empty():
			continue
		var bay: Dictionary = bays[bay_uid]
		var bubble := JobStatus.new()
		bubble.setup(bay_uid, job)
		var size: Vector2i = bay["size"]
		# The original callout floats just above the car on the lift.
		bubble.position = Iso.to_screen(bay["item"]["x"] + size.x / 2.0, bay["item"]["y"] + size.y / 2.0) + Vector2(0, -85)
		bubble.pressed.connect(func() -> void: object_clicked.emit("bay", bay_uid))
		_overlay_layer.add_child(bubble)
		_job_bubbles[bay_uid] = bubble
	# And above each car that's out on a car task. (The original's car drove
	# off into town; ours waits in its spot with the callout.)
	for c: Dictionary in s["cars"]:
		var task: Dictionary = s.get("car_tasks", {}).get(str(c["uid"]), {})
		if task.is_empty() or not c["placed"]:
			continue
		var bubble := JobStatus.new()
		bubble.setup(c["uid"], task)
		var size := GarageGrid.rotated_size(car_size[0], car_size[1], c["rot"])
		bubble.position = Iso.to_screen(c["x"] + size.x / 2.0, c["y"] + size.y / 2.0) + Vector2(0, -85)
		var car_uid: int = c["uid"]
		bubble.pressed.connect(func() -> void: object_clicked.emit("car_task", car_uid))
		_overlay_layer.add_child(bubble)
		_job_bubbles[car_uid] = bubble


func _on_bay_entry(kind: String, entry: Dictionary, bay: Dictionary, car_size: Array) -> Dictionary:
	var item: Dictionary = bay["item"]
	var size: Vector2i = bay["size"]
	# Centre the car on the lift, facing along its long side.
	var rot: int = 1 if size.y > size.x else 0
	var csize := GarageGrid.rotated_size(car_size[0], car_size[1], rot)
	var h: int = item["x"] + (size.x - csize.x) / 2
	var v: int = item["y"] + (size.y - csize.y) / 2
	# Draw just after the lift itself.
	return {"kind": kind, "entry": entry, "h": h, "v": v, "size": csize, "rot": rot,
		"depth_of": {"h": item["x"], "v": item["y"], "size": size}, "bias": 1}


func _depth(e: Dictionary) -> int:
	var d: Dictionary = e.get("depth_of", e)
	var size: Vector2i = d["size"]
	return Iso.depth(d["h"], d["v"], size.x, size.y) + e.get("bias", 0)


func _make_node(e: Dictionary) -> Node2D:
	var entry: Dictionary = e["entry"]
	var pos := object_position(e["h"], e["v"])
	if e["kind"] == "item":
		var iv := ItemView.new()
		iv.setup(entry["item_id"], entry["rot"])
		iv.position = pos
		if not iv.has_art():
			return _placeholder_box(e)
		return iv
	var cv := CarView.new()
	var rot: int = e.get("rot", entry.get("rot", 0))
	var vm := CarView.iso_view_for_rotation(rot)
	cv.setup(entry, vm[0], vm[1])
	cv.position = pos
	return cv


func _placeholder_box(e: Dictionary) -> Node2D:
	var size: Vector2i = e["size"]
	var poly := Polygon2D.new()
	poly.polygon = Iso.area_polygon(e["h"], e["v"], size.x, size.y)
	poly.color = Color(0.9, 0.6, 0.2, 0.6)
	return poly


# --- Input ----------------------------------------------------------------------------

## The topmost object under a global point: {"kind", "uid"} or {}.
## Where a drawn object sits (its node's position in this view), or null.
func object_anchor(kind: String, uid: int) -> Variant:
	for p: Dictionary in _pickables:
		if p["kind"] == kind and p["uid"] == uid and is_instance_valid(p["node"]):
			return (p["node"] as Node2D).position
	return null


## Uids of the objects of [param kind] that are drawn, in draw order.
func drawn_uids(kind: String) -> Array[int]:
	var out: Array[int] = []
	for p: Dictionary in _pickables:
		if p["kind"] == kind:
			out.append(p["uid"])
	return out


## Adds something to the world overlay (e.g. a tutorial arrow).
func add_overlay(node: Node2D) -> void:
	_overlay_layer.add_child(node)


func pick(global_point: Vector2) -> Dictionary:
	for i in range(_pickables.size() - 1, -1, -1):
		var p: Dictionary = _pickables[i]
		var node: Node2D = p["node"]
		if _node_hit(node, global_point):
			return {"kind": p["kind"], "uid": p["uid"]}
	return {}


func _node_hit(node: Node2D, global_point: Vector2) -> bool:
	if node is ItemView:
		return (node as ItemView).hit(global_point)
	if node is Sprite2D:
		return _sprite_hit(node, global_point)
	if node is Polygon2D:
		return Geometry2D.is_point_in_polygon(node.to_local(global_point), (node as Polygon2D).polygon)
	for child in node.get_children():
		if child is Sprite2D and _sprite_hit(child, global_point):
			return true
		if child is Node2D and not child is Sprite2D and _node_hit(child, global_point):
			return true
	return false


func _sprite_hit(s: Sprite2D, global_point: Vector2) -> bool:
	return s.texture != null and s.is_pixel_opaque(s.to_local(global_point))


func set_hover(target: Dictionary) -> void:
	var key := "%s:%d" % [target.get("kind", ""), target.get("uid", 0)]
	if key == _hover_key:
		return
	_hover_key = key
	for p: Dictionary in _pickables:
		var on: bool = p["kind"] == target.get("kind", "") and p["uid"] == target.get("uid", -1)
		var node: Node2D = p["node"]
		if node is CarView:
			(node as CarView).set_highlight(Color(1, 1, 0.6, 0.25) if on else Color(0, 0, 0, 0))
		else:
			node.modulate = Color(1.15, 1.15, 0.9) if on else Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if not interactive or not visiting.is_empty():
		return
	if event is InputEventMouseMotion:
		set_hover(pick(get_global_mouse_position()))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var target := pick(get_global_mouse_position())
		if not target.is_empty():
			object_clicked.emit(target["kind"], target["uid"])
			get_viewport().set_input_as_handled()
		else:
			var tile := tile_under_mouse()
			if tile.x >= 0 and tile.y >= 0 and tile.x < land_size.x and tile.y < land_size.y:
				empty_tile_clicked.emit(tile)
