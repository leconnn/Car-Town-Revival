class_name SaveMigrations
extends RefCounted
## Upgrades old saves one version at a time. Never delete a step: a save from
## any past version must still load.
##
## To change the save layout:
##   1. Bump GameLogic.CURRENT_SAVE_VERSION.
##   2. Add a `_v<N>_to_v<N+1>` function and a `match` branch in _step().
##   3. Add a test in tests/save/ with a fixture of the old layout.


## Returns the upgraded save, or an empty Dictionary with [param errors]
## filled in if the save can't be read.
static func migrate(data: Dictionary, errors: Array[String] = []) -> Dictionary:
	if not data.has("save_version"):
		errors.append("Not a save file (no save_version).")
		return {}
	var version: int = data["save_version"]
	if version > GameLogic.CURRENT_SAVE_VERSION:
		errors.append("This save is from a newer version of the game (v%d)." % version)
		return {}
	var out := data.duplicate(true)
	while version < GameLogic.CURRENT_SAVE_VERSION:
		var next := _step(version, out)
		if next.is_empty():
			errors.append("No upgrade path from save version %d." % version)
			return {}
		out = next
		version += 1
		out["save_version"] = version
	return out


## Upgrades from [param version] to version + 1. Returns {} if unknown.
static func _step(version: int, data: Dictionary) -> Dictionary:
	match version:
		1:
			return _v1_to_v2(data)
		2:
			return _v2_to_v3(data)
		_:
			return {}


## v2 added car tasks (jobs your own car goes out on) and split the single
## upgrade stage into the original's four tracks; old stages go to engine.
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	data["car_tasks"] = {}
	for car: Dictionary in data.get("cars", []):
		car["upgrades"] = [int(car.get("upgrade", 0)), 0, 0, 0]
		car.erase("upgrade")
	return data


## v3 added parts storage: parts taken off a car, to put back on for free.
static func _v2_to_v3(data: Dictionary) -> Dictionary:
	data["part_storage"] = {}
	return data
