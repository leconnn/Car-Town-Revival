extends GdUnitTestSuite

const NOW := TestEnv.NOW


func test_unsupported_missions_are_hidden() -> void:
	var logic := TestEnv.logic(-1, true)
	var ids := logic.active_missions(NOW)
	# Mission 3 needs pink-slip races (not built yet); mission 2 needs mission 1 first.
	assert_array(ids).contains([1, 6])
	assert_array(ids).not_contains([2, 3])
	# 8 duplicates tutorial mission 6 on the other track; 9 was retired.
	assert_array(ids).not_contains([8, 9])


func test_mission_completes_and_pays() -> void:
	var logic := TestEnv.logic(10000, true)
	var bay := TestEnv.first_bay(logic)
	logic.put_car_on_bay(logic.save["cars"][0]["uid"], bay)
	var completed := {}
	var t := NOW
	for i in 2:
		logic.start_job(bay, 4, t)
		t += 300
		for n: Dictionary in logic.collect_job(bay, t).notices:
			if n["kind"] == "mission_complete":
				completed = n
	assert_int(completed.get("mission_id", 0)).is_equal(1)
	assert_array(logic.save["missions"]["completed"]).contains([1])
	# Mission 2 unlocks once 1 is done.
	assert_array(logic.active_missions(t)).contains([2])


func test_step_params_must_match() -> void:
	var logic := TestEnv.logic(100000, true)
	logic.save["player"]["level"] = 3
	logic.save["missions"]["completed"].append(1)
	logic.buy_item(900, 9, 9, 0, false, NOW) # decoration, not a work bay
	assert_bool(logic.save["missions"]["completed"].has(2)).is_false()
	var spot := GarageGrid.build(logic.catalog, logic.save).find_free(Vector2i(4, 5))
	logic.buy_item(156, spot.x, spot.y, 0, false, NOW)
	assert_bool(logic.save["missions"]["completed"].has(2)).is_true()


func test_reward_item_goes_to_storage() -> void:
	var logic := TestEnv.logic(100000, true)
	logic.save["player"]["level"] = 4
	logic.expand_land(false, NOW)
	assert_int(logic.save["storage"].get("900", 0)).is_equal(1)


func test_daily_missions_are_picked_per_day_and_repeatable() -> void:
	var logic := TestEnv.logic(10000, true)
	logic.active_missions(NOW)
	var daily: Dictionary = logic.save["missions"]["daily"]
	assert_int(daily["day"]).is_equal(NOW / 86400)
	# Pool: 4 (start job), 5 (visit diner), 7 (paint). All supported, 3 picked.
	assert_array(daily["ids"]).contains_exactly_in_any_order([4, 5, 7])
	var r := logic.visit_location(9, NOW)
	var kinds := r.notices.map(func(n: Dictionary) -> String: return n["kind"])
	assert_array(kinds).contains(["mission_complete"])
	assert_array(logic.save["missions"]["daily"]["done"]).contains([5])
	# Next day, a fresh set.
	logic.active_missions(NOW + 86400)
	assert_array(logic.save["missions"]["daily"]["done"]).is_empty()


func test_same_day_same_dailies() -> void:
	var a := TestEnv.logic(-1, true)
	var b := TestEnv.logic(-1, true)
	a.active_missions(NOW)
	b.active_missions(NOW + 100)
	assert_that(a.save["missions"]["daily"]["ids"]).is_equal(b.save["missions"]["daily"]["ids"])
