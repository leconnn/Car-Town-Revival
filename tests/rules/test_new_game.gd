extends GdUnitTestSuite


func test_new_save_uses_tuning_start_values() -> void:
	var logic := TestEnv.logic()
	var s := logic.save
	assert_int(s["save_version"]).is_equal(GameLogic.CURRENT_SAVE_VERSION)
	assert_int(s["player"]["coins"]).is_equal(10000)
	assert_int(s["player"]["blue"]).is_equal(5)
	assert_int(s["player"]["level"]).is_equal(1)
	assert_int(s["garage"]["land_id"]).is_equal(1)
	assert_int(s["cars"].size()).is_equal(1)
	assert_int(s["cars"][0]["car_id"]).is_equal(1)
	assert_int(s["garage"]["items"].size()).is_equal(1)


func test_starter_car_gets_stock_parts_and_a_free_spot() -> void:
	var car: Dictionary = TestEnv.logic().save["cars"][0]
	assert_int(car["parts"]["1"]).is_equal(11)
	assert_bool(car["placed"]).is_true()
	# The starting lift covers x 0-3, y 0-4, so the car must not overlap it.
	assert_bool(car["x"] >= 4 or car["y"] >= 5).is_true()


func test_uids_are_unique() -> void:
	var logic := TestEnv.logic()
	var a := logic._uid()
	var b := logic._uid()
	assert_int(b).is_not_equal(a)
