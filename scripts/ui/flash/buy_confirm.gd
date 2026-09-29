class_name BuyConfirm
extends Node2D
## The original BuyConfirm: a white rounded box (404 x 93, 3.5 px blue-grey
## stroke) asking "Buy <name> for <cost> coins?" with a green OK and a red
## close button. Sits on top of the bottom tray.

signal accepted
signal cancelled

const SIZE := Vector2(404, 93)
const TEXT := Color8(0x5B, 0x5B, 0x5B)
const NAME := Color8(0x38, 0x78, 0x99)
const STROKE := Color8(0x5F, 0x77, 0x91)


static func create(item_name: String, price: int, blue: bool) -> BuyConfirm:
	var b := BuyConfirm.new()
	b._build(item_name, price, blue)
	return b


func _build(item_name: String, price: int, blue: bool) -> void:
	var box := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = STROKE
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	box.add_theme_stylebox_override("panel", style)
	box.size = SIZE
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(box)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_override("normal_font", FlashUi.style_font("casualA01"))
	text.add_theme_font_size_override("normal_font_size", 20)
	text.add_theme_color_override("default_color", TEXT)
	text.size = Vector2(240, 84)
	text.text = "Buy [color=#%s]%s[/color] for %s %s?" % [NAME.to_html(false), item_name,
		Format.number(price), "blue coins" if blue else "coins"]
	add_child(text)
	# Centred once it has wrapped (content height is only known after layout).
	(func() -> void: text.position = Vector2(35, (SIZE.y - text.get_content_height()) / 2.0)).call_deferred()
	var ok_icon := FlashUi.make("UISymbolOk")
	var ok := FlashTextButton.create("", FlashTextButton.Kind.GREEN, 34, 32, 18, false,
		ok_icon if ok_icon != null else Node2D.new())
	ok.position = Vector2(280, 31)
	ok.pressed.connect(func() -> void: accepted.emit())
	add_child(ok)
	var cancel := FlashPopup.close_button()
	cancel.position = Vector2(344, 31)
	cancel.pressed.connect(func() -> void: cancelled.emit())
	add_child(cancel)
