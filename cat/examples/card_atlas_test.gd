extends Node2D

## Example: Card Atlas System Test
## Demonstrates how to use the new atlas-based card system with pooling

func _ready():
	# Card pool is automatically initialized by Cluster
	# Create a deck manager
	var deck_manager = DeckManager.new()

	# Create and shuffle a deck
	var deck = deck_manager.create_deck_with_custom()
	deck_manager.shuffle_deck(deck)

	print("Created and shuffled deck with ", deck.size(), " cards")

	# Display first 10 cards in a grid
	var cards_to_show = 10
	var spacing = 110  # Card width (96) + margin

	for i in range(min(cards_to_show, deck.size())):
		var card = deck_manager.draw_card(deck)
		if card:
			add_child(card)
			card.position = Vector2(
				(i % 5) * spacing + 100,  # 5 cards per row
				(i / 5) * 160 + 100       # Card height (144) + margin
			)
			print("Card ", i, ": ", card.get_card_name())

	# Example: Change a card after 2 seconds
	await get_tree().create_timer(2.0).timeout
	if get_child_count() > 0:
		var first_card = get_child(0) as PooledCard
		if first_card:
			print("Changing first card to King of Hearts...")
			first_card.init_card(PlayingDeckAtlas.Suit.HEARTS, 13)

	# Return remaining cards to pool after 5 seconds
	await get_tree().create_timer(5.0).timeout
	print("Returning deck to pool...")
	deck_manager.return_deck(deck)
