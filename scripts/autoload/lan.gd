extends Node
## Autoload "Lan": LAN multiplayer over Godot's ENet (no internet needed).
##
## The host runs the game rules for everyone in its world and stores all
## players in its world save. Guests send actions by name and get results
## back; they never change data themselves. Hosts announce themselves on the
## local network so guests can find them without typing an IP.

signal hosts_changed
signal players_changed
signal join_finished(ok: bool, message: String)
signal garage_received(player_id: String, player_state: Dictionary)

const PORT := 24555
const DISCOVERY_PORT := 24556
const MAX_GUESTS := 15
const GAME_TAG := "CarTownRevival"
const BROADCAST_SECONDS := 1.0
const HOST_TIMEOUT_MSEC := 4000

enum Role { NONE, HOST, GUEST }

var role := Role.NONE
## Discovered hosts: "ip:port" -> {"world", "host", "version", "players", "ip", "port", "seen"}
var found_hosts: Dictionary[String, Dictionary] = {}
## Everyone in the session: [{"id", "name", "level", "online"}]
var players: Array[Dictionary] = []
var world_name := ""

# Host state
var _world: Dictionary = {}
var _world_slot := -1
var _world_store: LanWorld
var _logics: Dictionary[String, GameLogic] = {}
var _peer_players: Dictionary[int, String] = {}
var _host_id := ""
var _host_backend: LanHostBackend
var _broadcaster: PacketPeerUDP
var _broadcast_left := 0.0

# Guest state
var _guest_backend: LanGuestBackend
var _listener: PacketPeerUDP


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func() -> void: _fail_join("Couldn't reach the host."))
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Set only by tests to pretend to be another version.
static var version_override := ""


static func game_version() -> String:
	if version_override != "":
		return version_override
	return str(ProjectSettings.get_setting("application/config/version", "0"))


func _process(delta: float) -> void:
	if role == Role.HOST and _broadcaster != null:
		_broadcast_left -= delta
		if _broadcast_left <= 0.0:
			_broadcast_left = BROADCAST_SECONDS
			_announce()
	if _listener != null:
		_listen()


# --- Hosting --------------------------------------------------------------------------

## Starts hosting a world slot. [param import_save], if given, becomes the
## host's player (moving a single-player save into LAN). Returns "" or an error.
func host(store: LanWorld, slot: int, new_world_name: String, host_name: String, import_save: Dictionary = {}) -> String:
	stop()
	var now := int(Time.get_unix_time_from_system())
	var errors: Array[String] = []
	_world_store = store
	_world_slot = slot
	_world = store.load_slot(slot, errors) if store.exists(slot) else LanWorld.new_world(new_world_name, now)
	if _world.is_empty():
		return "\n".join(errors)
	_host_id = PlayerIdentity.get_id()
	_world["host_id"] = _host_id
	if not import_save.is_empty():
		_world["players"][_host_id] = import_save.duplicate(true)
	elif not _world["players"].has(_host_id):
		_world["players"][_host_id] = GameLogic.new_save(GameData.catalog, host_name, now)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_GUESTS)
	if err != OK:
		return "Couldn't open port %d for LAN play (%s). Is another game already hosting?" % [PORT, error_string(err)]
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	world_name = _world["name"]
	for pid: String in _world["players"]:
		_logics[pid] = GameLogic.new(GameData.catalog, _world["players"][pid])
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_save_world()
	_refresh_players()
	return ""


func host_backend() -> LanHostBackend:
	if _host_backend == null:
		_host_backend = LanHostBackend.new(self, _host_id)
	return _host_backend


func host_state(player_id: String) -> Dictionary:
	return _world.get("players", {}).get(player_id, {})


## Runs an action for a player in the hosted world (host and guests).
func host_act(player_id: String, action: String, args: Array) -> GameResult:
	if not _logics.has(player_id):
		return GameResult.fail("Unknown player.")
	var logic: GameLogic = _logics[player_id]
	var level_before: int = logic.save["player"]["level"]
	var result := BackendImpl.run_on(logic, action, args, int(Time.get_unix_time_from_system()))
	if result.ok and (action != "tick" or result.data.get("arrived", 0) > 0):
		_world["updated_at"] = int(Time.get_unix_time_from_system())
		_save_world()
	if logic.save["player"]["level"] != level_before:
		_refresh_players()
	return result


func _save_world() -> void:
	if _world_store != null and _world_slot >= 0:
		_world_store.write_slot(_world_slot, _world)


func _announce() -> void:
	var info := {"game": GAME_TAG, "world": world_name, "host": _host_name(),
		"version": game_version(), "port": PORT, "players": _peer_players.size() + 1}
	_broadcaster.put_packet(JSON.stringify(info).to_utf8_buffer())


func _host_name() -> String:
	return _world["players"].get(_host_id, {}).get("player", {}).get("name", "Host")


func _on_peer_connected(_id: int) -> void:
	pass # Guests introduce themselves with _hello.


func _on_peer_disconnected(id: int) -> void:
	if role == Role.HOST:
		_peer_players.erase(id)
		_refresh_players()


