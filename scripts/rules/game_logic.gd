class_name GameLogic
extends RefCounted
## The game rules. Validates and applies every player action to a save.
##
## This is the authority: LocalBackend runs it on the player's PC, and the LAN
## host runs it for everyone in its world. It never touches files, the network
## or the UI. Every action takes [param now] (unix seconds) from the caller so
## timers can use a trusted clock.

const CURRENT_SAVE_VERSION := 2

var catalog: Catalog
var save: Dictionary
var missions: MissionTracker
var _dealer_ids: Dictionary = {}


func _init(cat: Catalog, save_data: Dictionary) -> void:
	catalog = cat
	save = save_data
	missions = MissionTracker.new(cat)
	for id: int in dealer_car_ids():
		_dealer_ids[id] = true


# --- New game ---------------------------------------------------------------

static func new_save(cat: Catalog, player_name: String, now: int) -> Dictionary:
	var start: Dictionary = cat.tune("start", {})
	var s := {
		"save_version": CURRENT_SAVE_VERSION,
		"created_at": now,
		"updated_at": now,
		"player": {
			"name": player_name,
			"coins": start.get("coins", 10000),
			"blue": start.get("blue", 0),
			"xp": 0,
			"level": 1,
		},
		"next_uid": 1,
		"rng": now % SimpleRng.MODULUS,
		"garage": {
			"land_id": start.get("land_id", 1),
			"floor_item_id": start.get("floor_item_id", 0),
			"wall_item_id": start.get("wall_item_id", 0),
			"items": [],
			"wall_items": [],
		},
		"cars": [],
		"storage": {},
		"jobs": {},
		"car_tasks": {},
		"job_mastery": {},
		"customers": [],
		"next_customer_at": now,
		"missions": {"progress": {}, "completed": [], "daily": {}},
		"tutorial": {"step": 0, "done": false},
		"visited_locations": [],
		"stats": {},
	}
	var logic := GameLogic.new(cat, s)
	for it: Dictionary in start.get("items", []):
		logic._add_item(it["item_id"], it["x"], it["y"], it["rot"])
	var car_id: int = start.get("car_id", 0)
	if not cat.car(car_id).is_empty():
		var colors := cat.colors_for_car(car_id)
		var color_index: int = start.get("car_color_index", 0)
		var color_id: int = colors[color_index]["id"] if color_index < colors.size() else 0
		var car := logic._add_car(car_id, color_id)
		# Like the original's new garage: the car sits on the first work bay
		# with a job that's just finished, ready for the tutorial to collect.
		var job_id: int = start.get("job", {}).get("job_id", 0)
		var bay := 0
		for it: Dictionary in s["garage"]["items"]:
			if bay == 0 and logic._is_bay(it["uid"]):
				bay = it["uid"]
		if job_id != 0 and bay != 0 and not cat.job(job_id).is_empty():
			car["bay_uid"] = bay
			car["placed"] = true
			var minutes: int = cat.job(job_id)["minutes"]
			s["jobs"][str(bay)] = {"job_id": job_id, "started_at": now - minutes * 60, "ends_at": now}
	return s


# --- Helpers ------------------------------------------------------------------

func _uid() -> int:
	var id: int = save["next_uid"]
	save["next_uid"] = id + 1
	return id


func _player() -> Dictionary:
	return save["player"]


func _find(list_key: String, uid: int) -> Dictionary:
	for entry: Dictionary in save[list_key]:
		if entry["uid"] == uid:
			return entry
	return {}


func _find_item(uid: int) -> Dictionary:
	for entry: Dictionary in save["garage"]["items"]:
		if entry["uid"] == uid:
			return entry
	return {}


func get_car(uid: int) -> Dictionary:
	return _find("cars", uid)


func get_customer(uid: int) -> Dictionary:
	return _find("customers", uid)


## Pays coins, or blue coins if [param use_blue]. [param def] is any catalog
## entry with the shared shop fields.
func _charge(def: Dictionary, use_blue: bool, multiplier: float = 1.0) -> String:
	var p := _player()
	if use_blue:
		var cost: int = ceili(def.get("blue_price", 0) * multiplier)
		if not def.get("can_buy_with_blue", false) or cost <= 0:
			return "This can't be bought with blue coins."
		if p["blue"] < cost:
			return "Not enough blue coins."
		p["blue"] -= cost
	else:
		var cost: int = ceili(def.get("price", 0) * multiplier)
		if not def.get("can_buy_with_coins", true) and cost > 0:
			return "This can only be bought with blue coins."
		if p["coins"] < cost:
			return "Not enough coins."
		p["coins"] -= cost
	return ""


func _level_ok(def: Dictionary) -> String:
	if _player()["level"] < def.get("min_level", 0):
		return "Requires level %d." % def["min_level"]
	if def.get("min_garage_value_tier", 0) > garage_value_tier():
		return "Requires a more valuable garage (tier %d)." % def["min_garage_value_tier"]
	return ""


func _bump_stat(key: String, amount: int = 1) -> void:
	save["stats"][key] = save["stats"].get(key, 0) + amount


# --- Economy --------------------------------------------------------------------

## Adds coins, blue coins and XP, handling level-ups.
func add_rewards(coins: int, blue: int, xp: int, result: GameResult) -> void:
	var p := _player()
	p["coins"] += coins
	p["blue"] += blue
	p["xp"] += xp
	var new_level: int = catalog.level_for_xp(p["xp"])
	while p["level"] < new_level:
		p["level"] += 1
		var info: Dictionary = catalog.level_info(p["level"])
		var bonus_blue: int = catalog.tune("economy.blue_per_level_up", 0)
		p["coins"] += info["coin_bonus"]
		p["blue"] += bonus_blue
		result.notices.append({
			"kind": "level_up", "level": p["level"], "title": info.get("title", ""),
			"coins": info["coin_bonus"], "blue": bonus_blue,
		})


