extends Node
class_name CardComboBridgeClass

## Bridge between GDScript and Rust CardComboDetector
## Detects poker hands and calculates bonuses
## Accessed via CardComboBridge singleton (autoload)
##
## USAGE EXAMPLE:
## ```gdscript
## # 1. Collect cards with hex positions
## var cards = []
## for card_node in placed_cards:
##     var card_dict = CardComboBridge.create_card_dict(
##         card_node.ulid,
##         card_node.suit,
##         card_node.value,
##         card_node.card_id,
##         card_node.hex_x,
##         card_node.hex_y,
##         card_node.is_custom  # Jokers are custom cards
##     )
##     cards.append(card_dict)
##
## # 2. Request combo detection (ASYNC - runs on worker thread)
## var request_id = CardComboBridge.request_combo_detection(cards, _on_combo_result)
##
## # 3. Handle result in callback
## func _on_combo_result(result: Dictionary):
##     # Highlight cards in the combo
##     if result.has("card_indices"):
##         for idx in result["card_indices"]:
##             var card = placed_cards[idx]
##             if card is PooledCard:
##                 card.highlight_combo()
##
##     # Show popup and apply resources
##     if result.has("hand_name"):
##         ComboPopup.show_combo(result)
##         ComboPopup.apply_combo_resources(result)
## ```
##
## RESOURCE MAPPING:
## - Diamonds (♦) → Gold
## - Hearts (♥) → Food
## - Spades (♠) → Labor
## - Clubs (♣) → Faith
##
## COMBO DETECTION:
## - Cards must be in STRAIGHT LINES on hex grid (6 directions)
## - Jokers (custom cards) can be skipped in the middle
## - Example: 4♠-Joker-5♠-6♠-7♠-8♠ = valid 5-card straight
## - Bonus = base_amount (10) × card_count × hand_multiplier

# Signals
signal combo_detected(request_id: int, result: Dictionary)

# Rust combo detector (typed as Variant since it's a Rust class loaded at runtime)
var combo_detector = null
var pending_requests: Dictionary = {}  # request_id -> callback

func _ready() -> void:
	# Create the Rust combo detector
	combo_detector = ClassDB.instantiate("CardComboDetector")

	if combo_detector == null:
		push_error("CardComboBridge: Failed to instantiate CardComboDetector from Rust!")
		push_error("Make sure the Rust extension is compiled and loaded.")
		return

	# Add as child to enable process() calls
	if combo_detector is Node:
		add_child(combo_detector)
	else:
		push_error("CardComboBridge: CardComboDetector is not a Node! Cannot add as child.")
		return

	# Connect to signal from Rust
	if combo_detector.has_signal("combo_found"):
		combo_detector.connect("combo_found", _on_combo_found)
	else:
		push_error("CardComboBridge: CardComboDetector missing 'combo_found' signal!")

	# Start worker thread
	if combo_detector.has_method("start_worker"):
		combo_detector.start_worker()
	else:
		push_error("CardComboBridge: CardComboDetector missing 'start_worker' method!")

	print("CardComboBridge: Initialized with worker thread")

func _exit_tree() -> void:
	if combo_detector:
		combo_detector.stop_worker()

## Callback when Rust thread finishes combo detection
func _on_combo_found(request_id: int, result: Dictionary) -> void:
	# Call callback if registered
	if pending_requests.has(request_id):
		var callback = pending_requests[request_id]
		pending_requests.erase(request_id)
		callback.call(result)

	# Emit signal
	combo_detected.emit(request_id, result)

