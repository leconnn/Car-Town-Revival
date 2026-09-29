class_name Settings
extends RefCounted
## Player settings (not part of any save): window mode and volumes.

const PATH := "user://settings.cfg"

static var fullscreen := false
static var music_volume := 0.7
static var sfx_volume := 0.8
## Missions the player has opened (so their "NEW GOAL!" flag stops showing).
static var missions_seen: Array = []


static func load_and_apply() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		fullscreen = cfg.get_value("display", "fullscreen", false)
		music_volume = cfg.get_value("audio", "music", 0.7)
		sfx_volume = cfg.get_value("audio", "sfx", 0.8)
		missions_seen = cfg.get_value("missions", "seen", [])
	apply()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("missions", "seen", missions_seen)
	cfg.save(PATH)


static func apply() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)


static func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)
