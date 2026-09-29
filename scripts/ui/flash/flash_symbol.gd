class_name FlashSymbol
extends Node2D
## One instance of an original library symbol (see FlashUi). Static art is
## drawn from pre-rendered layers; parts the original code addressed by name
## (text fields, needles, bars, nested clips) are real child nodes, named like
## the original instances so they can be found with part().

var char_id: String = ""
var frame: int = 0
var frame_count: int = 1
var labels: Dictionary = {}
## Named parts: instance name -> node (FlashSymbol or FlashText).
var parts: Dictionary[String, Node] = {}


func setup(id: String, start_frame: int = 0) -> void:
	char_id = id
	var info := FlashUi.char_info(id)
	frame_count = maxi(1, info.get("frames", []).size())
	labels = info.get("labels", {})
	goto(start_frame)


## Shows a frame (0-based index or a frame label), like gotoAndStop.
func goto(target: Variant) -> void:
	var f: int = labels.get(target, 0) if typeof(target) == TYPE_STRING else int(target)
	frame = clampi(f, 0, frame_count - 1)
	_build()


## Plays the timeline in a loop, like a MovieClip left to play. The SWF asks
## for 140 fps, but browsers ran Flash at about 60.
## With [param loop] false it stops on the last frame (a timeline ending in stop()).
func play(fps: float = 60.0, loop: bool = true) -> void:
	_fps = fps
	_loop = loop
	_elapsed = 0.0
	_playing = frame_count > 1
	set_process(_playing)


func stop() -> void:
	_playing = false
	set_process(false)


var _fps := 60.0
var _elapsed := 0.0
var _playing := false
var _loop := true


func _ready() -> void:
	# Godot turns processing on for any script with _process; only play()
	# should.
	set_process(_playing)


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	var step := 1.0 / _fps
	if _elapsed < step:
		return
	var n := int(_elapsed / step)
	_elapsed -= n * step
	if not _loop and frame + n >= frame_count - 1:
		goto(frame_count - 1)
		stop()
		return
	goto((frame + n) % frame_count)


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	parts.clear()
	var info := FlashUi.char_info(char_id)
	var frames: Array = info.get("frames", [])
	if frames.is_empty():
		return
	for layer: Dictionary in frames[frame]:
		if layer.has("layer"):
			var tex := FlashUi.layer_texture(layer["layer"])
			if tex.is_empty():
				continue
			var s := Sprite2D.new()
			s.texture = tex["texture"]
			s.centered = false
			s.offset = -tex["o"]
			add_child(s)
			continue
		var child_info := FlashUi.char_info(layer["char"])
		var node: Node2D
		match child_info.get("type", ""):
			"sprite":
				var fs := FlashSymbol.new()
				fs.setup(layer["char"])
				node = fs
			"text":
				var ft := FlashText.new()
				ft.setup(child_info)
				if layer.has("f"):
					ft.apply_filters(layer["f"])
				node = ft
			_:
				continue
		var m: Array = layer["m"]
		node.transform = Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))
		var ct: Variant = layer.get("ct")
		if typeof(ct) == TYPE_ARRAY:
			node.modulate = Color(ct[0], ct[1], ct[2], ct[3])
		var inst: String = layer.get("name", "")
		if inst != "":
			node.name = inst
			parts[inst] = node
		add_child(node)
	for path: String in _mods:
		_apply_mod(path)


## A named part, e.g. part("needle") or part("moneyGainsSprite/moneyGainsField").
func part(path: String) -> Node:
	var node: Node = self
	for piece: String in path.split("/"):
		if node is FlashSymbol and (node as FlashSymbol).parts.has(piece):
			node = (node as FlashSymbol).parts[piece]
		else:
			return null
	return node


## Sets the text of a named text field (returns false if there isn't one).
func text(path: String, value: String) -> bool:
	_mod(path)["text"] = value
	return _apply_mod(path)


## Sets a text field's text and swaps in a text style's font, like the
## original setTextFieldText(field, value, style) / cascadeTextStyleOnTextField.
func styled_text(path: String, value: String, style: String, font_size: int = 0) -> bool:
	var m := _mod(path)
	m["text"] = value
	m["style"] = [style, font_size]
	return _apply_mod(path)


## Gives a text field an outline (the original's GlowFilters).
func outline(path: String, color: Color, px: int) -> bool:
	_mod(path)["outline"] = [color, px]
	return _apply_mod(path)


## Text changes are remembered so they survive frame changes (a playing
## timeline rebuilds its parts every frame).
var _mods: Dictionary[String, Dictionary] = {}


func _mod(path: String) -> Dictionary:
	if not _mods.has(path):
		_mods[path] = {}
	return _mods[path]


func _apply_mod(path: String) -> bool:
	var t := part(path) as FlashText
	if t == null:
		return false
	var m: Dictionary = _mods[path]
	if m.has("style"):
		t.set_style(m["style"][0], m["style"][1])
	if m.has("outline"):
		t.set_outline(m["outline"][0], m["outline"][1])
	if m.has("text"):
		t.set_text(m["text"])
	return true


## Bounding box of the drawn art in local coordinates (approximate).
func local_bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for c in get_children():
		var cr := Rect2()
		if c is Sprite2D and (c as Sprite2D).texture != null:
			cr = Rect2((c as Sprite2D).offset, (c as Sprite2D).texture.get_size())
		elif c is FlashSymbol:
			cr = (c as FlashSymbol).transform * (c as FlashSymbol).local_bounds()
		elif c is FlashText:
			# Flash counts a text field's whole box, not just its glyphs.
			cr = (c as FlashText).transform * (c as FlashText).box()
		else:
			continue
		r = cr if first else r.merge(cr)
		first = false
	return r
