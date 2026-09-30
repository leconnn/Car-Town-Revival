extends Node
## Local-only parity check on the real catalog (output stays in _reference/,
## since it contains original game data). Compare with:
##   node supabase/functions/_shared/rules/real_parity.mjs


func _ready() -> void:
	var t0 := 1_760_000_000
	var steps: Array = [
		["buy_car", [28, 0, false], t0], ["tick", [], t0], ["put_car_on_bay", [4, 1], t0],
		["start_job", [1, 4], t0], ["collect_job", [1], t0 + 300], ["start_job", [1, 13], t0 + 300],
		["finish_job_now", [1], t0 + 400], ["paint_car", [3, 0x3366aa, false], t0 + 500],
		["buy_item", [900, 8, 8, 0, false], t0 + 600], ["buy_item", [158, 3, 3, 0, false], t0 + 700],
		["buy_item", [1357, 0, 2, 0, false], t0 + 700], ["buy_item", [1357, 0, 3, 0, false], t0 + 700],
		["buy_item", [856, 0, 2, 0, false], t0 + 700],
		["upgrade_car", [3, 2], t0 + 800], ["install_part", [3, 2965, false], t0 + 800],
		["take_car_off_bay", [4], t0 + 900], ["start_car_task", [3, 3], t0 + 900], ["collect_car_task", [3], t0 + 1200], ["tick", [], t0 + 7200], ["accept_customer", [5, 1], t0 + 7200],
		["start_job", [1, 4], t0 + 7200], ["collect_job", [1], t0 + 7600], ["open_gps", [], t0 + 7600],
		["visit_location", [9], t0 + 7600],
		["start_race", [9, 0, 3], t0 + 7700], ["finish_race", [700, 1, false], t0 + 7730],
		["start_race", [7, 2, 3], t0 + 7800], ["finish_race", [100, 0, true], t0 + 7830], ["buy_fuel", [4], t0 + 7900], ["expand_land", [false], t0 + 86400 * 3], ["tick", [], t0 + 86400 * 3],
	]
	var logic := GameLogic.new(GameData.catalog, GameLogic.new_save(GameData.catalog, "Real", t0))
	var start := logic.save.duplicate(true)
	var out: Array = []
	for st: Array in steps:
		var r := BackendImpl.run_on(logic, st[0], st[1], st[2])
		out.append({"action": st[0], "args": st[1], "now": st[2], "result": r.to_dict(), "save": logic.save.duplicate(true)})
	var f := FileAccess.open("res://_reference/golden_real.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"start": start, "steps": out}, " ", false))
	f.close()
	print("wrote _reference/golden_real.json")
	get_tree().quit()
