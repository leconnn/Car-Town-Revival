extends GdUnitTestSuite
## Car restoration: junkers restored on a work bay from collected parts.

const NOW := TestEnv.NOW
## Fixture builds: 52 restores car 2 from Pistons x1 and Paint x2, 53 car 3
## from Pistons x2, 91 is a Master Mechanic build (after 2 restorations),
## 29 a stock car build (not a restoration). Pistons are 1 Blue Coin, Paint 4.


func _logic() -> GameLogic:
	var logic := TestEnv.logic(100000)
	logic.save["player"]["level"] = 50
	return logic


func test_builds_on_offer() -> void:
	var logic := _logic()
	assert_bool(logic.restoration_build_ids().has(52)).is_true()
	assert_bool(logic.restoration_build_ids().has(91)).is_false()
	assert_bool(logic.restoration_build_ids().has(29)).is_false()
	logic.save["restoration"]["restored"] = [52, 53]
	assert_bool(logic.is_master_mechanic()).is_true()
	assert_bool(logic.restoration_build_ids().has(91)).is_true()
	# Junk Yard spots show the cars you haven't restored first.
	logic.save["restoration"]["restored"] = [52]
	assert_array(logic.junkyard_build_ids()).is_equal([53, 52])


func test_restore_a_car() -> void:
	var logic := _logic()
	var bay := TestEnv.first_bay(logic)
	assert_bool(logic.start_restoration(52, bay, NOW).ok).is_true()
	assert_str(logic.put_car_on_bay(logic.save["cars"][0]["uid"], bay).error).is_equal("That work bay is taken.")
	assert_str(logic.start_restoration(53, bay, NOW).error).is_equal("That work bay is busy.")
	assert_that(logic.build_parts_needed(bay)).is_equal({1: 1, 17: 2})
	assert_str(logic.install_build_part(bay, 1).error).is_equal("You don't have that part.")
	assert_str(logic.finish_restoration(bay, NOW).error).is_equal("It still needs parts.")
	var coins: int = logic.save["player"]["coins"]
	assert_bool(logic.buy_build_part(17, NOW).ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins - 4 * 2500)
	logic.buy_build_part(17, NOW)
	logic.buy_build_part(1, NOW)
	assert_bool(logic.install_build_part(bay, 17).ok).is_true()
	assert_bool(logic.install_build_part(bay, 17).ok).is_true()
	assert_str(logic.install_build_part(bay, 17).error).is_equal("This car doesn't need that part.")
	assert_bool(logic.install_build_part(bay, 1).data["done"]).is_true()
	var cars: int = logic.save["cars"].size()
	var r := logic.finish_restoration(bay, NOW)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["cars"].size()).is_equal(cars + 1)
	assert_int(logic.save["cars"][-1]["car_id"]).is_equal(2)
	assert_array(logic.save["restoration"]["restored"]).is_equal([52])
	assert_bool(logic.bay_build(bay).is_empty()).is_true()


func test_junkyard_part_once_a_day() -> void:
	var logic := _logic()
	var bay := TestEnv.first_bay(logic)
	logic.start_restoration(53, bay, NOW)
	var r := logic.collect_junkyard_part(NOW)
	# The only part 53 needs is Pistons.
	assert_int(r.data["part_id"]).is_equal(1)
	assert_str(logic.collect_junkyard_part(NOW + 3600).error).is_equal("You've already found today's part. Come back tomorrow!")
	assert_bool(logic.collect_junkyard_part(NOW + 86400).ok).is_true()
	assert_int(logic.save["restoration"]["inventory"]["1"]).is_equal(2)


func test_townsfolk_bring_needed_parts() -> void:
	var logic := _logic()
	var bay := TestEnv.first_bay(logic)
	logic.start_restoration(53, bay, NOW)
	# Every 4 hours a needed part; 53 needs two Pistons, then deliveries stop.
	var r := logic.tick(NOW + 10 * 3600)
	var gifts: Array = r.notices.filter(func(n: Dictionary) -> bool: return n["kind"] == "part_gift")
	assert_int(gifts.size()).is_equal(2)
	assert_int(logic.save["restoration"]["inventory"]["1"]).is_equal(2)
	r = logic.tick(NOW + 30 * 3600)
	assert_int(r.notices.filter(func(n: Dictionary) -> bool: return n["kind"] == "part_gift").size()).is_equal(0)


func test_abandon_returns_parts() -> void:
	var logic := _logic()
	var bay := TestEnv.first_bay(logic)
	logic.start_restoration(53, bay, NOW)
	logic.buy_build_part(1, NOW)
	logic.install_build_part(bay, 1)
	assert_bool(logic.abandon_restoration(bay).ok).is_true()
	assert_int(logic.save["restoration"]["inventory"]["1"]).is_equal(1)
	assert_bool(logic.bay_build(bay).is_empty()).is_true()
