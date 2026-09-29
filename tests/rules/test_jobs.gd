extends GdUnitTestSuite

const NOW := TestEnv.NOW


func _logic_with_car_on_bay() -> GameLogic:
	var logic := TestEnv.logic(10000)
	logic.put_car_on_bay(logic.save["cars"][0]["uid"], TestEnv.first_bay(logic))
	return logic


func test_start_job_needs_a_car_on_the_bay() -> void:
	var logic := TestEnv.logic(10000)
	var bay := TestEnv.first_bay(logic)
	assert_str(logic.start_job(bay, 4, NOW).error).is_equal("Put a car on the work bay first.")


func test_start_and_collect_job() -> void:
	var logic := _logic_with_car_on_bay()
	var bay := TestEnv.first_bay(logic)
	var r := logic.start_job(bay, 4, NOW)
	assert_bool(r.ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(9990)
	assert_str(logic.collect_job(bay, NOW + 60).error).is_equal("The job isn't finished yet.")
	var c := logic.collect_job(bay, NOW + 5 * 60)
	assert_bool(c.ok).is_true()
	assert_int(c.data["coins"]).is_equal(40)
	assert_int(logic.save["player"]["coins"]).is_equal(10030)
	assert_int(logic.save["player"]["xp"]).is_equal(10)
	assert_int(logic.save["job_mastery"]["4"]).is_equal(1)


func test_job_level_gate_and_busy_bay() -> void:
	var logic := _logic_with_car_on_bay()
	var bay := TestEnv.first_bay(logic)
	assert_str(logic.start_job(bay, 12, NOW).error).is_equal("Requires level 2.")
	assert_bool(logic.start_job(bay, 4, NOW).ok).is_true()
	assert_str(logic.start_job(bay, 4, NOW).error).is_equal("That work bay is already busy.")
	assert_bool(logic.start_job(bay, 34, NOW).ok).is_false() # not a work bay job


func test_worker_cap() -> void:
	var logic := TestEnv.logic(100000)
	logic.save["player"]["level"] = 1 # 2 workers
	# Three bays in free spots, each with a car.
	var bays: Array[int] = []
	for it: Dictionary in logic.save["garage"]["items"]:
		if it["item_id"] == 156:
			bays.append(it["uid"])
	while bays.size() < 3:
		var spot := GarageGrid.build(logic.catalog, logic.save).find_free(Vector2i(4, 5))
		bays.append(logic.buy_item(156, spot.x, spot.y, 0, false, NOW).data["uid"])
	for i in 3:
		var car_uid: int = logic.buy_car(1, 1, false, NOW).data["uid"]
		logic.put_car_on_bay(car_uid, bays[i])
	assert_bool(logic.start_job(bays[0], 4, NOW).ok).is_true()
	assert_bool(logic.start_job(bays[1], 4, NOW).ok).is_true()
	assert_str(logic.start_job(bays[2], 4, NOW).error).contains("workers are busy")


func test_mastery_raises_xp_and_pays_bonus() -> void:
	var logic := _logic_with_car_on_bay()
	var bay := TestEnv.first_bay(logic)
	var t := NOW
	var mastery_notice := {}
	for i in 3:
		logic.start_job(bay, 4, t)
		t += 300
		var r := logic.collect_job(bay, t)
		for n: Dictionary in r.notices:
			if n["kind"] == "mastery":
				mastery_notice = n
	# Threshold for level 2 is 3 completions; bonus 500 coins.
	assert_int(logic.mastery_level(4)).is_equal(2)
	assert_int(mastery_notice.get("level", 0)).is_equal(2)
	assert_int(logic.job_payout(4)["xp"]).is_equal(12)


func test_finish_now_costs_blue_and_collects() -> void:
	var logic := _logic_with_car_on_bay()
	var bay := TestEnv.first_bay(logic)
	logic.save["player"]["level"] = 2
	logic.start_job(bay, 12, NOW) # 48 hours
	assert_int(logic.finish_now_price(bay, NOW)).is_equal(48)
	assert_str(logic.finish_job_now(bay, NOW).error).is_equal("Not enough blue coins.")
	logic.save["player"]["blue"] = 100
	assert_bool(logic.finish_job_now(bay, NOW).ok).is_true()
	# 100 - 48, plus 1 blue per level-up from the job's 250 XP (level 2 -> 4).
	assert_int(logic.save["player"]["blue"]).is_equal(54)
	assert_bool(logic.save["jobs"].is_empty()).is_true()


func test_car_on_bay_cannot_leave_mid_job() -> void:
	var logic := _logic_with_car_on_bay()
	var bay := TestEnv.first_bay(logic)
	var car: int = logic.save["cars"][0]["uid"]
	logic.start_job(bay, 4, NOW)
	assert_bool(logic.take_car_off_bay(car).ok).is_false()
	logic.collect_job(bay, NOW + 300)
	assert_bool(logic.take_car_off_bay(car).ok).is_true()
	assert_int(logic.get_car(car)["bay_uid"]).is_equal(0)


func test_customers_arrive_over_time_up_to_a_limit() -> void:
	var logic := TestEnv.logic()
	logic.tick(NOW)
	assert_int(logic.save["customers"].size()).is_equal(1)
	logic.tick(NOW + 60 * 60)
	assert_int(logic.save["customers"].size()).is_equal(3)


func test_customer_job_pays_and_customer_leaves() -> void:
	var logic := TestEnv.logic(10000)
	var bay := TestEnv.first_bay(logic)
	logic.tick(NOW)
	var cust: int = logic.save["customers"][0]["uid"]
	assert_bool(logic.accept_customer(cust, bay).ok).is_true()
	# Customers only want quick jobs: in the test catalog that's the car wash.
	assert_int(logic.get_customer(cust)["job_id"]).is_equal(4)
	assert_str(logic.start_job(bay, 13, NOW).error).contains("This customer wants a Job 4")
	assert_bool(logic.start_job(bay, 4, NOW).ok).is_true()
	assert_bool(logic.collect_job(bay, NOW + 300).ok).is_true()
	assert_bool(logic.get_customer(cust).is_empty()).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(10000 - 10 + 40)


func test_customer_arrivals_are_deterministic() -> void:
	var a := TestEnv.logic()
	var b := TestEnv.logic()
	a.tick(NOW + 3600)
	b.tick(NOW + 3600)
	assert_that(a.save["customers"]).is_equal(b.save["customers"])


func test_stop_job_cancels_without_refund() -> void:
	var logic := _logic_with_car_on_bay()
	var bay := TestEnv.first_bay(logic)
	logic.start_job(bay, 4, NOW)
	var coins: int = logic.save["player"]["coins"]
	assert_bool(logic.stop_job(bay).ok).is_true()
	assert_bool(logic.save["jobs"].is_empty()).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins)
	assert_bool(logic.stop_job(bay).ok).is_false()


