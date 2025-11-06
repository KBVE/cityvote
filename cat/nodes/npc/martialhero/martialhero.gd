extends NPC
class_name MartialHero

## Martial Hero - Animated ground NPC
## Uses UV-baked animation mesh system for high performance
## Animation atlas: res://nodes/npc/martialhero/martialhero_atlas.png

# Pool configuration
var pool_key: String = "martial_hero"

func _ready():
	# Set terrain type to LAND
	terrain_type = TerrainType.LAND

	# Set pool name
	pool_name = "martialhero"

	# Combat configuration
	combat_type = CombatType.MELEE
	projectile_type = ProjectileType.NONE
	combat_range = 1  # Melee range (1 hex)

	# Enable UV-baked animation mesh system (high performance)
	# IMPORTANT: Set these BEFORE calling super._ready() so parent can initialize correctly
	use_animation_mesh = true
	entity_type_for_animation = "martial_hero"
	animation_fps = 10.0  # Default animation speed

	# Call parent _ready() after configuration
	super._ready()

	# Note: Animation is handled automatically by parent NPC class
	# using UV-baked mesh system for high performance
