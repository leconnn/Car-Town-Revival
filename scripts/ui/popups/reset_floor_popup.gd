class_name ResetFloorPopup
extends Node2D
## The original "Reset This Floor!" popup (ClearGarageFloorConfirmPopup with
## ClearGaragePopupContent): checkboxes for what goes into storage, and
## Close / Reset on the frame.

signal confirmed(cars: bool, items: bool, bays: bool, walls: bool, floors: bool)
signal cancelled

const SIZE := Vector2(632, 498)
const CHECK_X := 275.0
const CHECK_Y := 208.0
const CHECK_STEP := 27.0

var _checks: Array[FlashSymbol] = []


static func create() -> ResetFloorPopup:
	var p := ResetFloorPopup.new()
	p._build()
	return p


## Close (grey) and Reset (green) for the frame's bottom edge.
func frame_buttons() -> Array:
	var close := FrameButton.with_text("     Close     ", FrameButton.GREY)
	close.pressed.connect(func() -> void: cancelled.emit())
	var reset := FrameButton.with_text("     Reset     ", FrameButton.GREEN)
	reset.pressed.connect(func() -> void:
		confirmed.emit(_checked(2), _checked(0), _checked(1), _checked(3), _checked(4)))
	return [close, reset]


func _build() -> void:
	var content := FlashUi.make("ClearGaragePopupContent")
	if content == null:
		return
	add_child(content)
	content.styled_text("titleField", "Reset This Floor!", "casualA01")
	content.styled_text("messageField", "What would you like to put into storage from this floor?", "casualA01")
	content.styled_text("message2Field", "All of these will be placed into your storage. Anything that's busy with a job stays where it is.", "casualA01")
	content.styled_text("garageItemsFld", "Garage Items", "sansD01")
	content.styled_text("workbayFld", "Workbays", "sansD01")
	content.styled_text("carsFld", "Cars", "sansD01")
	content.styled_text("wallsFld", "Walls", "sansD01")
	content.styled_text("floorTilesFld", "Floor Tiles", "sansD01")
	# Garage items, workbays, cars, walls, floor tiles, top to bottom.
	for i in 5:
		var box := FlashUi.make("UICarCityCheckBox")
		if box == null:
			continue
		_set_check(box, false)
		var btn := FlashButton.wrap_node(box)
		btn.set_base_scale(1.0, 1.0)
		btn.position = Vector2(CHECK_X, CHECK_Y + CHECK_STEP * i)
		btn.pressed.connect(func() -> void: _set_check(box, not box.get_meta("checked", false)))
		add_child(btn)
		_checks.append(box)


static func _set_check(box: FlashSymbol, on: bool) -> void:
	box.set_meta("checked", on)
	var check := box.part("check") as CanvasItem
	if check != null:
		check.visible = on


func _checked(i: int) -> bool:
	return i < _checks.size() and _checks[i].get_meta("checked", false)
