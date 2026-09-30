class_name CollectMoney
extends Node2D
## The original CollectMoney (components/ui/CollectMoney): what a collected
## job paid, floating up from its callout. A double-size coin and the
## amount, the XP in digit boxes under it; both rise 25 px over two seconds
## and fade out in the second one.

const TEXT_GLOW := Color8(0x68, 0x6F, 0x7F)
const DIGIT_STEP := 22.0
const RISE := 25.0


static func spawn(parent: Node, pos: Vector2, coins: int, xp: int) -> CollectMoney:
	var c := CollectMoney.new()
	c.position = pos
	parent.add_child(c)
	c._build(coins, xp)
	return c


func _build(coins: int, xp: int) -> void:
	var money := Node2D.new()
	add_child(money)
	var coin_w := 0.0
	var icon := FlashUi.make("UIIconCoin")
	if icon != null:
		var credit := icon.part("creditIcon") as CanvasItem
		if credit != null:
			credit.visible = false
		icon.scale = Vector2(2, 2)
		var r := icon.local_bounds()
		icon.position = -r.position * 2.0
		coin_w = r.size.x * 2.0
		money.add_child(icon)
	var amount := FlashUi.styled_label(Format.number(coins), "casualA01", 30, Color.WHITE, TEXT_GLOW, 5)
	amount.position = Vector2(coin_w - 1, -3)
	money.add_child(amount)
	var money_size := Vector2(amount.position.x + amount.get_minimum_size().x, maxf(coin_w, amount.get_minimum_size().y))

	var xp_node := Node2D.new()
	xp_node.position.y = money_size.y - 4
	add_child(xp_node)
	var digits := str(xp)
	var probe := FlashUi.make("UIXPSpriteBg")
	var bg_h := probe.local_bounds().size.y if probe != null else 30.0
	var xp_w := digits.length() * DIGIT_STEP + 30
	var bg := FlashNine.make("UIXPSpriteBg", Vector2(xp_w, bg_h))
	xp_node.add_child(bg)
	for i in digits.length():
		var d := FlashUi.make("UIXPDigit")
		if d == null:
			continue
		d.styled_text("digitField", digits[i], "sansD03")
		d.position = Vector2(15 + DIGIT_STEP * i, 3)
		xp_node.add_child(d)
	xp_node.visible = xp > 0

	if money_size.x > xp_w:
		xp_node.position.x = (money_size.x - xp_w) / 2.0
	else:
		money.position.x = (xp_w - money_size.x) / 2.0
	# Centred over the spot, sitting just above it.
	var w := maxf(money_size.x, xp_w)
	var h := money_size.y + (bg_h - 4 if xp > 0 else 0.0)
	position += Vector2(-w / 2.0, -h)

	var tw := create_tween().set_parallel()
	for n: Node2D in [money, xp_node]:
		tw.tween_property(n, "position:y", n.position.y - RISE, 2.0)
		tw.tween_property(n, "modulate:a", 0.0, 1.0).set_delay(1.0)
	tw.chain().tween_callback(queue_free)
