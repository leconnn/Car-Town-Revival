extends GdUnitTestSuite
## Mystery boxes: buy a boxed car, spin, then claim it or respin once.

const NOW := TestEnv.NOW
## Fixture box 1 holds cars 1, 2, 4 and 5 (3 is on the excluded list) and
## costs 4,000 coins or 5 Blue Coins; a respin is 1 Blue Coin. Box 2 isn't
## on sale.


func _logic() -> GameLogic:
	var logic := TestEnv.logic(100000)
	logic.save["player"]["blue"] = 100
	return logic


func test_pool_and_levels() -> void:
	var logic := _logic()
	assert_array(logic.mystery_pool(1)).is_equal([1, 2, 4, 5])
	assert_array(logic.mystery_box_levels()).is_equal([1])
	logic.catalog.art_car_ids = {2: true, 5: true}
	assert_array(logic.mystery_pool(1)).is_equal([2, 5])


func test_coin_prices_follow_the_blue_coin_ratio() -> void:
	var logic := _logic()
	assert_int(logic.mystery_box_price(1)).is_equal(4000)
	# 1 of 5 Blue Coins: a fifth of the coin price.
	assert_int(logic.mystery_box_respin_price(1)).is_equal(800)
	logic.catalog.tuning["mystery_boxes"]["currency"] = "blue"
	assert_int(logic.mystery_box_price(1)).is_equal(5)
	assert_int(logic.mystery_box_respin_price(1)).is_equal(1)


func test_buy_spin_respin_claim() -> void:
	var logic := _logic()
	var coins: int = logic.save["player"]["coins"]
	assert_str(logic.buy_mystery_box(2, 6, 6, 0, NOW).error).is_equal("That mystery box isn't for sale.")
	var r := logic.buy_mystery_box(1, 6, 6, 0, NOW)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins - 4000)
	var uid: int = r.data["uid"]
	var first: int = r.data["car_id"]
	assert_bool([1, 2, 4, 5].has(first)).is_true()
	# Not opened yet: can't claim, sell or store it.
	assert_str(logic.mystery_box_claim(uid, NOW).error).is_equal("Spin the wheel first.")
	assert_str(logic.sell_item(uid).error).is_equal("Open the mystery box first.")
	assert_str(logic.store_item(uid).error).is_equal("Open the mystery box first.")
	assert_str(logic.mystery_box_respin(uid, NOW).error).is_equal("This box can't be spun again.")
	assert_int(logic.mystery_box_spun(uid).data["spin"]).is_equal(GameLogic.BOX_SPUN)
	var again := logic.mystery_box_respin(uid, NOW)
	assert_bool(again.ok).is_true()
	assert_int(again.data["car_id"]).is_not_equal(first)
	assert_int(logic.save["player"]["coins"]).is_equal(coins - 4800)
	assert_str(logic.mystery_box_claim(uid, NOW).error).is_equal("Spin the wheel first.")
	logic.mystery_box_spun(uid)
	assert_str(logic.mystery_box_respin(uid, NOW).error).is_equal("This box can't be spun again.")
	var cars: int = logic.save["cars"].size()
	var claimed := logic.mystery_box_claim(uid, NOW)
	assert_bool(claimed.ok).is_true()
	assert_int(logic.save["cars"].size()).is_equal(cars + 1)
	var car: Dictionary = logic.save["cars"][-1]
	assert_int(car["car_id"]).is_equal(again.data["car_id"])
	assert_bool(car["placed"]).is_true()
	assert_int(car["x"]).is_equal(6)
	assert_int(car["y"]).is_equal(6)
	assert_bool(logic.save["mystery_boxes"].is_empty()).is_true()
	assert_bool(logic._find_item(uid).is_empty()).is_true()


func test_clearing_the_floor_leaves_boxes() -> void:
	var logic := _logic()
	var uid: int = logic.buy_mystery_box(1, 6, 6, 0, NOW).data["uid"]
	logic.clear_floor(false, true, false, false, false)
	assert_bool(logic._find_item(uid).is_empty()).is_false()


func test_not_enough_coins() -> void:
	var logic := _logic()
	logic.save["player"]["coins"] = 100
	assert_str(logic.buy_mystery_box(1, 6, 6, 0, NOW).error).is_equal("Not enough coins.")
