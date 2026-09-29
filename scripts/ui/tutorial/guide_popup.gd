class_name GuidePopup
extends Node2D
## The original tutorial guide (AvatarGuidancePopup with RoxyPortrait):
## Roxy pops out of a round portrait (the frame grows in with a back-ease,
## then she bounces up into it), talks in a TextBubble to her left, and shows
## an OK button under the bubble when the step waits for one.

signal ok_pressed
signal intro_finished

const NAME := "Roxy"
const BUBBLE_FONT := 25
const BUBBLE_MAX_WIDTH := 250.0
## Where Roxy sits inside the portrait: hidden below (74) or shown (-131).
const AVATAR_HIDDEN_Y := 74.0
const AVATAR_SHOWN_Y := -131.0

var _portrait: FlashSymbol
var _outline: Node2D
var _background: Node2D
var _avatar: Node2D
var _bubble: TalkBubble
var _ok: FlashTextButton
var _tween: Tween
var shown := false


func _ready() -> void:
	_portrait = FlashUi.make("RoxyPortrait")
	if _portrait == null:
		return
	add_child(_portrait)
	_outline = _portrait.part("outline") as Node2D
	_background = _portrait.part("background") as Node2D
	_avatar = _portrait.part("avatar") as Node2D
	_clip_avatar()
	_ok = FlashTextButton.create("OK", FlashTextButton.Kind.GREEN, 65, 40, 22)
	_ok.visible = false
	_ok.pressed.connect(func() -> void:
		_ok.visible = false
		if _bubble != null:
			_bubble.queue_free()
			_bubble = null
		ok_pressed.emit())
	add_child(_ok)
	visible = false


## Roxy is only visible inside the round portrait (the original masked her).
func _clip_avatar() -> void:
	if _background == null or _avatar == null:
		return
	var r := (_background as FlashSymbol).local_bounds() if _background is FlashSymbol else Rect2(-75, -150, 150, 150)
	var mask := Polygon2D.new()
	var pts := PackedVector2Array()
	var c := _background.position + r.get_center()
	var radius := Vector2(r.size.x / 2.0, r.size.y / 2.0)
	# The portrait's lower half, opened straight up so her head can rise
	# above the rim, like the original.
	for i in 25:
		var a := PI * i / 24.0
		pts.append(c + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	pts.append(c + Vector2(-radius.x, -400))
	pts.append(c + Vector2(radius.x, -400))
	mask.polygon = pts
	mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var index := _avatar.get_index()
	_portrait.remove_child(_avatar)
	mask.add_child(_avatar)
	_portrait.add_child(mask)
	_portrait.move_child(mask, index)


## Shows [param text]. With [param intro], plays Roxy's entrance first.
func say(text: String, intro: bool, show_ok: bool) -> void:
	visible = true
	if intro or not shown:
		await _play_intro()
	_show_bubble(text, show_ok)


func _play_intro() -> void:
	shown = true
	if _tween != null:
		_tween.kill()
	if _outline == null:
		return
	_outline.scale = Vector2.ZERO
	_background.scale = Vector2.ZERO
	_avatar.position.y = AVATAR_HIDDEN_Y
	_tween = create_tween().set_parallel()
	_tween.tween_property(_outline, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_background, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_avatar, "position:y", AVATAR_SHOWN_Y, 0.5).set_delay(0.5) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await _tween.finished
	intro_finished.emit()


func _show_bubble(text: String, show_ok: bool) -> void:
	if _bubble != null:
		_bubble.queue_free()
	_bubble = TalkBubble.create(text, BUBBLE_MAX_WIDTH, BUBBLE_FONT)
	_bubble.position = Vector2(-_bubble.content_size.x - 45, -_bubble.content_size.y)
	# Over the portrait (so its tip shows), under the OK button.
	add_child(_bubble)
	move_child(_bubble, _ok.get_index())
	_ok.visible = show_ok
	if show_ok:
		_ok.position = Vector2(_bubble.position.x + _bubble.content_size.x / 2.0 - _ok.size().x / 2.0,
			_bubble.position.y + _bubble.content_size.y - _ok.size().y / 2.0)


## Roxy ducks back down and the portrait shrinks away (playOutro).
func outro() -> void:
	if not shown:
		return
	shown = false
	if _bubble != null:
		_bubble.queue_free()
		_bubble = null
	_ok.visible = false
	if _tween != null:
		_tween.kill()
	if _outline == null:
		visible = false
		return
	_tween = create_tween()
	_tween.tween_property(_avatar, "position:y", AVATAR_HIDDEN_Y, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.set_parallel()
	_tween.chain().tween_property(_outline, "scale", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_background, "scale", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _tween.finished
	visible = false


## Glides to [param pos] (TweenDisplayObjectProcess).
func move_to(pos: Vector2, seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", pos, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
