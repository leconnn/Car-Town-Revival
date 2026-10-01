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
## GPS icons and town location layers (tools/export_art.py "town").
var town_art: Dictionary = {}
## Signs and posters as they hang on walls ("posters").
var poster_art: Dictionary = {}
## UI art the original loaded at runtime from static/ui ("static_ui").
var static_ui_art: Dictionary = {}
var mysterybox_art: Dictionary = {}
var restoration_art: Dictionary = {}
## The original loading screen's logo and background ("title").
var title_art: Dictionary = {}

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
	town_art = _read_manifest("town")
	poster_art = _read_manifest("posters")
	static_ui_art = _read_manifest("static_ui")
	mysterybox_art = _read_manifest("mysterybox")
	restoration_art = _read_manifest("restoration")
	title_art = _read_manifest("title")
	# Only cars with a body (painted, or unpainted like the junkers) in every
	# view can be drawn everywhere.
	for key: String in car_art:
		var views: Dictionary = car_art[key].get("views", {})
		if ["front", "rear", "angle"].all(func(v: String) -> bool:
				var layers: Dictionary = views.get(v, {}).get("layers", {})
				return layers.has("body") or layers.has("body_np")):
			catalog.art_car_ids[int(key)] = true


## Cars that are a restoration's starting junker (a car build's primer car).
func is_primer_car(car_id: int) -> bool:
	if _primer_ids.is_empty():
		for b: Dictionary in catalog.car_builds.values():
			_primer_ids[int(b.get("primer_car_id", 0))] = true
	return _primer_ids.has(car_id)


var _primer_ids: Dictionary[int, bool] = {}


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


## A mission's picture. The revival files only have one daily mission
## picture (the gold box with a clock), so dailies without their own use it.
func mission_picture(mission_id: int) -> Texture2D:
	var m: Dictionary = catalog.missions.get(mission_id, {})
	var tex := texture("missions/mission_%d.png" % m.get("icon_id", 0))
	if tex == null and m.get("category", "") == "daily":
		tex = texture("missions/mission_%d.png" % DAILY_MISSION_PICTURE)
	return tex


const DAILY_MISSION_PICTURE := 131025


func car_name(car_id: int) -> String:
	var c: Dictionary = catalog.car(car_id)
	if c.is_empty():
		return "Unknown car"
	return "%d %s %s" % [c["year"], c["make"], c["model"]]
