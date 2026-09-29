class_name LanWorld
extends RefCounted
## A LAN world: the host's save file holding every player who has joined.
##
## Layout:
##   {"world_version": 1, "name": str, "created_at": int, "updated_at": int,
##    "host_id": str, "players": {player_id: <normal player save>}}
## Each player save is the same format as single-player, so saves can move
## between single-player and LAN.

const WORLD_VERSION := 1
const SLOT_COUNT := 3

var folder: String


func _init(save_folder: String) -> void:
	folder = save_folder
	DirAccess.make_dir_recursive_absolute(folder)


func path_for(slot: int) -> String:
	return folder.path_join("world_%d.json" % slot)


static func new_world(world_name: String, now: int) -> Dictionary:
	return {"world_version": WORLD_VERSION, "name": world_name, "created_at": now,
		"updated_at": now, "host_id": "", "players": {}}


func load_slot(slot: int, errors: Array[String] = []) -> Dictionary:
	for path: String in [path_for(slot), path_for(slot) + ".bak"]:
		var raw: Variant = JsonUtil.read_file(path)
		if typeof(raw) != TYPE_DICTIONARY or not raw.has("world_version"):
			continue
		var world := migrate(raw, errors)
		if not world.is_empty():
			return world
	if errors.is_empty():
		errors.append("World slot %d is empty or unreadable." % slot)
	return {}


## Upgrades the world wrapper and every player save inside it.
static func migrate(world: Dictionary, errors: Array[String] = []) -> Dictionary:
	if world["world_version"] > WORLD_VERSION:
		errors.append("This world is from a newer version of the game.")
		return {}
	var out := world.duplicate(true)
	for pid: String in out["players"]:
		var p := SaveMigrations.migrate(out["players"][pid], errors)
		if p.is_empty():
			return {}
		out["players"][pid] = p
	return out


func write_slot(slot: int, world: Dictionary) -> bool:
	var path := path_for(slot)
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(world, "", false))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(path + ".tmp", path) == OK


func exists(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot))


func delete_slot(slot: int) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path_for(slot) + suffix):
			DirAccess.remove_absolute(path_for(slot) + suffix)


func summary(slot: int) -> Dictionary:
	var w := load_slot(slot)
	if w.is_empty():
		return {}
	return {"name": w["name"], "players": w["players"].size(), "updated_at": w.get("updated_at", 0)}
