extends Node2D
## Developer view of original UI symbols rebuilt by FlashUi.
## godot --path . res://scenes/dev/ui_gallery.tscn -- shot=<png> [names=A,B,C]

const DEFAULT := ["UIXPGaugeGfx", "BalanceLegacy", "UIEnergyFuelGaugeGfx", "CarOptionsMasthead",
	"UICustomerTaskInfo", "UIIconButtonBodyRed", "UIIconButtonBodyGray", "swcassets.hud.GPSButtonGfx",
	"swcassets.hud.BottomNavChrome", "UIBgFrame", "UITanStrokedRoundedBg"]


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.45, 0.55, 0.6))
	var names: Array = DEFAULT
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("names="):
			names = a.trim_prefix("names=").split(",")
	var x := 20.0
	var y := 20.0
	var row_h := 0.0
	for n: String in names:
		var s := FlashUi.make(n)
		if s == null:
			continue
		add_child(s)
		var b := s.local_bounds()
		if x + b.size.x > 1580:
			x = 20
			y += row_h + 30
			row_h = 0
		s.position = Vector2(x, y) - b.position
		var l := Label.new()
		l.text = n.get_slice(".", n.get_slice_count(".") - 1)
		l.position = Vector2(x, y + b.size.y)
		l.add_theme_font_size_override("font_size", 11)
		add_child(l)
		x += b.size.x + 30
		row_h = maxf(row_h, b.size.y + 16)
	DevShot.maybe_capture(self)
