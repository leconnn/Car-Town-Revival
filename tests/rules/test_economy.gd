extends GdUnitTestSuite


func test_level_for_xp() -> void:
	var cat := TestEnv.catalog()
	assert_int(cat.level_for_xp(0)).is_equal(1)
	assert_int(cat.level_for_xp(42)).is_equal(1)
	assert_int(cat.level_for_xp(43)).is_equal(2)
	assert_int(cat.level_for_xp(99999)).is_equal(10)


func test_rewards_level_up_and_pay_bonus() -> void:
	var logic := TestEnv.logic(0)
	var result := GameResult.success()
	logic.add_rewards(0, 0, 95, result)
	# 95 XP crosses level 2 (43) and 3 (90): bonuses 500 + 750, 1 blue each.
	assert_int(logic.save["player"]["level"]).is_equal(3)
	assert_int(logic.save["player"]["coins"]).is_equal(1250)
	assert_int(logic.save["player"]["blue"]).is_equal(5 + 2)
	assert_int(result.notices.size()).is_equal(2)
	assert_str(result.notices[0]["kind"]).is_equal("level_up")


func test_garage_value_counts_cars_and_items() -> void:
	var logic := TestEnv.logic()
	# Starter car 4000 + lift 800.
	assert_int(logic.garage_value()).is_equal(4800)
	assert_int(logic.garage_value_tier()).is_equal(1)


func test_max_workers_follows_level() -> void:
	var logic := TestEnv.logic()
	assert_int(logic.max_workers()).is_equal(2)
	logic.save["player"]["level"] = 3
	assert_int(logic.max_workers()).is_equal(3)
