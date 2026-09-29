class_name GameResult
extends RefCounted
## Outcome of one game action.

var ok: bool = true
var error: String = ""
## Action-specific values (new uid, coins earned, ...).
var data: Dictionary = {}
## Things the UI should announce: level-ups, missions completed, mastery.
## Each is a Dictionary with a "kind" key.
var notices: Array[Dictionary] = []


static func fail(message: String) -> GameResult:
	var r := GameResult.new()
	r.ok = false
	r.error = message
	return r


static func success(values: Dictionary = {}) -> GameResult:
	var r := GameResult.new()
	r.data = values
	return r


func to_dict() -> Dictionary:
	return {"ok": ok, "error": error, "data": data, "notices": notices}


static func from_dict(d: Dictionary) -> GameResult:
	var r := GameResult.new()
	r.ok = d.get("ok", false)
	r.error = d.get("error", "")
	r.data = d.get("data", {})
	for n: Dictionary in d.get("notices", []):
		r.notices.append(n)
	return r
