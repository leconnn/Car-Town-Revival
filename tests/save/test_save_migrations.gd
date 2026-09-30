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
