class_name ShiftControl
extends Node2D
## The race's shift mini-game (views/racing/shiftcontrol/AbstractShiftControl):
## a drag-race light tree over the gauge. Press Start, wait for the lights,
## click on green to launch, then click three times as the needle nears the
## redline. Scoring is in [RaceRules]; this is the timing and the display.

## Every scored event: the launch and each shift.
signal scored(points: int, type: String, perfect: bool)
signal lights_started
## Launch clicked.
signal launched
## A shift after the launch (the opponent shifts along with you).
signal shifted
signal fouled
## 1350 ms after the last shift.
signal finished

const LIGHT_STEP := 50.0
const LIGHT_SIZE := Vector2(99, 46)
const LAMP_RADIUS := 23.0
const GAUGE_GAP := 20.0
enum State { IDLE, COUNTDOWN, LIGHTS, RUNNING, DONE }
const RECHARGE_MS := 200
const RECHARGE_FROM := 247.0
const END_DELAY := 1.35
const POINTS_GLOW := Color8(0x23, 0x4F, 0x70)
const RED := Color(1, 0.3, 0.3)

var power := 100
var state := State.IDLE
var gauge: ShiftGauge
var _lights: Array[Sprite2D] = []
var _dimmers: Array[Node2D] = []
var _points_label: Label
var _stamp := 0
var _light_stamp := 0
var _gear := 0
var _run := 0
var _points_run := 0


func _ready() -> void:
	var lights_holder := Node2D.new()
	lights_holder.position.x = (ShiftGauge.DIAMETER - LIGHT_SIZE.x) / 2.0
	add_child(lights_holder)
	for i in 4:
		var s := Sprite2D.new()
		s.texture = GameData.main_texture("swcassets.race.LightsGreenBmd" if i == 3 else "swcassets.race.LightsYellowBmd")
		s.position = LIGHT_SIZE / 2.0 + Vector2(0, LIGHT_STEP * i)
		lights_holder.add_child(s)
		_lights.append(s)
		var dim := LightDimmer.new()
		dim.position = Vector2(0, LIGHT_STEP * i)
		lights_holder.add_child(dim)
		_dimmers.append(dim)
	var tree_height := LIGHT_STEP * 3 + LIGHT_SIZE.y
	_points_label = FlashUi.styled_label(" ", "casualA01", 36, Color.WHITE, POINTS_GLOW, 6)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.size = Vector2(ShiftGauge.DIAMETER + 80, 50)
	_points_label.position = Vector2(-40, tree_height - 6)
	add_child(_points_label)
	gauge = ShiftGauge.new()
	gauge.position.y = tree_height + GAUGE_GAP
	gauge.pressed.connect(_on_pressed)
	add_child(gauge)


func control_size() -> Vector2:
	return Vector2(ShiftGauge.DIAMETER, LIGHT_STEP * 3 + LIGHT_SIZE.y + GAUGE_GAP + ShiftGauge.DIAMETER)


## Gets ready for a race with a car of [param car_power].
func prepare(car_power: int) -> void:
	power = car_power
	_run += 1
	state = State.IDLE
	_gear = 0
	for d in _dimmers:
		d.visible = true
	_points_label.text = " "
	gauge.needle_degrees = 0.0
	gauge.set_text("Start")
	gauge.activate()


func _on_pressed() -> void:
	match state:
		State.IDLE:
			_start_countdown()
		State.LIGHTS:
			_launch()
		State.RUNNING:
			_shift()


func _start_countdown() -> void:
	state = State.COUNTDOWN
	gauge.set_text("")
	var run := _run
	await get_tree().create_timer((1500 + randi() % 1500) / 1000.0).timeout
	if run != _run:
		return
	_light(0)
	lights_started.emit()
	state = State.LIGHTS
	_light_stamp = Time.get_ticks_msec()
	for i in [1, 2, 3]:
		await get_tree().create_timer(0.5).timeout
		if run != _run or state != State.LIGHTS:
			return
		_light(i)
		if i == 3:
			gauge.set_text("Click!")


func _light(i: int) -> void:
	_dimmers[i].visible = false
	Sound.play("LightsGreenSound" if i == 3 else "LightsYellowSound")
	var l := _lights[i]
	l.scale = Vector2(1.3, 1.3)
	create_tween().tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _launch() -> void:
	var now := Time.get_ticks_msec()
	var r := RaceRules.launch(power, now - _light_stamp)
	_run += 1 # stops the light timers
	if r["foul"]:
		state = State.DONE
		gauge.deactivate()
		Sound.play("JobExpiredSound")
		_show_points("FOUL! -%d" % power, true)
		scored.emit(int(r["points"]), r["type"], false)
		fouled.emit()
		return
	_gear = 1
	gauge.set_text("1")
	state = State.RUNNING
	_stamp = now
	_announce(r, r["type"] == RaceRules.SHIFT_BONUS)
	launched.emit()


func _shift() -> void:
	var r := RaceRules.shift(power, gauge.needle_degrees)
	_gear += 1
	_stamp = Time.get_ticks_msec()
	gauge.set_text(str(mini(_gear, 3)))
	_announce(r, r["type"] in [RaceRules.SHIFT_PERFECT, RaceRules.SHIFT_BONUS])
	shifted.emit()
	if _gear >= 4:
		state = State.DONE
		gauge.deactivate()
		gauge.set_text("")
		var run := _run
		await get_tree().create_timer(END_DELAY).timeout
		if run == _run:
			finished.emit()


func _announce(r: Dictionary, perfect: bool) -> void:
	var points: int = r["points"]
	match r["type"]:
		RaceRules.SHIFT_REDLINED: Sound.play("ActionDeniedSound")
		RaceRules.SHIFT_BONUS: Sound.play("SuccessSound1")
		RaceRules.SHIFT_PERFECT: Sound.play("SuccessSound2")
		_: Sound.play("ApprovalSound")
	_show_points("%s%d" % [r["message"], points], points < 0)
	scored.emit(points, r["type"], perfect)


func _show_points(text: String, negative: bool) -> void:
	_points_label.text = text
	_points_label.modulate = RED if negative else Color.WHITE
	_points_run += 1
	var mine := _points_run
	await get_tree().create_timer(1.2).timeout
	if mine == _points_run:
		_points_label.text = " "


func _process(_delta: float) -> void:
	if state != State.RUNNING:
		return
	var elapsed := Time.get_ticks_msec() - _stamp
	if _gear >= 2 and elapsed < RECHARGE_MS:
		# The needle drops back after a shift.
		gauge.needle_degrees = maxf(0.0, (1.0 - elapsed / float(RECHARGE_MS)) * RECHARGE_FROM)
	else:
		gauge.needle_degrees = RaceRules.needle_angle(power, elapsed)
