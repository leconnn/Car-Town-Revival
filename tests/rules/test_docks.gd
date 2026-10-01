extends GdUnitTestSuite
## The Docks: Tony's boats of retired limited cars in crates.

const NOW := TestEnv.NOW
## Fixture cars 10-20 are retired limited cars; 16 is on the excluded list.
## Blue Coin price is 10 x (id - 9).
const POOL: Array[int] = [10, 11, 12, 13, 14, 15, 17, 18, 19, 20]


func _logic() -> GameLogic:
	var logic := TestEnv.logic(100000)
	logic.save["player"]["blue"] = 1000
	return logic


func test_dealer_leaves_retired_limited_cars_to_the_docks() -> void:
	var logic := _logic()
	for id: int in POOL:
		assert_bool(logic.dealer_car_ids().has(id)).is_false()


func test_pool_is_retired_limited_drawable_cars() -> void:
	var logic := _logic()
	assert_array(logic.docks_pool(1, NOW)).is_equal(POOL)
	# The special boat only brings cars worth 20+ (fixture tuning).
	assert_array(logic.docks_pool(2, NOW)).is_equal([11, 12, 13, 14, 15, 17, 18, 19, 20])
	# Cars without art never come in.
	logic.catalog.art_car_ids = {10: true, 11: true}
	assert_array(logic.docks_pool(1, NOW)).is_equal([10, 11])
	# Before the cars were retired there's nothing to bring.
	assert_array(logic.docks_pool(1, 400000)).is_empty()


func test_first_search_is_free_and_claim_takes_the_car() -> void:
	var logic := _logic()
	var r := logic.docks_manifest(1, 0, NOW)
	assert_bool(r.ok).is_true()
	var boat: Dictionary = logic.save["docks"]["boat"]
	assert_int(boat["cars"].size()).is_equal(8)
	for id: int in boat["cars"]:
		assert_bool(POOL.has(id)).is_true()
	var sorted_crates: Array = boat["crates"].duplicate()
	sorted_crates.sort()
	var sorted_cars: Array = boat["cars"].duplicate()
	sorted_cars.sort()
	assert_array(sorted_crates).is_equal(sorted_cars)
	assert_int(r.data["price"]).is_equal(0)
	assert_str(logic.docks_open_crate(0, NOW).error).is_equal("Search the boat first.")
	assert_bool(logic.docks_search(NOW).ok).is_true()
	assert_int(logic.save["player"]["blue"]).is_equal(1000)
	assert_str(logic.docks_manifest(1, 0, NOW).error).is_equal("Finish searching this boat first.")
	assert_str(logic.docks_claim(NOW).error).is_equal("Open a crate first.")
	var opened := logic.docks_open_crate(3, NOW)
	assert_int(opened.data["car_id"]).is_equal(boat["crates"][3])
	assert_str(logic.docks_open_crate(4, NOW).error).is_equal("Claim this car or search again first.")
	var cars_before: int = logic.save["cars"].size()
	var claimed := logic.docks_claim(NOW)
	assert_bool(claimed.ok).is_true()
	assert_int(logic.save["cars"].size()).is_equal(cars_before + 1)
	assert_int(logic.save["cars"][-1]["car_id"]).is_equal(opened.data["car_id"])
	assert_bool(logic.save["docks"]["first_done"]).is_true()
	assert_bool(logic.save["docks"]["boat"].is_empty()).is_true()


func test_paid_search_and_search_again() -> void:
	var logic := _logic()
	logic.save["docks"]["first_done"] = true
	logic.save["docks"]["last_claim"] = NOW - 100
	assert_bool(logic.docks_manifest(1, 0, NOW).ok).is_true()
	var boat: Dictionary = logic.save["docks"]["boat"]
	var total := 0
	for id: int in boat["cars"]:
		total += 10 * (id - 9)
	var price: int = (total + 4) / 8
	assert_int(boat["price"]).is_equal(price)
	var search: int = (price * 60 + 99) / 100
	var again: int = (price * 20 + 99) / 100
	assert_int(logic.docks_search_price()).is_equal(search)
	logic.docks_search(NOW)
	assert_int(logic.save["player"]["blue"]).is_equal(1000 - search)
	logic.docks_open_crate(0, NOW)
	assert_bool(logic.docks_search_again(NOW).ok).is_true()
	assert_int(logic.save["player"]["blue"]).is_equal(1000 - search - again)
	assert_int(boat["states"][0]).is_equal(GameLogic.CRATE_PASSED)
	assert_str(logic.docks_open_crate(0, NOW).error).is_equal("That crate's already open.")
	# Pass over all but the last crate; then there's nothing left to search.
	for i in range(1, 7):
		logic.docks_open_crate(i, NOW)
		logic.docks_search_again(NOW)
	logic.docks_open_crate(7, NOW)
	assert_str(logic.docks_search_again(NOW).error).is_equal("That was the last crate.")
	assert_bool(logic.docks_claim(NOW).ok).is_true()


func test_wanted_car_is_on_the_boat_and_sets_the_price() -> void:
	var logic := _logic()
	logic.save["docks"]["first_done"] = true
	assert_str(logic.docks_manifest(1, 16, NOW).error).is_equal("Tony can't get that car.")
	assert_bool(logic.docks_manifest(1, 15, NOW).ok).is_true()
	var boat: Dictionary = logic.save["docks"]["boat"]
	assert_int(boat["cars"][0]).is_equal(15)
	assert_bool(boat["crates"].has(15)).is_true()
	assert_int(boat["price"]).is_equal(60)
	assert_int(logic.docks_search_price()).is_equal(36)
	logic.docks_search(NOW)
	var at: int = boat["crates"].find(15)
	assert_bool(logic.docks_open_crate(at, NOW).data["wanted"]).is_true()


func test_special_boat_sails_for_a_day_after_a_claim() -> void:
	var logic := _logic()
	assert_str(logic.docks_manifest(2, 0, NOW).error).is_equal("Tony's special boat isn't in.")
	logic.save["docks"]["first_done"] = true
	logic.save["docks"]["last_claim"] = NOW - 3600
	assert_bool(logic.docks_manifest(2, 0, NOW).ok).is_true()
	for id: int in logic.save["docks"]["boat"]["cars"]:
		assert_int(id).is_not_equal(10)
	logic.save["docks"]["boat"] = {}
	assert_str(logic.docks_manifest(2, 0, NOW + 86400).error).is_equal("Tony's special boat isn't in.")


func test_not_enough_blue_coins() -> void:
	var logic := _logic()
	logic.save["docks"]["first_done"] = true
	logic.save["player"]["blue"] = 0
	logic.docks_manifest(1, 0, NOW)
	assert_str(logic.docks_search(NOW).error).is_equal("Not enough Blue Coins.")
	assert_bool(logic.save["docks"]["boat"]["active"]).is_false()


func test_coin_priced_docks() -> void:
	var logic := _logic()
	logic.catalog.tuning["docks"]["currency"] = "coins"
	logic.save["docks"]["first_done"] = true
	logic.save["player"]["coins"] = 50000
	# Car 15 costs 60,000 coins: searching for it is 60%.
	logic.docks_manifest(1, 15, NOW)
	assert_int(logic.docks_search_price()).is_equal(36000)
	assert_bool(logic.docks_search(NOW).ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(14000)
	assert_int(logic.save["player"]["blue"]).is_equal(1000)
	logic.docks_open_crate(0, NOW)
	logic.save["player"]["coins"] = 0
	assert_str(logic.docks_search_again(NOW).error).is_equal("Not enough coins.")
