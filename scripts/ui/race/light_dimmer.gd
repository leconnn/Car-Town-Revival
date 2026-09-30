class_name LightDimmer
extends Node2D
## The dark discs over an unlit pair of lamps (Lights: two circles of radius
## 23, at 40% black); hidden when the row's lit.


func _draw() -> void:
	var r := ShiftControl.LAMP_RADIUS
	draw_circle(Vector2(r, r), r, Color(0, 0, 0, 0.4))
	draw_circle(Vector2(r * 3 + 7, r), r, Color(0, 0, 0, 0.4))
