class_name RaceScreen
extends StageUi
## The street race page (views/townracing/racing/TownRacingPage + TownRaceView
## + VersusRaceView): both cars on the road, the shift control in the middle
## and the two scores along the bottom. The opponent's score is known up
## front (the rules picked it); it comes in a piece at the launch and at each
## of your shifts, and the opponent's car pulls ahead or falls behind by half
## the difference in points.

## The race is over: what you scored and how, ready for Backend.finish_race.
signal race_over(score: int, perfect_shifts: int, redlined: bool)

const BACKGROUND := Color8(0xAB, 0x9F, 0x87)
const MY_CAR_START := Vector2(135, 120)
const OPPONENT_START := Vector2(377, 0)
## The second lane sits this far from the first (VersusRaceView).
const CAR_SEPARATION := Vector2(242, -120)
## Points of lead to pixels of gap (Conversion(0,0,100,50)).
const POINTS_TO_PIXELS := 0.5
## Isometric slope of a car's drift: down the road.
const SLOPE := 0.5
const CAR_SCALE := 0.8
## Cars are placed by their centre; the original placed them by their feet.
const CAR_DROP := 90.0
const PANEL_Y := 572.0
const TEXT_COLOR := Color8(0x33, 0x4D, 0x66)
const SHIFT_X := 380.0
const SHIFT_Y := 190.0
const FRAME_GLOW := Color8(0x23, 0x4F, 0x70)

var location_id := 0
var my_car: Dictionary = {}
var opponent: Dictionary = {}
var opponent_score := 0
var score := 0
var perfect_shifts := 0
var redlined := false
var _shown_opponent := 0
var _opponent_parts: Array[int] = []
var _opponent_shifts := 0
var _world: Node2D
var _road: RaceRoad
var _my_view: CarView
var _opponent_view: CarView
var _shift: ShiftControl
var _my_score_label: Label
var _opponent_score_label: Label
var _speed := 0.0
var _over := false


static func create(loc_id: int, car: Dictionary, opp: Dictionary, opp_score: int) -> RaceScreen:
	var r := RaceScreen.new()
	r.location_id = loc_id
	r.my_car = car
	r.opponent = opp
	r.opponent_score = opp_score
	return r


func _ready() -> void:
	super()
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	move_child(bg, 0)
	var fit := func() -> void: bg.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(fit)
	fit.call()

	_world = Node2D.new()
	center.add_child(_world)
	_road = RaceRoad.new()
	_road.center = (MY_CAR_START + OPPONENT_START) / 2.0 + Vector2(0, CAR_DROP)
	_world.add_child(_road)
	_my_view = _car_view(my_car)
	_my_view.position = MY_CAR_START + Vector2(0, CAR_DROP)
	_opponent_view = _car_view(CarView.stock_entry(opponent["car_id"], opponent["color_id"]))
	_world.add_child(_opponent_view)
	_world.add_child(_my_view)
	_opponent_view.position = OPPONENT_START + Vector2(0, CAR_DROP)

	_shift = ShiftControl.new()
	_shift.position = Vector2(SHIFT_X - ShiftGauge.DIAMETER / 2.0, SHIFT_Y)
	center.add_child(_shift)
	_shift.prepare(Backend.query().car_score(my_car["uid"]))
	_shift.lights_started.connect(_on_lights)
	_shift.scored.connect(_on_scored)
	_shift.shifted.connect(_opponent_shift)
	_shift.fouled.connect(_on_foul)
	_shift.finished.connect(_end_race)
	_opponent_parts = RaceRules.split_opponent_score(opponent_score, RandomNumberGenerator.new())
	_build_panel()


func _car_view(entry: Dictionary) -> CarView:
	var view := CarView.new()
	# Facing down the road: the front view, not mirrored.
	view.setup(entry, CarView.VIEW_FRONT, false)
	view.scale = Vector2(CAR_SCALE, CAR_SCALE)
	return view


func _build_panel() -> void:
	var panel := FlashNine.make("UIWhiteStrokedRoundedBg", Vector2(700, 100))
	panel.position = Vector2(30, PANEL_Y)
	center.add_child(panel)
	var mine: String = Backend.state()["player"]["name"]
	_add_side(mine, Vector2(60, PANEL_Y + 12), true)
	_add_side(str(opponent["name"]), Vector2(730 - 260, PANEL_Y + 12), false)
	var power := FlashUi.styled_label("%s vs %s" % [
		GameData.car_name(my_car["car_id"]), GameData.car_name(opponent["car_id"])], "sansD01", 14, TEXT_COLOR)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power.size = Vector2(700, 20)
	power.position = Vector2(30, PANEL_Y + 76)
	center.add_child(power)


func _add_side(who: String, pos: Vector2, mine: bool) -> void:
	var name_label := FlashUi.styled_label(who, "casualA01", 24, TEXT_COLOR)
	name_label.position = pos
	center.add_child(name_label)
	var caption := FlashUi.styled_label("score:", "sansD01", 14, TEXT_COLOR)
	caption.position = pos + Vector2(0, 38)
	center.add_child(caption)
	var value := FlashUi.styled_label("0", "casualA01", 40, Color.WHITE, FRAME_GLOW, 4)
	value.position = pos + Vector2(70, 22)
	center.add_child(value)
	if mine:
		_my_score_label = value
	else:
		_opponent_score_label = value


func _on_lights() -> void:
	# The opponent launches 1.5 s or so after the first light.
	get_tree().create_timer(1.5 + randf() * 0.2).timeout.connect(_opponent_shift)


func _opponent_shift() -> void:
	if _over or _opponent_shifts >= _opponent_parts.size():
		return
	_shown_opponent += _opponent_parts[_opponent_shifts]
	_opponent_shifts += 1
	_opponent_score_label.text = str(_shown_opponent)
	_speed = 60.0 * _opponent_shifts + 200.0
	_place_cars(3.0 if _opponent_shifts < 4 else 1.0)


func _on_scored(points: int, type: String, perfect: bool) -> void:
	score += points
	if perfect:
		perfect_shifts += 1
	if type == RaceRules.SHIFT_REDLINED:
		redlined = true
	_my_score_label.text = str(score)
	_place_cars(1.0)


func _place_cars(seconds: float) -> void:
	var gap := (_shown_opponent - score) * POINTS_TO_PIXELS
	var target := OPPONENT_START + Vector2(0, CAR_DROP) + Vector2(gap, gap * SLOPE)
	create_tween().tween_property(_opponent_view, "position", target, seconds)


func _on_foul() -> void:
	_over = true
	await get_tree().create_timer(1.0).timeout
	race_over.emit(score, perfect_shifts, redlined)


func _end_race() -> void:
	if _over:
		return
	_over = true
	race_over.emit(score, perfect_shifts, redlined)


func _process(delta: float) -> void:
	# The road slides under the cars, faster as you gain speed.
	if _road != null and _speed > 0.0 and not _over:
		_road.advance(_speed * delta)


## Testing aid: plays a whole race by itself (start, launch on green, three
## shifts near the redline).
func autoplay() -> void:
	await get_tree().create_timer(0.5).timeout
	_shift.gauge.simulate_click()
	await _shift.lights_started
	await get_tree().create_timer(1.55).timeout
	_shift.gauge.simulate_click()
	for i in 3:
		await get_tree().create_timer((RaceRules.REDLINE - 3.0) / 360.0 * RaceRules.throttle_time_ms(_shift.power) / 1000.0).timeout
		_shift.gauge.simulate_click()
