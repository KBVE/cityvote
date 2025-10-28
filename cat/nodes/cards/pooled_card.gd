extends MeshInstance2D
class_name PooledCard

## Pooled playing card using atlas shader system
## Designed to work with the Cluster pool system for efficient card management

# Card properties
var suit: int = CardAtlas.Suit.CLUBS
var value: int = CardAtlas.ACE
var card_id: int = 0  # 0-51 for standard, 52+ for custom
var is_custom: bool = false

# Pool management
var pool_id: String = "playing_card"

func _ready():
	# All cards share the same material - no duplication needed!
	# Per-instance shader parameters handle uniqueness
	pass

## Initialize the card with a specific suit and value
func init_card(p_suit: int, p_value: int) -> void:
	suit = p_suit
	value = p_value
	is_custom = false
	card_id = CardAtlas.get_card_id(suit, value)

	# Use per-instance shader parameter - this allows all cards to share the same material
	# while each instance displays a different card. Great for batching!
	set_instance_shader_parameter("card_id", card_id)
	print("PooledCard: Set card_id to ", card_id, " (", get_card_name(), ")")

## Initialize as a custom card
func init_custom_card(p_card_id: int) -> void:
	assert(CardAtlas.is_custom_card(p_card_id), "Invalid custom card_id: %d (must be >= %d)" % [p_card_id, CardAtlas.CUSTOM_CARD_START])
	card_id = p_card_id
	is_custom = true
	suit = -1
	value = -1

	# Use per-instance shader parameter
	set_instance_shader_parameter("card_id", card_id)

## Reset the card for pooling (called when returned to pool)
func reset_for_pool() -> void:
	# Reset to default state
	suit = CardAtlas.Suit.CLUBS
	value = CardAtlas.ACE
	card_id = -1  # -1 indicates unused (hidden nodes don't draw anyway)
	is_custom = false
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	visible = false  # Hidden when in pool

	# Clear per-instance parameter (optional since it's hidden)
	set_instance_shader_parameter("card_id", -1)

## Get card name as string
func get_card_name() -> String:
	if is_custom:
		return CardAtlas.get_card_name_from_id(card_id)
	else:
		return CardAtlas.get_card_name(suit, value)
