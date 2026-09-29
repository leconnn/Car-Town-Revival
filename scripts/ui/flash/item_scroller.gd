class_name ItemScroller
extends Node2D
## The original AbstractItemScroller: a masked row of items a fixed spacing
## apart, paged with arrow buttons on either side (BtnScrollArrowLeft) and a
## row of radio dots underneath (ScrollerPaging with UIRadioButton). Pages
## slide over in 0.5 s. Items are built lazily: [member make_item] is called
## for an index when its page first comes into view.

signal page_changed

const SLIDE_TIME := 0.5
const DOT_SPACING := 24.0
const DOTS_MAX_WIDTH := 684.0

## func(index: int) -> Node2D
var make_item: Callable
var count := 0
var view_size: Vector2
var spacing: float
var per_page: int
var first_index := 0

var _clip: Control
var _row: Node2D
var _built: Dictionary[int, Node2D] = {}
var _left: FlashButton
var _right: FlashButton
var _dots: Node2D
var _tween: Tween


static func create(w: float, h: float, item_spacing: float) -> ItemScroller:
	var s := ItemScroller.new()
	s.view_size = Vector2(w, h)
	s.spacing = item_spacing
	s.per_page = maxi(1, floori(w / item_spacing))
	s._build()
	return s


func _build() -> void:
	_clip = Control.new()
	_clip.size = view_size
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_row = Node2D.new()
	_clip.add_child(_row)
	_left = FlashButton.of("BtnScrollArrowLeft")
	_right = FlashButton.of("BtnScrollArrowLeft")
	if _right != null:
		_right.body.rotation_degrees = 180
		_right._hit.position = -_right._hit.position - _right._hit.size
	for arrow: FlashButton in [_left, _right]:
		if arrow != null:
			arrow.visible = false
			add_child(arrow)
	if _left != null:
		_left.pressed.connect(func() -> void: page_to(maxi(0, first_index - per_page)))
	if _right != null:
		_right.pressed.connect(func() -> void: page_to(first_index + per_page))
	_dots = Node2D.new()
	_dots.position = Vector2(roundf(view_size.x / 2.0), view_size.y)
	add_child(_dots)
	position_arrows(0, 0)


## Arrows [param out] px outside the view, at height [param y].
func position_arrows(out: float, y: float) -> void:
	if _left != null:
		_left.position = Vector2(-out, y)
	if _right != null:
		_right.position = Vector2(view_size.x + out, y)


## Replaces the items; [param maker] builds item i on demand.
func set_items(n: int, maker: Callable) -> void:
	count = n
	make_item = maker
	for c in _row.get_children():
		c.queue_free()
	_built.clear()
	first_index = 0
	if _tween != null:
		_tween.kill()
	_row.position.x = 0
	_rebuild_dots()
	_ensure_page()
	_refresh_arrows()


func page_to(index: int) -> void:
	first_index = clampi(index, 0, maxi(0, count - 1))
	_ensure_page()
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_row, "position:x", -first_index * spacing, SLIDE_TIME)
	_set_dot(first_index / per_page)
	_refresh_arrows()
	page_changed.emit()


func item(index: int) -> Node2D:
	return _built.get(index, null)


func _ensure_page() -> void:
	# The page in view plus its neighbours, so a slide never shows gaps.
	var from := maxi(0, first_index - per_page)
	var to := mini(count, first_index + per_page * 2)
	for i in range(from, to):
		if _built.has(i):
			continue
		var node: Node2D = make_item.call(i)
		if node == null:
			continue
		node.position.x = i * spacing
		_row.add_child(node)
		_built[i] = node


func _refresh_arrows() -> void:
	if _left != null:
		_left.visible = first_index != 0
	if _right != null:
		_right.visible = count - per_page > first_index


func _rebuild_dots() -> void:
	for c in _dots.get_children():
		c.queue_free()
	var pages := ceili(float(count) / per_page)
	_dots.visible = pages > 1
	var step := minf(DOT_SPACING, roundf(DOTS_MAX_WIDTH / maxi(1, pages)))
	var x0 := -roundf((pages - 1) * step / 2.0)
	for p in pages:
		var dot := FlashUi.make("UIRadioButton")
		if dot == null:
			return
		dot.goto("on" if p == 0 else "off")
		var btn := FlashButton.wrap_node(dot)
		btn.set_base_scale(1.0, 1.0)
		btn.position.x = x0 + p * step
		btn.pressed.connect(func() -> void: page_to(p * per_page))
		_dots.add_child(btn)


func _set_dot(page: int) -> void:
	var i := 0
	for btn in _dots.get_children():
		if btn is FlashButton and (btn as FlashButton).body is FlashSymbol:
			((btn as FlashButton).body as FlashSymbol).goto("on" if i == page else "off")
		i += 1
