class_name TaskTile
extends Node2D
## The original task tile (AbstractTaskSprite / CarTaskSprite on
## UITaskSpriteGfxNew): the job's icon and title, "Done in", XP and coins it
## pays, what it costs, and a Start button, or, while the car is out on it,
## a progress bar and a Stop button.

signal start_pressed
signal stop_pressed

## WorkerTask button colours -> TextButton kinds.
const KINDS := {
	"green": FlashTextButton.Kind.GREEN, "red": FlashTextButton.Kind.RED, "blue": FlashTextButton.Kind.BLUE,
	"yellow": FlashTextButton.Kind.YELLOW, "gray": FlashTextButton.Kind.GRAY,
}
const HIDDEN := ["gigawattsLabel", "creditsSprite", "roadTripGainsSprite", "additionalCostText",
	"freeField", "fldUnlocksAt", "fldUnlocksLevel", "fldClickToCancel", "masteryLevels"]
const GAIN_FIELDS := ["moneyGainsSprite", "xpGainsField", "cashSprite", "costHead", "doneinField"]

var job_id: int
var _gfx: FlashSymbol
var _progress: FlashProgress
var _job_state: Dictionary = {}
var _button: FlashTextButton


## [param job_state] is the running task on this car ({} if none).
static func create(id: int, job_state: Dictionary = {}, disabled: bool = false) -> TaskTile:
	var t := TaskTile.new()
	t.job_id = id
	t._job_state = job_state
	t._build(disabled)
	return t


## setAsLocked: the gains make way for "Unlocks at Level N" and a padlock.
func set_locked(min_level: int) -> void:
	if _gfx == null:
		return
	for part: String in GAIN_FIELDS + ["freeField", "roadTripGainsSprite", "fldClickToCancel"]:
		var p := _gfx.part(part) as CanvasItem
		if p != null:
			p.visible = false
	_gfx.styled_text("fldUnlocksAt", "Unlocks at", "sansA02")
	_gfx.styled_text("fldUnlocksLevel", "Level %d" % min_level, "sansA02")
	for part: String in ["fldUnlocksAt", "fldUnlocksLevel"]:
		var p := _gfx.part(part) as CanvasItem
		if p != null:
			p.visible = true
	var lock := FlashUi.make("UIIconLock")
	if lock != null:
		lock.position = Vector2(59, 131)
		_gfx.add_child(lock)
	if _button != null:
		_button.visible = false


func _build(disabled: bool) -> void:
	var def: Dictionary = GameData.catalog.job(job_id)
	var payout: Dictionary = Backend.query().job_payout(job_id)
	_gfx = FlashUi.make("UITaskSpriteGfxNew")
	if _gfx == null:
		return
	add_child(_gfx)
	for part: String in HIDDEN:
		var p := _gfx.part(part) as CanvasItem
		if p != null:
			p.visible = false
	var icon := FlashUi.make("UITaskIcon%d" % job_id)
	var holder := _gfx.part("icon") as Node2D
	if icon != null and holder != null:
		holder.add_child(icon)
	_gfx.styled_text("titleField", def.get("name", ""), "sansD04")
	_gfx.styled_text("doneinField", "Done in: %s" % Format.minutes(def.get("minutes", 0)).replace(" ", ""), "sansA01")
	_gfx.styled_text("xpGainsField", "XP: %d" % payout["xp"], "sansA03")
	_gfx.styled_text("moneyGainsSprite/moneyGainsField", Format.number(payout["coins"]), "sansA03")
	_gfx.styled_text("costHead", "Cost:", "sansA01")
	_gfx.styled_text("cashSprite/moneyField", Format.number(def.get("price", 0)), "sansA03")
	# The white amount's glow is on its parent clip, which we don't draw.
	_gfx.outline("cashSprite/moneyField", StoreTile.PRICE_GLOW, 4)
	var gains := _gfx.part("moneyGainsSprite") as FlashSymbol
	var size := _gfx.local_bounds().end
	if gains != null:
		gains.position.x = (size.x - gains.local_bounds().size.x) / 2.0 + 5

	var running := not _job_state.is_empty()
	var label: String = def.get("button_label", "")
	var button := FlashTextButton.create("Stop" if running else (label if label != "" else "Start"),
		FlashTextButton.Kind.RED if running else KINDS.get(def.get("color", "red"), FlashTextButton.Kind.RED),
		62, 35, 18, true)
	button.position = Vector2(int((size.x - button.size().x) / 2.0), size.y - button.size().y / 2.0 - 45)
	button.pressed.connect(func() -> void: (stop_pressed if running else start_pressed).emit())
	add_child(button)
	_button = button
	if running:
		# toggleTextFields(false): the gains make way for the progress bar.
		for part: String in GAIN_FIELDS + ["lineSprite"]:
			var p := _gfx.part(part) as CanvasItem
			if p != null:
				p.visible = false
		var bar := FlashUi.make("UIStatusProgressWithTimeGfx")
		if bar != null:
			bar.position = Vector2(23, 135)
			add_child(bar)
			_progress = FlashProgress.attach(bar, JobStatus.COLORS.get(def.get("color", "green"), JobStatus.COLORS["green"]))
			_progress.show_job(_job_state, Backend.now())
	elif def.get("price", 0) > Backend.state()["player"]["coins"]:
		button.modulate = Color(0.7, 0.7, 0.7) # setAsNoMoney
	if disabled:
		modulate = Color(0.6, 0.6, 0.6) # setAsDisabled (desaturated)
		button.set_disabled(true)


func _process(_delta: float) -> void:
	if _progress != null:
		_progress.show_job(_job_state, Backend.now())
