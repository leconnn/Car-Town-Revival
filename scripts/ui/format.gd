class_name Format
extends RefCounted
## Text formatting for the UI.


## 12345 -> "12,345"
static func number(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The original GarageValueHelper: 93,450,000 -> "93M", 5,200 -> "5K".
static func abbreviated(n: int) -> String:
	var s := str(n)
	var cut := s.length() % 3
	if cut == 0:
		cut = 3
	var suffix := ""
	if s.length() >= 13:
		suffix = "T"
	elif s.length() >= 10:
		suffix = "B"
	elif s.length() >= 7:
		suffix = "M"
	elif s.length() >= 4:
		suffix = "K"
	return s.substr(0, cut) + suffix


## Seconds -> "2d 4h", "3h 12m", "4m 05s", "12s".
static func duration(seconds: int) -> String:
	seconds = maxi(0, seconds)
	var d := seconds / 86400
	var h := (seconds % 86400) / 3600
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	if d > 0:
		return "%dd %dh" % [d, h]
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm %02ds" % [m, s]
	return "%ds" % s


## Minutes -> "5 min", "2 hr", "3 days".
static func minutes(mins: int) -> String:
	if mins < 60:
		return "%d min" % mins
	if mins < 1440:
		return "%s hr" % _trim(mins / 60.0)
	return "%s day%s" % [_trim(mins / 1440.0), "" if mins == 1440 else "s"]


static func _trim(f: float) -> String:
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


## Coin / blue coin price text.
static func price(coins: int, blue: int, use_blue: bool) -> String:
	return ("%s blue" % number(blue)) if use_blue else ("%s coins" % number(coins))
