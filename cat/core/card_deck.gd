extends Node

# Card Deck Manager (Autoload Singleton)
# Manages a pool of 52 unique card sprites
# Prevents duplicate cards in play
# Cards can be in hand, on board, or available in deck

# Card state tracking
var available_cards: Array[Dictionary] = []  # Cards still in deck
var active_cards: Dictionary = {}  # Cards in play {card_id: sprite_node}
var card_sprites: Dictionary = {}  # All 52 card sprites {card_id: sprite_node}

func _ready() -> void:
	_initialize_card_pool()

# Initialize all 52 unique card sprites
func _initialize_card_pool() -> void:
	# Preload all card textures
	var card_textures = {
		0: {  # Spades
			1: preload("res://nodes/cards/playing/card-spades-1.png"),
			2: preload("res://nodes/cards/playing/card-spades-2.png"),
			3: preload("res://nodes/cards/playing/card-spades-3.png"),
			4: preload("res://nodes/cards/playing/card-spades-4.png"),
			5: preload("res://nodes/cards/playing/card-spades-5.png"),
			6: preload("res://nodes/cards/playing/card-spades-6.png"),
			7: preload("res://nodes/cards/playing/card-spades-7.png"),
			8: preload("res://nodes/cards/playing/card-spades-8.png"),
			9: preload("res://nodes/cards/playing/card-spades-9.png"),
			10: preload("res://nodes/cards/playing/card-spades-10.png"),
			11: preload("res://nodes/cards/playing/card-spades-11.png"),
			12: preload("res://nodes/cards/playing/card-spades-12.png"),
			13: preload("res://nodes/cards/playing/card-spades-13.png"),
		},
		1: {  # Hearts
			1: preload("res://nodes/cards/playing/card-hearts-1.png"),
			2: preload("res://nodes/cards/playing/card-hearts-2.png"),
			3: preload("res://nodes/cards/playing/card-hearts-3.png"),
			4: preload("res://nodes/cards/playing/card-hearts-4.png"),
			5: preload("res://nodes/cards/playing/card-hearts-5.png"),
			6: preload("res://nodes/cards/playing/card-hearts-6.png"),
			7: preload("res://nodes/cards/playing/card-hearts-7.png"),
			8: preload("res://nodes/cards/playing/card-hearts-8.png"),
			9: preload("res://nodes/cards/playing/card-hearts-9.png"),
			10: preload("res://nodes/cards/playing/card-hearts-10.png"),
			11: preload("res://nodes/cards/playing/card-hearts-11.png"),
			12: preload("res://nodes/cards/playing/card-hearts-12.png"),
			13: preload("res://nodes/cards/playing/card-hearts-13.png"),
		},
		2: {  # Diamonds
			1: preload("res://nodes/cards/playing/card-diamonds-1.png"),
			2: preload("res://nodes/cards/playing/card-diamonds-2.png"),
			3: preload("res://nodes/cards/playing/card-diamonds-3.png"),
			4: preload("res://nodes/cards/playing/card-diamonds-4.png"),
			5: preload("res://nodes/cards/playing/card-diamonds-5.png"),
			6: preload("res://nodes/cards/playing/card-diamonds-6.png"),
			7: preload("res://nodes/cards/playing/card-diamonds-7.png"),
			8: preload("res://nodes/cards/playing/card-diamonds-8.png"),
			9: preload("res://nodes/cards/playing/card-diamonds-9.png"),
			10: preload("res://nodes/cards/playing/card-diamonds-10.png"),
			11: preload("res://nodes/cards/playing/card-diamonds-11.png"),
			12: preload("res://nodes/cards/playing/card-diamonds-12.png"),
			13: preload("res://nodes/cards/playing/card-diamonds-13.png"),
		},
		3: {  # Clubs
			1: preload("res://nodes/cards/playing/card-clubs-1.png"),
			2: preload("res://nodes/cards/playing/card-clubs-2.png"),
			3: preload("res://nodes/cards/playing/card-clubs-3.png"),
			4: preload("res://nodes/cards/playing/card-clubs-4.png"),
			5: preload("res://nodes/cards/playing/card-clubs-5.png"),
			6: preload("res://nodes/cards/playing/card-clubs-6.png"),
			7: preload("res://nodes/cards/playing/card-clubs-7.png"),
			8: preload("res://nodes/cards/playing/card-clubs-8.png"),
			9: preload("res://nodes/cards/playing/card-clubs-9.png"),
			10: preload("res://nodes/cards/playing/card-clubs-10.png"),
			11: preload("res://nodes/cards/playing/card-clubs-11.png"),
			12: preload("res://nodes/cards/playing/card-clubs-12.png"),
			13: preload("res://nodes/cards/playing/card-clubs-13.png"),
		}
	}

	for suit in range(4):  # 4 suits
		for value in range(1, 14):  # 1-13 (Ace through King)
			var card_id = _get_card_id(suit, value)
			var card_data = {
				"suit": suit,
				"value": value,
				"id": card_id
			}

			# Create sprite for this card
			var sprite = Sprite2D.new()
			sprite.texture = card_textures[suit][value]
			sprite.name = "Card_%s" % card_id
			sprite.hide()
			sprite.set_process(false)
			add_child(sprite)

			# Store in registry
			card_sprites[card_id] = sprite
			available_cards.append(card_data)

	print("CardDeck initialized: 52 unique cards created")

