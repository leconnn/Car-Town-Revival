class_name FlashNine
extends RefCounted
## 9-slice panels from original symbols that have a scaling grid (UIBgFrame,
## UITanStrokedRoundedBg, ...), and bounds measuring for built layouts.


## A panel stretched to [param size] like Flash stretched 9-slice sprites.
## Returns a NinePatchRect whose top-left is the symbol's top-left.
static func make(class_name_: String, size: Vector2) -> Control:
	var id := FlashUi.char_id(class_name_)
	var info := FlashUi.char_info(id)
	var frames: Array = info.get("frames", [])
	if frames.is_empty() or frames[0].is_empty() or not frames[0][0].has("layer"):
		return _fallback(size)
	var tex := FlashUi.layer_texture(frames[0][0]["layer"])
	if tex.is_empty():
		return _fallback(size)
	var t: Texture2D = tex["texture"]
	var o: Vector2 = tex["o"]
	var n := NinePatchRect.new()
	n.texture = t
	n.size = size
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid: Array = info.get("grid", [])
	if grid.size() == 4:
		n.patch_margin_left = maxi(0, int(grid[0] + o.x))
		n.patch_margin_top = maxi(0, int(grid[1] + o.y))
		n.patch_margin_right = maxi(0, int(t.get_width() - o.x - grid[2]))
		n.patch_margin_bottom = maxi(0, int(t.get_height() - o.y - grid[3]))
	else:
		# No grid: Flash stretched the whole thing.
		n.patch_margin_left = 0
		n.patch_margin_right = 0
		n.patch_margin_top = 0
		n.patch_margin_bottom = 0
	return n


static func _fallback(size: Vector2) -> Control:
	var p := Panel.new()
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Bounds of everything drawn under [param node], in its parent's space.
static func bounds(node: Node) -> Rect2:
	var r := Rect2()
	var first := true
	var xf := Transform2D.IDENTITY
	if node is Node2D:
		xf = (node as Node2D).transform
	elif node is Control:
		xf = Transform2D(0, (node as Control).scale, 0, (node as Control).position)
	var own := Rect2()
	var has_own := false
	if node is Sprite2D and (node as Sprite2D).texture != null:
		var s := node as Sprite2D
		own = Rect2(s.offset - (s.texture.get_size() / 2.0 if s.centered else Vector2.ZERO), s.texture.get_size())
		has_own = true
	elif node is Polygon2D and not (node as Polygon2D).polygon.is_empty():
		var pts := (node as Polygon2D).polygon
		own = Rect2(pts[0], Vector2.ZERO)
		for pt in pts:
			own = own.expand(pt)
		has_own = true
	elif node is Control and (node as Control).visible:
		own = Rect2(Vector2.ZERO, (node as Control).size)
		has_own = own.size != Vector2.ZERO
	if has_own:
		r = xf * own
		first = false
	for c in node.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		var cr := bounds(c)
		if cr.size == Vector2.ZERO:
			continue
		cr = xf * cr
		r = cr if first else r.merge(cr)
		first = false
	return r
