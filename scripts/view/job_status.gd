class_name JobStatus
extends Node2D
## The original job callout over a busy work bay (StatusFull with
## UIStatusFullGfxNew): the job's icon and title, a progress bar in the
## job's colour, "3min left" and "(Click to finish now)", or "Collect!".

signal pressed

## WorkerTask colour names -> the original's progress colours.
const COLORS: Dictionary[String, Color] = {
	"green": Color8(0x59, 0x7C, 0x47), "red": Color8(0xA5, 0x3C, 0x3B), "blue": Color8(0x5B, 0x82, 0x8F),
	"yellow": Color8(0xEA, 0xA7, 0x00), "gray": Color8(0x54, 0x54, 0x54),
}
const ICON_WIDTH := 92.0

var bay_uid: int
var job: Dictionary
var _gfx: FlashSymbol
var _clip: Polygon2D
var _progress_size := Vector2.ZERO
var _done := false


func setup(bay: int, job_state: Dictionary) -> void:
	bay_uid = bay
	job = job_state
	var def: Dictionary = GameData.catalog.job(job["job_id"])
	_gfx = FlashUi.make("UIStatusFullGfxNew")
	if _gfx == null:
		return
	for hidden: String in ["dirt", "collectText", "textClean", "expiredField", "smallFrame", "smallBg"]:
		var p := _gfx.part(hidden) as CanvasItem
		if p != null:
			p.visible = false
	_gfx.text("jobTitleField", def.get("name", ""))
	_gfx.text("finishNowField", "(Click to finish now)")
	_gfx.text("collectText/fld", "Collect!")
	var holder := _gfx.part("icon") as Node2D
	var icon := FlashUi.make("UITaskIcon%d" % job["job_id"])
	if holder != null and icon != null:
		var r := icon.local_bounds()
		var s := ICON_WIDTH / maxf(1.0, r.size.x)
		icon.scale = Vector2(s, s)
		icon.position = -r.position * s
		holder.add_child(icon)
	_setup_progress(COLORS.get(def.get("color", "green"), COLORS["green"]))
	# Centre the callout horizontally on its position, bottom at the position.
	var b := _gfx.local_bounds()
	_gfx.position = Vector2(-b.position.x - b.size.x / 2.0, -b.position.y - b.size.y)
	add_child(_gfx)
	var hit := Control.new()
	hit.position = _gfx.position + b.position
	hit.size = b.size
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			hit.accept_event())
	add_child(hit)
	refresh(Backend.now())


## The bar is revealed left to right by a mask, tinted in the job colour.
func _setup_progress(color: Color) -> void:
	var bar := _gfx.part("progress") as Node2D
	if bar == null:
		return
	var tint := (bar as FlashSymbol).part("progressColor") as CanvasItem if bar is FlashSymbol else null
	if tint != null:
		tint.modulate = color
	var r := (bar as FlashSymbol).local_bounds() if bar is FlashSymbol else Rect2(0, 0, 100, 10)
	_progress_size = r.size
	_clip = Polygon2D.new()
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip.position = bar.position + r.position
	var parent := bar.get_parent()
	var index := bar.get_index()
	parent.remove_child(bar)
	bar.position = -r.position
	_clip.add_child(bar)
	parent.add_child(_clip)
	parent.move_child(_clip, index)


func refresh(now: int) -> void:
	if _gfx == null:
		return
	var total: int = maxi(1, job["ends_at"] - job["started_at"])
	var left: int = job["ends_at"] - now
	var frac := clampf(1.0 - float(left) / total, 0.0, 1.0)
	if _clip != null:
		var w := _progress_size.x * frac
		_clip.polygon = PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, _progress_size.y + 1), Vector2(0, _progress_size.y + 1)])
	if left <= 0:
		if not _done:
			_done = true
			_gfx.text("timeLeftField", "")
			var ft := _gfx.part("finishNowField") as CanvasItem
			if ft != null:
				ft.visible = false
			var ct := _gfx.part("collectText") as CanvasItem
			if ct != null:
				ct.visible = true
		return
	_gfx.text("timeLeftField", _time_left(left))


## "{time;format:abbr;maxunit:hour;minunit:min} left", or seconds under a minute.
static func _time_left(seconds: int) -> String:
	if seconds < 60:
		return "%dsec left" % seconds
	var h := seconds / 3600
	var m := (seconds % 3600 + 59) / 60
	if m == 60:
		h += 1
		m = 0
	if h > 0:
		return ("%dhr %dmin left" % [h, m]) if m > 0 else ("%dhr left" % h)
	return "%dmin left" % m
