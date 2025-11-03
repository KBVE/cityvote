extends Node

# Bridge between GDScript and Rust CardRegistry system
# Manages cards placed on the hex board

var card_registry: Node = null

func _ready() -> void:
	# Create the Rust card registry
	card_registry = ClassDB.instantiate("CardRegistryBridge")

	if card_registry == null:
		push_error("CardRegistryBridge: Failed to instantiate from Rust!")
		return

	add_child(card_registry)

# === PUBLIC API ===

## Place a card on the board at specific hex coordinates
## Returns true if successful, false if position is occupied
func place_card(x: int, y: int, ulid: PackedByteArray, suit: int, value: int, is_custom: bool, card_id: int) -> bool:
	if not card_registry:
		push_error("CardRegistryBridge: Not initialized!")
		return false
	return card_registry.place_card(x, y, ulid, suit, value, is_custom, card_id)

## Remove a card from the board by position
## Returns Dictionary with card data if found, empty Dictionary otherwise
func remove_card_at(x: int, y: int) -> Dictionary:
	if not card_registry:
		return {}
	return card_registry.remove_card_at(x, y)

## Remove a card from the board by ULID
func remove_card_by_ulid(ulid: PackedByteArray) -> Dictionary:
	if not card_registry:
		return {}
	return card_registry.remove_card_by_ulid(ulid)

## Move a card from one position to another
func move_card(from_x: int, from_y: int, to_x: int, to_y: int) -> bool:
	if not card_registry:
		return false
	return card_registry.move_card(from_x, from_y, to_x, to_y)

## Get card at specific position
func get_card_at(x: int, y: int) -> Dictionary:
	if not card_registry:
		return {}
	return card_registry.get_card_at(x, y)

## Get card by ULID
func get_card_by_ulid(ulid: PackedByteArray) -> Dictionary:
	if not card_registry:
		return {}
	return card_registry.get_card_by_ulid(ulid)

## Get position of a card by ULID
## Returns Vector2i with position, or (-1, -1) if not found
func get_position(ulid: PackedByteArray) -> Vector2i:
	if not card_registry:
		return Vector2i(-1, -1)
	return card_registry.get_position(ulid)

## Check if position has a card
func has_card_at(x: int, y: int) -> bool:
	if not card_registry:
		return false
	return card_registry.has_card_at(x, y)

## Get all cards within a radius
## Returns Array of Dictionaries with keys: x, y, card
func get_cards_in_radius(center_x: int, center_y: int, radius: int) -> Array:
	if not card_registry:
		return []
	return card_registry.get_cards_in_radius(center_x, center_y, radius)

## Get all cards in a rectangular area
func get_cards_in_area(min_x: int, min_y: int, max_x: int, max_y: int) -> Array:
	if not card_registry:
		return []
	return card_registry.get_cards_in_area(min_x, min_y, max_x, max_y)

## Get all cards on the board
func get_all_cards() -> Array:
	if not card_registry:
		return []
	return card_registry.get_all_cards()

## Get count of cards on board
func count() -> int:
	if not card_registry:
		return 0
	return card_registry.count()

## Clear all cards from the board
func clear() -> void:
	if card_registry:
		card_registry.clear()

## Update card state
func update_card_state(ulid: PackedByteArray, state: String) -> bool:
	if not card_registry:
		return false
	return card_registry.update_card_state(ulid, state)

## Debug: Print all cards on board
func print_cards() -> void:
	if card_registry:
		card_registry.print_cards()
