extends MeshInstance2D
class_name PooledCard

## Pooled playing card using HYBRID rendering system:
## - Static cards (hand, placed tiles): Use mesh swapping with baked UVs (~200 bytes/card)
## - Dynamic cards (tile info ghost): Use shader parameters (~5KB/card)
## Designed to work with the Cluster pool system for efficient card management

# Card properties
var suit: int = CardAtlas.Suit.CLUBS
var value: int = CardAtlas.ACE
var card_id: int = 0  # 0-51 for standard, 52+ for custom
var is_custom: bool = false

# Rendering mode
var is_dynamic: bool = false  # false = mesh swapping (default), true = shader parameters

# Pool management
var pool_id: String = "playing_card"

func _ready():
	if is_dynamic:
		# Dynamic cards (tile info ghost): Use shader parameter approach
		# Create unique material to avoid shader instance buffer limits
		if material:
			material = material.duplicate()
	else:
		# Static cards (hand, placed tiles): Use mesh swapping approach
		# No material duplication needed - just display the atlas texture
		# Mesh will be swapped in init_card() to show correct card
		pass

## Initialize the card with a specific suit and value
func init_card(p_suit: int, p_value: int) -> void:
	suit = p_suit
	value = p_value
	is_custom = false
	card_id = CardAtlas.get_card_id(suit, value)

	if is_dynamic:
		# Dynamic card: Update shader parameter
		if material and material is ShaderMaterial:
			material.set_shader_parameter("card_id", card_id)
	else:
		# Static card: Swap mesh with baked UVs (no shader needed)
		mesh = CardAtlasMeshes.get_mesh(card_id)
		texture = CardAtlasMeshes.get_texture()
		material = null  # Remove shader material - we're using baked UVs

## Initialize as a custom card
func init_custom_card(p_card_id: int) -> void:
	assert(CardAtlas.is_custom_card(p_card_id), "Invalid custom card_id: %d (must be >= %d)" % [p_card_id, CardAtlas.CUSTOM_CARD_START])
	card_id = p_card_id
	is_custom = true
	suit = -1
	value = -1

	if is_dynamic:
		# Dynamic card: Update shader parameter
		if material and material is ShaderMaterial:
			material.set_shader_parameter("card_id", card_id)
	else:
		# Static card: Swap mesh with baked UVs (no shader needed)
		mesh = CardAtlasMeshes.get_mesh(card_id)
		texture = CardAtlasMeshes.get_texture()
		material = null  # Remove shader material - we're using baked UVs

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

	# Reset material card_id (optional since it's hidden, but keeps it clean)
	if material and material is ShaderMaterial:
		material.set_shader_parameter("card_id", -1)

## Get card name as string
func get_card_name() -> String:
	if is_custom:
		return CardAtlas.get_card_name_from_id(card_id)
	else:
		return CardAtlas.get_card_name(suit, value)

## Burn card animation (used when card is consumed in combo)
## Returns true when animation completes
func burn_card(direction_degrees: float = 180.0, duration: float = 1.0) -> void:
	# Always create a new burn shader material (cards are static by default with null material)
	var burn_shader = load("res://shader/burn_object.gdshader")
	if not burn_shader:
		push_error("PooledCard: Failed to load burn_object.gdshader")
		return

	var shader_material = ShaderMaterial.new()
	shader_material.shader = burn_shader

	# Set shader parameters - adjusted for better fire effect
	shader_material.set_shader_parameter("progress", -1.5)
	shader_material.set_shader_parameter("direction", direction_degrees)
	shader_material.set_shader_parameter("noiseForce", 0.35)  # More irregular burn pattern
	shader_material.set_shader_parameter("burnColor", Color(1.0, 0.75, 0.25, 1.0))  # Bright yellow-orange hot flame
	shader_material.set_shader_parameter("borderWidth", 0.18)  # Wider to see more burn effect

	# Generate procedural noise texture for burn effect
	var noise_texture = _generate_noise_texture()
	if noise_texture:
		shader_material.set_shader_parameter("noiseTexture", noise_texture)
	else:
		push_error("PooledCard: Failed to generate noise texture for burn effect")

	# Apply the shader material
	material = shader_material

	# Wait one frame for material to be applied
	await get_tree().process_frame

	# Animate the burn effect
	if material and material is ShaderMaterial:
		var tween = create_tween()
		tween.tween_method(_update_burn_progress, -1.5, 1.5, duration)
		await tween.finished
	else:
		push_error("PooledCard: Material is not a ShaderMaterial after assignment!")

## Generate a procedural noise texture for burn effect
func _generate_noise_texture() -> NoiseTexture2D:
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.05
	noise.fractal_octaves = 3

	var noise_texture = NoiseTexture2D.new()
	noise_texture.noise = noise
	noise_texture.width = 128
	noise_texture.height = 128
	noise_texture.seamless = true

	return noise_texture

## Helper to update burn progress (called by tween)
func _update_burn_progress(value: float) -> void:
	if material and material is ShaderMaterial:
		material.set_shader_parameter("progress", value)