## Request combo detection (ASYNC - result via callback or signal)
## Each dictionary should have: ulid, suit, value, card_id, is_custom, x, y (hex position)
## Jokers (custom cards) can be in the line and will be skipped
## Returns request_id for tracking
func request_combo_detection(cards: Array[Dictionary], callback: Callable) -> int:
	if not combo_detector:
		push_error("CardComboBridge: Combo detector not initialized!")
		return 0

	if cards.size() < 5:
		push_warning("CardComboBridge: Need at least 5 cards to detect combo")
		return 0

	# Serialize cards to PackedByteArray for maximum performance
	var card_data = _serialize_cards(cards)

	if card_data.size() == 0:
		push_error("CardComboBridge: Failed to serialize cards")
		return 0

	# Request combo detection from Rust worker thread
	var request_id = combo_detector.request_combo_detection(card_data)

	# Register callback
	if request_id > 0:
		pending_requests[request_id] = callback

	return request_id

## Serialize cards to PackedByteArray
## Format per card (31 bytes): [16 ULID][1 suit][1 value][4 card_id][1 is_custom][4 x][4 y]
func _serialize_cards(cards: Array[Dictionary]) -> PackedByteArray:
	var buffer = PackedByteArray()
	buffer.resize(cards.size() * 31)

	var offset = 0
	for card in cards:
		# ULID (16 bytes)
		var ulid: PackedByteArray = card.get("ulid", PackedByteArray())
		if ulid.size() != 16:
			push_error("CardComboBridge: Invalid ULID size: %d" % ulid.size())
			return PackedByteArray()
		for i in range(16):
			buffer[offset + i] = ulid[i]

		# Suit (1 byte)
		buffer[offset + 16] = card.get("suit", 0)

		# Value (1 byte)
		buffer[offset + 17] = card.get("value", 0)

		# Card ID (4 bytes, little-endian)
		var card_id: int = card.get("card_id", 0)
		buffer[offset + 18] = card_id & 0xFF
		buffer[offset + 19] = (card_id >> 8) & 0xFF
		buffer[offset + 20] = (card_id >> 16) & 0xFF
		buffer[offset + 21] = (card_id >> 24) & 0xFF

		# Is Custom (1 byte)
		buffer[offset + 22] = 1 if card.get("is_custom", false) else 0

		# X position (4 bytes, little-endian)
		var x: int = card.get("x", 0)
		buffer[offset + 23] = x & 0xFF
		buffer[offset + 24] = (x >> 8) & 0xFF
		buffer[offset + 25] = (x >> 16) & 0xFF
		buffer[offset + 26] = (x >> 24) & 0xFF

		# Y position (4 bytes, little-endian)
		var y: int = card.get("y", 0)
		buffer[offset + 27] = y & 0xFF
		buffer[offset + 28] = (y >> 8) & 0xFF
		buffer[offset + 29] = (y >> 16) & 0xFF
		buffer[offset + 30] = (y >> 24) & 0xFF

		offset += 31

	return buffer

## Helper: Create card dictionary for detection (with hex position)
## Use this to build the cards array
func create_card_dict(ulid: PackedByteArray, suit: int, value: int, card_id: int, x: int, y: int, is_custom: bool = false) -> Dictionary:
	return {
		"ulid": ulid,
		"suit": suit,
		"value": value,
		"card_id": card_id,
		"is_custom": is_custom,
		"x": x,
		"y": y
	}

## Get hand rank name from rank number
func get_hand_name(rank: int) -> String:
	match rank:
		0: return "High Card"
		1: return "One Pair"
		2: return "Two Pair"
		3: return "Three of a Kind"
		4: return "Straight"
		5: return "Flush"
		6: return "Full House"
		7: return "Four of a Kind"
		8: return "Straight Flush"
		9: return "Royal Flush"
		_: return "Unknown"

## Get bonus multiplier from rank
func get_bonus_multiplier(rank: int) -> float:
	match rank:
		0: return 1.0   # High Card
		1: return 1.5   # One Pair
		2: return 2.0   # Two Pair
		3: return 3.0   # Three of a Kind
		4: return 4.0   # Straight
		5: return 5.0   # Flush
		6: return 7.0   # Full House
		7: return 10.0  # Four of a Kind
		8: return 20.0  # Straight Flush
		9: return 50.0  # Royal Flush
		_: return 1.0
