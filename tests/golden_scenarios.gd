class_name GoldenScenarios
extends RefCounted
## Scripted play sessions used to keep the two copies of the rules in sync.
##
## Each scenario is a list of actions. Running it on GameLogic produces a
## transcript (every result and the save after each step) that is stored in
## tests/fixtures/golden/. The TypeScript server rules replay the same
## transcripts and must produce identical results.
##
## Regenerate after an intended rule change:
##   godot --headless --path . res://scenes/dev/make_golden.tscn

const DIR := "res://tests/fixtures/golden"
const T0 := TestEnv.NOW
## Uid of the first wall bought in garage_and_cars (the one the sign hangs on).
const WALL_UID := 7

## name -> [[action, args, now], ...]. Bay uid 1 is the starting lift and
## car uid 2 is the starter car in the test catalog.
static func all() -> Dictionary:
	return {
		"garage_and_cars": [
			["buy_car", [1, 2, false], T0],
			["buy_car", [2, 3, false], T0],
			["buy_car", [5, 4, true], T0],
			["paint_car", [2, 0x3366aa, false], T0 + 10],
			["install_part", [2, 12, false], T0 + 20],
			["install_part", [2, 13, false], T0 + 20],
			["install_part", [2, 100, true], T0 + 20],
			# Parts storage: stock back on, then the stored wheels again for free.
			["install_part", [2, 11, false], T0 + 21],
			["install_part", [2, 12, false], T0 + 22],
			["remove_part", [2, 10], T0 + 23],
			["upgrade_car", [2, 1], T0 + 30],
			["upgrade_car", [2, 3], T0 + 30],
			["upgrade_car", [2, 7], T0 + 30],
			["set_ride_height", [2, 3, false], T0 + 40],
			["set_plate", [2, "rusty 1", false], T0 + 40],
			["set_plate", [2, "b@d", false], T0 + 40],
			["buy_item", [900, 9, 9, 0, false], T0 + 50],
			["buy_item", [900, 9, 9, 0, false], T0 + 50],
			["move_item", [4, 8, 9, 1], T0 + 60],
			["store_item", [4], T0 + 60],
			["place_stored_item", [900, 9, 0, 0], T0 + 60],
			# Floor tiles, walls and a sign on them (item 950 is two tiles wide).
			["buy_item", [293, 3, 3, 0, false], T0 + 70],
			["buy_item", [293, 3, 3, 0, false], T0 + 70],
			["buy_item", [1, 0, 2, 0, false], T0 + 70],
			["buy_item", [1, 0, 3, 0, false], T0 + 70],
			["buy_item", [950, 0, 2, 0, false], T0 + 70],
			["buy_item", [950, 0, 3, 0, false], T0 + 70],
			["buy_item", [2, 5, 3, 1, false], T0 + 70],
			["buy_item", [2, 0, 0, 1, false], T0 + 70],
			["store_item", [WALL_UID], T0 + 71],
			["place_stored_item", [1, 0, 3, 0], T0 + 72],
			["clear_floor", [false, false, false, true, true], T0 + 73],
			# Street racing: a race, a foul, fuel.
			["start_race", [9, 0, 2], T0 + 74],
			["finish_race", [5000, 2, false], T0 + 75],
			["start_race", [9, 1, 2], T0 + 76],
			["finish_race", [-50, 0, true], T0 + 77],
			["finish_race", [10, 0, false], T0 + 77],
			["start_race", [14, 0, 2], T0 + 78],
			["buy_fuel", [3], T0 + 78],
			# Daily rewards: a streak over three days, a repeat, then a gap.
			["claim_daily_reward", [], T0 + 79],
			["claim_daily_reward", [], T0 + 80],
			["claim_daily_reward", [], T0 + 86400 + 79],
			["claim_daily_reward", [], T0 + 2 * 86400 + 79],
			["claim_daily_reward", [], T0 + 5 * 86400],
			["expand_land", [false], T0 + 80],
			["move_car", [2, 6, 6, 1], T0 + 90],
			["store_car", [2], T0 + 90],
			["sell_car", [2], T0 + 100],
		],
		"jobs_and_customers": [
			["tick", [], T0],
			["put_car_on_bay", [2, 1], T0],
			["start_job", [1, 4], T0],
			["collect_job", [1], T0 + 100],
			["collect_job", [1], T0 + 300],
			["start_job", [1, 4], T0 + 300],
			["collect_job", [1], T0 + 600],
			["start_job", [1, 4], T0 + 600],
			["finish_job_now", [1], T0 + 700],
			["start_job", [1, 4], T0 + 700],
			["stop_job", [1], T0 + 710],
			["stop_job", [1], T0 + 710],
			["take_car_off_bay", [2], T0 + 700],
			["start_car_task", [2, 4], T0 + 700],
			["start_car_task", [2, 3], T0 + 700],
			["sell_car", [2], T0 + 710],
			["collect_car_task", [2], T0 + 800],
			["collect_car_task", [2], T0 + 1000],
			["start_car_task", [2, 3], T0 + 1000],
			["finish_car_task_now", [2], T0 + 1100],
			["start_car_task", [2, 3], T0 + 1100],
			["stop_car_task", [2], T0 + 1110],
			# Road trip: a bare start is refused, then off to the beach and back.
			["start_car_task", [2, 34], T0 + 1120],
			["start_road_trip", [2, 6], T0 + 1120],
			["start_road_trip", [2, 1], T0 + 1120],
			["collect_car_task", [2], T0 + 1120 + 86400],
			# The Docks: Tony's free first boat, a claim, then his special boat
			# with a paid search and a search again; and asking for a car.
			["docks_search", [], T0 + 90000],
			["docks_manifest", [2, 0], T0 + 90000],
			["docks_manifest", [1, 0], T0 + 90000],
			["docks_open_crate", [0], T0 + 90000],
			["docks_search", [], T0 + 90000],
			["docks_open_crate", [2], T0 + 90010],
			["docks_open_crate", [3], T0 + 90010],
			["docks_claim", [], T0 + 90020],
			["docks_manifest", [2, 0], T0 + 90030],
			["docks_search", [], T0 + 90030],
			["docks_open_crate", [5], T0 + 90040],
			["docks_search_again", [], T0 + 90050],
			["docks_open_crate", [5], T0 + 90050],
			["docks_open_crate", [6], T0 + 90060],
			["docks_claim", [], T0 + 90070],
			["docks_manifest", [1, 16], T0 + 90080],
			["docks_manifest", [1, 15], T0 + 90080],
			["docks_search", [], T0 + 90090],
			# Mystery boxes: one not for sale, then buy, spin, respin, claim.
			["buy_mystery_box", [2, 0, 0, 0], T0 + 90100],
			["buy_mystery_box", [1, 0, 0, 0], T0 + 90100],
			["buy_mystery_box", [1, 0, 5, 0], T0 + 90100],
			["mystery_box_claim", [5], T0 + 90110],
			["mystery_box_spun", [5], T0 + 90110],
			["mystery_box_respin", [5], T0 + 90120],
			["mystery_box_spun", [5], T0 + 90120],
			["mystery_box_claim", [5], T0 + 90130],
			# Restoration: a junker on a bay, the day's pile part, townsfolk
			# deliveries, a bought part, then the car.
			["start_restoration", [29, 1], T0 + 90200],
			["start_restoration", [53, 1], T0 + 90200],
			["collect_junkyard_part", [], T0 + 90210],
			["collect_junkyard_part", [], T0 + 90220],
			["tick", [], T0 + 90200 + 5 * 3600],
			["buy_build_part", [1], T0 + 90200 + 5 * 3600],
			["install_build_part", [1, 1], T0 + 90200 + 5 * 3600],
			["install_build_part", [1, 1], T0 + 90200 + 5 * 3600],
			["install_build_part", [1, 1], T0 + 90200 + 5 * 3600],
			["finish_restoration", [1], T0 + 90200 + 5 * 3600],
			["tick", [], T0 + 3600],
			["accept_customer", [4, 1], T0 + 3600],
			["start_job", [1, 13], T0 + 3600],
			["start_job", [1, 4], T0 + 3600],
			["collect_job", [1], T0 + 5400],
			["dismiss_customer", [5], T0 + 5400],
			# An empty lift: the job gets a random car.
			["start_job", [1, 4], T0 + 5400],
			["collect_job", [1], T0 + 5700],
			["clear_floor", [true, true, false, false, false], T0 + 86400],
			["tick", [], T0 + 86400 * 2],
			["visit_location", [9], T0 + 86400 * 2],
			["visit_location", [14], T0 + 86400 * 2],
			["open_gps", [], T0 + 86400 * 2],
			["set_tutorial", [3, false], T0 + 86400 * 2],
			["rename", ["New Name"], T0 + 86400 * 2],
		],
	}


## Runs a scenario from a new game (with missions on) and returns the transcript.
static func run(steps: Array) -> Dictionary:
	var logic := TestEnv.logic(-1, true)
	var start := logic.save.duplicate(true)
	var out: Array = []
	for step: Array in steps:
		var r := BackendImpl.run_on(logic, step[0], step[1], step[2])
		out.append({"action": step[0], "args": step[1], "now": step[2],
			"result": r.to_dict(), "save": logic.save.duplicate(true)})
	return {"start": start, "steps": out}
