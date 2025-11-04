extends Node

## Card Atlas Helper
## Provides utilities for working with the card atlas system

# Card atlas layout constants
const ATLAS_WIDTH = 1248
const ATLAS_HEIGHT = 720
const CARD_WIDTH = 96
const CARD_HEIGHT = 144
const COLS = 13
const ROWS = 5

# Card counts
const CARDS_PER_SUIT = 13  # Ace through King
const NUM_STANDARD_SUITS = 4  # Clubs, Diamonds, Hearts, Spades
const STANDARD_CARD_COUNT = CARDS_PER_SUIT * NUM_STANDARD_SUITS  # 52
const CUSTOM_CARD_START = STANDARD_CARD_COUNT  # 52

# Suit constants (matching row indices)
enum Suit {
	CLUBS = 0,
	DIAMONDS = 1,
	HEARTS = 2,
	SPADES = 3,
	CUSTOM = 4
}

# Card value constants
const ACE = 1
const JACK = 11
const QUEEN = 12
const KING = 13

# Custom card IDs (start at 52)
const CARD_VIKINGS = 52      # Custom row, position 0
const CARD_DINO = 53         # Custom row, position 1
const CARD_BARON = 54        # Custom row, position 2
const CARD_SKULL_WIZARD = 55 # Custom row, position 3
const CARD_WARRIOR = 56      # Custom row, position 4
const CARD_FIREWORM = 57     # Custom row, position 5
const CUSTOM_CARD_COUNT = 6  # Total number of custom cards
const TOTAL_CARD_COUNT = STANDARD_CARD_COUNT + CUSTOM_CARD_COUNT  # 58

## Convert suit and value to card_id for standard cards
## suit: 0-3 (CLUBS, DIAMONDS, HEARTS, SPADES)
## value: 1-13 (Ace through King)
## Returns: card_id (0-51)
func get_card_id(suit: int, value: int) -> int:
	assert(suit >= 0 and suit < NUM_STANDARD_SUITS, "Suit must be 0-%d" % (NUM_STANDARD_SUITS - 1))
	assert(value >= ACE and value <= KING, "Value must be %d-%d" % [ACE, KING])
	return suit * CARDS_PER_SUIT + (value - 1)

## Get card_id from suit enum and value
func get_card_id_from_suit(suit: Suit, value: int) -> int:
	if suit == Suit.CUSTOM:
		push_error("Use CARD_VIKINGS or CARD_DINO constants for custom cards")
		return 0
	return get_card_id(suit, value)

## Create a card material with the specified card_id
func create_card_material(card_id: int) -> ShaderMaterial:
	var shader = load("res://nodes/cards/card_atlas.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("card_id", card_id)
	return material

## Update an existing material to show a different card
func set_card(material: ShaderMaterial, card_id: int) -> void:
	material.set_shader_parameter("card_id", card_id)

## Get human-readable card name
func get_card_name(suit: int, value: int) -> String:
	if suit < 0 or suit > 3 or value < 1 or value > 13:
		return "Invalid Card"

	# Get translated suit name
	var suit_keys = ["card.suit.clubs", "card.suit.diamonds", "card.suit.hearts", "card.suit.spades"]
	var suit_name = I18n.translate(suit_keys[suit])

	# Get translated value name
	var value_name = ""
	if value == 1:
		value_name = I18n.translate("card.value.ace")
	elif value == 11:
		value_name = I18n.translate("card.value.jack")
	elif value == 12:
		value_name = I18n.translate("card.value.queen")
	elif value == 13:
		value_name = I18n.translate("card.value.king")
	else:
		value_name = str(value)

	# Handle Chinese language which doesn't use "of"
	var of_text = I18n.translate("card.of")
	if of_text == "":
		return "%s%s" % [value_name, suit_name]
	else:
		return "%s %s %s" % [value_name, of_text, suit_name]

## Get card name from card_id
func get_card_name_from_id(card_id: int) -> String:
	if card_id == CARD_VIKINGS:
		return I18n.translate("card.custom.viking")
	elif card_id == CARD_DINO:
		return I18n.translate("card.custom.dino")
	elif card_id == CARD_BARON:
		return I18n.translate("card.custom.baron")
	elif card_id == CARD_SKULL_WIZARD:
		return I18n.translate("card.custom.skull_wizard")
	elif card_id == CARD_WARRIOR:
		return I18n.translate("card.custom.warrior")
	elif card_id == CARD_FIREWORM:
		return I18n.translate("card.custom.fireworm")
	elif card_id >= 0 and card_id < STANDARD_CARD_COUNT:
		var suit = card_id / CARDS_PER_SUIT
		var value = (card_id % CARDS_PER_SUIT) + 1
		return get_card_name(suit, value)
	else:
		return I18n.translate("card.custom.generic")

## Check if a card_id is valid
func is_valid_card_id(card_id: int) -> bool:
	return card_id >= 0 and card_id < TOTAL_CARD_COUNT

## Check if a card_id is a custom card
func is_custom_card(card_id: int) -> bool:
	return card_id >= CUSTOM_CARD_START and card_id < TOTAL_CARD_COUNT

## Example usage:
## var material = CardAtlas.create_card_material(CardAtlas.get_card_id(CardAtlas.Suit.HEARTS, 1))
## sprite.material = material
