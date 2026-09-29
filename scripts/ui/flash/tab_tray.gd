class_name TabTray
extends Node2D
## The original MainTabbedStack: the blue-grey framed tray along the bottom
## of the Buy Cars, Customize and Edit Garage screens, with icon tabs
## sticking up from its top edge. The selected tab gets the UITabMainBg
## behind its icon (TabMain), the others just show the icon.
## [method create_sub] makes the SubTabbedStack inside it: a white panel with
## smaller tabs (TabSub, UITabSubBg) along its top.

signal tab_selected(index: int)

const TAB_Y := -36.0
const ICON_Y := 30.0

var chrome: Control
var _tabs_x: float
var _spacing: float
var _tabs: Array[Dictionary] = []
var _current := -1
var _tab_y := TAB_Y
var _icon_y := ICON_Y
var _tab_bg := "UITabMainBg"


## [param w] x [param h] frame; tabs from [param tabs_x], [param spacing] apart.
static func create(w: float, h: float, tabs_x: float = 90.0, spacing: float = 76.0, brown: bool = false) -> TabTray:
	var t := TabTray.new()
	t._tabs_x = tabs_x
	t._spacing = spacing
	t.chrome = FlashNine.make("UIBgBrownFrame" if brown else "UIBgFrame", Vector2(w, h))
	t.add_child(t.chrome)
	return t


## The original SubTabbedStack: tabs from x 87, 51 apart, 27 px up.
static func create_sub(w: float, h: float) -> TabTray:
	var t := TabTray.new()
	t._tabs_x = 87
	t._spacing = 51
	t._tab_y = -27
	t._icon_y = 25
	t._tab_bg = "UITabSubBg"
	t.chrome = FlashNine.make("UIWhiteStrokedRoundedBg", Vector2(w, h))
	t.add_child(t.chrome)
	return t


## Adds a tab showing [param icon] (e.g. FlashUi.make("BtnShop2")).
func add_tab(icon: Node2D, brown: bool = false) -> int:
	var tab := Node2D.new()
	tab.position = Vector2(_tabs_x + _spacing * _tabs.size(), _tab_y)
	var bg := FlashUi.make("UITabMainBrownBg" if brown else _tab_bg)
	var bg_w := 64.0
	if bg != null:
		bg.visible = false
		bg_w = bg.local_bounds().end.x
		tab.add_child(bg)
	var btn := FlashButton.wrap_node(icon)
	btn.position = Vector2(bg_w / 2.0, _icon_y)
	tab.add_child(btn)
	var index := _tabs.size()
	btn.pressed.connect(func() -> void: select(index))
	add_child(tab)
	_tabs.append({"node": tab, "bg": bg, "button": btn})
	return index


func select(index: int) -> void:
	if index == _current:
		return
	_current = index
	for i in _tabs.size():
		var bg: Node2D = _tabs[i]["bg"]
		if bg != null:
			bg.visible = i == index
	tab_selected.emit(index)


func current() -> int:
	return _current
