class_name MissionTracker
extends RefCounted
## Mission availability, progress and completion.
##
## Save layout (save["missions"]):
##   progress:  {"<mission id>": {"<step id>": count}}
##   completed: [mission ids]
##   daily:     {"day": int, "ids": [mission ids], "done": [mission ids]}

const SECONDS_PER_DAY := 86400

var catalog: Catalog
## Titles of new-player-track missions. The original ran two tracks with
## copies of the same missions; a standard mission with one of these titles
## is a duplicate and is skipped.
var _new_player_titles: Dictionary[String, bool] = {}


func _init(cat: Catalog) -> void:
	catalog = cat
	for mid: int in catalog.missions:
		var m: Dictionary = catalog.missions[mid]
		if m["category"] == "tutorial" and not m["hidden"]:
			_new_player_titles[m["title"]] = true


## Retired (hidden in the original) or duplicated across the two tracks.
func _skipped(m: Dictionary) -> bool:
	if m["hidden"]:
		return true
	return m["category"] == "standard" and _new_player_titles.has(m["title"])


## Whether a single step can be done with the features in this build.
func step_achievable(step: Dictionary, dealer_car_ids: Dictionary) -> bool:
	var events: Array = catalog.tune("missions.v1_events", [])
	var event: String = step["event"]
	if not events.has(event):
		return false
	var params: Array = step["params"]
	match event:
		"WENT_TO_LOCATION":
			var locs: Array = catalog.tune("town.v1_locations", [])
			for p: int in params:
				if not locs.has(p):
					return false
		"BOUGHT_CAR_ID":
			for p: int in params:
				if not dealer_car_ids.has(p):
					return false
		"BOUGHT_ITEM_ID":
			for p: int in params:
				if not GarageGrid.is_floor_object(catalog.item(p)):
					return false
		"BOUGHT_ITEM_CATEGORY":
			if params.is_empty():
				return false
		"FINISHED_ROAD_TRIP_WITH_ID", "FINISHED_ROAD_TRIP_CAR_FULL_WITH_ROADTRIP_ID":
			var hidden: Array = catalog.tune("road_trips.hidden", [])
			for p: int in params:
				if hidden.has(p) or not catalog.road_trips.has(p):
					return false
		"COMPLETED_CAR_BUILD_ID":
			# Only restorations are in; the other builds were licensed events.
			for p: int in params:
				if int(catalog.car_builds.get(p, {}).get("task_id", 0)) not in [42, 43]:
					return false
	return true


## Mission is buildable in this version at all (ignores player state).
func mission_supported(mission_id: int, dealer_car_ids: Dictionary) -> bool:
	var steps: Array = catalog.steps_by_mission.get(mission_id, [])
	if steps.is_empty():
		return false
	for s: Dictionary in steps:
		if not step_achievable(s, dealer_car_ids):
			return false
	return true


## Missions the player can currently work on (not daily ones).
func available(save: Dictionary, now: int, dealer_car_ids: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var completed: Array = save["missions"]["completed"]
	var level: int = save["player"]["level"]
	for mid: int in catalog.missions:
		var m: Dictionary = catalog.missions[mid]
		if m["category"] == "daily" or completed.has(mid) or _skipped(m):
			continue
		if level < m["min_level"] or level > m["max_level"]:
			continue
		if not _prereqs_met(m, completed):
			continue
		if not mission_supported(mid, dealer_car_ids):
			continue
		result.append(mid)
	result.sort_custom(func(a: int, b: int) -> bool:
		return catalog.missions[a]["index"] < catalog.missions[b]["index"])
	return result


func _prereqs_met(m: Dictionary, completed: Array) -> bool:
	for req: int in m["requires_missions"]:
		if not completed.has(req):
			return false
	for hide: int in m["hidden_after_missions"]:
		if completed.has(hide):
			return false
	return true


## Picks today's daily missions if the day changed.
func refresh_daily(save: Dictionary, now: int, dealer_car_ids: Dictionary) -> void:
	var day: int = now / SECONDS_PER_DAY
	var daily: Dictionary = save["missions"]["daily"]
	if daily.get("day", -1) == day:
		return
	var pool: Array[int] = []
	for mid: int in catalog.missions:
		var m: Dictionary = catalog.missions[mid]
		if m["category"] == "daily" and not m["hidden"] and mission_supported(mid, dealer_car_ids) \
				and save["player"]["level"] >= m["min_level"]:
			pool.append(mid)
	pool.sort()
	var picked: Array[int] = []
	var count: int = mini(catalog.tune("missions.daily_count", 3), pool.size())
	# Deterministic per day, simple enough to reproduce on a server.
	var state: int = day
	while picked.size() < count:
		state = SimpleRng.next(state)
		var mid: int = pool[(state >> 8) % pool.size()]
		if not picked.has(mid):
			picked.append(mid)
	for old: int in daily.get("ids", []):
		save["missions"]["progress"].erase(str(old))
	save["missions"]["daily"] = {"day": day, "ids": picked, "done": []}


func active_ids(save: Dictionary, now: int, dealer_car_ids: Dictionary) -> Array[int]:
	var ids := available(save, now, dealer_car_ids)
	var daily: Dictionary = save["missions"]["daily"]
	for mid: int in daily.get("ids", []):
		if not daily.get("done", []).has(mid):
			ids.append(mid)
	return ids


## Counts [param event] toward every active mission. Returns completed
## mission ids (rewards are applied by the caller).
func record(save: Dictionary, event: String, param: int, now: int, dealer_car_ids: Dictionary) -> Array[int]:
	var done: Array[int] = []
	var progress: Dictionary = save["missions"]["progress"]
	for mid: int in active_ids(save, now, dealer_car_ids):
		var changed := false
		for step: Dictionary in catalog.steps_by_mission.get(mid, []):
			if step["event"] != event:
				continue
			var params: Array = step["params"]
			if not params.is_empty() and not params.has(param):
				continue
			var key := str(mid)
			if not progress.has(key):
				progress[key] = {}
			var skey := str(step["id"])
			var count: int = progress[key].get(skey, 0)
			if count < step["count"]:
				progress[key][skey] = count + 1
				changed = true
		if changed and is_complete(save, mid):
			done.append(mid)
	return done


func is_complete(save: Dictionary, mission_id: int) -> bool:
	var progress: Dictionary = save["missions"]["progress"].get(str(mission_id), {})
	for step: Dictionary in catalog.steps_by_mission.get(mission_id, []):
		if progress.get(str(step["id"]), 0) < step["count"]:
			return false
	return true


func step_progress(save: Dictionary, mission_id: int, step_id: int) -> int:
	return save["missions"]["progress"].get(str(mission_id), {}).get(str(step_id), 0)


## Marks a mission finished and clears its progress.
func mark_done(save: Dictionary, mission_id: int) -> void:
	var m: Dictionary = catalog.missions[mission_id]
	save["missions"]["progress"].erase(str(mission_id))
	if m["category"] == "daily":
		save["missions"]["daily"]["done"].append(mission_id)
	elif not save["missions"]["completed"].has(mission_id):
		save["missions"]["completed"].append(mission_id)
