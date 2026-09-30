extends GdUnitTestSuite

const NOW := TestEnv.NOW


func test_dealer_excludes_retired_and_placeholder_cars() -> void:
	var ids := TestEnv.logic().dealer_car_ids()
	assert_array(ids).contains_exactly([1, 5, 2])


func test_buy_car_charges_and_adds_car() -> void:
	var logic := TestEnv.logic(10000)
	var r := logic.buy_car(1, 2, false, NOW)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(6000)
	assert_int(logic.save["cars"].size()).is_equal(2)
	assert_int(logic.get_car(r.data["uid"])["color_id"]).is_equal(2)


func test_buy_car_rejects_bad_colour_by_using_default() -> void:
	var logic := TestEnv.logic(10000)
	var r := logic.buy_car(1, 999, false, NOW)
	assert_int(logic.get_car(r.data["uid"])["color_id"]).is_equal(1)


func test_buy_car_needs_money_level_and_dealer() -> void:
	var logic := TestEnv.logic(100)
	assert_str(logic.buy_car(1, 1, false, NOW).error).is_equal("Not enough coins.")
	logic.save["player"]["coins"] = 100000
	assert_str(logic.buy_car(2, 3, false, NOW).error).is_equal("Requires level 5.")
	assert_bool(logic.buy_car(3, 0, false, NOW).ok).is_false()
	assert_int(logic.save["player"]["coins"]).is_equal(100000)


func test_buy_car_with_blue_coins() -> void:
	var logic := TestEnv.logic()
	logic.save["player"]["blue"] = 20
	assert_bool(logic.buy_car(5, 4, true, NOW).ok).is_true()
	assert_int(logic.save["player"]["blue"]).is_equal(10)
	assert_str(logic.buy_car(1, 1, true, NOW).error).is_equal("This can't be bought with blue coins.")


func test_sell_car_refunds_fraction_but_keeps_last_car() -> void:
	var logic := TestEnv.logic(10000)
	var starter: int = logic.save["cars"][0]["uid"]
	assert_bool(logic.sell_car(starter, NOW).ok).is_false()
	var uid: int = logic.buy_car(1, 1, false, NOW).data["uid"]
	var coins: int = logic.save["player"]["coins"]
	var r := logic.sell_car(uid, NOW)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins + 400)


func test_paint_car() -> void:
	var logic := TestEnv.logic(10000)
	var uid: int = logic.save["cars"][0]["uid"]
	# The starter car comes in its catalog colour, as RGB.
	assert_int(logic.car_paint(logic.get_car(uid))).is_equal(0xff0000)
	assert_bool(logic.paint_car(uid, 0x3366aa, false, NOW).ok).is_true()
	assert_int(logic.get_car(uid)["paint"]).is_equal(0x3366aa)
	assert_int(logic.save["player"]["coins"]).is_equal(9500)
	assert_str(logic.paint_car(uid, 0x3366aa, false, NOW).error).is_equal("The car is already that colour.")
	assert_str(logic.paint_car(uid, 0x1000000, false, NOW).error).is_equal("That isn't a colour.")


func test_old_cars_without_paint_use_their_catalog_colour() -> void:
	var logic := TestEnv.logic(10000)
	var car: Dictionary = logic.save["cars"][0]
	car.erase("paint")
	car["color_id"] = 2
	assert_int(logic.car_paint(car)).is_equal(0x00ff00)
	assert_bool(logic.paint_car(car["uid"], 0x00ff00, false, NOW).ok).is_false()


