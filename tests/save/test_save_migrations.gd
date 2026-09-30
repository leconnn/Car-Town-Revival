extends GdUnitTestSuite
## Every save layout change needs a migration and a test here, using a
## fixture of the old layout in tests/fixtures/saves/.


func test_current_version_loads_unchanged() -> void:
	var save := TestEnv.logic().save
	var errors: Array[String] = []
	var out := SaveMigrations.migrate(save, errors)
	assert_that(out).is_equal(save)
	assert_array(errors).is_empty()


func test_v1_fixture_loads() -> void:
	var raw: Variant = JsonUtil.read_file("res://tests/fixtures/saves/v1.json")
	var out := SaveMigrations.migrate(raw)
	assert_int(out["save_version"]).is_equal(GameLogic.CURRENT_SAVE_VERSION)
	# The upgraded save must work with the current rules.
	var logic := GameLogic.new(TestEnv.catalog(), out)
	assert_bool(logic.tick(TestEnv.NOW).ok).is_true()


func test_v1_to_v2_adds_car_tasks() -> void:
	var raw: Variant = JsonUtil.read_file("res://tests/fixtures/saves/v1.json")
	assert_bool((raw as Dictionary).has("car_tasks")).is_false()
	var out := SaveMigrations.migrate(raw)
	assert_that(out["car_tasks"]).is_equal({})
	for car: Dictionary in out["cars"]:
		assert_bool(car.has("upgrade")).is_false()
		assert_int(car["upgrades"].size()).is_equal(4)


func test_rejects_newer_version() -> void:
	var errors: Array[String] = []
	var out := SaveMigrations.migrate({"save_version": GameLogic.CURRENT_SAVE_VERSION + 1}, errors)
	assert_bool(out.is_empty()).is_true()
	assert_str(errors[0]).contains("newer version")


func test_rejects_non_save() -> void:
	var errors: Array[String] = []
	assert_bool(SaveMigrations.migrate({"hello": 1}, errors).is_empty()).is_true()
	assert_array(errors).is_not_empty()


func test_v2_to_v3_adds_part_storage() -> void:
	var raw: Variant = JsonUtil.read_file("res://tests/fixtures/saves/v2.json")
	assert_int(raw["save_version"]).is_equal(2)
	assert_bool((raw as Dictionary).has("part_storage")).is_false()
	var out := SaveMigrations.migrate(raw)
	assert_int(out["save_version"]).is_equal(GameLogic.CURRENT_SAVE_VERSION)
	assert_that(out["part_storage"]).is_equal({})
	var logic := GameLogic.new(TestEnv.catalog(), out)
	assert_bool(logic.tick(TestEnv.NOW).ok).is_true()


func test_v3_to_v4_makes_floor_and_walls_tile_by_tile() -> void:
	var raw: Variant = JsonUtil.read_file("res://tests/fixtures/saves/v3.json")
	assert_int(raw["save_version"]).is_equal(3)
	var out := SaveMigrations.migrate(raw)
	assert_int(out["save_version"]).is_equal(GameLogic.CURRENT_SAVE_VERSION)
	assert_that(out["garage"]["floor_tiles"]).is_equal({})
	# The old wall style turns into back walls once the rules load it.
	var logic := GameLogic.new(TestEnv.catalog(), out)
	assert_bool(out["garage"].has("wall_item_id")).is_false()
	assert_int(out["garage"]["walls"].size()).is_greater(0)
	assert_bool(logic.tick(TestEnv.NOW).ok).is_true()


func test_v4_to_v5_adds_racing_and_a_full_tank() -> void:
	var raw: Variant = JsonUtil.read_file("res://tests/fixtures/saves/v4.json")
	assert_int(raw["save_version"]).is_equal(4)
	var out := SaveMigrations.migrate(raw)
	assert_that(out["race"]).is_equal({})
	var logic := GameLogic.new(TestEnv.catalog(), out)
	assert_int(logic.fuel(TestEnv.NOW)).is_equal(logic.fuel_tank())
	assert_bool(logic.tick(TestEnv.NOW).ok).is_true()
	assert_int(out["player"]["fuel"]).is_equal(logic.fuel_tank())


func test_v5_to_v6_adds_the_daily_reward() -> void:
	var raw: Variant = JsonUtil.read_file("res://tests/fixtures/saves/v5.json")
	assert_int(raw["save_version"]).is_equal(5)
	var out := SaveMigrations.migrate(raw)
	assert_int(out["save_version"]).is_equal(GameLogic.CURRENT_SAVE_VERSION)
	assert_int(out["daily_reward"]["last_day"]).is_equal(-1)
	var logic := GameLogic.new(TestEnv.catalog(), out)
	assert_bool(logic.daily_reward_status(TestEnv.NOW)["available"]).is_true()


func test_v6_to_v7_adds_car_collections() -> void:
	var raw: Variant = JsonUtil.read_file("res://tests/fixtures/saves/v6.json")
	assert_int(raw["save_version"]).is_equal(6)
	var out := SaveMigrations.migrate(raw)
	assert_int(out["save_version"]).is_equal(GameLogic.CURRENT_SAVE_VERSION)
	assert_that(out["collections_done"]).is_equal([])
	assert_bool(GameLogic.new(TestEnv.catalog(), out).tick(TestEnv.NOW).ok).is_true()
