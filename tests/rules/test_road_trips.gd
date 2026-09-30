extends GdUnitTestSuite
## Road trips: a car task with a destination that pays per passenger.

const NOW := TestEnv.NOW
const DAY := 1440 * 60


func _car_of_model(logic: GameLogic, car_id: int) -> int:
	var car := logic._add_car(car_id, 0)
	car["placed"] = true
	return car["uid"]


func test_destinations_follow_specific_car() -> void:
	var logic := TestEnv.logic(100000)
	# Trip 6 is only for car 5; the starter (car 1) gets the beach only.
	assert_array(logic.road_trip_ids(logic.save["cars"][0]["uid"])).contains_exactly([1])
	assert_array(logic.road_trip_ids(_car_of_model(logic, 5))).contains_exactly([1, 6])
	assert_array(logic.road_trip_ids(_car_of_model(logic, 2))).is_empty()


func test_road_trip_needs_a_destination() -> void:
	var logic := TestEnv.logic(100000)
	var car: int = logic.save["cars"][0]["uid"]
	assert_str(logic.start_car_task(car, GameLogic.ROAD_TRIP_JOB, NOW).error).is_equal("Pick where the road trip goes.")
	assert_str(logic.start_road_trip(car, 6, NOW).error).is_equal("This car can't go there.")


func test_pay_per_passenger_and_fill_up_bonus() -> void:
	var logic := TestEnv.logic(100000)
	# Class 101: 255 coins and 35 XP a head, 3000 for a full car; trip 6 doubles.
	assert_that(logic.road_trip_pay(5, 1, 2)).is_equal({"coins": 510, "xp": 70, "full": false,
		"per_coins": 255, "per_xp": 35, "bonus": 3000})
	assert_int(logic.road_trip_pay(5, 6, 4)["coins"]).is_equal(510 * 4 + 3000)
	assert_int(logic.road_trip_pay(5, 6, 4)["xp"]).is_equal(70 * 4)
	# Car 1 has two seats: driver plus one fills it.
	assert_bool(logic.road_trip_pay(1, 1, 2)["full"]).is_true()


func test_start_and_finish_a_road_trip() -> void:
	var logic := TestEnv.logic(100000)
	var car := _car_of_model(logic, 5)
	var coins: int = logic.save["player"]["coins"]
	var r := logic.start_road_trip(car, 6, NOW)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins - 250)
	var task: Dictionary = logic.save["car_tasks"][str(car)]
	assert_int(task["road_trip"]).is_equal(6)
	var passengers: Array = task["passengers"]
	assert_int(passengers.size()).is_less_equal(3)
	for p: Dictionary in passengers:
		assert_int(p["at"]).is_between(NOW, NOW + DAY)
	assert_int(logic.road_trip_passengers(task, NOW - 1)).is_equal(1)
	assert_str(logic.collect_car_task(car, NOW + 60).error).is_equal("The job isn't finished yet.")
	coins = logic.save["player"]["coins"]
	r = logic.collect_car_task(car, NOW + DAY)
	assert_bool(r.ok).is_true()
	var aboard := 1 + passengers.size()
	assert_int(r.data["passengers"]).is_equal(aboard)
	assert_int(r.data["seats"]).is_equal(4)
	assert_int(r.data["coins"]).is_equal(logic.road_trip_pay(5, 6, aboard)["coins"])
	assert_int(logic.save["player"]["coins"]).is_greater_equal(coins + r.data["coins"])
	assert_bool(logic.save["car_tasks"].is_empty()).is_true()


func test_every_seat_filled_when_everyone_joins() -> void:
	var logic := TestEnv.logic(100000)
	logic.catalog.tuning["road_trips"]["passenger_chance_percent"] = 100
	var car := _car_of_model(logic, 5)
	assert_bool(logic.start_road_trip(car, 1, NOW).ok).is_true()
	var r := logic.collect_car_task(car, NOW + DAY)
	assert_int(r.data["passengers"]).is_equal(4)
	assert_bool(r.data["full"]).is_true()
	assert_int(r.data["coins"]).is_equal(255 * 4 + 3000)