func test_stopping_a_customer_job_sends_them_away() -> void:
	var logic := TestEnv.logic(10000)
	var bay := TestEnv.first_bay(logic)
	logic.tick(NOW)
	var cust: int = logic.save["customers"][0]["uid"]
	logic.accept_customer(cust, bay)
	logic.start_job(bay, 4, NOW)
	logic.stop_job(bay)
	assert_bool(logic.get_customer(cust).is_empty()).is_true()


# --- Car tasks ----------------------------------------------------------------------

func _car_of_model(logic: GameLogic, car_id: int) -> int:
	# Straight into the garage: fixture cars 2 and 3 aren't all for sale.
	var car := logic._add_car(car_id, 0)
	car["placed"] = true
	return car["uid"]


func test_car_tasks_follow_categories_and_car_ids() -> void:
	var logic := TestEnv.logic(100000)
	# Job 3 is for category 1 (car 1, the starter) and specifically car 3.
	assert_array(logic.car_task_ids(logic.save["cars"][0]["uid"])).contains_exactly([3])
	assert_array(logic.car_task_ids(_car_of_model(logic, 2))).is_empty()
	assert_array(logic.car_task_ids(_car_of_model(logic, 3))).contains_exactly([3])


func test_start_and_collect_car_task() -> void:
	var logic := TestEnv.logic(10000)
	var car := _car_of_model(logic, 3)
	var coins: int = logic.save["player"]["coins"]
	assert_bool(logic.start_car_task(car, 3, NOW).ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins - 5)
	assert_str(logic.start_car_task(car, 3, NOW).error).is_equal("This car is already out on a job.")
	assert_str(logic.sell_car(car, NOW).error).is_equal("This car is out on a job.")
	assert_str(logic.put_car_on_bay(car, TestEnv.first_bay(logic)).error).is_equal("This car is out on a job.")
	assert_str(logic.collect_car_task(car, NOW + 60).error).is_equal("The job isn't finished yet.")
	var r := logic.collect_car_task(car, NOW + 5 * 60)
	assert_bool(r.ok).is_true()
	assert_int(r.data["coins"]).is_equal(40)
	assert_int(logic.save["player"]["coins"]).is_equal(coins - 5 + 40)
	assert_int(logic.save["job_mastery"]["3"]).is_equal(1)
	assert_bool(logic.save["car_tasks"].is_empty()).is_true()


func test_car_task_rejects_ineligible_car() -> void:
	var logic := TestEnv.logic(10000)
	assert_str(logic.start_car_task(_car_of_model(logic, 2), 3, NOW).error).is_equal("This car can't do that job.")


func test_car_tasks_share_workers_with_bay_jobs() -> void:
	var logic := _logic_with_car_on_bay()
	logic.save["player"]["level"] = 1 # 2 workers
	assert_bool(logic.start_job(TestEnv.first_bay(logic), 4, NOW).ok).is_true()
	assert_bool(logic.start_car_task(_car_of_model(logic, 3), 3, NOW).ok).is_true()
	assert_str(logic.start_car_task(_car_of_model(logic, 3), 3, NOW).error).contains("workers are busy")


func test_stop_and_finish_car_task_now() -> void:
	var logic := TestEnv.logic(10000)
	var car := _car_of_model(logic, 3)
	logic.start_car_task(car, 3, NOW)
	assert_bool(logic.stop_car_task(car).ok).is_true()
	assert_bool(logic.save["car_tasks"].is_empty()).is_true()
	logic.start_car_task(car, 3, NOW)
	var blue: int = logic.save["player"]["blue"]
	assert_int(logic.car_task_finish_price(car, NOW)).is_equal(1)
	assert_bool(logic.finish_car_task_now(car, NOW).ok).is_true()
	assert_int(logic.save["player"]["blue"]).is_equal(blue - 1)
