extends GdUnitTestSuite


func test_validate_converts_json_floats() -> void:
	var clean: Variant = BackendImpl.validate("buy_car", [1.0, 2.0, false])
	assert_that(clean).is_equal([1, 2, false])
	assert_int(typeof(clean[0])).is_equal(TYPE_INT)


func test_validate_rejects_bad_input() -> void:
	assert_that(BackendImpl.validate("buy_car", [1, 2])).is_null()
	assert_that(BackendImpl.validate("buy_car", ["1", 2, false])).is_null()
	assert_that(BackendImpl.validate("give_me_money", [])).is_null()
	assert_that(BackendImpl.validate("set_plate", [1, "x".repeat(100), false])).is_null()


func test_every_action_exists_on_game_logic() -> void:
	var logic := TestEnv.logic()
	for action: String in BackendImpl.ACTIONS:
		assert_bool(logic.has_method(action)).override_failure_message("missing " + action).is_true()


func test_run_on_passes_time_and_stamps_save() -> void:
	var logic := TestEnv.logic()
	var r := BackendImpl.run_on(logic, "open_gps", [], TestEnv.NOW + 5)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["updated_at"]).is_equal(TestEnv.NOW + 5)


func test_local_backend_persists_actions() -> void:
	var dir := create_temp_dir("local_backend")
	var cat := TestEnv.catalog()
	var backend := LocalBackend.new(cat, SaveStore.new(dir))
	assert_bool(backend.new_game(0, "Tester")).is_true()
	var car: int = backend.state()["cars"][0]["uid"]
	var r: GameResult = backend.act("paint_car", [car, 0x3366aa, false])
	assert_bool(r.ok).is_true()
	var again := LocalBackend.new(cat, SaveStore.new(dir))
	assert_bool(again.load_game(0)).is_true()
	assert_int(again.state()["cars"][0]["paint"]).is_equal(0x3366aa)
