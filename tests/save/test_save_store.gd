extends GdUnitTestSuite

var _dir: String


func before_test() -> void:
	_dir = create_temp_dir("saves")


func test_write_then_load_round_trip() -> void:
	var store := SaveStore.new(_dir)
	var logic := TestEnv.logic()
	assert_bool(store.write_slot(0, logic.save)).is_true()
	var loaded := store.load_slot(0)
	assert_that(loaded).is_equal(logic.save)
	# Numbers come back as ints, not floats.
	assert_int(typeof(loaded["player"]["coins"])).is_equal(TYPE_INT)


func test_falls_back_to_backup_when_main_file_is_damaged() -> void:
	var store := SaveStore.new(_dir)
	var logic := TestEnv.logic()
	store.write_slot(1, logic.save)
	logic.save["player"]["coins"] = 1
	store.write_slot(1, logic.save)
	var f := FileAccess.open(store.path_for(1), FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var loaded := store.load_slot(1)
	assert_int(loaded["player"]["coins"]).is_equal(10000)


func test_empty_slot() -> void:
	var store := SaveStore.new(_dir)
	var errors: Array[String] = []
	assert_bool(store.load_slot(2, errors).is_empty()).is_true()
	assert_bool(errors.is_empty()).is_false()
	assert_bool(store.summary(2).is_empty()).is_true()


func test_delete_slot() -> void:
	var store := SaveStore.new(_dir)
	store.write_slot(0, TestEnv.logic().save)
	store.write_slot(0, TestEnv.logic().save)
	store.delete_slot(0)
	assert_bool(store.exists(0)).is_false()


func test_summary() -> void:
	var store := SaveStore.new(_dir)
	store.write_slot(0, TestEnv.logic().save)
	var s := store.summary(0)
	assert_str(s["name"]).is_equal("Tester")
	assert_int(s["level"]).is_equal(1)
