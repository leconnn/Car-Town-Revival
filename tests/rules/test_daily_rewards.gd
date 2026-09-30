extends GdUnitTestSuite
## The daily login reward: a prize per day of the streak.

const DAY := 86400
const NOW := TestEnv.NOW


func test_first_claim_is_day_one_and_only_once_a_day() -> void:
	var logic := TestEnv.logic(1000)
	var s := logic.daily_reward_status(NOW)
	assert_bool(s["available"]).is_true()
	assert_int(s["day"]).is_equal(1)
	var r := logic.claim_daily_reward(NOW)
	assert_bool(r.ok).is_true()
	assert_str(r.data["type"]).is_equal("Point")
	assert_int(logic.save["player"]["blue"]).is_equal(6) # 5 to start with plus the prize
	assert_bool(logic.daily_reward_status(NOW + 100)["available"]).is_false()
	assert_str(logic.claim_daily_reward(NOW + 100).error).is_equal("You've already collected today's prize.")


func test_streak_walks_the_list_and_a_gap_resets_it() -> void:
	var logic := TestEnv.logic(1000)
	# Days 1 (blue coin), 2 (250 coins), 3 (20 XP) on consecutive days.
	logic.claim_daily_reward(NOW)
	var r := logic.claim_daily_reward(NOW + DAY)
	assert_int(r.data["day"]).is_equal(2)
	assert_int(logic.save["player"]["coins"]).is_equal(1250)
	r = logic.claim_daily_reward(NOW + 2 * DAY)
	assert_int(r.data["streak"]).is_equal(3)
	assert_int(logic.save["player"]["xp"]).is_equal(20)
	# Skip a day: back to day 1.
	r = logic.claim_daily_reward(NOW + 4 * DAY)
	assert_int(r.data["streak"]).is_equal(1)
	assert_str(r.data["type"]).is_equal("Point")


func test_item_car_fuel_and_unsupported_prizes() -> void:
	var logic := TestEnv.logic(1000)
	var cars: int = logic.save["cars"].size()
	var t := NOW
	for i in 4:
		logic.claim_daily_reward(t)
		t += DAY
	# Day 4: an item into storage.
	assert_int(logic.save["storage"].get("900", 0)).is_equal(1)
	# Day 5: a car.
	logic.claim_daily_reward(t)
	t += DAY
	assert_int(logic.save["cars"].size()).is_equal(cars + 1)
	# Day 6: gallons of fuel on top of a full tank.
	var tank := logic.fuel_tank()
	logic.claim_daily_reward(t)
	t += DAY
	assert_int(logic.save["player"]["fuel"]).is_equal(tank + 3)
	# Day 7 is a tournament item, which we pay as coins.
	var coins: int = logic.save["player"]["coins"]
	var r := logic.claim_daily_reward(t)
	assert_str(r.data["type"]).is_equal("Coins")
	assert_int(logic.save["player"]["coins"]).is_equal(coins + 250)
	# The list starts over after the last day.
	t += DAY
	assert_int(logic.claim_daily_reward(t).data["day"]).is_equal(1)
