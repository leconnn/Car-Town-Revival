extends GdUnitTestSuite
## The shift mini-game's scoring.


func test_launch_before_green_is_a_foul() -> void:
	var r := RaceRules.launch(300, 1499)
	assert_bool(r["foul"]).is_true()
	assert_int(r["points"]).is_equal(-300)


func test_launch_scores_fall_off_over_a_second() -> void:
	assert_int(RaceRules.launch(300, 1500)["points"]).is_equal(600) # bonus: doubled
	assert_str(RaceRules.launch(300, 1500)["type"]).is_equal(RaceRules.SHIFT_BONUS)
	assert_int(RaceRules.launch(300, 1550)["points"]).is_equal(285)
	assert_str(RaceRules.launch(300, 1550)["type"]).is_equal(RaceRules.SHIFT_NORMAL)
	assert_int(RaceRules.launch(300, 2500)["points"]).is_equal(0)


func test_shifts_score_by_needle_angle() -> void:
	# Early: proportional to the angle.
	assert_int(RaceRules.shift(244, 122)["points"]).is_equal(122)
	assert_str(RaceRules.shift(244, 122)["type"]).is_equal(RaceRules.SHIFT_NORMAL)
	# Dead on the redline is a perfect shift worth double.
	var perfect := RaceRules.shift(244, 244)
	assert_int(perfect["points"]).is_equal(488)
	assert_str(perfect["type"]).is_equal(RaceRules.SHIFT_PERFECT)
	assert_str(perfect["message"]).is_equal("Perfect! ")
	# Just inside the bonus zone is worth a little less.
	assert_str(RaceRules.shift(244, 242)["message"]).is_equal("Bonus! ")
	# Past it: redlined, and it costs points.
	var red := RaceRules.shift(244, 300)
	assert_bool(red["redlined"]).is_true()
	assert_bool(red["points"] < 0).is_true()


func test_needle_speed_depends_on_power() -> void:
	assert_int(RaceRules.throttle_time_ms(1000)).is_equal(2000)
	assert_int(RaceRules.throttle_time_ms(0)).is_equal(4000)
	assert_float(RaceRules.needle_angle(1000, 1000)).is_equal_approx(180.0, 0.01)
	assert_float(RaceRules.needle_angle(1000, 99999)).is_equal_approx(342.0, 0.01)


func test_opponent_score_splits_into_four_pieces_that_add_up() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for total in [531, 100, 1200]:
		var parts := RaceRules.split_opponent_score(total, rng)
		assert_int(parts.size()).is_equal(4)
		assert_int(parts.reduce(func(a: int, b: int) -> int: return a + b, 0)).is_equal(total)
