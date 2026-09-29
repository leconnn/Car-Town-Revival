extends Node
## Autoload "GameData": the loaded catalog and art manifests.

const EA_DATA_DIR := "res://assets/ea/data"
const EA_ART_DIR := "res://assets/ea/art"
const TUNING_PATH := "res://data/tuning.json"

var catalog: Catalog
var load_error: String = ""
## Art manifests written by tools/export_art.py.
var car_art: Dictionary = {}
var item_art: Dictionary = {}
var wheel_art: Dictionary = {}

var _texture_cache: Dictionary[String, Texture2D] = {}


func _ready() -> void:
	catalog = Catalog.new()
	if not catalog.load_from(EA_DATA_DIR, TUNING_PATH):
		load_error = catalog.load_error + "\n\nRun tools/convert_catalog.py first (see docs/extraction.md)."
		push_error(load_error)
		return
	car_art = _read_manifest("cars")
	item_art = _read_manifest("items")
	wheel_art = _read_manifest("wheels")
	# Only cars with a body in every view can be drawn everywhere.
	for key: String in car_art:
		var views: Dictionary = car_art[key].get("views", {})
		if ["front", "rear", "angle"].all(func(v: String) -> bool:
				return views.get(v, {}).get("layers", {}).has("body")):
			catalog.art_car_ids[int(key)] = true


func is_loaded() -> bool:
	return load_error == "" and catalog != null


func _read_manifest(name: String) -> Dictionary:
	var value: Variant = JsonUtil.read_file(EA_ART_DIR.path_join(name + ".json"))
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Loads an exported art file ("cars/1/front/body.png"). Cached.
func texture(rel_path: String) -> Texture2D:
	if rel_path.is_empty():
		return null
	if _texture_cache.has(rel_path):
		return _texture_cache[rel_path]
	var path := EA_ART_DIR.path_join(rel_path)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	elif FileAccess.file_exists(path):
		# Not imported yet (e.g. art exported while the editor was closed).
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			tex = ImageTexture.create_from_image(img)
	_texture_cache[rel_path] = tex
	return tex


## A bitmap from CarTownMain.swf by class name (PNG or JPEG).
func main_texture(class_name_: String) -> Texture2D:
	var tex := texture("main/%s.png" % class_name_)
	return tex if tex != null else texture("main/%s.jpg" % class_name_)


func car_name(car_id: int) -> String:
	var c: Dictionary = catalog.car(car_id)
	if c.is_empty():
		return "Unknown car"
	return "%d %s %s" % [c["year"], c["make"], c["model"]]
