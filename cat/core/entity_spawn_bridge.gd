extends Node

## EntitySpawnBridge - Singleton for Rust-authoritative entity spawning
##
## This bridge ensures Rust is the source of truth for entity positions.
## GDScript only handles rendering - Rust validates spawn locations,
## checks terrain types, avoids collisions, and creates entity data.

# Reference to Rust EntitySpawnBridge
var spawn_bridge: Node = null

func _ready():
	# Create Rust bridge instance
	spawn_bridge = ClassDB.instantiate("EntitySpawnBridge")
	if spawn_bridge:
		add_child(spawn_bridge)
		print("EntitySpawnBridge: Initialized with Rust backend")
	else:
		push_error("EntitySpawnBridge: Failed to instantiate Rust bridge!")

## Spawn an entity with Rust validation
##
## # Arguments
## * entity_type: String - Type of entity ("viking", "jezza", "king", etc.)
## * terrain_type: int - 0=Water, 1=Land (matches NPC.TerrainType enum)
## * preferred_location: Vector2i - Optional preferred spawn location (use Vector2i(-999999, -999999) for none)
## * search_radius: int - Radius to search for valid spawn location
##
## # Returns
## Dictionary with:
## * success: bool - Whether spawn succeeded
## * ulid: PackedByteArray - Entity ULID (empty if failed)
## * entity_type: String - Entity type
## * position: Vector2i - Spawn position (q, r)
## * terrain_type: int - Terrain type
## * error_message: String - Error message if failed
func spawn_entity(
	entity_type: String,
	terrain_type: int,
	preferred_location: Vector2i = Vector2i(-999999, -999999),
	search_radius: int = 25
) -> Dictionary:
	if not spawn_bridge:
		push_error("EntitySpawnBridge: Rust bridge not initialized!")
		return {
			"success": false,
			"ulid": PackedByteArray(),
			"entity_type": entity_type,
			"position": Vector2i(0, 0),
			"terrain_type": terrain_type,
			"error_message": "Rust bridge not initialized"
		}

	# Call Rust spawn function
	var result = spawn_bridge.spawn_entity(
		entity_type,
		terrain_type,
		preferred_location.x,
		preferred_location.y,
		search_radius
	)

	# Convert position to Vector2i for GDScript convenience
	if result.has("position_q") and result.has("position_r"):
		result["position"] = Vector2i(result["position_q"], result["position_r"])

	return result

## Check if a location is valid for spawning
##
## # Arguments
## * position: Vector2i - Position to check (q, r)
## * terrain_type: int - 0=Water, 1=Land
##
## # Returns
## bool - True if location is valid for spawning
func is_valid_spawn_location(position: Vector2i, terrain_type: int) -> bool:
	if not spawn_bridge:
		push_warning("EntitySpawnBridge: Rust bridge not initialized!")
		return false

	return spawn_bridge.is_valid_spawn_location(position.x, position.y, terrain_type)
