class_name PlayerIdentity
extends RefCounted
## A random id for this PC's player, so a LAN host can recognise returning
## guests. Stored locally; it isn't an account and holds no personal data.

const PATH := "user://player_identity.cfg"

## Lets two copies of the game on one PC act as different players
## (command line: -- player_id=<anything>). Also used by tests.
static var override_id := ""


static func get_id() -> String:
	if override_id == "":
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("player_id="):
				override_id = a.trim_prefix("player_id=")
	if override_id != "":
		return override_id
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var id: String = cfg.get_value("player", "id", "")
	if id.is_empty():
		var crypto := Crypto.new()
		id = crypto.generate_random_bytes(12).hex_encode()
		cfg.set_value("player", "id", id)
		cfg.save(PATH)
	return id


static func get_name() -> String:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg.get_value("player", "name", "")


static func set_name(player_name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("player", "name", player_name)
	cfg.save(PATH)
