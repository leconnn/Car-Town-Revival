extends GdUnitTestSuite

const NOW := TestEnv.NOW


func test_rotated_size() -> void:
	assert_that(GarageGrid.rotated_size(4, 3, 0)).is_equal(Vector2i(4, 3))
	assert_that(GarageGrid.rotated_size(4, 3, 1)).is_equal(Vector2i(3, 4))


func test_wall_items_are_not_floor_objects() -> void:
	var cat := TestEnv.catalog()
	assert_bool(GarageGrid.is_floor_object(cat.item(900))).is_true()
	assert_bool(GarageGrid.is_floor_object(cat.item(950))).is_false()
	assert_bool(GarageGrid.is_floor_object(cat.item(292))).is_false()


func test_buy_item_places_and_blocks_tiles() -> void:
	var logic := TestEnv.logic(10000)
	var r := logic.buy_item(900, 9, 9, 0, false, NOW)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(9900)
	assert_str(logic.buy_item(900, 9, 9, 0, false, NOW).error).is_equal("There's no room there.")
	assert_str(logic.buy_item(901, 5, 5, 0, false, NOW).error).is_equal("Requires level 3.")


func test_move_store_place_sell_item() -> void:
	var logic := TestEnv.logic(10000)
	var uid: int = logic.buy_item(900, 9, 9, 0, false, NOW).data["uid"]
	assert_bool(logic.move_item(uid, 9, 8, 0).ok).is_true()
	assert_bool(logic.store_item(uid).ok).is_true()
	assert_int(logic.save["storage"]["900"]).is_equal(1)
	var placed := logic.place_stored_item(900, 9, 9, 0)
	assert_bool(placed.ok).is_true()
	assert_bool(logic.save["storage"].has("900")).is_false()
	var coins: int = logic.save["player"]["coins"]
	assert_bool(logic.sell_item(placed.data["uid"]).ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins + 50)


func test_bay_with_car_cannot_be_moved() -> void:
	var logic := TestEnv.logic()
	var bay := TestEnv.first_bay(logic)
	var car: int = logic.save["cars"][0]["uid"]
	assert_bool(logic.put_car_on_bay(car, bay).ok).is_true()
	assert_bool(logic.move_item(bay, 5, 5, 0).ok).is_false()
	assert_bool(logic.store_item(bay).ok).is_false()


func test_expand_land_needs_level() -> void:
	var logic := TestEnv.logic(100000)
	assert_str(logic.expand_land(false, NOW).error).is_equal("Requires level 4.")
	logic.save["player"]["level"] = 4
	assert_bool(logic.expand_land(false, NOW).ok).is_true()
	assert_int(logic.save["garage"]["land_id"]).is_equal(2)
	assert_int(logic.save["player"]["coins"]).is_equal(92500)
	# max_land_id is 2 in the test tuning.
	assert_bool(logic.expand_land(false, NOW).ok).is_false()


func test_set_surface_charges_per_tile() -> void:
	var logic := TestEnv.logic(10000)
	assert_bool(logic.set_surface(293, false, NOW).ok).is_true()
	assert_int(logic.save["garage"]["floor_item_id"]).is_equal(293)
	assert_int(logic.save["player"]["coins"]).is_equal(10000 - 5 * 100)
	assert_bool(logic.set_surface(293, false, NOW).ok).is_false()
	assert_bool(logic.set_surface(900, false, NOW).ok).is_false()
