extends Node
class_name PlayingDeck

# Playing card deck with 4 suits
# Index 0 = card blank
# Index 1-13 = Ace through King

var spades: Array[Texture2D] = [
	preload("res://nodes/cards/playing/card-blank.png"),   # 0 - Card blank
	preload("res://nodes/cards/playing/card-spades-1.png"),  # 1 - Ace
	preload("res://nodes/cards/playing/card-spades-2.png"),  # 2
	preload("res://nodes/cards/playing/card-spades-3.png"),  # 3
	preload("res://nodes/cards/playing/card-spades-4.png"),  # 4
	preload("res://nodes/cards/playing/card-spades-5.png"),  # 5
	preload("res://nodes/cards/playing/card-spades-6.png"),  # 6
	preload("res://nodes/cards/playing/card-spades-7.png"),  # 7
	preload("res://nodes/cards/playing/card-spades-8.png"),  # 8
	preload("res://nodes/cards/playing/card-spades-9.png"),  # 9
	preload("res://nodes/cards/playing/card-spades-10.png"), # 10
	preload("res://nodes/cards/playing/card-spades-11.png"), # 11 - Jack
	preload("res://nodes/cards/playing/card-spades-12.png"), # 12 - Queen
	preload("res://nodes/cards/playing/card-spades-13.png"), # 13 - King
]

var hearts: Array[Texture2D] = [
	preload("res://nodes/cards/playing/card-blank.png"),   # 0 - Card blank
	preload("res://nodes/cards/playing/card-hearts-1.png"),  # 1 - Ace
	preload("res://nodes/cards/playing/card-hearts-2.png"),  # 2
	preload("res://nodes/cards/playing/card-hearts-3.png"),  # 3
	preload("res://nodes/cards/playing/card-hearts-4.png"),  # 4
	preload("res://nodes/cards/playing/card-hearts-5.png"),  # 5
	preload("res://nodes/cards/playing/card-hearts-6.png"),  # 6
	preload("res://nodes/cards/playing/card-hearts-7.png"),  # 7
	preload("res://nodes/cards/playing/card-hearts-8.png"),  # 8
	preload("res://nodes/cards/playing/card-hearts-9.png"),  # 9
	preload("res://nodes/cards/playing/card-hearts-10.png"), # 10
	preload("res://nodes/cards/playing/card-hearts-11.png"), # 11 - Jack
	preload("res://nodes/cards/playing/card-hearts-12.png"), # 12 - Queen
	preload("res://nodes/cards/playing/card-hearts-13.png"), # 13 - King
]

var diamonds: Array[Texture2D] = [
	preload("res://nodes/cards/playing/card-blank.png"),     # 0 - Card blank
	preload("res://nodes/cards/playing/card-diamonds-1.png"),  # 1 - Ace
	preload("res://nodes/cards/playing/card-diamonds-2.png"),  # 2
	preload("res://nodes/cards/playing/card-diamonds-3.png"),  # 3
	preload("res://nodes/cards/playing/card-diamonds-4.png"),  # 4
	preload("res://nodes/cards/playing/card-diamonds-5.png"),  # 5
	preload("res://nodes/cards/playing/card-diamonds-6.png"),  # 6
	preload("res://nodes/cards/playing/card-diamonds-7.png"),  # 7
	preload("res://nodes/cards/playing/card-diamonds-8.png"),  # 8
	preload("res://nodes/cards/playing/card-diamonds-9.png"),  # 9
	preload("res://nodes/cards/playing/card-diamonds-10.png"), # 10
	preload("res://nodes/cards/playing/card-diamonds-11.png"), # 11 - Jack
	preload("res://nodes/cards/playing/card-diamonds-12.png"), # 12 - Queen
	preload("res://nodes/cards/playing/card-diamonds-13.png"), # 13 - King
]

var clubs: Array[Texture2D] = [
	preload("res://nodes/cards/playing/card-blank.png"),   # 0 - Card blank
	preload("res://nodes/cards/playing/card-clubs-1.png"),  # 1 - Ace
	preload("res://nodes/cards/playing/card-clubs-2.png"),  # 2
	preload("res://nodes/cards/playing/card-clubs-3.png"),  # 3
	preload("res://nodes/cards/playing/card-clubs-4.png"),  # 4
	preload("res://nodes/cards/playing/card-clubs-5.png"),  # 5
	preload("res://nodes/cards/playing/card-clubs-6.png"),  # 6
	preload("res://nodes/cards/playing/card-clubs-7.png"),  # 7
	preload("res://nodes/cards/playing/card-clubs-8.png"),  # 8
	preload("res://nodes/cards/playing/card-clubs-9.png"),  # 9
	preload("res://nodes/cards/playing/card-clubs-10.png"), # 10
	preload("res://nodes/cards/playing/card-clubs-11.png"), # 11 - Jack
	preload("res://nodes/cards/playing/card-clubs-12.png"), # 12 - Queen
	preload("res://nodes/cards/playing/card-clubs-13.png"), # 13 - King
]

# Enum for suits
enum Suit {
	SPADES,
	HEARTS,
	DIAMONDS,
	CLUBS
}

# Helper function to get a card texture
func get_card(suit: Suit, value: int) -> Texture2D:
	match suit:
		Suit.SPADES:
			return spades[value]
		Suit.HEARTS:
			return hearts[value]
		Suit.DIAMONDS:
			return diamonds[value]
		Suit.CLUBS:
			return clubs[value]
	return null

# Get card blank texture
func get_card_blank() -> Texture2D:
	return spades[0]

# Get all cards in a suit
func get_suit(suit: Suit) -> Array[Texture2D]:
	match suit:
		Suit.SPADES:
			return spades
		Suit.HEARTS:
			return hearts
		Suit.DIAMONDS:
			return diamonds
		Suit.CLUBS:
			return clubs
	return []
