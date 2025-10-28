extends Node
class_name DeckManager

## Deck Manager using Pool/Cluster system
## Efficiently manages decks of cards using object pooling

# Cluster configuration
const POOL_NAME = "playing_card"

## Note: The card pool is automatically initialized in Cluster._setup_pools()
## No need to manually call init_pool() anymore!

## Create a standard 52-card deck
## Returns an array of PooledCard instances
func create_deck() -> Array[PooledCard]:
	var deck: Array[PooledCard] = []

	# Create all 52 standard cards
	for suit in range(4):  # Clubs, Diamonds, Hearts, Spades
		for value in range(1, 14):  # Ace through King
			var card = Cluster.acquire(POOL_NAME) as PooledCard
			if card:
				card.init_card(suit, value)
				deck.append(card)
			else:
				push_error("DeckManager: Failed to acquire card from pool")

	return deck

## Create a deck with custom cards included
func create_deck_with_custom() -> Array[PooledCard]:
	var deck = create_deck()

	# Add Viking card
	var viking_card = Cluster.acquire(POOL_NAME) as PooledCard
	if viking_card:
		viking_card.init_custom_card(CardAtlas.CARD_VIKINGS)
		deck.append(viking_card)

	# Add Dino card
	var dino_card = Cluster.acquire(POOL_NAME) as PooledCard
	if dino_card:
		dino_card.init_custom_card(CardAtlas.CARD_DINO)
		deck.append(dino_card)

	return deck

## Shuffle a deck in-place
func shuffle_deck(deck: Array[PooledCard]) -> void:
	for i in range(deck.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp

## Return all cards in a deck back to the pool
func return_deck(deck: Array[PooledCard]) -> void:
	for card in deck:
		if card:
			card.reset_for_pool()
			Cluster.release(POOL_NAME, card)
	deck.clear()

## Draw a card from the deck
func draw_card(deck: Array[PooledCard]) -> PooledCard:
	if deck.size() > 0:
		return deck.pop_back()
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
