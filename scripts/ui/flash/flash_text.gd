class_name FlashText
extends Node2D
## A text field from an original symbol: same box, font, size, colour and
## alignment as the Flash TextField. Shows the field's initial text until the
## game sets its own.

const GUTTER := 2.0

var label: Label
var _info: Dictionary


## The field's box in its own coordinates.
func box() -> Rect2:
	var b: Array = _info.get("bounds", [0, 0, 0, 0])
	return Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])


func setup(info: Dictionary) -> void:
	_info = info
	var b: Array = info["bounds"]
	label = Label.new()
	label.position = Vector2(b[0] + GUTTER, b[1] + GUTTER)
	label.size = Vector2(b[2] - b[0] - GUTTER * 2, b[3] - b[1] - GUTTER * 2)
	label.clip_text = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	settings.font = FlashUi.font_by_id(str(info.get("font", "")))
	var size: float = info.get("size", 12)
	var color := Color.html(info.get("color", "#000000"))
	# HTML fields carry their real size/colour in the first <font> tag.
	var html: String = info.get("html", "")
	var re := RegEx.create_from_string("size=\"(\\d+)\"")
	var m := re.search(html)
	if m != null:
		size = float(m.get_string(1))
	var rc := RegEx.create_from_string("color=\"#([0-9a-fA-F]{6})\"")
	var mc := rc.search(html)
	if mc != null:
		color = Color.html(mc.get_string(1))
	settings.font_size = int(round(size))
	settings.font_color = color
	settings.line_spacing = info.get("leading", 0)
	label.label_settings = settings
	label.horizontal_alignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT,
		HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_FILL][clampi(info.get("align", 0), 0, 3)]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if info.get("wrap", false) else TextServer.AUTOWRAP_OFF
	set_text(_strip_html(html) if html != "" else info.get("text", ""))
	add_child(label)


func set_text(value: String) -> void:
	label.text = value


## The field's Flash filters from the symbol: an outer glow, or a drop shadow
## at (almost) no distance, draws as an outline; a real drop shadow as a
## shadow. Inner glows are skipped.
func apply_filters(filters: Array) -> void:
	var settings := label.label_settings
	for f: Dictionary in filters:
		if f.get("inner", false):
			continue
		var color := Color.html(f["color"])
		var blur: float = f.get("blur", 2.0)
		var strength: float = f.get("strength", 1.0)
		var distance: float = f.get("distance", 0.0)
		if f["type"] == "glow" or distance <= 1.0:
			# A strong small glow is a solid edge about blur/2 px wide.
			var width := clampf(blur * minf(strength, 2.0) / 2.0, 1.0, 6.0)
			settings.outline_color = color
			settings.outline_size = maxi(settings.outline_size, roundi(width * 2.0))
		else:
			settings.shadow_color = color
			settings.shadow_size = roundi(blur / 2.0)
			settings.shadow_offset = Vector2(distance, distance) * 0.7071


## LanguageManager.cascadeTextStyleOnTextField: swap in a text style's font
## (and size, if given), keeping the field's colour.
func set_style(style: String, font_size: int = 0) -> void:
	var f := FlashUi.style_font(style)
	if f != null:
		label.label_settings.font = f
	if font_size > 0:
		label.label_settings.font_size = font_size


## Wraps the text in the field's box and shrinks the font until it fits
## (for text longer than the original's).
func fit_to_box(min_size: int = 12) -> void:
	var b := box()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = Vector2(b.size.x - GUTTER * 2, 0)
	var s := label.label_settings.font_size
	while s > min_size:
		label.size = Vector2(b.size.x - GUTTER * 2, 0)
		if label.get_minimum_size().y <= b.size.y - GUTTER * 2:
			break
		s -= 2
		label.label_settings.font_size = s


func set_color(c: Color) -> void:
	label.label_settings.font_color = c


func set_outline(c: Color, px: int) -> void:
	label.label_settings.outline_color = c
	label.label_settings.outline_size = px


static func _strip_html(html: String) -> String:
	var re := RegEx.create_from_string("<[^>]*>")
	var t := re.sub(html, "", true)
	return t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'")
