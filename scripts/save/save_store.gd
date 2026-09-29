class_name SaveStore
extends RefCounted
## Reads and writes save files for one folder of slots.
##
## Writes go to a temp file first, then replace the real file, keeping the
## previous version as a .bak so a crash mid-write never loses a save.

const SLOT_COUNT := 3

var folder: String


func _init(save_folder: String) -> void:
	folder = save_folder
	DirAccess.make_dir_recursive_absolute(folder)


func path_for(slot: int) -> String:
	return folder.path_join("slot_%d.json" % slot)


func exists(slot: int) -> bool:
	return FileAccess.file_exists(path_for(slot)) or FileAccess.file_exists(path_for(slot) + ".bak")


## Loads and upgrades a slot. Falls back to the backup if the main file is
## damaged. Returns {} and fills [param errors] on failure.
func load_slot(slot: int, errors: Array[String] = []) -> Dictionary:
	for path: String in [path_for(slot), path_for(slot) + ".bak"]:
		var raw: Variant = JsonUtil.read_file(path)
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var migrated := SaveMigrations.migrate(raw, errors)
		if not migrated.is_empty():
			return migrated
	if errors.is_empty():
		errors.append("Save slot %d is empty or unreadable." % slot)
	return {}


func write_slot(slot: int, data: Dictionary) -> bool:
	var path := path_for(slot)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Could not write %s: %s" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "", false))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(tmp, path) == OK


func delete_slot(slot: int) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path_for(slot) + suffix):
			DirAccess.remove_absolute(path_for(slot) + suffix)


## Small summary for the slot picker, or {} if empty.
func summary(slot: int) -> Dictionary:
	var data := load_slot(slot)
	if data.is_empty():
		return {}
	return {
		"name": data["player"]["name"],
		"level": data["player"]["level"],
		"coins": data["player"]["coins"],
		"updated_at": data.get("updated_at", 0),
	}
