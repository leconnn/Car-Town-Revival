extends GdUnitTestSuite


func test_clear_floor_stores_what_is_not_busy() -> void:
	var logic := TestEnv.logic(100000)
	var bay := TestEnv.first_bay(logic)
	var car: int = logic.save["cars"][0]["uid"]
	logic.put_car_on_bay(car, bay)
	logic.start_job(bay, 4, TestEnv.NOW)
	var spot := GarageGrid.build(logic.catalog, logic.save).find_free(Vector2i(4, 5))
	assert_bool(logic.buy_item(156, spot.x, spot.y, 0, false, TestEnv.NOW).ok).is_true()
	# Only cars: the car on the busy bay stays.
	var r := logic.clear_floor(true, false, false, false, false)
	assert_int(r.data["cars"]).is_equal(0)
	# Bays: the busy one stays, the empty one goes to storage.
	r = logic.clear_floor(false, false, true, false, false)
	assert_int(r.data["bays"]).is_equal(1)
	assert_int(logic.save["storage"]["156"]).is_equal(1)
	logic.collect_job(bay, TestEnv.NOW + 5 * 60)
	r = logic.clear_floor(true, false, true, false, false)
	assert_int(r.data["cars"]).is_equal(1)
	assert_int(r.data["bays"]).is_equal(1)
	assert_bool(logic.get_car(car)["placed"]).is_false()
	assert_int(logic.get_car(car)["bay_uid"]).is_equal(0)

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


func test_floor_tiles_are_painted_one_by_one() -> void:
	var logic := TestEnv.logic(10000)
	assert_bool(logic.buy_item(293, 3, 3, 0, false, NOW).ok).is_true()
	assert_int(logic.floor_tile(3, 3)).is_equal(293)
	assert_int(logic.floor_tile(4, 3)).is_equal(292)
	assert_int(logic.save["player"]["coins"]).is_equal(9995)
	assert_str(logic.buy_item(293, 3, 3, 0, false, NOW).error).is_equal("That tile already has that floor.")
	assert_str(logic.buy_item(293, 30, 3, 0, false, NOW).error).is_equal("That's outside your garage.")
	# Painting the (free) default back puts the bought tile in storage...
	assert_bool(logic.buy_item(292, 3, 3, 0, false, NOW).ok).is_true()
	assert_int(logic.floor_tile(3, 3)).is_equal(292)
	assert_bool(logic.save["garage"]["floor_tiles"].has("3,3")).is_false()
	assert_int(logic.save["storage"]["293"]).is_equal(1)
	# ...and it goes back down from storage for free.
	assert_bool(logic.place_stored_item(293, 4, 4, 0).ok).is_true()
	assert_int(logic.floor_tile(4, 4)).is_equal(293)
	assert_int(logic.save["player"]["coins"]).is_equal(9995)
	assert_bool(logic.save["storage"].has("293")).is_false()


func test_walls_go_on_edges_and_not_through_things() -> void:
	var logic := TestEnv.logic(10000)
	logic.save["player"]["level"] = 5
	# Item 1 is a one-edge wall: vertical on the line h = 0.
	var r := logic.buy_item(1, 0, 2, GarageGrid.VERTICAL, false, NOW)
	assert_bool(r.ok).is_true()
	assert_str(logic.buy_item(1, 0, 2, GarageGrid.VERTICAL, false, NOW).error).is_equal("A wall can't go there.")
	# Not through the work bay at (1, 1)-(4, 5).
	assert_str(logic.buy_item(2, 2, 3, GarageGrid.HORIZONTAL, false, NOW).error).is_equal("A wall can't go there.")
	# And floor objects can't straddle a wall.
	assert_bool(logic.buy_item(2, 7, 8, GarageGrid.HORIZONTAL, false, NOW).ok).is_true()
	assert_str(logic.buy_item(901, 7, 7, 0, false, NOW).error).is_equal("There's no room there.")
	assert_bool(logic.buy_item(901, 7, 8, 0, false, NOW).ok).is_true()
	assert_int(logic.garage_value()).is_greater(0)


func test_signs_hang_on_walls_and_go_with_them() -> void:
	var logic := TestEnv.logic(10000)
	# Item 950 is two segments wide: it needs two walls in a row.
	var wall: int = logic.buy_item(1, 0, 2, GarageGrid.VERTICAL, false, NOW).data["uid"]
	assert_str(logic.buy_item(950, 0, 2, GarageGrid.VERTICAL, false, NOW).error).is_equal("That needs an empty wall to hang on.")
	assert_bool(logic.buy_item(1, 0, 3, GarageGrid.VERTICAL, false, NOW).ok).is_true()
	assert_bool(logic.buy_item(950, 0, 2, GarageGrid.VERTICAL, false, NOW).ok).is_true()
	assert_bool(logic.buy_item(950, 0, 3, GarageGrid.VERTICAL, false, NOW).ok).is_false()
	# Storing a wall takes its sign down too.
	assert_bool(logic.store_item(wall).ok).is_true()
	assert_int(logic.save["storage"]["1"]).is_equal(1)
	assert_int(logic.save["storage"]["950"]).is_equal(1)
	assert_int(logic.save["garage"]["wall_items"].size()).is_equal(0)
	# Reset Floor can clear walls and floor tiles.
	logic.buy_item(293, 5, 5, 0, false, NOW)
	var r := logic.clear_floor(false, false, false, true, true)
	assert_int(r.data["walls"]).is_equal(1)
	assert_int(r.data["floors"]).is_equal(1)
	assert_int(logic.save["storage"]["1"]).is_equal(2)
	assert_int(logic.save["storage"]["293"]).is_equal(1)


func test_old_wall_style_becomes_back_walls() -> void:
	var cat := TestEnv.catalog()
	var s := GameLogic.new_save(cat, "Old", NOW)
	s["garage"].erase("walls")
	s["garage"]["wall_item_id"] = 2
	var logic := GameLogic.new(cat, s)
	assert_bool(s["garage"].has("wall_item_id")).is_false()
	var land: Dictionary = cat.land(s["garage"]["land_id"])
	assert_int(s["garage"]["walls"].size()).is_equal(land["size_x"] + land["size_y"])
	# Signs can hang on them.
	assert_bool(logic.buy_item(950, 0, 0, GarageGrid.VERTICAL, false, NOW).ok).is_true()