func test_install_part_checks_fit_and_level() -> void:
	var logic := TestEnv.logic(10000)
	var uid: int = logic.save["cars"][0]["uid"]
	assert_bool(logic.install_part(uid, 12, false, NOW).ok).is_true()
	assert_int(logic.get_car(uid)["parts"]["1"]).is_equal(12)
	assert_int(logic.save["player"]["coins"]).is_equal(9700)
	assert_str(logic.install_part(uid, 13, false, NOW).error).is_equal("Requires level 10.")
	assert_bool(logic.install_part(uid, 21, false, NOW).ok).is_false() # another car's wheels
	# Going back to stock is free.
	assert_bool(logic.install_part(uid, 11, false, NOW).ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(9700)


func test_replaced_parts_go_to_storage_and_come_back_free() -> void:
	var logic := TestEnv.logic(10000)
	var uid: int = logic.save["cars"][0]["uid"]
	assert_bool(logic.install_part(uid, 12, false, NOW).ok).is_true() # bought: 300
	# Back to stock: the bought wheels go to storage; stock ones never do.
	assert_bool(logic.install_part(uid, 11, false, NOW).ok).is_true()
	assert_int(logic.stored_parts(12)).is_equal(1)
	assert_int(logic.stored_parts(11)).is_equal(0)
	# Putting them back on is free and takes them out of storage.
	var r := logic.install_part(uid, 12, false, NOW)
	assert_bool(r.ok).is_true()
	assert_bool(r.data["from_storage"]).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(9700)
	assert_bool(logic.save["part_storage"].has("12")).is_false()
	# Taking a part off stores it too.
	assert_bool(logic.install_part(uid, 100, false, NOW).ok).is_true()
	assert_bool(logic.remove_part(uid, 10).ok).is_true()
	assert_int(logic.stored_parts(100)).is_equal(1)
	# Paint, tint and the like aren't kept.
	assert_bool(logic.install_part(uid, 694, false, NOW).ok).is_true()
	assert_int(logic.stored_parts(694)).is_equal(0)


func test_universal_part_fits_any_car() -> void:
	var logic := TestEnv.logic(10000)
	var uid: int = logic.save["cars"][0]["uid"]
	assert_bool(logic.install_part(uid, 100, false, NOW).ok).is_true()
	assert_int(logic.get_car(uid)["parts"]["10"]).is_equal(100)


func test_upgrade_prices_and_max_stage() -> void:
	var logic := TestEnv.logic(1_000_000)
	logic.save["player"]["blue"] = 10
	var uid: int = logic.save["cars"][0]["uid"]
	# Car price 4000: stage 1 = max(40, 25) coins; stage 5 = 400 coins as blue.
	assert_that(logic.upgrade_stage_price(1, 1)).is_equal([40, 0])
	assert_that(logic.upgrade_stage_price(1, 3)).is_equal([200, 0])
	assert_that(logic.upgrade_stage_price(1, 5)).is_equal([0, 1])
	for i in 5:
		assert_bool(logic.upgrade_car(uid, GameLogic.UPGRADE_ENGINE, NOW).ok).is_true()
	assert_that(logic.get_car(uid)["upgrades"]).is_equal([5, 0, 0, 0])
	assert_int(logic.save["player"]["blue"]).is_equal(9)
	assert_str(logic.upgrade_car(uid, GameLogic.UPGRADE_ENGINE, NOW).error).is_equal("That upgrade is maxed out.")
	assert_bool(logic.upgrade_car(uid, GameLogic.UPGRADE_WEIGHT, NOW).ok).is_true()
	assert_str(logic.upgrade_car(uid, 5, NOW).error).is_equal("Unknown upgrade.")
	assert_int(logic.car_score(uid)).is_equal(100 + 6 * 20)


func test_plate_validation() -> void:
	var logic := TestEnv.logic(10000)
	var uid: int = logic.save["cars"][0]["uid"]
	assert_bool(logic.set_plate(uid, "cartown", false, NOW).ok).is_true()
	assert_str(logic.get_car(uid)["plate"]).is_equal("CARTOWN")
	assert_bool(logic.set_plate(uid, "TOO LONG1", false, NOW).ok).is_false()
	assert_bool(logic.set_plate(uid, "B@D", false, NOW).ok).is_false()


func test_move_and_store_car() -> void:
	var logic := TestEnv.logic()
	var uid: int = logic.save["cars"][0]["uid"]
	assert_bool(logic.move_car(uid, 0, 0, 0).ok).is_false() # the lift is there
	assert_bool(logic.move_car(uid, 6, 6, 1).ok).is_true()
	assert_bool(logic.move_car(uid, 8, 8, 0).ok).is_false() # off the edge
	assert_bool(logic.store_car(uid).ok).is_true()
	assert_bool(logic.get_car(uid)["placed"]).is_false()
