class_name CarPreviewBox
extends Control
## Shows a car in the big showroom (angle) view inside the UI.

var _view: CarView
var _entry: Dictionary = {}
var _scale := 0.62


func _init(min_size: Vector2 = Vector2(340, 250), view_scale: float = 0.62) -> void:
	custom_minimum_size = min_size
	_scale = view_scale
	clip_contents = true


func show_car(entry: Dictionary) -> void:
	_entry = entry
	if _view != null:
		_view.queue_free()
	_view = CarView.new()
	_view.setup(entry, CarView.VIEW_ANGLE, false)
	_view.scale = Vector2(_scale, _scale)
	add_child(_view)
	_place()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


func _place() -> void:
	if _view != null:
		# The angle view's car sits roughly centred 180px above its origin.
		_view.position = Vector2(size.x / 2.0, size.y / 2.0 + 150.0 * _scale)


func _draw() -> void:
	# The original dealer backdrop: a vertical gradient strip and a halo.
	var bg := GameData.main_texture("swcassets.img.BuyCarBG")
	if bg != null:
		draw_texture_rect(bg, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.84, 0.88, 0.93))
	var halo := GameData.main_texture("swcassets.img.BuyCarGroundHalo")
	if halo != null:
		var w := minf(size.x * 0.95, halo.get_width() * _scale * 1.6)
		var h := w * halo.get_height() / halo.get_width()
		draw_texture_rect(halo, Rect2(size.x / 2.0 - w / 2.0, size.y / 2.0 + 150.0 * _scale - h * 0.6, w, h), false)


## A car entry for previews: stock parts and the given colour.
static func stock_entry(car_id: int, color_id: int) -> Dictionary:
	var entry := {"car_id": car_id, "color_id": color_id, "parts": {}, "ride_height": 0}
	var defaults: Dictionary = GameData.catalog.car(car_id).get("defaults", {})
	for key: String in defaults:
		var p: Dictionary = GameData.catalog.part(defaults[key])
		if not p.is_empty():
			entry["parts"][str(p["category_id"])] = p["id"]
	return entry
