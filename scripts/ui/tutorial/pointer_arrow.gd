class_name PointerArrow
extends Node2D
## The original TutorialPointerArrow: the big PointerArrow pointing at
## something, bouncing back 30 px (0.5 s ease-out) and dropping onto it again
## with a bounce (1 s), forever. DOWN is the symbol's own direction.

enum Dir { DOWN, UP, LEFT, RIGHT }

var _container: FlashSymbol
var _arrow: Node2D
var _origin_y := 0.0
var _tween: Tween


static func create(dir: Dir) -> PointerArrow:
	var p := PointerArrow.new()
	p._container = FlashUi.make("PointerArrow")
	if p._container != null:
		p.add_child(p._container)
		p._arrow = p._container.part("arrow") as Node2D
		if p._arrow != null:
			p._origin_y = p._arrow.position.y
	p.set_direction(dir)
	return p


func set_direction(dir: Dir) -> void:
	if _container != null:
		_container.rotation_degrees = [0.0, 180.0, 90.0, -90.0][dir]
	_animate()


func _animate() -> void:
	if _arrow == null:
		return
	if _tween != null:
		_tween.kill()
	_arrow.position.y = _origin_y
	_tween = create_tween().set_loops()
	_tween.tween_property(_arrow, "position:y", _origin_y - 30, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_arrow, "position:y", _origin_y, 1.0).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
