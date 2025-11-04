extends Node

## EntitySpawnBridge - Singleton for Rust-authoritative entity spawning
##
## This bridge ensures Rust is the source of truth for entity positions.
## GDScript only handles rendering - Rust validates spawn locations,
## checks terrain types, avoids collisions, and creates entity data.
##
## ASYNC API: spawn_entity() now queues requests and emits spawn_completed signal

# Signal emitted when a spawn request completes (async)
signal spawn_completed(success: bool, ulid: PackedByteArray, position: Vector2i, terrain_type: int, entity_type: String, error_message: String)

# Reference to Rust EntitySpawnBridge
var spawn_bridge: Node = null

func _ready():
	# Create Rust bridge instance
	spawn_bridge = ClassDB.instantiate("EntitySpawnBridge")
	if spawn_bridge:
		add_child(spawn_bridge)
		# Connect to Rust spawn_completed signal
		spawn_bridge.spawn_completed.connect(_on_rust_spawn_completed)
		print("EntitySpawnBridge: Initialized with Rust backend (async mode)")
	else:
		push_error("EntitySpawnBridge: Failed to instantiate Rust bridge!")

func _on_rust_spawn_completed(success: bool, ulid: PackedByteArray, position_q: int, position_r: int, terrain_type: int, entity_type: String, error_message: String):
	# Convert position to Vector2i and re-emit signal
	var position = Vector2i(position_q, position_r)
	spawn_completed.emit(success, ulid, position, terrain_type, entity_type, error_message)

## Queue an entity spawn request (ASYNC - result comes via spawn_completed signal)
##
## # Arguments
## * entity_type: String - Type of entity ("viking", "jezza", "king", etc.)
## * terrain_type: int - 0=Water, 1=Land (matches NPC.TerrainType enum)
## * preferred_location: Vector2i - Optional preferred spawn location (use Vector2i(-999999, -999999) for none)
## * search_radius: int - Radius to search for valid spawn location
##
## # Returns
## void - Connect to spawn_completed signal to get the result
func spawn_entity(
	entity_type: String,
	terrain_type: int,
	preferred_location: Vector2i = Vector2i(-999999, -999999),
	search_radius: int = 25
) -> void:
	if not spawn_bridge:
		push_error("EntitySpawnBridge: Rust bridge not initialized!")
		# Emit failure immediately
		spawn_completed.emit(false, PackedByteArray(), Vector2i(0, 0), terrain_type, entity_type, "Rust bridge not initialized")
		return

	# Queue the spawn request (async - result will come via signal)
	spawn_bridge.spawn_entity(
		entity_type,
		terrain_type,
		preferred_location.x,
		preferred_location.y,
		search_radius
	)

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
