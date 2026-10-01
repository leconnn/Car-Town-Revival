class_name WorkerCrew
extends Node
## The garage's workers (views/worker/AvatarWorkerManager + AvatarAI): one per
## worker slot, the first wearing your avatar and the rest townsfolk. Each
## running job gets a worker, who runs over and works the way that job was
## done in the original (walking round the car with a sponge or wrench, or
## standing at the lift), and waves once it's ready; the rest wander.

## How a worker does each job (WorkerTask.getJobForWorkerTaskID):
## [mode, animation, facing, finish animation]. "around" walks round the car;
## "spot" stands at the lift's front corner, facing it.
const JOBS := {
	1: ["spot", "idle", 0, "hold_trophy"], 2: ["spot", "work_with_nothing", 180, "wave_rag"],
	3: ["spot", "pizza", 0, "wave_pizza"], 4: ["around", "wash", 0, "wave_rag"],
	5: ["around", "work_with_nothing", 0, "wave_rag"], 6: ["spot", "wave_ice_cream", 0, "ice_cream"],
	7: ["spot", "hold_milk", 0, "wave"], 8: ["spot", "wave_taco", 0, "taco"],
	10: ["around", "work_with_nothing", 0, "wave_rag"], 11: ["around", "wash", 0, "wave_rag"],
	12: ["around", "fix2", 0, "wave_rag"], 13: ["spot", "fix2", 180, "wave_rag"],
	14: ["around", "wash", 0, "wave_rag"], 15: ["spot", "work_with_nothing", 180, "wave_rag"],
	16: ["around", "fix2", 0, "dance1"], 17: ["around", "fix2", 0, "dance1"],
	18: ["spot", "work_with_nothing", 180, "wave_rag"], 19: ["around", "work_with_gun", 0, "dance1"],
	20: ["around", "fix2", 0, "shoryuken"], 21: ["around", "fix2", 0, "wave_rag"],
	22: ["around", "fix2", 0, "wave_rag"], 23: ["around", "fix2", 0, "fix2"],
	24: ["around", "fix2", 0, "shooting"], 25: ["around", "fix2", 0, "dance1"],
	26: ["around", "fix2", 0, "dance1"], 27: ["around", "work_with_nothing", 0, "wave_rag"],
	28: ["spot", "work_with_nothing", 180, "wave_rag"], 29: ["around", "fix2", 0, "wave_rag"],
	30: ["around", "fix2", 0, "wave_rag"], 31: ["around", "fix2", 0, "wave_rag"],
	32: ["around", "fix2", 0, "dance1"], 33: ["around", "fix2", 0, "dance1"],
	34: ["spot", "wave_map", 0, "wave_luggage"], 35: ["around", "work_with_gun", 0, "dance1"],
	36: ["around", "fix2", 0, "dance1"], 37: ["spot", "wave", 0, "wave"],
	38: ["around", "fix2", 0, "dance1"], 39: ["around", "fix2", 0, "dance1"],
	42: ["around", "fix2", 0, "dance1"], 43: ["around", "fix2", 0, "dance1"],
}
const WALK_SPEED := 1.6
const RUN_SPEED := 3.2
## Facing the camera (RotateAvatarProcess(avatar, 0)).
const FACE_CAMERA := 45.0
const WORK_PAUSE := 3.5
const IDLE_PAUSE := Vector2(3.0, 9.0)

var garage: GarageView
var _workers: Array[Dictionary] = []
var _astar := AStarGrid2D.new()
var _grid: GarageGrid


func _init(view: GarageView) -> void:
	garage = view


## Called after the garage is (re)built: workers to match the slots, jobs
## to match the save.
func refresh() -> void:
	if not AvatarRig.available() or not garage.visiting.is_empty():
		_clear()
		return
	var s := Backend.state()
	_grid = GarageGrid.build(GameData.catalog, s)
	_astar.region = Rect2i(0, 0, _grid.width, _grid.height)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()
	for x in _grid.width:
		for y in _grid.height:
			_astar.set_point_solid(Vector2i(x, y), _grid.occupant(x, y) != "")
	var count := maxi(1, Backend.query().max_workers())
	while _workers.size() > count:
		var gone: Dictionary = _workers.pop_back()
		(gone["view"] as Node).queue_free()
	while _workers.size() < count:
		_workers.append(_spawn(_workers.size()))
	for w: Dictionary in _workers:
		if not is_instance_valid(w["view"]) or (w["view"] as Node).get_parent() == null:
			w["view"] = _make_view(w["index"])
			_place(w, w["tile"])
	_assign(s)


