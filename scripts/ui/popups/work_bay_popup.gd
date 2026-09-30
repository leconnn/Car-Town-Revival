class_name WorkBayPopup
extends Node2D
## The original work bay menu (views/items/WorkBayOptions), shown when you
## click an empty lift: the Service Menu sign on the masthead and a scroller
## of every work bay job in sort order, locked ones showing the level they
## open at. 720 x 399.

signal start_task(job_id: int)

const POPUP_SIZE := Vector2(720, 399)

var bay_uid: int


static func create(uid: int) -> WorkBayPopup:
	var p := WorkBayPopup.new()
	p.bay_uid = uid
	p._build()
	return p


func _build() -> void:
	var container := Node2D.new()
	container.position.x = 25
	add_child(container)
	var masthead := FlashUi.make("CarOptionsMasthead")
	if masthead != null:
		masthead.position = Vector2(25, 21)
		container.add_child(masthead)
	var head: Dictionary = GameData.static_ui_art.get("serviceMenuIcon", {})
	var tex := GameData.texture(head.get("file", ""))
	if tex != null:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		var o: Array = head.get("o", [0, 0])
		s.offset = -Vector2(o[0], o[1])
		s.scale = Vector2(0.7, 0.7)
		s.position = Vector2(344, -35)
		container.add_child(s)

	var bg := FlashNine.make("UIWhiteStrokedRoundedBg", Vector2(664, 247))
	bg.position = Vector2(3, 128)
	container.add_child(bg)

	var ids := _job_ids()
	var level: int = Backend.state()["player"]["level"]
	var scroller := ItemScroller.create(588, 331, 147)
	scroller.position = Vector2(43, 33)
	scroller.position_arrows(25, 199)
	container.add_child(scroller)
	scroller.set_items(ids.size(), func(i: int) -> Node2D:
		var id: int = ids[i]
		var tile := TaskTile.create(id)
		tile.position.y = 52
		var min_level: int = GameData.catalog.job(id).get("min_level", 0)
		if min_level > level:
			tile.set_locked(min_level)
		tile.start_pressed.connect(func() -> void: start_task.emit(id))
		return tile)


## Work bay jobs in the catalog's sort order (WorkBayOptions.compareSortOrder).
static func _job_ids() -> Array[int]:
	# This client has no icon for a few late jobs (46, 50, 55), so it could
	# never have shown them: AbstractTaskSprite looks up "UITaskIcon<id>".
	var ids := Backend.query().available_job_ids().filter(func(id: int) -> bool:
		return FlashUi.has_class("UITaskIcon%d" % id))
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ja: Dictionary = GameData.catalog.job(a)
		var jb: Dictionary = GameData.catalog.job(b)
		var sa: int = ja.get("sort", 0)
		var sb: int = jb.get("sort", 0)
		return sa < sb if sa != sb else a < b)
	return ids