# Get unique card ID (e.g., "spades_8", "hearts_13")
func _get_card_id(suit: int, value: int) -> String:
	var suit_name = ""
	match suit:
		0:  # Spades
			suit_name = "spades"
		1:  # Hearts
			suit_name = "hearts"
		2:  # Diamonds
			suit_name = "diamonds"
		3:  # Clubs
			suit_name = "clubs"
	return "%s_%d" % [suit_name, value]

# Draw a random card from available cards
func draw_card() -> Dictionary:
	if available_cards.is_empty():
		push_warning("CardDeck: No cards available to draw!")
		return {}

	# Draw random card
	var index = randi() % available_cards.size()
	var card_data = available_cards[index]
	available_cards.remove_at(index)

	# Mark as active
	var card_id = card_data["id"]
	var sprite = card_sprites[card_id]
	active_cards[card_id] = sprite

	# Prepare sprite for use
	sprite.show()
	sprite.set_process(true)

	return card_data

# Get the sprite for a specific card
func get_card_sprite(suit: int, value: int) -> Sprite2D:
	var card_id = _get_card_id(suit, value)
	if card_id in card_sprites:
		return card_sprites[card_id]
	return null

# Return a card to the available pool
func return_card(suit: int, value: int) -> void:
	var card_id = _get_card_id(suit, value)

	if card_id not in active_cards:
		push_warning("CardDeck: Trying to return card that's not active: %s" % card_id)
		return

	# Remove from active
	var sprite = active_cards[card_id]
	active_cards.erase(card_id)

	# Add back to available
	var card_data = {
		"suit": suit,
		"value": value,
		"id": card_id
	}
	available_cards.append(card_data)

	# Reset sprite
	sprite.hide()
	sprite.set_process(false)
	if sprite.get_parent():
		sprite.get_parent().remove_child(sprite)
	add_child(sprite)
	sprite.position = Vector2.ZERO
	sprite.rotation = 0
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE

# Shuffle the available cards
func shuffle() -> void:
	available_cards.shuffle()

# Get count of available cards
func get_available_count() -> int:
	return available_cards.size()

# Get count of active cards
func get_active_count() -> int:
	return active_cards.size()

# Check if a specific card is available
func is_card_available(suit: int, value: int) -> bool:
	var card_id = _get_card_id(suit, value)
	for card_data in available_cards:
		if card_data["id"] == card_id:
			return true
	return false

# Reset deck (return all cards)
func reset_deck() -> void:
	# Return all active cards
	var active_ids = active_cards.keys()
	for card_id in active_ids:
		var sprite = active_cards[card_id]

		# Parse card_id back to suit/value
		var parts = card_id.split("_")
		var suit_name = parts[0]
		var value = int(parts[1])
		var suit = 0
		match suit_name:
			"spades":
				suit = 0
			"hearts":
				suit = 1
			"diamonds":
				suit = 2
			"clubs":
				suit = 3

		return_card(suit, value)

	shuffle()
	print("CardDeck: Reset complete, %d cards available" % available_cards.size())
