extends Node

## Card Deck Manager (Autoload Singleton)
## NEW: Uses atlas-based pooled cards for efficiency
## Manages decks using the Cluster pool system

# Deck instances
var active_decks: Dictionary = {}  # deck_id -> DeckManager instance
var next_deck_id: int = 0

func _ready() -> void:
	# Card pool is automatically initialized in Cluster._setup_pools()
	print("CardDeck: Ready! Using atlas-based pooling system")

## Create a new deck
## Returns a deck_id that can be used to reference this deck
func create_deck(include_custom: bool = false) -> int:
	var deck_manager = DeckManager.new()
	var deck_id = next_deck_id
	next_deck_id += 1

	var deck_data = {
		"manager": deck_manager,
		"cards": deck_manager.create_deck_with_custom() if include_custom else deck_manager.create_deck(),
		"drawn_cards": []
	}

	active_decks[deck_id] = deck_data
	deck_manager.shuffle_deck(deck_data["cards"])

	return deck_id

## Draw a card from a deck
func draw_card(deck_id: int) -> PooledCard:
	if not active_decks.has(deck_id):
		push_error("CardDeck: Invalid deck_id %d" % deck_id)
		return null

	var deck_data = active_decks[deck_id]
	var card = deck_data["manager"].draw_card(deck_data["cards"])

	if card:
		deck_data["drawn_cards"].append(card)

	return card

## Return a card to the deck
func return_card_to_deck(deck_id: int, card: PooledCard) -> void:
	if not active_decks.has(deck_id):
		push_error("CardDeck: Invalid deck_id %d" % deck_id)
		return

	var deck_data = active_decks[deck_id]
	deck_data["drawn_cards"].erase(card)
	deck_data["cards"].append(card)

## Shuffle a deck
func shuffle_deck(deck_id: int) -> void:
	if not active_decks.has(deck_id):
		push_error("CardDeck: Invalid deck_id %d" % deck_id)
		return

	var deck_data = active_decks[deck_id]
	deck_data["manager"].shuffle_deck(deck_data["cards"])

## Get cards remaining in deck
func get_cards_remaining(deck_id: int) -> int:
	if not active_decks.has(deck_id):
		return 0
	return active_decks[deck_id]["cards"].size()

## Destroy a deck and return all cards to pool
func destroy_deck(deck_id: int) -> void:
	if not active_decks.has(deck_id):
		return

	var deck_data = active_decks[deck_id]

	# Return all drawn cards to pool
	for card in deck_data["drawn_cards"]:
		if card and is_instance_valid(card):
			card.reset_for_pool()
			Cluster.release("playing_card", card)

	# Return all remaining cards to pool
	deck_data["manager"].return_deck(deck_data["cards"])

	active_decks.erase(deck_id)

## Reset deck (return drawn cards back to deck)
func reset_deck(deck_id: int) -> void:
	if not active_decks.has(deck_id):
		return

	var deck_data = active_decks[deck_id]

	# Move drawn cards back to deck
	for card in deck_data["drawn_cards"]:
		deck_data["cards"].append(card)

	deck_data["drawn_cards"].clear()
	shuffle_deck(deck_id)

## Clean up all decks on exit
func _exit_tree() -> void:
	var deck_ids = active_decks.keys()
	for deck_id in deck_ids:
		destroy_deck(deck_id)
