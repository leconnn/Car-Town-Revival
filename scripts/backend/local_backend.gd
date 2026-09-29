class_name LocalBackend
extends BackendImpl
## Single-player: rules run on this PC and the save is a file in a slot.

var catalog: Catalog
var store: SaveStore
var slot: int = -1
var logic: GameLogic


func _init(cat: Catalog, save_store: SaveStore) -> void:
	catalog = cat
	store = save_store


func new_game(slot_index: int, player_name: String) -> bool:
	slot = slot_index
	logic = GameLogic.new(catalog, GameLogic.new_save(catalog, player_name, now()))
	return _persist()


func load_game(slot_index: int, errors: Array[String] = []) -> bool:
	var data := store.load_slot(slot_index, errors)
	if data.is_empty():
		return false
	slot = slot_index
	logic = GameLogic.new(catalog, data)
	return true


func is_ready() -> bool:
	return logic != null


func state() -> Dictionary:
	return logic.save if logic != null else {}


func act(action: String, args: Array) -> GameResult:
	if logic == null:
		return GameResult.fail("No game is running.")
	var result := BackendImpl.run_on(logic, action, args, now())
	if not result.ok:
		return result
	# Ticks only matter when a customer arrived; skip the disk write otherwise.
	if action != "tick" or result.data.get("arrived", 0) > 0:
		_persist()
		state_changed.emit()
	for n: Dictionary in result.notices:
		notice.emit(n)
	return result


func _persist() -> bool:
	return store.write_slot(slot, logic.save)


func shutdown() -> void:
	if logic != null:
		_persist()
	logic = null
