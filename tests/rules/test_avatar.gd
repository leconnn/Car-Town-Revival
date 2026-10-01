extends GdUnitTestSuite
## Your avatar: free pieces, bought pieces, and the setting digits.

const NOW := TestEnv.NOW
## Fixture avatar items: free ones (eyes 1, hair 33/44, tops 53/54, pants 57/58,
## skirt 74, hats 49/77...), the Birthday Cupcake Shirt (top 164, 500 coins)
## and the Radiation Helmet (hat 120), which was never for sale.


func test_new_game_wears_the_default_look() -> void:
	var logic := TestEnv.logic(100000)
	assert_that(logic.save["avatar"]).is_equal(GameLogic.default_avatar())


func test_free_pieces_can_be_worn() -> void:
	var logic := TestEnv.logic(100000)
	assert_bool(logic.set_avatar_part(8, 54, 0).ok).is_true()
	assert_int(logic.save["avatar"]["top"]).is_equal(54)
	# Skirts and pants share the bottom.
	assert_bool(logic.set_avatar_part(12, 74, 0).ok).is_true()
	assert_int(logic.save["avatar"]["bottom"]).is_equal(74)
	assert_str(logic.set_avatar_part(8, 57, 0).error).is_equal("That doesn't go there.")
	assert_str(logic.set_avatar_part(8, 0, 0).error).is_equal("That can't be left off.")
	assert_bool(logic.set_avatar_part(7, 0, 0).ok).is_true()


func test_settings_and_colours() -> void:
	var logic := TestEnv.logic(100000)
	assert_bool(logic.set_avatar_part(11, 68, 50000).ok).is_true()
	assert_int(logic.save["avatar"]["settings"]["head"]).is_equal(50000)
	assert_str(logic.set_avatar_part(11, 68, 90000).error).is_equal("Bad colour.")
	assert_str(logic.set_avatar_part(1, 1, 100000).error).is_equal("Bad setting.")


func test_buying_a_piece() -> void:
	var logic := TestEnv.logic(100000)
	var coins: int = logic.save["player"]["coins"]
	assert_str(logic.set_avatar_part(8, 164, 0).error).is_equal("Buy it first.")
	assert_str(logic.buy_avatar_item(120, false, NOW).error).is_equal("That isn't for sale.")
	assert_bool(logic.buy_avatar_item(164, false, NOW).ok).is_true()
	assert_int(logic.save["player"]["coins"]).is_equal(coins - 500)
	assert_str(logic.buy_avatar_item(164, false, NOW).error).is_equal("You already have that.")
	assert_str(logic.buy_avatar_item(53, false, NOW).error).is_equal("You already have that.")
	assert_bool(logic.set_avatar_part(8, 164, 0).ok).is_true()