func debug_dump() -> void:
	for w: Dictionary in _workers:
		print("worker ", w["index"], " tile=", w["tile"], " state=", w["state"], " task=", w["task"], " job=", w["job"],
			" finished=", w["finished"], " vis=", (w["view"] as Node2D).is_visible_in_tree(), " pos=", (w["view"] as Node2D).position,
			" screen=", (w["view"] as Node2D).get_global_transform_with_canvas().origin, " idx=", (w["view"] as Node).get_index(),
			" parent=", (w["view"] as Node).get_parent().name)


func _clear() -> void:
	for w: Dictionary in _workers:
		if is_instance_valid(w["view"]):
			(w["view"] as Node).queue_free()
	_workers.clear()


func _spawn(index: int) -> Dictionary:
	var w := {"index": index, "view": _make_view(index), "tile": _random_free(), "pos": Vector2.ZERO,
		"path": [], "state": "idle", "wait": randf_range(0.5, 3.0), "task": "", "job": [], "ring": [], "ring_i": 0,
		"speed": WALK_SPEED, "finished": false, "focus": Vector2.ZERO}
	_place(w, w["tile"])
	return w


func _make_view(index: int) -> WorkerView:
	var view := WorkerView.create(look_for(index))
	garage.add_actor(view)
	return view


## Worker 1 wears your avatar; the others are townsfolk dressed from the
## free clothes, the same each time.
static func look_for(index: int) -> Dictionary:
	if index == 0:
		var mine: Dictionary = Backend.state().get("avatar", {})
		return mine if not mine.is_empty() else AvatarPortrait.DEFAULT_OUTFIT
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * index + 17
	var free := {}
	for id: int in GameData.catalog.avatar_items:
		var it: Dictionary = GameData.catalog.avatar_items[id]
		if int(it.get("price", 0)) == 0 and int(it.get("blue_price", 0)) == 0 and AvatarRig.has_3d(id):
			var t := int(it["type"])
			if not free.has(t):
				free[t] = []
			free[t].append(id)
	var pick := func(t: int, fallback: int) -> int:
		var ids: Array = free.get(t, [])
		return fallback if ids.is_empty() else int(ids[rng.randi_range(0, ids.size() - 1)])
	var skirt := rng.randf() < 0.3
	return {
		"head": pick.call(11, 68), "eyes": pick.call(1, 1), "mouth": pick.call(2, 12), "brows": pick.call(3, 20),
		"facial_hair": 0 if skirt or rng.randf() < 0.6 else pick.call(4, 0), "hair": pick.call(5, 33),
		"misc": 0, "hat": 0 if rng.randf() < 0.6 else pick.call(7, 0), "top": pick.call(8, 53),
		"bottom": pick.call(12, 74) if skirt else pick.call(9, 57), "nose": pick.call(10, 60),
		"settings": {"head": rng.randi_range(0, 5) * 10000, "hair": rng.randi_range(0, 7) * 10000,
			"eyes": rng.randi_range(0, 8) * 10000 + 5425, "mouth": 5300, "brows": 7226, "nose": 6200},
	}


# --- Jobs -------------------------------------------------------------------------------

