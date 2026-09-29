class_name StageUi
extends Node2D
## Lays out UI built in the original's 760 x 700 stage coordinates on a
## window of any size: everything scales with the window height, the left and
## right groups stick to their edges and the bottom bar stays centred.

const STAGE := Vector2(760, 700)

## Anchored to the top-left corner.
var left: Node2D
## Anchored to the top-right corner (children use original x, 0-760).
var right: Node2D
## Centred horizontally, bottom-aligned (children use original y, 0-700).
var bottom: Node2D
## Centred on screen (popups).
var center: Node2D


func _ready() -> void:
	left = Node2D.new()
	right = Node2D.new()
	bottom = Node2D.new()
	center = Node2D.new()
	for g in [left, right, bottom, center]:
		add_child(g)
	get_viewport().size_changed.connect(_layout)
	_layout()


func stage_scale() -> float:
	return get_viewport().get_visible_rect().size.y / STAGE.y


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var s := stage_scale()
	for g in [left, right, bottom, center]:
		g.scale = Vector2(s, s)
	left.position = Vector2.ZERO
	right.position = Vector2(vp.x - STAGE.x * s, 0)
	bottom.position = Vector2((vp.x - STAGE.x * s) / 2.0, vp.y - STAGE.y * s)
	center.position = Vector2((vp.x - STAGE.x * s) / 2.0, (vp.y - STAGE.y * s) / 2.0)
