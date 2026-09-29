class_name PlayersPanel
extends GamePanel
## LAN: everyone in this world. Visit their garages.

var game: Node


func _init(game_node: Node) -> void:
	game = game_node
	title = "Players in %s" % Lan.world_name


func _ready() -> void:
	super()
	Lan.players_changed.connect(_on_state_changed)
	Lan.garage_received.connect(_on_garage)


func _build() -> void:
	var me := PlayerIdentity.get_id()
	for p: Dictionary in Lan.players:
		var row := UiKit.hbox(8)
		var status := "online" if p.get("online", false) else "offline"
		var label := UiKit.label("%s%s  ·  level %d  ·  %s" % [p["name"], " (host)" if p.get("host", false) else "", p["level"], status], 16,
			Color.WHITE if p.get("online", false) else Color(0.7, 0.75, 0.8))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if p["id"] != me:
			row.add_child(UiKit.button("Visit", func() -> void: Lan.request_garage(p["id"]), 14))
		body.add_child(row)
	if Lan.players.size() <= 1:
		body.add_child(UiKit.label("Nobody else is here yet. Friends on your network can join from LAN → Join a world.", 15, Color(0.85, 0.9, 1)))


func _on_garage(_player_id: String, player_state: Dictionary) -> void:
	if player_state.is_empty():
		toast("Couldn't load that garage.")
		return
	game.visit_garage(player_state)