## Who works on what: bay jobs, then cars out on tasks, then restorations.
func _assign(s: Dictionary) -> void:
	var tasks: Array[Dictionary] = []
	var bays := {}
	for it: Dictionary in s["garage"]["items"]:
		bays[int(it["uid"])] = it
	for key: String in s["jobs"]:
		var it: Dictionary = bays.get(int(key), {})
		if not it.is_empty():
			tasks.append({"key": "bay:" + key, "job": int(s["jobs"][key]["job_id"]), "rect": _rect_of_item(it),
				"ends_at": int(s["jobs"][key]["ends_at"])})
	for key: String in s.get("restoration", {}).get("builds", {}):
		var it: Dictionary = bays.get(int(key), {})
		if not it.is_empty():
			tasks.append({"key": "build:" + key, "job": 42, "rect": _rect_of_item(it), "ends_at": 0})
	for key: String in s["car_tasks"]:
		var car := Backend.query().get_car(int(key))
		if not car.is_empty() and car.get("placed", false):
			var size := GarageGrid.rotated_size(4, 3, int(car.get("rot", 0)))
			tasks.append({"key": "car:" + key, "job": int(s["car_tasks"][key]["job_id"]),
				"rect": Rect2i(int(car["x"]), int(car["y"]), size.x, size.y), "ends_at": int(s["car_tasks"][key]["ends_at"])})
	var taken := {}
	for w: Dictionary in _workers:
		if w["task"] != "":
			var still := tasks.filter(func(t: Dictionary) -> bool: return t["key"] == w["task"])
			if still.is_empty():
				_go_idle(w)
			else:
				taken[w["task"]] = true
				w["finished"] = int(still[0]["ends_at"]) > 0 and Backend.now() >= int(still[0]["ends_at"])
	for t: Dictionary in tasks:
		if taken.has(t["key"]):
			continue
		for w: Dictionary in _workers:
			if w["task"] == "":
				_start_task(w, t)
				taken[t["key"]] = true
				break


func _rect_of_item(it: Dictionary) -> Rect2i:
	var def: Dictionary = GameData.catalog.item(int(it["item_id"]))
	var size := GarageGrid.rotated_size(int(def.get("size_x", 1)), int(def.get("size_y", 1)), int(it.get("rot", 0)))
	return Rect2i(int(it["x"]), int(it["y"]), size.x, size.y)


func _start_task(w: Dictionary, t: Dictionary) -> void:
	var job: Array = JOBS.get(int(t["job"]), ["spot", "work_with_nothing", 180, "wave_rag"])
	w["task"] = t["key"]
	w["job"] = job
	w["finished"] = int(t["ends_at"]) > 0 and Backend.now() >= int(t["ends_at"])
	var rect: Rect2i = t["rect"]
	w["focus"] = Vector2(rect.position) + Vector2(rect.size) / 2.0
	w["ring"] = _ring(rect) if job[0] == "around" else []
	w["ring_i"] = 0
	var corner := rect.position + rect.size - Vector2i.ONE + Vector2i(1, 1)
	var goal: Vector2i = corner if job[0] == "spot" or (w["ring"] as Array).is_empty() else w["ring"][0]
	_walk_to(w, goal, RUN_SPEED, "working")