func garage_value() -> int:
	var total := 0
	for c: Dictionary in save["cars"]:
		total += catalog.car(c["car_id"]).get("price", 0)
	for it: Dictionary in save["garage"]["items"]:
		total += catalog.item(it["item_id"]).get("price", 0)
	return total


func garage_value_tier() -> int:
	return catalog.garage_value_tier(garage_value())


func max_workers() -> int:
	return catalog.level_info(_player()["level"])["max_workers"]


## Workers busy on bay jobs and car tasks (one each, like the original's
## UserWorkerTasks).
func busy_workers() -> int:
	return save["jobs"].size() + save["car_tasks"].size()


# --- Missions -------------------------------------------------------------------

func _emit(event: String, param: int, now: int, result: GameResult) -> void:
	missions.refresh_daily(save, now, _dealer_ids)
	var done := missions.record(save, event, param, now, _dealer_ids)
	for mid: int in done:
		_complete_mission(mid, now, result)


func _complete_mission(mid: int, now: int, result: GameResult) -> void:
	var m: Dictionary = catalog.missions[mid]
	missions.mark_done(save, mid)
	add_rewards(m["coins"], m["blue"], m["xp"], result)
	var reward := _give_reward(m["reward_type"], m["reward_id"])
	result.notices.append({
		"kind": "mission_complete", "mission_id": mid, "title": m["title"],
		"text": m["complete_text"], "coins": m["coins"], "blue": m["blue"],
		"xp": m["xp"], "reward": reward,
	})
	if m["category"] == "daily":
		_emit("COMPLETED_DAILY_MISSION", 0, now, result)


func _give_reward(reward_type: String, reward_id: int) -> Dictionary:
	if reward_id <= 0:
		return {}
	match reward_type.to_lower():
		"item":
			if catalog.item(reward_id).is_empty():
				return {}
			_store_item(reward_id)
			return {"type": "item", "id": reward_id}
		"car":
			if catalog.car(reward_id).is_empty():
				return {}
			var colors := catalog.colors_for_car(reward_id)
			_add_car(reward_id, colors[0]["id"] if not colors.is_empty() else 0)
			return {"type": "car", "id": reward_id}
	return {}


func active_missions(now: int) -> Array[int]:
	missions.refresh_daily(save, now, _dealer_ids)
	return missions.active_ids(save, now, _dealer_ids)


# --- Dealer and cars ----------------------------------------------------------------

## Car ids sold at the dealer, sorted by price.
func dealer_car_ids() -> Array[int]:
	var min_price: int = catalog.tune("dealer.min_price", 100)
	var retired: bool = catalog.tune("dealer.include_retired_cars", false)
	var need_art: bool = catalog.tune("dealer.require_art", true)
	var result: Array[int] = []
	for id: int in catalog.cars:
		var c: Dictionary = catalog.cars[id]
		if c["price"] < min_price:
			continue
		if not (c["purchasable"] or c["always_purchasable"] or retired):
			continue
		if need_art and not catalog.art_car_ids.is_empty() and not catalog.art_car_ids.has(id):
			continue
		result.append(id)
	result.sort_custom(func(a: int, b: int) -> bool:
		var ca: Dictionary = catalog.cars[a]
		var cb: Dictionary = catalog.cars[b]
		return ca["price"] < cb["price"] if ca["price"] != cb["price"] else a < b)
	return result


func _add_car(car_id: int, color_id: int) -> Dictionary:
	var def: Dictionary = catalog.car(car_id)
	var defaults: Dictionary = def.get("defaults", {})
	var parts := {}
	for key: String in defaults:
		var part_id: int = defaults[key]
		if part_id > 0 and not catalog.part(part_id).is_empty():
			parts[str(catalog.part(part_id)["category_id"])] = part_id
	var car := {
		"uid": _uid(), "car_id": car_id, "color_id": color_id,
		"paint": catalog.color_rgb(car_id, color_id), "parts": parts,
		"upgrades": [0, 0, 0, 0], "ride_height": 0, "plate": "",
		"placed": false, "x": 0, "y": 0, "rot": 0, "bay_uid": 0,
	}
	var car_size: Array = catalog.tune("garage.car_size", [4, 3])
	var spot := GarageGrid.build(catalog, save).find_free(Vector2i(car_size[0], car_size[1]))
	if spot.x >= 0:
		car["placed"] = true
		car["x"] = spot.x
		car["y"] = spot.y
	save["cars"].append(car)
	return car


func buy_car(car_id: int, color_id: int, use_blue: bool, now: int) -> GameResult:
	var def: Dictionary = catalog.car(car_id)
	if def.is_empty() or not _dealer_ids.has(car_id):
		return GameResult.fail("That car isn't for sale.")
	var err := _level_ok(def)
	if err != "":
		return GameResult.fail(err)
	var colors := catalog.colors_for_car(car_id)
	if not colors.is_empty() and not colors.any(func(c: Dictionary) -> bool: return c["id"] == color_id):
		color_id = colors[0]["id"]
	err = _charge(def, use_blue)
	if err != "":
		return GameResult.fail(err)
	var car := _add_car(car_id, color_id)
	var result := GameResult.success({"uid": car["uid"], "placed": car["placed"]})
	add_rewards(0, 0, def.get("xp", 0), result)
	_bump_stat("cars_bought")
	_emit("BOUGHT_CAR_ID", car_id, now, result)
	return result


