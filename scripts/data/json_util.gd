class_name JsonUtil
extends RefCounted
## JSON helpers. Godot parses every JSON number as a float; game data and
## saves only use whole numbers for counts, ids and money, so we convert
## whole floats back to ints after parsing.


static func ints(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
				return int(f)
			return f
		TYPE_ARRAY:
			var out: Array = []
			for v: Variant in value:
				out.append(ints(v))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = {}
			for k: Variant in value:
				d[k] = ints(value[k])
			return d
	return value


## Parses a JSON file; returns null if missing or invalid (without logging,
## since a damaged save is an expected case).
static func read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return ints(json.data)
