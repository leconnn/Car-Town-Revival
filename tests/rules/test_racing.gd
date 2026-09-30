extends GdUnitTestSuite
## Street racing and fuel.

const NOW := TestEnv.NOW
const DINER := 9


func _car(logic: GameLogic) -> int:
	return logic.save["cars"][0]["uid"]


func test_new_game_starts_with_a_full_tank_that_refills() -> void:
	var logic := TestEnv.logic(10000)
	var tank := logic.fuel_tank()
	assert_int(tank).is_equal(5 + 5) # level 1 tank plus our bonus
	assert_int(logic.save["player"]["fuel"]).is_equal(tank)
	assert_bool(logic.start_race(DINER, 0, _car(logic), NOW).ok).is_true()
	assert_int(logic.save["player"]["fuel"]).is_equal(tank - 1)
	# One gallon back after one refill period.
	assert_int(logic.fuel(NOW + logic.fuel_refill_seconds() - 1)).is_equal(tank - 1)
	assert_int(logic.fuel(NOW + logic.fuel_refill_seconds())).is_equal(tank)
	logic.tick(NOW + logic.fuel_refill_seconds())
	assert_int(logic.save["player"]["fuel"]).is_equal(tank)


func test_no_fuel_no_race() -> void:
	var logic := TestEnv.logic(10000)
	logic.save["player"]["fuel"] = 0
	logic.save["player"]["fuel_at"] = NOW
	assert_str(logic.start_race(DINER, 0, _car(logic), NOW).error).is_equal("You're out of fuel.")
	assert_str(logic.start_race(14, 0, _car(logic), NOW).error).is_equal("There's no racing here.")


func test_opponents_are_the_same_all_hour() -> void:
	var logic := TestEnv.logic(10000)
	var a := logic.race_opponents(DINER, NOW)
	assert_int(a.size()).is_equal(6)
	assert_that(logic.race_opponents(DINER, NOW + 60)).is_equal(a)
	for o: Dictionary in a:
		assert_bool(logic.dealer_car_ids().has(o["car_id"])).is_true()


func test_winning_pays_by_the_opponents_power_and_counts_for_missions() -> void:
	var logic := TestEnv.logic(10000)
	var r := logic.start_race(DINER, 0, _car(logic), NOW)
	var opponent_score: int = r.data["opponent_score"]
	assert_int(opponent_score).is_greater(0)
	# Power 100 is the prize table's minimum: 50 coins and 2 XP.
	var coins: int = logic.save["player"]["coins"]
	var done := logic.finish_race(opponent_score + 1, 1, false, NOW + 30)
	assert_bool(done.data["win"]).is_true()
	assert_int(done.data["coins"]).is_equal(50)
	assert_int(logic.save["player"]["coins"]).is_equal(coins + 50)
	assert_int(logic.save["stats"]["races_won"]).is_equal(1)
	assert_str(logic.finish_race(0, 0, false, NOW + 31).error).is_equal("You aren't racing.")


func test_losing_gives_a_little_xp_and_scores_are_checked() -> void:
	var logic := TestEnv.logic(10000)
	logic.start_race(DINER, 0, _car(logic), NOW)
	var xp: int = logic.save["player"]["xp"]
	var done := logic.finish_race(-50, 0, true, NOW + 30)
	assert_bool(done.data["win"]).is_false()
	assert_int(logic.save["player"]["xp"]).is_equal(xp + 1)
	# A score no car of power 100 could reach is cut down to the maximum.
	logic.start_race(DINER, 1, _car(logic), NOW + 40)
	done = logic.finish_race(999999, 9, false, NOW + 60)
	assert_int(done.data["score"]).is_equal(8 * 100 + 3 * 50)


func test_fuel_cans_and_refills_cost_blue_coins() -> void:
	var logic := TestEnv.logic(10000)
	logic.save["player"]["blue"] = 20
	var tank := logic.fuel_tank()
	# Cans go over the tank.
	assert_bool(logic.buy_fuel(3, NOW).ok).is_true()
	assert_int(logic.save["player"]["fuel"]).is_equal(tank + 3)
	assert_int(logic.save["player"]["blue"]).is_equal(18)
	logic.save["player"]["fuel"] = 1
	assert_bool(logic.buy_fuel(6, NOW).ok).is_true()
	assert_int(logic.save["player"]["fuel"]).is_equal(tank)
	assert_bool(logic.buy_fuel(1, NOW).ok).is_false() # not sold
