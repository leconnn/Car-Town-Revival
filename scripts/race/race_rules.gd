class_name RaceRules
extends RefCounted
## The shift mini-game's scoring (views/racing/AbstractRaceRules), kept free
## of UI so it can be tested. [param power] is the car's performance.
## Angles are the needle's rotation in degrees; the redline starts at 244.

const REDLINE := 244.0
const BONUS_STARTS := REDLINE - 3.0
const BONUS_ENDS := REDLINE + 3.0
## The needle stops short of a full turn: 95%.
const NEEDLE_MAX := 360.0 * 0.95
const NOS_BONUS := 50
## After the third light: green. Clicking sooner than this is a foul.
const LIGHT_TIME_MS := 1500
## Within this long after the green light the launch counts double.
const BONUS_WINDOW_MS := 50

const SHIFT_PERFECT := "perfect"
const SHIFT_BONUS := "bonus"
const SHIFT_NORMAL := "normal"
const SHIFT_REDLINED := "redlined"


## How long the needle takes to sweep a full turn (setParams).
static func throttle_time_ms(power: int) -> int:
	return 2000 + 2 * maxi(0, 1000 - power)


## The launch: [param ms] since the first light. Returns
## {foul, points, type, message}.
static func launch(power: int, ms: int) -> Dictionary:
	if ms < LIGHT_TIME_MS:
		return {"foul": true, "points": -power, "type": SHIFT_REDLINED, "message": ""}
	var bonus := ms < LIGHT_TIME_MS + BONUS_WINDOW_MS
	var points := power * (2 if bonus else 1) * (1.0 - minf(1.0, (ms - LIGHT_TIME_MS) / 1000.0))
	return {"foul": false, "points": int(points), "type": SHIFT_BONUS if bonus else SHIFT_NORMAL,
		"message": "Bonus! " if bonus else ""}


## A shift at needle [param angle]. Returns {points, type, message, redlined}.
static func shift(power: int, angle: float) -> Dictionary:
	if angle < BONUS_STARTS:
		return {"points": roundi(power * angle / REDLINE), "type": SHIFT_NORMAL, "message": "", "redlined": false}
	if angle > BONUS_ENDS:
		return {"points": -roundi(power * (angle - BONUS_ENDS) / (NEEDLE_MAX - BONUS_ENDS)),
			"type": SHIFT_REDLINED, "message": "", "redlined": true}
	var points := roundi(2.0 * power * (REDLINE - absf(REDLINE - angle)) / REDLINE)
	return {"points": points, "type": SHIFT_PERFECT, "redlined": false,
		"message": "Perfect! " if points == 2 * power else "Bonus! "}


## The needle's angle [param elapsed_ms] after the launch or a shift.
static func needle_angle(power: int, elapsed_ms: int) -> float:
	return minf(0.95, float(elapsed_ms) / throttle_time_ms(power)) * 360.0


## The opponent's score in four pieces, the launch about twice a shift
## (RacingScoreInterpolator.getShuffledShiftScoresWithBigStart); the pieces
## add up to [param total].
static func split_opponent_score(total: int, rng: RandomNumberGenerator) -> Array[int]:
	var parts: Array[float] = [total * 2.0 / 5.0, total / 5.0, total / 5.0, total / 5.0]
	for i in 4:
		var from := rng.randi_range(1, 3)
		var to := rng.randi_range(1, 3)
		var moved := rng.randf() * parts[from]
		parts[from] -= moved
		parts[to] += moved
	var out: Array[int] = []
	var sum := 0
	for i in 3:
		out.append(roundi(parts[i]))
		sum += out[i]
	out.append(total - sum)
	return out
