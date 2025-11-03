extends Node
class_name DeckManager

## Deck Manager using Pool/Cluster system
## Efficiently manages decks of cards using object pooling
## NEW: Decks store card DATA (suit/value), not PooledCard instances
## PooledCard instances are only acquired when cards are drawn

# Cluster configuration
const POOL_NAME = "playing_card"

# Card data structure (lightweight)
class CardData:
	var suit: int = -1
	var value: int = -1
	var is_custom: bool = false
	var custom_id: int = -1

	func _init(p_suit: int = -1, p_value: int = -1, p_is_custom: bool = false, p_custom_id: int = -1):
		suit = p_suit
		value = p_value
		is_custom = p_is_custom
		custom_id = p_custom_id

## Note: The card pool is automatically initialized in Cluster._setup_pools()
## No need to manually call init_pool() anymore!

## Create a standard 52-card deck (returns card DATA, not instances)
## Returns an array of CardData
func create_deck() -> Array[CardData]:
	var deck: Array[CardData] = []

	# Create all 52 standard cards as DATA
	for suit in range(4):  # Clubs, Diamonds, Hearts, Spades
		for value in range(1, 14):  # Ace through King
			deck.append(CardData.new(suit, value, false, -1))

	return deck

## Create a deck with custom cards included
func create_deck_with_custom() -> Array[CardData]:
	var deck = create_deck()

	# Add Viking card data
	deck.append(CardData.new(-1, -1, true, CardAtlas.CARD_VIKINGS))

	# Add Dino card data
	deck.append(CardData.new(-1, -1, true, CardAtlas.CARD_DINO))

	# Add Baron card data
	deck.append(CardData.new(-1, -1, true, CardAtlas.CARD_BARON))

	# Add Skull Wizard card data
	deck.append(CardData.new(-1, -1, true, CardAtlas.CARD_SKULL_WIZARD))

	# Add Warrior card data
	deck.append(CardData.new(-1, -1, true, CardAtlas.CARD_WARRIOR))

	# Add Fireworm card data
	deck.append(CardData.new(-1, -1, true, CardAtlas.CARD_FIREWORM))

	return deck

## Shuffle a deck in-place
func shuffle_deck(deck: Array[CardData]) -> void:
	for i in range(deck.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp

## Return all cards in a deck back to the pool (NOT NEEDED ANYMORE - cards returned individually)
func return_deck(deck: Array[CardData]) -> void:
	# CardData is lightweight, just clear the array
	deck.clear()

## Draw a card from the deck (acquires PooledCard instance on-demand)
func draw_card(deck: Array[CardData]) -> PooledCard:
	if deck.size() > 0:
		var card_data = deck.pop_back()

		# Acquire PooledCard instance from pool NOW (not during deck creation)
		var card = Cluster.acquire(POOL_NAME) as PooledCard
		if card:
			if card_data.is_custom:
				card.init_custom_card(card_data.custom_id)
			else:
				card.init_card(card_data.suit, card_data.value)
			return card
		else:
			push_error("DeckManager: Failed to acquire card from pool")
			return null
	return null

## Example usage:
## # In an autoload or main scene _ready():
## DeckManager.init_pool()
##
## # Later, when you need a deck:
## var deck_manager = DeckManager.new()
## var my_deck = deck_manager.create_deck()
## deck_manager.shuffle_deck(my_deck)
##
## # Draw cards
## var card1 = deck_manager.draw_card(my_deck)
## var card2 = deck_manager.draw_card(my_deck)
## add_child(card1)
## add_child(card2)
##
## # When done, return cards to pool
## deck_manager.return_deck(my_deck)