@rpc("any_peer", "call_remote", "reliable")
func _hello(version: String, player_id: String, player_name: String) -> void:
	if role != Role.HOST:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if version != game_version():
		_rejected.rpc_id(peer_id, "Host is on v%s, you're on v%s. Update to join." % [game_version(), version])
		_kick_later(peer_id)
		return
	if player_id.is_empty() or player_id.length() > 64 or player_id == _host_id or _peer_players.values().has(player_id):
		_rejected.rpc_id(peer_id, "That player is already in this world.")
		_kick_later(peer_id)
		return
	var now := int(Time.get_unix_time_from_system())
	if not _world["players"].has(player_id):
		var clean_name := player_name.strip_edges().left(20)
		_world["players"][player_id] = GameLogic.new_save(GameData.catalog, clean_name if clean_name != "" else "Guest", now)
		_logics[player_id] = GameLogic.new(GameData.catalog, _world["players"][player_id])
		_save_world()
	_peer_players[peer_id] = player_id
	_welcome.rpc_id(peer_id, world_name, _world["players"][player_id], now)
	_refresh_players()


func _kick_later(peer_id: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _request(req_id: int, action: String, args: Array) -> void:
	if role != Role.HOST:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var player_id: String = _peer_players.get(peer_id, "")
	var result: GameResult
	if player_id == "":
		result = GameResult.fail("You haven't joined this world.")
	else:
		result = host_act(player_id, action, args)
	_response.rpc_id(peer_id, req_id, result.to_dict(), host_state(player_id), int(Time.get_unix_time_from_system()))


@rpc("any_peer", "call_remote", "reliable")
func _ask_garage(player_id: String) -> void:
	if role != Role.HOST:
		return
	_garage.rpc_id(multiplayer.get_remote_sender_id(), player_id, _public_state(player_id))


## What other players may see of someone's garage.
func _public_state(player_id: String) -> Dictionary:
	var s := host_state(player_id)
	if s.is_empty():
		return {}
	return {"player": {"name": s["player"]["name"], "level": s["player"]["level"]},
		"garage": s["garage"], "cars": s["cars"], "customers": [], "jobs": {}}


func request_garage(player_id: String) -> void:
	if role == Role.HOST:
		garage_received.emit(player_id, _public_state(player_id))
	elif role == Role.GUEST:
		_ask_garage.rpc_id(1, player_id)


func _refresh_players() -> void:
	var list: Array[Dictionary] = []
	var online := {_host_id: true}
	for pid: String in _peer_players.values():
		online[pid] = true
	for pid: String in _world.get("players", {}):
		var p: Dictionary = _world["players"][pid]["player"]
		list.append({"id": pid, "name": p["name"], "level": p["level"], "online": online.has(pid), "host": pid == _host_id})
	players = list
	players_changed.emit()
	if role == Role.HOST and not _peer_players.is_empty():
		_players.rpc(list)


# --- Joining --------------------------------------------------------------------------

func start_discovery() -> void:
	stop_discovery()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null


func stop_discovery() -> void:
	if _listener != null:
		_listener.close()
	_listener = null


func _listen() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var data := _listener.get_packet().get_string_from_utf8()
		var ip := _listener.get_packet_ip()
		var info: Variant = JSON.parse_string(data)
		if typeof(info) != TYPE_DICTIONARY or info.get("game", "") != GAME_TAG:
			continue
		info["ip"] = ip
		info["port"] = int(info.get("port", PORT))
		info["seen"] = Time.get_ticks_msec()
		found_hosts["%s:%d" % [ip, info["port"]]] = info
		changed = true
	for key: String in found_hosts.keys():
		if Time.get_ticks_msec() - found_hosts[key]["seen"] > HOST_TIMEOUT_MSEC:
			found_hosts.erase(key)
			changed = true
	if changed:
		hosts_changed.emit()


func join(address: String, port: int, player_name: String) -> void:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		join_finished.emit(false, "Couldn't connect: %s" % error_string(err))
		return
	multiplayer.multiplayer_peer = peer
	role = Role.GUEST
	set_meta("join_name", player_name)


func _on_connected_to_server() -> void:
	_hello.rpc_id(1, game_version(), PlayerIdentity.get_id(), get_meta("join_name", "Guest"))


@rpc("authority", "call_remote", "reliable")
func _welcome(name_of_world: String, player_state: Dictionary, host_now: int) -> void:
	world_name = name_of_world
	_guest_backend = LanGuestBackend.new(self, JsonUtil.ints(player_state), host_now)
	join_finished.emit(true, "")


func guest_backend() -> LanGuestBackend:
	return _guest_backend


@rpc("authority", "call_remote", "reliable")
func _rejected(reason: String) -> void:
	_fail_join(reason)


func _fail_join(reason: String) -> void:
	stop()
	join_finished.emit(false, reason)


func send_request(req_id: int, action: String, args: Array) -> void:
	_request.rpc_id(1, req_id, action, args)


@rpc("authority", "call_remote", "reliable")
func _response(req_id: int, result: Dictionary, player_state: Dictionary, host_now: int) -> void:
	if _guest_backend != null:
		_guest_backend.receive(req_id, JsonUtil.ints(result), JsonUtil.ints(player_state), host_now)


@rpc("authority", "call_remote", "reliable")
func _players(list: Array) -> void:
	players.clear()
	for p: Dictionary in list:
		players.append(p)
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _garage(player_id: String, player_state: Dictionary) -> void:
	garage_received.emit(player_id, JsonUtil.ints(player_state))


func _on_server_disconnected() -> void:
	var was_guest := role == Role.GUEST
	stop()
	if was_guest:
		Backend.end_session("The host closed the world.")


# --- Shutdown ---------------------------------------------------------------------------

func stop() -> void:
	if role == Role.HOST:
		_save_world()
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _broadcaster != null:
		_broadcaster.close()
	_broadcaster = null
	role = Role.NONE
	_world = {}
	_logics.clear()
	_peer_players.clear()
	_host_backend = null
	_guest_backend = null
	players.clear()