func sell_car(uid: int, now: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if car["bay_uid"] != 0 and save["jobs"].has(str(car["bay_uid"])):
		return GameResult.fail("Finish the job on this car first.")
	if save["car_tasks"].has(str(uid)):
		return GameResult.fail("This car is out on a job.")
	if save["cars"].size() <= 1:
		return GameResult.fail("You can't sell your last car.")
	var fraction: float = catalog.tune("economy.resell_fraction", 0.1)
	var refund: int = floori(catalog.car(car["car_id"]).get("price", 0) * fraction)
	save["cars"].erase(car)
	_player()["coins"] += refund
	return GameResult.success({"coins": refund})


## The car's paint as 0xRRGGBB. Saves from before paint was stored as RGB
## only have the catalog colour.
func car_paint(car: Dictionary) -> int:
	return car["paint"] if car.has("paint") else catalog.color_rgb(car["car_id"], car.get("color_id", 0))


## Paints a car any colour, like the original's colour picker.
func paint_car(uid: int, rgb: int, use_blue: bool, now: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if rgb < 0 or rgb > 0xFFFFFF:
		return GameResult.fail("That isn't a colour.")
	if car_paint(car) == rgb:
		return GameResult.fail("The car is already that colour.")
	var err := _charge(catalog.part(catalog.tune("parts.paint_part_id", 0)), use_blue)
	if err != "":
		return GameResult.fail(err)
	car["paint"] = rgb
	_bump_stat("cars_painted")
	var result := GameResult.success()
	_emit("PAINTED_CAR", 0, now, result)
	return result


## Parts that fit a car in a category (its own parts plus universal ones).
func parts_for_car(car_id: int, category_id: int) -> Array[int]:
	var result: Array[int] = []
	for pid: int in catalog.parts:
		var p: Dictionary = catalog.parts[pid]
		if p["category_id"] != category_id:
			continue
		if p["car_id"] != 0 and p["car_id"] != car_id:
			continue
		if p["car_id"] == 0 and not p["purchasable"] and not p["is_stock"]:
			continue
		if p["car_id"] != 0 and not p["purchasable"] and pid != catalog.stock_part(car_id, category_id):
			continue
		result.append(pid)
	result.sort_custom(func(a: int, b: int) -> bool:
		return catalog.parts[a]["price"] < catalog.parts[b]["price"] if catalog.parts[a]["price"] != catalog.parts[b]["price"] else a < b)
	return result


func install_part(uid: int, part_id: int, use_blue: bool, now: int) -> GameResult:
	var car := get_car(uid)
	var p: Dictionary = catalog.part(part_id)
	if car.is_empty() or p.is_empty():
		return GameResult.fail("Part not found.")
	var cat_key := str(p["category_id"])
	if car["parts"].get(cat_key, 0) == part_id:
		return GameResult.fail("That part is already installed.")
	if not parts_for_car(car["car_id"], p["category_id"]).has(part_id):
		return GameResult.fail("That part doesn't fit this car.")
	var is_stock: bool = catalog.stock_part(car["car_id"], p["category_id"]) == part_id
	if not is_stock:
		var err := _level_ok(p)
		if err != "":
			return GameResult.fail(err)
		err = _charge(p, use_blue)
		if err != "":
			return GameResult.fail(err)
	car["parts"][cat_key] = part_id
	var result := GameResult.success()
	if not is_stock:
		add_rewards(0, 0, p.get("xp", 0), result)
		_emit("INSTALLED_CAR_PART_CATEGORY", p["category_id"], now, result)
	return result


func remove_part(uid: int, category_id: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	var stock := catalog.stock_part(car["car_id"], category_id)
	if stock > 0:
		car["parts"][str(category_id)] = stock
	else:
		car["parts"].erase(str(category_id))
	return GameResult.success()


## The original's four performance upgrade tracks, each with five stages.
const UPGRADE_ENGINE := 1
const UPGRADE_HANDLING := 2
const UPGRADE_AERODYNAMIC := 3
const UPGRADE_WEIGHT := 4


## Price of [param stage] of an upgrade track as [coins, blue]: stages 1-4
## cost coins, stage 5 blue coins (StaticData.getCarUpgradeParts).
func upgrade_stage_price(car_id: int, stage: int) -> Array[int]:
	var base: int = catalog.car(car_id).get("price", 0)
	var mult: float = catalog.consts.get("upgrade_stage%d_multiplier" % stage, 0.1)
	var coins: int = ceili(mult * base)
	if stage < 5:
		return [maxi(coins, int(catalog.consts.get("upgrade_min_price", 25))), 0]
	return [0, ceili(coins * float(catalog.consts.get("upgrade_coins_to_blue_conversion", 0.001)))]


## Buys the next stage of upgrade track [param track] (1-4).
func upgrade_car(uid: int, track: int, now: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if track < 1 or track > 4:
		return GameResult.fail("Unknown upgrade.")
	var stage: int = car["upgrades"][track - 1] + 1
	if stage > int(catalog.consts.get("upgrade_max_stage", 5)):
		return GameResult.fail("That upgrade is maxed out.")
	var price := upgrade_stage_price(car["car_id"], stage)
	if _player()["coins"] < price[0]:
		return GameResult.fail("Not enough coins.")
	if _player()["blue"] < price[1]:
		return GameResult.fail("Not enough blue coins.")
	_player()["coins"] -= price[0]
	_player()["blue"] -= price[1]
	car["upgrades"][track - 1] = stage
	var result := GameResult.success({"track": track, "stage": stage})
	_emit("INSTALLED_CAR_UPGRADE_TYPE", track, now, result)
	return result


## Performance score: catalog score plus upgrades and part scores.
func car_score(uid: int) -> int:
	var car := get_car(uid)
	var score: int = catalog.car(car.get("car_id", 0)).get("score", 0)
	for stage: int in car.get("upgrades", []):
		score += stage * int(catalog.consts.get("upgrade_score_per_stage", 20))
	return score


func set_ride_height(uid: int, height: int, use_blue: bool, now: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if height < 0 or height > catalog.tune("parts.max_ride_height", 4) or height == car["ride_height"]:
		return GameResult.fail("Invalid ride height.")
	var err := _charge(catalog.part(catalog.tune("parts.ride_height_part_id", 0)), use_blue)
	if err != "":
		return GameResult.fail(err)
	car["ride_height"] = height
	return GameResult.success()


func set_plate(uid: int, text: String, use_blue: bool, now: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	var plate := text.strip_edges().to_upper()
	var max_len: int = catalog.tune("parts.plate_max_length", 7)
	var re := RegEx.create_from_string("^[A-Z0-9 ]+$")
	if plate.is_empty() or plate.length() > max_len or re.search(plate) == null:
		return GameResult.fail("Plates use up to %d letters and numbers." % max_len)
	var err := _charge(catalog.part(catalog.tune("parts.vanity_plate_part_id", 0)), use_blue)
	if err != "":
		return GameResult.fail(err)
	car["plate"] = plate
	return GameResult.success()


func move_car(uid: int, x: int, y: int, rot: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if car["bay_uid"] != 0:
		return GameResult.fail("Take the car off the work bay first.")
	var car_size: Array = catalog.tune("garage.car_size", [4, 3])
	var size := GarageGrid.rotated_size(car_size[0], car_size[1], rot)
	if not GarageGrid.build(catalog, save).can_place(x, y, size, "car:%d" % uid):
		return GameResult.fail("There's no room there.")
	car["placed"] = true
	car["x"] = x
	car["y"] = y
	car["rot"] = posmod(rot, 4)
	return GameResult.success()


func store_car(uid: int) -> GameResult:
	var car := get_car(uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if car["bay_uid"] != 0:
		return GameResult.fail("Take the car off the work bay first.")
	if save["car_tasks"].has(str(uid)):
		return GameResult.fail("This car is out on a job.")
	car["placed"] = false
	return GameResult.success()


# --- Garage items -------------------------------------------------------------------

func _add_item(item_id: int, x: int, y: int, rot: int) -> Dictionary:
	var entry := {"uid": _uid(), "item_id": item_id, "x": x, "y": y, "rot": posmod(rot, 4)}
	save["garage"]["items"].append(entry)
	return entry


func _store_item(item_id: int) -> void:
	var key := str(item_id)
	save["storage"][key] = save["storage"].get(key, 0) + 1


func _item_fits(item_id: int, x: int, y: int, rot: int, ignore_key: String = "") -> bool:
	var def: Dictionary = catalog.item(item_id)
	var size := GarageGrid.rotated_size(def["size_x"], def["size_y"], rot)
	return GarageGrid.build(catalog, save).can_place(x, y, size, ignore_key)


## Items sold in the garage shop.
func shop_item_ids() -> Array[int]:
	var result: Array[int] = []
	for id: int in catalog.items:
		var it: Dictionary = catalog.items[id]
		if not (it["purchasable"] or it["always_purchasable"]):
			continue
		if it["price"] <= 0 and it["blue_price"] <= 0:
			continue
		var cat: int = it["category"]
		if GarageGrid.is_floor_object(it) or cat == GarageGrid.CAT_FLOOR_TILE or cat == GarageGrid.CAT_WALL:
			result.append(id)
	result.sort_custom(func(a: int, b: int) -> bool:
		var ia: Dictionary = catalog.items[a]
		var ib: Dictionary = catalog.items[b]
		return ia["sort"] < ib["sort"] if ia["sort"] != ib["sort"] else a < b)
	return result


func buy_item(item_id: int, x: int, y: int, rot: int, use_blue: bool, now: int) -> GameResult:
	var def: Dictionary = catalog.item(item_id)
	if def.is_empty() or not GarageGrid.is_floor_object(def):
		return GameResult.fail("That item can't be placed on the floor.")
	var err := _level_ok(def)
	if err != "":
		return GameResult.fail(err)
	if not _item_fits(item_id, x, y, rot):
		return GameResult.fail("There's no room there.")
	err = _charge(def, use_blue)
	if err != "":
		return GameResult.fail(err)
	var entry := _add_item(item_id, x, y, rot)
	var result := GameResult.success({"uid": entry["uid"]})
	add_rewards(0, 0, def.get("xp", 0), result)
	_emit("BOUGHT_ITEM_ID", item_id, now, result)
	_emit("BOUGHT_ITEM_CATEGORY", def["category"], now, result)
	if def["category"] != GarageGrid.CAT_WORK_BAY:
		_emit("DECORATE_GARAGE", 0, now, result)
	return result


func move_item(uid: int, x: int, y: int, rot: int) -> GameResult:
	var entry := _find_item(uid)
	if entry.is_empty():
		return GameResult.fail("Item not found.")
	if _bay_busy(uid):
		return GameResult.fail("Clear the work bay before moving it.")
	if not _item_fits(entry["item_id"], x, y, rot, "item:%d" % uid):
		return GameResult.fail("There's no room there.")
	entry["x"] = x
	entry["y"] = y
	entry["rot"] = posmod(rot, 4)
	return GameResult.success()


func store_item(uid: int) -> GameResult:
	var entry := _find_item(uid)
	if entry.is_empty():
		return GameResult.fail("Item not found.")
	if _bay_busy(uid):
		return GameResult.fail("Clear the work bay before storing it.")
	save["garage"]["items"].erase(entry)
	_store_item(entry["item_id"])
	return GameResult.success()


## The original "Reset Floor": puts cars, garage items and/or empty work bays
## into storage. Busy cars (on a job or out on a car task) and busy bays stay.
func clear_floor(cars: bool, items: bool, bays: bool) -> GameResult:
	var stored := {"cars": 0, "items": 0, "bays": 0}
	if cars:
		for car: Dictionary in save["cars"]:
			if not car["placed"] or save["car_tasks"].has(str(car["uid"])):
				continue
			if car["bay_uid"] != 0:
				if save["jobs"].has(str(car["bay_uid"])):
					continue
				car["bay_uid"] = 0
			car["placed"] = false
			stored["cars"] += 1
	for entry: Dictionary in save["garage"]["items"].duplicate():
		var is_bay := _is_bay(entry["uid"])
		if (is_bay and not bays) or (not is_bay and not items):
			continue
		if is_bay and _bay_busy(entry["uid"]):
			continue
		save["garage"]["items"].erase(entry)
		_store_item(entry["item_id"])
		stored["bays" if is_bay else "items"] += 1
	return GameResult.success(stored)


func place_stored_item(item_id: int, x: int, y: int, rot: int) -> GameResult:
	var key := str(item_id)
	if save["storage"].get(key, 0) <= 0:
		return GameResult.fail("You don't have that item in storage.")
	if not GarageGrid.is_floor_object(catalog.item(item_id)) or not _item_fits(item_id, x, y, rot):
		return GameResult.fail("There's no room there.")
	save["storage"][key] -= 1
	if save["storage"][key] == 0:
		save["storage"].erase(key)
	var entry := _add_item(item_id, x, y, rot)
	return GameResult.success({"uid": entry["uid"]})


func sell_item(uid: int) -> GameResult:
	var entry := _find_item(uid)
	if entry.is_empty():
		return GameResult.fail("Item not found.")
	if _bay_busy(uid):
		return GameResult.fail("Clear the work bay before selling it.")
	var fraction: float = catalog.tune("economy.item_resell_fraction", 0.5)
	var refund: int = floori(catalog.item(entry["item_id"]).get("price", 0) * fraction)
	save["garage"]["items"].erase(entry)
	_player()["coins"] += refund
	return GameResult.success({"coins": refund})


func sell_stored_item(item_id: int) -> GameResult:
	var key := str(item_id)
	if save["storage"].get(key, 0) <= 0:
		return GameResult.fail("You don't have that item in storage.")
	save["storage"][key] -= 1
	if save["storage"][key] == 0:
		save["storage"].erase(key)
	var fraction: float = catalog.tune("economy.item_resell_fraction", 0.5)
	var refund: int = floori(catalog.item(item_id).get("price", 0) * fraction)
	_player()["coins"] += refund
	return GameResult.success({"coins": refund})


## Floor tiles and wall styles cover the whole garage; price is per tile.
func set_surface(item_id: int, use_blue: bool, now: int) -> GameResult:
	var def: Dictionary = catalog.item(item_id)
	var cat: int = def.get("category", 0)
	if cat != GarageGrid.CAT_FLOOR_TILE and cat != GarageGrid.CAT_WALL:
		return GameResult.fail("That isn't a floor or wall style.")
	var key := "floor_item_id" if cat == GarageGrid.CAT_FLOOR_TILE else "wall_item_id"
	if save["garage"][key] == item_id:
		return GameResult.fail("Your garage already uses that style.")
	var err := _level_ok(def)
	if err != "":
		return GameResult.fail(err)
	var land: Dictionary = catalog.land(save["garage"]["land_id"])
	var tiles: int = land["size_x"] * land["size_y"] if cat == GarageGrid.CAT_FLOOR_TILE else land["size_x"] + land["size_y"]
	err = _charge(def, use_blue, tiles)
	if err != "":
		return GameResult.fail(err)
	save["garage"][key] = item_id
	var result := GameResult.success()
	_emit("BOUGHT_ITEM_ID", item_id, now, result)
	_emit("BOUGHT_ITEM_CATEGORY", cat, now, result)
	_emit("DECORATE_GARAGE", 0, now, result)
	return result


func next_land_id() -> int:
	var next: int = save["garage"]["land_id"] + 1
	if next > catalog.tune("garage.max_land_id", 7) or catalog.land(next).is_empty():
		return 0
	return next


func expand_land(use_blue: bool, now: int) -> GameResult:
	var next := next_land_id()
	if next == 0:
		return GameResult.fail("Your garage is as big as it gets.")
	var def: Dictionary = catalog.land(next).duplicate()
	def["can_buy_with_coins"] = def["price"] > 0
	def["can_buy_with_blue"] = def["blue_price"] > 0
	var err := _level_ok(def)
	if err != "":
		return GameResult.fail(err)
	err = _charge(def, use_blue)
	if err != "":
		return GameResult.fail(err)
	save["garage"]["land_id"] = next
	var result := GameResult.success({"land_id": next})
	_emit("LAND_EXPANDED", next, now, result)
	return result


# --- Work bays and jobs -------------------------------------------------------------------

func _is_bay(uid: int) -> bool:
	var entry := _find_item(uid)
	return not entry.is_empty() and catalog.item(entry["item_id"]).get("category", 0) == GarageGrid.CAT_WORK_BAY


## The car (own or customer) sitting on a bay: {"kind": "car"/"customer", "entry": {...}}.
func bay_occupant(bay_uid: int) -> Dictionary:
	for c: Dictionary in save["cars"]:
		if c["bay_uid"] == bay_uid:
			return {"kind": "car", "entry": c}
	for c: Dictionary in save["customers"]:
		if c.get("bay_uid", 0) == bay_uid:
			return {"kind": "customer", "entry": c}
	return {}


func _bay_busy(uid: int) -> bool:
	return not bay_occupant(uid).is_empty() or save["jobs"].has(str(uid))


func put_car_on_bay(car_uid: int, bay_uid: int) -> GameResult:
	var car := get_car(car_uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if not _is_bay(bay_uid):
		return GameResult.fail("That isn't a work bay.")
	if not bay_occupant(bay_uid).is_empty():
		return GameResult.fail("That work bay is taken.")
	if car["bay_uid"] != 0:
		return GameResult.fail("That car is already on a work bay.")
	if save["car_tasks"].has(str(car_uid)):
		return GameResult.fail("This car is out on a job.")
	car["bay_uid"] = bay_uid
	car["placed"] = true
	return GameResult.success()


func take_car_off_bay(car_uid: int) -> GameResult:
	var car := get_car(car_uid)
	if car.is_empty() or car["bay_uid"] == 0:
		return GameResult.fail("That car isn't on a work bay.")
	if save["jobs"].has(str(car["bay_uid"])):
		return GameResult.fail("Finish the job first.")
	car["bay_uid"] = 0
	var car_size: Array = catalog.tune("garage.car_size", [4, 3])
	var spot := GarageGrid.build(catalog, save).find_free(Vector2i(car_size[0], car_size[1]))
	if spot.x >= 0:
		car["x"] = spot.x
		car["y"] = spot.y
		car["rot"] = 0
	else:
		car["placed"] = false
	return GameResult.success({"placed": car["placed"]})


## Jobs the player can start (level-gated work bay jobs).
func available_job_ids() -> Array[int]:
	var result: Array[int] = []
	for id: int in catalog.jobs:
		var j: Dictionary = catalog.jobs[id]
		if j["type"] != 2 or j["is_car_build"] or j["specific_car_id"] != 0:
			continue
		if j["coins"] <= 0 and j["xp"] <= 0:
			continue
		result.append(id)
	result.sort_custom(func(a: int, b: int) -> bool:
		var ja: Dictionary = catalog.jobs[a]
		var jb: Dictionary = catalog.jobs[b]
		return ja["min_level"] < jb["min_level"] if ja["min_level"] != jb["min_level"] else ja["minutes"] < jb["minutes"])
	return result


func start_job(bay_uid: int, job_id: int, now: int) -> GameResult:
	if not _is_bay(bay_uid):
		return GameResult.fail("That isn't a work bay.")
	if save["jobs"].has(str(bay_uid)):
		return GameResult.fail("That work bay is already busy.")
	var def: Dictionary = catalog.job(job_id)
	if def.is_empty() or not available_job_ids().has(job_id):
		return GameResult.fail("Unknown job.")
	var occ := bay_occupant(bay_uid)
	if occ.get("kind", "") == "customer" and occ["entry"].get("job_id", 0) not in [0, job_id]:
		return GameResult.fail("This customer wants a %s." % catalog.job(occ["entry"]["job_id"]).get("name", "different job"))
	if _player()["level"] < def["min_level"]:
		return GameResult.fail("Requires level %d." % def["min_level"])
	if busy_workers() >= max_workers():
		return GameResult.fail("All your workers are busy. Level up to hire more.")
	var cost: int = ceili(def["price"] * float(catalog.tune("jobs.start_cost_multiplier", 1.0)))
	if _player()["coins"] < cost:
		return GameResult.fail("Not enough coins.")
	_player()["coins"] -= cost
	var job_state := {"job_id": job_id, "started_at": now, "ends_at": now + def["minutes"] * 60}
	if occ.is_empty():
		_add_job_car(job_state)
	save["jobs"][str(bay_uid)] = job_state
	_bump_stat("jobs_started")
	var result := GameResult.success({"ends_at": now + def["minutes"] * 60})
	_emit("STARTED_WORKBAY_TASK_ID", job_id, now, result)
	return result


## A job started on an empty lift gets a random factory car to work on
## (WorkBayFloorObj.createRandomCar), drawn from the customers' pool.
func _add_job_car(job_state: Dictionary) -> void:
	var pool := _customer_pool()
	if pool.is_empty():
		return
	var pick := SimpleRng.range_int(save["rng"], 0, pool.size() - 1)
	save["rng"] = pick[0]
	var car_id: int = pool[pick[1]]
	var colors := catalog.colors_for_car(car_id)
	var color_pick := SimpleRng.range_int(save["rng"], 0, maxi(0, colors.size() - 1))
	save["rng"] = color_pick[0]
	job_state["car_id"] = car_id
	job_state["color_id"] = colors[color_pick[1]]["id"] if not colors.is_empty() else 0


func mastery_level(job_id: int) -> int:
	var count: int = save["job_mastery"].get(str(job_id), 0)
	var thresholds: Array = catalog.job(job_id).get("mastery_thresholds", [0])
	var level := 1
	for i in range(1, thresholds.size()):
		if thresholds[i] > 0 and count >= thresholds[i]:
			level = i + 1
	return level


func job_payout(job_id: int) -> Dictionary:
	var def: Dictionary = catalog.job(job_id)
	var level := mastery_level(job_id)
	var xp_list: Array = def.get("mastery_xp", [def.get("xp", 0)])
	var xp: int = xp_list[mini(level - 1, xp_list.size() - 1)]
	if xp <= 0:
		xp = def.get("xp", 0)
	return {
		"coins": roundi(def.get("coins", 0) * float(catalog.tune("jobs.coin_multiplier", 1.0))),
		"xp": roundi(xp * float(catalog.tune("jobs.xp_multiplier", 1.0))),
	}


func collect_job(bay_uid: int, now: int) -> GameResult:
	var key := str(bay_uid)
	if not save["jobs"].has(key):
		return GameResult.fail("There's no job on that work bay.")
	var job_state: Dictionary = save["jobs"][key]
	if now < job_state["ends_at"]:
		return GameResult.fail("The job isn't finished yet.")
	var job_id: int = job_state["job_id"]
	save["jobs"].erase(key)
	var result := _pay_job(job_id)
	# A customer's car leaves once its job is collected.
	var occ := bay_occupant(bay_uid)
	if occ.get("kind", "") == "customer":
		save["customers"].erase(occ["entry"])
	_bump_stat("jobs_collected")
	_emit("COLLECTED_WORKBAY_TASK_ID", job_id, now, result)
	return result


## Pays out a finished job and counts it towards the job's mastery.
func _pay_job(job_id: int) -> GameResult:
	var pay := job_payout(job_id)
	var before := mastery_level(job_id)
	save["job_mastery"][str(job_id)] = save["job_mastery"].get(str(job_id), 0) + 1
	var result := GameResult.success(pay)
	add_rewards(pay["coins"], 0, pay["xp"], result)
	var after := mastery_level(job_id)
	if after > before:
		var bonus: Dictionary = {}
		for tm: Dictionary in catalog.task_mastery_levels:
			if tm["level"] == after:
				bonus = tm
		add_rewards(bonus.get("coin_bonus", 0), bonus.get("blue_bonus", 0), bonus.get("xp_bonus", 0), result)
		result.notices.append({"kind": "mastery", "job_id": job_id, "level": after,
			"coins": bonus.get("coin_bonus", 0), "blue": bonus.get("blue_bonus", 0)})
	return result


## Cancels a job with no refund (the original's "Stop Job"). A customer
## takes their car and leaves.
func stop_job(bay_uid: int) -> GameResult:
	var key := str(bay_uid)
	if not save["jobs"].has(key):
		return GameResult.fail("There's no job on that work bay.")
	save["jobs"].erase(key)
	var occ := bay_occupant(bay_uid)
	if occ.get("kind", "") == "customer":
		save["customers"].erase(occ["entry"])
	return GameResult.success()


func finish_now_price(bay_uid: int, now: int) -> int:
	var job_state: Dictionary = save["jobs"].get(str(bay_uid), {})
	return 0 if job_state.is_empty() else _finish_price(job_state["ends_at"] - now)


## Blue coins to finish a job with [param remaining] seconds left.
func _finish_price(remaining: int) -> int:
	var per_hour: float = catalog.tune("jobs.finish_now_blue_per_hour", 1)
	var min_blue: int = catalog.tune("jobs.finish_now_min_blue", 1)
	return maxi(min_blue, ceili(maxi(0, remaining) / 3600.0 * per_hour))


func finish_job_now(bay_uid: int, now: int) -> GameResult:
	var job_state: Dictionary = save["jobs"].get(str(bay_uid), {})
	if job_state.is_empty():
		return GameResult.fail("There's no job on that work bay.")
	if now >= job_state["ends_at"]:
		return collect_job(bay_uid, now)
	var price := finish_now_price(bay_uid, now)
	if _player()["blue"] < price:
		return GameResult.fail("Not enough blue coins.")
	_player()["blue"] -= price
	job_state["ends_at"] = now
	return collect_job(bay_uid, now)


# --- Car tasks ------------------------------------------------------------------------
# Jobs your own car goes out and does (the original's car tasks: pizza
# delivery, the truck routes...), started from the car itself rather than a
# work bay. They share workers, mastery and mission events with bay jobs.

## Car tasks [param car_uid] can do (CarTasksHelper.getTasksForCar), limited
## to the ones enabled in tuning.
func car_task_ids(car_uid: int) -> Array[int]:
	var car := get_car(car_uid)
	var result: Array[int] = []
	if car.is_empty():
		return result
	var category: int = catalog.car(car["car_id"]).get("category", 0)
	for id: Variant in catalog.tune("car_tasks.enabled", []):
		var def: Dictionary = catalog.job(int(id))
		if def.is_empty() or def["type"] != 1:
			continue
		var cats: Array = def.get("car_categories", [])
		if cats.has(0) or cats.has(category) or def.get("car_ids", []).has(car["car_id"]):
			result.append(int(id))
	return result


func start_car_task(car_uid: int, job_id: int, now: int) -> GameResult:
	var car := get_car(car_uid)
	if car.is_empty():
		return GameResult.fail("Car not found.")
	if not car["placed"]:
		return GameResult.fail("Put the car in your garage first.")
	if car["bay_uid"] != 0:
		return GameResult.fail("Take the car off the work bay first.")
	if save["car_tasks"].has(str(car_uid)):
		return GameResult.fail("This car is already out on a job.")
	if not car_task_ids(car_uid).has(job_id):
		return GameResult.fail("This car can't do that job.")
	var def: Dictionary = catalog.job(job_id)
	if _player()["level"] < def["min_level"]:
		return GameResult.fail("Requires level %d." % def["min_level"])
	if busy_workers() >= max_workers():
		return GameResult.fail("All your workers are busy. Level up to hire more.")
	var cost: int = ceili(def["price"] * float(catalog.tune("jobs.start_cost_multiplier", 1.0)))
	if _player()["coins"] < cost:
		return GameResult.fail("Not enough coins.")
	_player()["coins"] -= cost
	var ends_at: int = now + def["minutes"] * 60
	save["car_tasks"][str(car_uid)] = {"job_id": job_id, "started_at": now, "ends_at": ends_at}
	_bump_stat("jobs_started")
	var result := GameResult.success({"ends_at": ends_at})
	_emit("STARTED_WORKBAY_TASK_ID", job_id, now, result)
	return result


func collect_car_task(car_uid: int, now: int) -> GameResult:
	var key := str(car_uid)
	if not save["car_tasks"].has(key):
		return GameResult.fail("This car isn't out on a job.")
	var task: Dictionary = save["car_tasks"][key]
	if now < task["ends_at"]:
		return GameResult.fail("The job isn't finished yet.")
	var job_id: int = task["job_id"]
	save["car_tasks"].erase(key)
	var result := _pay_job(job_id)
	_bump_stat("jobs_collected")
	_emit("COLLECTED_WORKBAY_TASK_ID", job_id, now, result)
	return result


## Calls the car back with no refund ("Stop Job").
func stop_car_task(car_uid: int) -> GameResult:
	if not save["car_tasks"].has(str(car_uid)):
		return GameResult.fail("This car isn't out on a job.")
	save["car_tasks"].erase(str(car_uid))
	return GameResult.success()


func car_task_finish_price(car_uid: int, now: int) -> int:
	var task: Dictionary = save["car_tasks"].get(str(car_uid), {})
	return 0 if task.is_empty() else _finish_price(task["ends_at"] - now)


func finish_car_task_now(car_uid: int, now: int) -> GameResult:
	var task: Dictionary = save["car_tasks"].get(str(car_uid), {})
	if task.is_empty():
		return GameResult.fail("This car isn't out on a job.")
	if now >= task["ends_at"]:
		return collect_car_task(car_uid, now)
	var price := car_task_finish_price(car_uid, now)
	if _player()["blue"] < price:
		return GameResult.fail("Not enough blue coins.")
	_player()["blue"] -= price
	task["ends_at"] = now
	return collect_car_task(car_uid, now)


# --- Customers --------------------------------------------------------------------------

## Spawns customer cars that arrived since the last check.
func tick(now: int) -> GameResult:
	var result := GameResult.success()
	var interval: int = int(catalog.tune("customers.interval_minutes", 2)) * 60
	var max_waiting: int = catalog.tune("customers.max_waiting", 3)
	var pool := _customer_pool()
	while save["next_customer_at"] <= now and not pool.is_empty():
		if _waiting_customers() >= max_waiting:
			save["next_customer_at"] = now + interval
			break
		var pick := SimpleRng.range_int(save["rng"], 0, pool.size() - 1)
		save["rng"] = pick[0]
		var car_id: int = pool[pick[1]]
		var colors := catalog.colors_for_car(car_id)
		var color_pick := SimpleRng.range_int(save["rng"], 0, maxi(0, colors.size() - 1))
		save["rng"] = color_pick[0]
		# Like the original, a customer asks for one quick job you've unlocked.
		var jobs := _customer_jobs()
		var job_id := 0
		if not jobs.is_empty():
			var job_pick := SimpleRng.range_int(save["rng"], 0, jobs.size() - 1)
			save["rng"] = job_pick[0]
			job_id = jobs[job_pick[1]]
		save["customers"].append({
			"uid": _uid(), "car_id": car_id,
			"color_id": colors[color_pick[1]]["id"] if not colors.is_empty() else 0,
			"arrived_at": save["next_customer_at"], "bay_uid": 0, "job_id": job_id,
		})
		save["next_customer_at"] += interval
		result.data["arrived"] = result.data.get("arrived", 0) + 1
	if pool.is_empty():
		save["next_customer_at"] = now + interval
	missions.refresh_daily(save, now, _dealer_ids)
	return result


## Quick jobs a customer may ask for (unlocked, at most max_job_minutes).
func _customer_jobs() -> Array[int]:
	var max_minutes: int = catalog.tune("customers.max_job_minutes", 5)
	var result: Array[int] = []
	for id: int in available_job_ids():
		var j: Dictionary = catalog.job(id)
		if j["min_level"] <= _player()["level"] and j["minutes"] <= max_minutes:
			result.append(id)
	return result


func _waiting_customers() -> int:
	return save["customers"].filter(func(c: Dictionary) -> bool: return c.get("bay_uid", 0) == 0).size()


func _customer_pool() -> Array[int]:
	var level: int = _player()["level"]
	var pool: Array[int] = []
	for id: int in dealer_car_ids():
		if catalog.car(id)["min_level"] <= level + 5:
			pool.append(id)
	return pool


func accept_customer(customer_uid: int, bay_uid: int) -> GameResult:
	var cust := get_customer(customer_uid)
	if cust.is_empty() or cust.get("bay_uid", 0) != 0:
		return GameResult.fail("That customer isn't waiting.")
	if not _is_bay(bay_uid):
		return GameResult.fail("That isn't a work bay.")
	if not bay_occupant(bay_uid).is_empty():
		return GameResult.fail("That work bay is taken.")
	cust["bay_uid"] = bay_uid
	_bump_stat("customers_accepted")
	return GameResult.success()


func dismiss_customer(customer_uid: int) -> GameResult:
	var cust := get_customer(customer_uid)
	if cust.is_empty():
		return GameResult.fail("Customer not found.")
	if cust.get("bay_uid", 0) != 0 and save["jobs"].has(str(cust["bay_uid"])):
		return GameResult.fail("Finish the job first.")
	save["customers"].erase(cust)
	return GameResult.success()


# --- Town -------------------------------------------------------------------------------

func town_location_ids() -> Array[int]:
	var result: Array[int] = []
	for id: int in catalog.tune("town.v1_locations", []):
		if catalog.locations.has(id):
			result.append(id)
	return result


func open_gps(now: int) -> GameResult:
	var result := GameResult.success()
	_emit("OPEN_GPS", 0, now, result)
	return result


func visit_location(location_id: int, now: int) -> GameResult:
	if not town_location_ids().has(location_id):
		return GameResult.fail("You can't go there yet.")
	var loc: Dictionary = catalog.locations[location_id]
	if _player()["level"] < loc["min_level"]:
		return GameResult.fail("Requires level %d." % loc["min_level"])
	if not save["visited_locations"].has(location_id):
		save["visited_locations"].append(location_id)
	var result := GameResult.success()
	_emit("WENT_TO_LOCATION", location_id, now, result)
	return result


# --- Tutorial ---------------------------------------------------------------------------

func set_tutorial(step: int, done: bool) -> GameResult:
	save["tutorial"] = {"step": step, "done": done}
	return GameResult.success()


func rename(player_name: String) -> GameResult:
	var n := player_name.strip_edges()
	if n.is_empty() or n.length() > 20:
		return GameResult.fail("Names are 1 to 20 characters.")
	_player()["name"] = n
	return GameResult.success()
