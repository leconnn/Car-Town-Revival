class_name JunkyardScreen
extends StageUi
## The Junk Yard (views/carrestoration/CarRestorationJunkyard): junk piles to
## search for the day's free part, junkers waiting to be restored, and two
## mechanics: one for the list of cars to restore, one for Master Mechanic.
## Drag to look around.

signal restore_requested(build_id: int)

const LOCATION_ID := 17
const GROUND := Color8(0x6B, 0x5E, 0x4A)
const WORLD_SCALE := 0.7
## Where the original centred the yard on the stage.
const VIEW_CENTER := Vector2(400, 520)
const NPC_AT := Vector2(800, 1200)
const MM_NPC_AT := Vector2(1664, 1410)
const PILE_GLOW := Color(1.35, 1.35, 1.05)

var _world: Node2D
var _bg: FlashSymbol
var _size := Vector2(3000, 2280)
var _winning_pile := 1
var _dragging := false
var _dragged := 0.0


func _ready() -> void:
	super()
	var ground := ColorRect.new()
	ground.color = GROUND
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	move_child(ground, 0)
	var fit := func() -> void: ground.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(fit)
	fit.call()
	_world = Node2D.new()
	_world.scale = Vector2(WORLD_SCALE, WORLD_SCALE)
	center.add_child(_world)
	# The day's part hides in one of the four piles (picked per visit).
	_winning_pile = randi_range(1, 4)
	_build()
	_world.position = VIEW_CENTER - _size / 2.0 * WORLD_SCALE
	_clamp()


func _build() -> void:
	_bg = FlashUi.make("swcassets.carrestoration.CarRestorationJunkyardBG")
	if _bg == null:
		return
	_world.add_child(_bg)
	var r := _bg.local_bounds()
	_size = r.end
	for i in range(1, 5):
		var glass := _bg.part("lookingglass%d" % i) as CanvasItem
		if glass != null:
			glass.visible = true
		var pile := _bg.part("pile%d" % i) as FlashSymbol
		if pile != null:
			_hotspot(pile, _on_pile.bind(i))
	var builds := Backend.query().junkyard_build_ids()
	for i in range(1, 5):
		var spot := _bg.part("spot%d" % i) as Node2D
		if spot == null or i > builds.size():
			continue
		var b: Dictionary = GameData.catalog.car_builds[builds[i - 1]]
		var view := CarView.new()
		view.setup(CarView.stock_entry(int(b["primer_car_id"]), 0), CarView.VIEW_ANGLE, randi() % 2 == 0)
		spot.add_child(view)
		var hit := FlashButton.wrap_node(Node2D.new(), Rect2(-90, -110, 180, 120))
		hit.set_base_scale(1.0, 1.0)
		hit.pressed.connect(_open_list)
		spot.add_child(hit)
	_add_npc("JunkyardNPC", NPC_AT, "Search junk piles for a chance\nto get free parts for your car build!", _open_list)
	_add_npc("JunkyardNPC-mastermechanic", MM_NPC_AT, "Find out about Master Mechanic cars here!",
		func() -> void: RestorationPopups.open_master_mechanic_info(get_tree()))


func _add_npc(key: String, at: Vector2, says: String, action: Callable) -> void:
	var info: Dictionary = GameData.restoration_art.get(key, {})
	var tex := GameData.texture(info.get("file", ""))
	var holder := Node2D.new()
	holder.position = at
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		var o: Array = info.get("o", [0, 0])
		s.offset = -Vector2(o[0], o[1])
		s.scale = Vector2(1.6, 1.6)
		holder.add_child(s)
	var bubble := TalkBubble.create(says, 260, 18, true, false)
	bubble.position = Vector2(30, -170 - bubble.content_size.y)
	holder.add_child(bubble)
	var button := FlashButton.wrap_node(holder, Rect2(-20, -170 - bubble.content_size.y, 320, 200 + bubble.content_size.y))
	button.set_base_scale(1.0, 1.05)
	button.pressed.connect(action)
	_bg.add_child(button)


## A click area over one of the art's piles, glowing on hover.
func _hotspot(node: FlashSymbol, action: Callable) -> void:
	var r := node.local_bounds()
	var hit := Control.new()
	hit.position = r.position
	hit.size = r.size
	hit.mouse_filter = Control.MOUSE_FILTER_PASS
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.mouse_entered.connect(func() -> void: node.modulate = PILE_GLOW)
	hit.mouse_exited.connect(func() -> void: node.modulate = Color.WHITE)
	hit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _dragged < 8.0:
			action.call())
	node.add_child(hit)


## handlePileClicked: once a day, and only one pile has it.
func _on_pile(pile: int) -> void:
	var r: Dictionary = Backend.state()["restoration"]
	var last := int(r["last_pile_at"])
	var wait := int(GameData.catalog.tune("restoration.pile_hours", 24)) * 3600
	if last >= 0 and Backend.now() - last < wait:
		RestorationPopups.open_pile(get_tree(), "alreadyCollected")
		return
	if pile != _winning_pile:
		RestorationPopups.open_pile(get_tree(), "notFound")
		return
	var got: GameResult = await Backend.collect_junkyard_part()
	if not got.ok:
		RestorationPopups.open_pile(get_tree(), "alreadyCollected")
		return
	RestorationPopups.open_pile(get_tree(), "found", int(got.data["part_id"]))


func _open_list() -> void:
	if _dragged >= 8.0:
		return
	RestorationPopups.open_list(get_tree(), func(build_id: int) -> void: restore_requested.emit(build_id))


# --- Looking around -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Drags that start on a pile or a car still pan the yard.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_dragged = 0.0
	elif event is InputEventMouseMotion and _dragging:
		_world.position += event.relative / stage_scale()
		_dragged += event.relative.length()
		_clamp()


## Keeps the yard covering the stage (and the wider window around it).
func _clamp() -> void:
	var vp := get_viewport().get_visible_rect().size / stage_scale()
	var extra := (vp.x - STAGE.x) / 2.0
	var w := _size * WORLD_SCALE
	_world.position.x = clampf(_world.position.x, STAGE.x + extra - w.x, -extra)
	_world.position.y = clampf(_world.position.y, STAGE.y - w.y, 0.0)
