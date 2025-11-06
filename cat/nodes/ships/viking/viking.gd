extends NPC

# Viking ship - water-based NPC with wave shader effects

func _ready():
	# Configure terrain type for water pathfinding
	terrain_type = TerrainType.WATER

	# Set movement speed (ships are faster than ground NPCs)
	move_speed = 3.0

	# Set pool name for proper cleanup
	pool_name = "viking"

	# Combat configuration - Ranged bow attacker
	combat_type = CombatType.BOW
	projectile_type = ProjectileType.SPEAR
	combat_range = 5  # Bow range (5 hexes)

	# Configure attack speed (slower = more visible projectiles)
	attack_interval = 2.5  # Attack every 2.5 seconds
	# Use Sprite2D region mode with wave shader
	# Load the atlas image
	var atlas_image = preload("res://nodes/ships/viking/viking_atlas.png")
	sprite.texture = atlas_image

	# Enable region mode and set initial region (direction 0)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 64, 64)  # Start with first cell

	# Create shader material for wave motion
	var wave_shader = preload("res://nodes/ships/viking/viking_wave.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = wave_shader

	# Set wave parameters
	shader_material.set_shader_parameter("wave_speed", 0.6)
	shader_material.set_shader_parameter("wave_amplitude", 1.5)
	shader_material.set_shader_parameter("sway_amplitude", 1.0)
	shader_material.set_shader_parameter("wave_frequency", 1.2)

	sprite.material = shader_material

	# Scale down the sprite to fit better on hex tile (64x64 sprite -> ~38x38 visual size)
	sprite.scale = Vector2(0.6, 0.6)

	# Note: Viking uses region_rect updates (shader atlas approach), not individual sprite textures
	# No need to load ship_sprites array - saves memory by avoiding 16 texture preloads

	super._ready()

func _process(delta):
	# Call parent's _process to handle movement and rotation
	super._process(delta)

	# Example: rotate to face mouse (for testing)
	# Uncomment to test rotation:
	# var mouse_pos = get_global_mouse_position()
	# var direction_vec = mouse_pos - global_position
	# set_direction(vector_to_direction(direction_vec))
