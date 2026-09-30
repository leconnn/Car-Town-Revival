class_name Catalog
extends RefCounted
## All static game data: the converted original catalog plus our tuning.
##
## Loaded from JSON produced by tools/convert_catalog.py (assets/ea/data/) and
## our own overrides in data/tuning.json. Tests load small fixture folders
## with the same file layout instead.

const REQUIRED_FILES: Array[String] = [
	"consts", "cars", "car_colors", "parts", "part_categories", "items",
	"lands", "levels", "garage_value_tiers", "jobs", "task_mastery_levels",
	"missions", "mission_steps", "locations", "consumables", "daily_rewards", "car_collections",
]

var consts: Dictionary = {}
var tuning: Dictionary = {}
var cars: Dictionary[int, Dictionary] = {}
var car_colors: Dictionary[int, Array] = {}
var parts: Dictionary[int, Dictionary] = {}
var part_categories: Dictionary[int, Dictionary] = {}
var items: Dictionary[int, Dictionary] = {}
var lands: Dictionary[int, Dictionary] = {}
var levels: Array[Dictionary] = []
var garage_value_tiers: Array[Dictionary] = []
var jobs: Dictionary[int, Dictionary] = {}
var task_mastery_levels: Array[Dictionary] = []
var missions: Dictionary[int, Dictionary] = {}
var mission_steps: Dictionary[int, Dictionary] = {}
var locations: Dictionary[int, Dictionary] = {}
## Fuel cans and refills (kind 1: gallons, kind 2: a full tank).
var consumables: Dictionary[int, Dictionary] = {}
## The login streak's prizes, day 1 first.
var daily_rewards: Array[Dictionary] = []
## Sets of cars that pay a reward when you own them all.
var car_collections: Dictionary[int, Dictionary] = {}
## Mission id -> its step definitions, in id order.
var steps_by_mission: Dictionary[int, Array] = {}
## Car id -> {category id -> stock part id}.
var stock_parts: Dictionary[int, Dictionary] = {}
## Car ids that have exported art. Empty means "unknown" (no filtering).
var art_car_ids: Dictionary[int, bool] = {}
var load_error: String = ""
## Paint for a car with no known colour.
const DEFAULT_PAINT := 0xCC2222


## Loads every file from [param data_dir], then applies [param tuning_path].
## Returns false and sets [member load_error] if something is missing.
func load_from(data_dir: String, tuning_path: String) -> bool:
	var raw: Dictionary = {}
	for file_name: String in REQUIRED_FILES:
		var value: Variant = _read_json(data_dir.path_join(file_name + ".json"))
		if value == null:
			return false
		raw[file_name] = value
	var tuning_value: Variant = _read_json(tuning_path)
	if tuning_value == null:
		return false
	tuning = tuning_value
	_index(raw)
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_error = "Missing data file: %s" % path
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var value: Variant = JSON.parse_string(text)
	if value == null:
		load_error = "Could not parse %s" % path
		return null
	return JsonUtil.ints(value)


func _index(raw: Dictionary) -> void:
	consts = raw["consts"]
	for c: Dictionary in raw["cars"]:
		cars[c["id"]] = c
	var colors: Dictionary = raw["car_colors"]
	for key: String in colors:
		car_colors[int(key)] = colors[key]
	for p: Dictionary in raw["parts"]:
		parts[p["id"]] = p
		if p["is_stock"] and p["car_id"] != 0:
			if not stock_parts.has(p["car_id"]):
				stock_parts[p["car_id"]] = {}
			stock_parts[p["car_id"]][p["category_id"]] = p["id"]
	for pc: Dictionary in raw["part_categories"]:
		part_categories[pc["id"]] = pc
	for it: Dictionary in raw["items"]:
		items[it["id"]] = it
	for la: Dictionary in raw["lands"]:
		lands[la["id"]] = la
	for lv: Dictionary in raw["levels"]:
		levels.append(lv)
	levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["level"] < b["level"])
	for t: Dictionary in raw["garage_value_tiers"]:
		garage_value_tiers.append(t)
	garage_value_tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] < b["tier"])
	for j: Dictionary in raw["jobs"]:
		jobs[j["id"]] = j
	for tm: Dictionary in raw["task_mastery_levels"]:
		task_mastery_levels.append(tm)
	for m: Dictionary in raw["missions"]:
		missions[m["id"]] = m
	for s: Dictionary in raw["mission_steps"]:
		mission_steps[s["id"]] = s
		for mid: int in s["mission_ids"]:
			if not steps_by_mission.has(mid):
				steps_by_mission[mid] = []
			steps_by_mission[mid].append(s)
	for loc: Dictionary in raw["locations"]:
		locations[loc["id"]] = loc
	for c: Dictionary in raw["consumables"]:
		consumables[c["id"]] = c
	for r: Dictionary in raw["daily_rewards"]:
		daily_rewards.append(r)
	for c: Dictionary in raw["car_collections"]:
		car_collections[c["id"]] = c


# --- Lookups ---------------------------------------------------------------

func consumable(id: int) -> Dictionary:
	return consumables.get(id, {})


func car(car_id: int) -> Dictionary:
	return cars.get(car_id, {})


func part(part_id: int) -> Dictionary:
	return parts.get(part_id, {})


func item(item_id: int) -> Dictionary:
	return items.get(item_id, {})


func job(job_id: int) -> Dictionary:
	return jobs.get(job_id, {})


func land(land_id: int) -> Dictionary:
	return lands.get(land_id, {})


func max_level() -> int:
	return levels[-1]["level"] if not levels.is_empty() else 1


func level_info(level: int) -> Dictionary:
	var index: int = clampi(level, 1, max_level()) - 1
	return levels[index]


## The highest level whose XP requirement is met.
func level_for_xp(xp: int) -> int:
	var result: int = 1
	for lv: Dictionary in levels:
		if xp >= lv["xp"]:
			result = lv["level"]
		else:
			break
	return result


func garage_value_tier(value: int) -> int:
	var result: int = 1
	for t: Dictionary in garage_value_tiers:
		if value >= t["min_value"]:
			result = t["tier"]
	return result


func colors_for_car(car_id: int) -> Array:
	return car_colors.get(car_id, [])


## A car colour as 0xRRGGBB (the original stored paint as a plain RGB value).
func color_rgb(car_id: int, color_id: int) -> int:
	for c: Dictionary in colors_for_car(car_id):
		if c["id"] == color_id:
			return str(c["hex"]).trim_prefix("#").hex_to_int()
	return DEFAULT_PAINT


func stock_part(car_id: int, category_id: int) -> int:
	return stock_parts.get(car_id, {}).get(category_id, 0)


## Reads a tuning value by dotted path, e.g. "jobs.coin_multiplier".
func tune(path: String, default: Variant = null) -> Variant:
	var node: Variant = tuning
	for key: String in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not (node as Dictionary).has(key):
			return default
		node = node[key]
	return node
