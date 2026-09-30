extends GdUnitTestSuite
## Car collections: own every car in a set and it pays once.

const NOW := TestEnv.NOW


func test_completing_a_set_pays_coins_xp_and_the_plaque_once() -> void:
	var logic := TestEnv.logic(100000)
	# The test set is cars 1 (your starter) and 5.
	assert_that(logic.collection_progress(1)).is_equal([1, 2])
	var coins: int = logic.save["player"]["coins"]
	var r := logic.buy_car(5, 0, false, NOW)
	assert_bool(r.ok).is_true()
	assert_that(logic.collection_progress(1)).is_equal([2, 2])
	var done: Array = r.notices.filter(func(n: Dictionary) -> bool: return n["kind"] == "collection_complete")
	assert_int(done.size()).is_equal(1)
	assert_int(done[0]["coins"]).is_equal(4500)
	assert_int(logic.save["player"]["coins"]).is_greater(coins - 8000 + 4000)
	assert_int(logic.save["storage"].get("900", 0)).is_equal(1)
	assert_that(logic.save["collections_done"]).is_equal([1])
	# Selling a car and buying it back doesn't pay twice.
	var car5: int = logic.save["cars"][-1]["uid"]
	logic.sell_car(car5, NOW)
	r = logic.buy_car(5, 0, false, NOW)
	assert_int(r.notices.filter(func(n: Dictionary) -> bool: return n["kind"] == "collection_complete").size()).is_equal(0)
	assert_int(logic.save["storage"].get("900", 0)).is_equal(1)
