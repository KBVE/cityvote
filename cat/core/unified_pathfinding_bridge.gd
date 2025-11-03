extends Node

## Unified Pathfinding Bridge (V2 - Simplified)
## Single bridge to unified Rust pathfinding system
## Handles both water and land entities through one interface

# Terrain type enum (matches Rust TerrainType)
enum TerrainType {
	WATER = 0,  # Maps to TerrainType::Water in Rust
	LAND = 1,   # Maps to TerrainType::Land in Rust
}

# Reference to unified Rust pathfinding bridge
var pathfinding_bridge: Node = null

func _ready() -> void:
	call_deferred("_initialize_bridge")

func _initialize_bridge() -> void:
	# Instantiate UnifiedPathfindingBridge from Rust
	pathfinding_bridge = ClassDB.instantiate("UnifiedPathfindingBridge")
	if not pathfinding_bridge:
		push_error("UnifiedPathfindingBridge: Failed to instantiate UnifiedPathfindingBridge from Rust!")
		return

	add_child(pathfinding_bridge)

	# Connect signal for pathfinding results (all entities use same signal now)
	pathfinding_bridge.connect("path_found", _on_path_found)

	# Start worker threads (2 threads for all pathfinding)
	pathfinding_bridge.start_workers(2)

	print("UnifiedPathfindingBridge: Initialized with unified pathfinding system")

# Pending requests keyed by ULID hex
var pending_requests: Dictionary = {}  # ulid_hex -> callback

func _on_path_found(entity_ulid: PackedByteArray, path: Array, success: bool, cost: float) -> void:
	var ulid_hex = UlidManager.to_hex(entity_ulid)

	# Find and call the pending callback
	if ulid_hex in pending_requests:
		var callback = pending_requests[ulid_hex]
		pending_requests.erase(ulid_hex)

		# Convert path to Vector2i array
		var path_coords: Array[Vector2i] = []
		for coord_dict in path:
			path_coords.append(Vector2i(coord_dict["q"], coord_dict["r"]))

		# Call the callback
		if callback.is_valid():
			callback.call(path_coords, success, cost)
	else:
		# DEBUG: No pending request found for this entity
		push_warning("UnifiedPathfindingBridge: Received path result for %s but no pending request found!" % ulid_hex)

## === PUBLIC API ===

## Request pathfinding for any entity (water or land)
func request_path(
	entity_ulid: PackedByteArray,
	terrain_type: int,
	start: Vector2i,
	goal: Vector2i,
	callback: Callable,
	avoid_entities: bool = false
) -> void:
	if not pathfinding_bridge:
		push_error("UnifiedPathfindingBridge: Pathfinding bridge not initialized!")
		if callback.is_valid():
			callback.call([], false, 0.0)
		return

	# Store callback
	var ulid_hex = UlidManager.to_hex(entity_ulid)
	pending_requests[ulid_hex] = callback

	# Request pathfinding from unified Rust system
	pathfinding_bridge.request_path(
		entity_ulid,
		terrain_type,
		start.x, start.y,
		goal.x, goal.y,
		avoid_entities
	)

## Update entity position (for collision avoidance)
func update_entity_position(entity_ulid: PackedByteArray, position: Vector2i, terrain_type: int) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.update_entity_position(entity_ulid, position.x, position.y, terrain_type)

## Remove entity from tracking
func remove_entity(entity_ulid: PackedByteArray) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.remove_entity(entity_ulid)

## Find random destination for any entity
func find_random_destination(
	entity_ulid: PackedByteArray,
	terrain_type: int,
	start: Vector2i,
	min_distance: int,
	max_distance: int
) -> Vector2i:
	if not pathfinding_bridge:
		return start

	var result = pathfinding_bridge.find_random_destination(
		entity_ulid,
		terrain_type,
		start.x, start.y,
		min_distance, max_distance
	)

	if result.get("found", false):
		var destination = Vector2i(result["q"], result["r"])
		# Defensive: Verify destination is actually walkable for this terrain type
		if pathfinding_bridge.is_tile_walkable(terrain_type, destination.x, destination.y):
			return destination
		else:
			push_error("find_random_destination: Returned destination %s is NOT walkable for terrain_type=%d!" % [destination, terrain_type])
			return start
	else:
		return start

## Check if tile is walkable for given terrain type
func is_tile_walkable(terrain_type: int, coord: Vector2i) -> bool:
	if not pathfinding_bridge:
		return false
	return pathfinding_bridge.is_tile_walkable(terrain_type, coord.x, coord.y)

## Get pathfinding statistics
func get_stats() -> Dictionary:
	if not pathfinding_bridge:
		return {}
	return pathfinding_bridge.get_stats()

## Set world seed for procedural terrain generation
## IMPORTANT: Call this before pathfinding to ensure terrain cache can generate chunks on-demand
func set_world_seed(seed: int) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.set_world_seed(seed)

## LEGACY COMPATIBILITY (deprecated - these now just call the unified API)

## Legacy: Initialize map (no-op for procedural world)
func init_map(_hex_map: Node) -> void:
	pass  # Procedural world - chunks loaded on demand

## Load chunk into terrain cache
func load_chunk(chunk_coords: Vector2i, tile_data: Array) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.load_chunk(chunk_coords, tile_data)

## Legacy: Ship-specific API (redirects to unified API)
var ship_pathfinding: Node:
	get: return pathfinding_bridge

## Legacy: NPC-specific API (redirects to unified API)
var npc_pathfinding: Node:
	get: return pathfinding_bridge
