class_name TestEnv
extends RefCounted
## Shared setup for rule tests: a tiny invented catalog in tests/fixtures.

const NOW := 1_000_000


static func catalog() -> Catalog:
	var cat := Catalog.new()
	var ok := cat.load_from("res://tests/fixtures/catalog", "res://tests/fixtures/tuning.json")
	assert(ok, cat.load_error)
	return cat


## A new game. Missions are off unless [param with_missions], so their
## rewards don't disturb tests of other rules.
static func logic(coins: int = -1, with_missions: bool = false) -> GameLogic:
	var cat := catalog()
	if not with_missions:
		cat.missions.clear()
		cat.steps_by_mission.clear()
	var logic := GameLogic.new(cat, GameLogic.new_save(cat, "Tester", NOW))
	if coins >= 0:
		logic.save["player"]["coins"] = coins
	return logic


static func first_bay(logic: GameLogic) -> int:
	for it: Dictionary in logic.save["garage"]["items"]:
		if it["item_id"] == 156:
			return it["uid"]
	return 0
