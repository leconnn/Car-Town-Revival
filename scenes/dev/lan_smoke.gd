extends Node
## Two-process LAN smoke test (run by tools/lan_smoke.sh):
##   host:  -- role=host dir=<folder>
##   guest: -- role=guest [version=<fake>] [expect=reject]
## The guest joins, buys and paints a car, checks the host's replies and
## prints PASS or FAIL before quitting. The host quits after 30 seconds.

var _args := {}


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() == 2:
			_args[parts[0]] = parts[1]
	if _args.get("role", "") == "host":
		_run_host()
	else:
		_run_guest()


func _run_host() -> void:
	var err: String = Lan.host(LanWorld.new(_args.get("dir", "user://lan_smoke")), 0, "Smoke World", "HostPlayer")
	print("HOST ", "OK" if err == "" else err)
	await get_tree().create_timer(30.0).timeout
	Lan.stop()
	get_tree().quit()


func _run_guest() -> void:
	PlayerIdentity.override_id = "smoke_guest"
	if _args.has("version"):
		Lan.version_override = _args["version"]
	Lan.join("127.0.0.1", Lan.PORT, "GuestPlayer")
	var res: Array = await Lan.join_finished
	var ok: bool = res[0]
	if _args.get("expect", "") == "reject":
		_finish(not ok and str(res[1]).contains("Update to join"), "rejected: %s" % res[1])
		return
	if not ok:
		_finish(false, "join failed: %s" % res[1])
		return
	await Backend.use(Lan.guest_backend())
	var s := Backend.state()
	if s["player"]["name"] != "GuestPlayer":
		_finish(false, "wrong player: %s" % s["player"]["name"])
		return
	var coins: int = s["player"]["coins"]
	var car_id := 0
	for id: int in Backend.query().dealer_car_ids():
		var c: Dictionary = GameData.catalog.car(id)
		if c["can_buy_with_coins"] and c["min_level"] <= 1 and c["price"] <= coins:
			car_id = id
			break
	var buy: GameResult = await Backend.buy_car(car_id, 0, false)
	if not buy.ok:
		_finish(false, "buy failed: %s" % buy.error)
		return
	var after: int = Backend.state()["player"]["coins"]
	# The world persists between runs, so a level-up or mission may pay out.
	var bonus := 0
	for n: Dictionary in buy.notices:
		bonus += int(n.get("coins", 0))
	if after != coins - GameData.catalog.car(car_id)["price"] + bonus:
		_finish(false, "coins %d -> %d" % [coins, after])
		return
	var bad: GameResult = await Backend.act("give_me_money", [])
	if bad.ok:
		_finish(false, "invalid action was accepted")
		return
	Lan.request_garage(Lan.players[0]["id"])
	var g: Array = await Lan.garage_received
	_finish(not g[1].is_empty(), "visited %s" % g[1].get("player", {}).get("name", "?"))


func _finish(ok: bool, detail: String) -> void:
	print(("PASS " if ok else "FAIL ") + detail)
	Lan.stop()
	get_tree().quit(0 if ok else 1)
