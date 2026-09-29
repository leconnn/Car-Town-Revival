class_name SimpleRng
extends RefCounted
## Tiny deterministic generator (31-bit LCG) used by game rules, so the same
## results can be reproduced by the online server code.

const MODULUS := 2147483648 # 2^31
const MULTIPLIER := 1103515245
const INCREMENT := 12345


## Next state (and value) in [0, 2^31).
static func next(state: int) -> int:
	return (state * MULTIPLIER + INCREMENT) % MODULUS


## Returns [new_state, value in [low, high]].
static func range_int(state: int, low: int, high: int) -> Array[int]:
	var s := next(state)
	return [s, low + (s >> 8) % (high - low + 1)]
