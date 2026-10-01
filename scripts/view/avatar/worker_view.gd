class_name WorkerView
extends Node2D
## A 3D worker drawn into the isometric garage: the rig renders in its own
## small 3D world through an orthographic camera at the garage's angle (the
## original gave each avatar its own Away3D view), and the picture is placed
## with its feet at this node's origin.

## Pixels of render target; the worker is drawn at half of that.
const VIEW_SIZE := Vector2i(256, 320)
const DRAW_SCALE := 0.5
## Model units shown across the viewport's height.
const CAMERA_SIZE := 300.0
## Where the feet sit in the picture, from its top-left.
const FEET := Vector2(128, 290)

var rig: AvatarRig
var _vp: SubViewport
var _facing := 0.0


static func create(look: Dictionary) -> WorkerView:
	var w := WorkerView.new()
	w._build(look)
	return w


func _build(look: Dictionary) -> void:
	_vp = SubViewport.new()
	_vp.size = VIEW_SIZE
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	rig = AvatarRig.new()
	_vp.add_child(rig)
	rig.setup(look)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAMERA_SIZE
	cam.near = 1.0
	cam.far = 4000.0
	_vp.add_child(cam)
	# The garage's 2:1 isometric view: 30 degrees down, 45 degrees around.
	var look_at := Vector3(0, CAMERA_SIZE * (FEET.y / VIEW_SIZE.y - 0.5), 0)
	cam.look_at_from_position(look_at + Vector3(1, tan(deg_to_rad(30.0)) * sqrt(2.0), 1).normalized() * 1000.0, look_at)
	var sprite := Sprite2D.new()
	sprite.texture = _vp.get_texture()
	sprite.centered = false
	sprite.scale = Vector2(DRAW_SCALE, DRAW_SCALE)
	sprite.position = -FEET * DRAW_SCALE
	add_child(sprite)


## Turns the worker to face a screen direction (degrees around the vertical).
func face(degrees: float) -> void:
	_facing = degrees
	if rig != null:
		rig.rotation_degrees.y = degrees


func play(anim: String) -> void:
	if rig != null:
		rig.play(anim)
