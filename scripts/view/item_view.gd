class_name ItemView
extends Sprite2D
## A garage item drawn from its exported frames (one frame per rotation).

var item_id: int = 0
var rot: int = 0


func setup(id: int, rotation_index: int) -> void:
	item_id = id
	rot = rotation_index
	centered = false
	var frames: Array = GameData.item_art.get(str(id), {}).get("frames", [])
	if frames.is_empty():
		texture = null
		return
	var info: Dictionary = frames[posmod(rot, frames.size())]
	texture = GameData.texture(info["file"])
	offset = -Vector2(info["o"][0], info["o"][1])


func has_art() -> bool:
	return texture != null


## True if the item's visible pixels cover [param global_point].
func hit(global_point: Vector2) -> bool:
	if texture == null:
		return false
	var local := to_local(global_point) - offset
	if not Rect2(Vector2.ZERO, texture.get_size()).has_point(local):
		return false
	return is_pixel_opaque(to_local(global_point))
