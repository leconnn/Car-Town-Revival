extends Node
## Autoload "FlashUi": the original game's UI symbols, rebuilt from the data
## written by tools/export_ui.py (assets/ea/ui/). See docs/original-ui-map.md.
##
##   var gauge := FlashUi.make("UIXPGaugeGfx")
##   gauge.text("levelField", "27")
##   gauge.part("needle").rotation_degrees = 90

const UI_DIR := "res://assets/ea/ui"

var db: Dictionary = {}
var styles: Dictionary = {}
var _fonts: Dictionary[String, Font] = {}
var _textures: Dictionary[String, Texture2D] = {}


func _ready() -> void:
	var value: Variant = JsonUtil.read_file(UI_DIR.path_join("symbols.json"))
	db = value if typeof(value) == TYPE_DICTIONARY else {}
	var st: Variant = JsonUtil.read_file(UI_DIR.path_join("styles.json"))
	styles = st if typeof(st) == TYPE_DICTIONARY else {}


func is_loaded() -> bool:
	return not db.is_empty()


func has_class(class_name_: String) -> bool:
	return db.get("classes", {}).has(class_name_)


## Symbol key ("lib:id") for a class name, or "". Short names work too
## ("BalanceLegacy" finds "swcassets.hud.BalanceLegacy").
func char_id(class_name_: String) -> String:
	var classes: Dictionary = db.get("classes", {})
	if classes.has(class_name_):
		return classes[class_name_]
	if not _short_names.has(class_name_):
		_short_names[class_name_] = ""
		for full: String in classes:
			if full.ends_with("." + class_name_):
				_short_names[class_name_] = classes[full]
				break
	return _short_names[class_name_]


var _short_names: Dictionary[String, String] = {}


func char_info(id: String) -> Dictionary:
	return db.get("chars", {}).get(id, {})


## A new instance of a library symbol by its class name, or null.
func make(class_name_: String, frame: int = 0) -> FlashSymbol:
	var id := char_id(class_name_)
	if id == "" or char_info(id).is_empty():
		push_warning("FlashUi: no symbol %s" % class_name_)
		return null
	var s := FlashSymbol.new()
	s.setup(id, frame)
	return s


func layer_texture(key: String) -> Dictionary:
	var info: Dictionary = db.get("layers", {}).get(key, {})
	if info.is_empty() or info.get("file", "") == "":
		return {}
	var file: String = info["file"]
	if not _textures.has(file):
		_textures[file] = _load_texture(UI_DIR.path_join(file))
	return {"texture": _textures[file], "o": Vector2(info["o"][0], info["o"][1])}


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		return ImageTexture.create_from_image(img) if img != null else null
	return null


## Font for an embedded font id (text fields inside symbols).
func font_by_id(font_id: String) -> Font:
	var info: Dictionary = db.get("fonts", {}).get(font_id, {})
	return _font(info.get("file", ""))


## Font for one of the game's text styles ("casualA01", "sansD01", ...).
func style_font(style: String) -> Font:
	return _font(styles.get(style, {}).get("file", ""))


func _font(file: String) -> Font:
	if file == "":
		return null
	if not _fonts.has(file):
		var path := UI_DIR.path_join(file)
		var f: Font = null
		if ResourceLoader.exists(path):
			f = load(path)
		elif FileAccess.file_exists(path):
			var ff := FontFile.new()
			ff.load_dynamic_font(ProjectSettings.globalize_path(path))
			f = ff
		_fonts[file] = f
	return _fonts[file]


## A label in one of the game's text styles.
func styled_label(text: String, style: String, size: int, color: Color = Color.WHITE,
		outline: Color = Color(0, 0, 0, 0), outline_size: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	var settings := LabelSettings.new()
	settings.font = style_font(style)
	settings.font_size = size
	settings.font_color = color
	if outline.a > 0.0:
		settings.outline_color = outline
		settings.outline_size = outline_size
	l.label_settings = settings
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