## Free tiles just outside a rectangle, going round it.
func _ring(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := rect.grow(1)
	for x in range(r.position.x, r.end.x):
		out.append(Vector2i(x, r.position.y))
	for y in range(r.position.y + 1, r.end.y):
		out.append(Vector2i(r.end.x - 1, y))
	for x in range(r.end.x - 2, r.position.x - 1, -1):
		out.append(Vector2i(x, r.end.y - 1))
	for y in range(r.end.y - 2, r.position.y, -1):
		out.append(Vector2i(r.position.x, y))
	return out.filter(func(c: Vector2i) -> bool: return _free(c))


func _go_idle(w: Dictionary) -> void:
	w["task"] = ""
	w["job"] = []
	w["state"] = "idle"
	w["wait"] = randf_range(IDLE_PAUSE.x, IDLE_PAUSE.y)
	(w["view"] as WorkerView).play("idle")


# --- Moving -------------------------------------------------------------------------------

func _free(c: Vector2i) -> bool:
	return _grid != null and c.x >= 0 and c.y >= 0 and c.x < _grid.width and c.y < _grid.height and _grid.occupant(c.x, c.y) == ""


func _random_free() -> Vector2i:
	if _grid == null:
		_grid = GarageGrid.build(GameData.catalog, Backend.state())
	for i in 200:
		var c := Vector2i(randi_range(0, _grid.width - 1), randi_range(0, _grid.height - 1))
		if _free(c):
			return c
	return Vector2i.ZERO


func _walk_to(w: Dictionary, goal: Vector2i, speed: float, then: String) -> void:
	var from: Vector2i = w["tile"]
	var path: Array[Vector2i] = []
	if _free(goal) and _astar.is_in_boundsv(from) and _astar.is_in_boundsv(goal):
		var solid := _astar.is_point_solid(from)
		_astar.set_point_solid(from, false)
		path = _astar.get_id_path(from, goal)
		_astar.set_point_solid(from, solid)
	if path.size() <= 1:
		# TELEPORT_IF_NO_PATH_FOUND: no way there, so just appear.
		_place(w, goal if _free(goal) else from)
		_arrive(w, then)
		return
	path.remove_at(0)
	w["path"] = path
	w["speed"] = speed
	w["state"] = "walking"
	w["then"] = then
	(w["view"] as WorkerView).play("running" if speed > WALK_SPEED else "walk")


func _place(w: Dictionary, tile: Vector2i) -> void:
	w["tile"] = tile
	w["pos"] = Vector2(tile) + Vector2(0.5, 0.5)
	_update_view(w)


func _update_view(w: Dictionary) -> void:
	var view := w["view"] as WorkerView
	if not is_instance_valid(view):
		return
	var p: Vector2 = w["pos"]
	view.position = Iso.to_screen(p.x, p.y)
	var t: Vector2i = w["tile"]
	garage.sort_actor(view, Iso.depth(t.x, t.y, 1, 1) + 500)


func _face_towards(w: Dictionary, target: Vector2) -> void:
	var d: Vector2 = target - (w["pos"] as Vector2)
	if d.length() > 0.01:
		(w["view"] as WorkerView).face(rad_to_deg(atan2(d.x, d.y)))


func _arrive(w: Dictionary, then: String) -> void:
	var view := w["view"] as WorkerView
	w["path"] = []
	match then:
		"working":
			w["state"] = "working"
			w["wait"] = WORK_PAUSE
			if w["finished"]:
				view.face(FACE_CAMERA)
				view.play(w["job"][3])
			else:
				_face_towards(w, w["focus"])
				if w["job"][0] == "spot" and int(w["job"][2]) == 0:
					view.face(FACE_CAMERA)
				view.play(w["job"][1])
		_:
			w["state"] = "idle"
			w["wait"] = randf_range(IDLE_PAUSE.x, IDLE_PAUSE.y)
			view.play("idle")


func _process(delta: float) -> void:
	for w: Dictionary in _workers:
		if not is_instance_valid(w["view"]):
			continue
		match w["state"]:
			"walking":
				_step(w, delta)
			"working":
				w["wait"] -= delta
				if w["wait"] <= 0.0 and not w["finished"] and w["job"][0] == "around" and (w["ring"] as Array).size() > 1:
					# GenericMoveAroundCarActionProcess: on to the next spot round the car.
					var ring: Array = w["ring"]
					w["ring_i"] = (int(w["ring_i"]) + randi_range(2, 4)) % ring.size()
					_walk_to(w, ring[w["ring_i"]], WALK_SPEED, "working")
			"idle":
				w["wait"] -= delta
				if w["wait"] <= 0.0:
					var c: Vector2i = w["tile"]
					var goal := c + Vector2i(randi_range(-4, 4), randi_range(-4, 4))
					if _free(goal):
						_walk_to(w, goal, WALK_SPEED, "idle")
					else:
						w["wait"] = 1.0


func _step(w: Dictionary, delta: float) -> void:
	var path: Array = w["path"]
	if path.is_empty():
		_arrive(w, w.get("then", "idle"))
		return
	var next: Vector2 = Vector2(path[0]) + Vector2(0.5, 0.5)
	var pos: Vector2 = w["pos"]
	_face_towards(w, next)
	var move: float = float(w["speed"]) * delta
	if pos.distance_to(next) <= move:
		w["pos"] = next
		w["tile"] = path[0]
		path.remove_at(0)
	else:
		w["pos"] = pos + (next - pos).normalized() * move
	_update_view(w)
