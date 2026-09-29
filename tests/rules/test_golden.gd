extends GdUnitTestSuite
## The stored transcripts must match what the rules do now. If a rule change
## is intended, regenerate them (see GoldenScenarios) so the server rules get
## the same change.


func test_transcripts_match_current_rules() -> void:
	var scenarios := GoldenScenarios.all()
	for name: String in scenarios:
		var stored: Variant = JsonUtil.read_file(GoldenScenarios.DIR.path_join(name + ".json"))
		assert_that(stored).override_failure_message("missing golden file " + name).is_not_null()
		var fresh: Variant = JsonUtil.ints(JSON.parse_string(JSON.stringify(GoldenScenarios.run(scenarios[name]))))
		assert_that(fresh).override_failure_message("rules changed for scenario " + name).is_equal(stored)
