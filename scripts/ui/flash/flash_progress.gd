class_name FlashProgress
extends RefCounted
## The original ProgressWithTime bars: a symbol with a "progress" clip,
## tinted in the job's colour through its "progressColor" part and revealed
## left to right by a mask, plus a "timeLeftField".

var gfx: FlashSymbol
var _clip: Polygon2D
var _size := Vector2.ZERO


## Sets up [param symbol] (e.g. UIStatusProgressWithTimeGfx) in place.
static func attach(symbol: FlashSymbol, color: Color) -> FlashProgress:
	var p := FlashProgress.new()
	p.gfx = symbol
	p._setup(color)
	return p


func _setup(color: Color) -> void:
	var bar := gfx.part("progress") as FlashSymbol
	if bar == null:
		return
	var tint := bar.part("progressColor") as CanvasItem
	if tint != null:
		tint.modulate = color
	var r := bar.local_bounds()
	_size = r.size
	_clip = Polygon2D.new()
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_clip.position = bar.position + r.position
	var index := bar.get_index()
	gfx.remove_child(bar)
	bar.position = -r.position
	_clip.add_child(bar)
	gfx.add_child(_clip)
	gfx.move_child(_clip, index)


## Shows [param fraction] done (0-1) and [param text] in the time field.
func show(fraction: float, text: String) -> void:
	if _clip != null:
		var w := _size.x * clampf(fraction, 0.0, 1.0)
		_clip.polygon = PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, _size.y + 1), Vector2(0, _size.y + 1)])
	gfx.text("timeLeftField", text)


## The job's progress at [param now] and the original's "3min left" text.
func show_job(job_state: Dictionary, now: int) -> bool:
	var total: int = maxi(1, job_state["ends_at"] - job_state["started_at"])
	var left: int = job_state["ends_at"] - now
	show(1.0 - float(left) / total, JobStatus._time_left(left) if left > 0 else "Job Complete!")
	return left <= 0
