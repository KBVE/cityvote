extends Node

## Unified Pathfinding Bridge (V2 - Simplified)
## Single bridge to unified Rust pathfinding system
## Handles both water and land entities through one interface

## Signals for async pathfinding results
signal path_found(entity_ulid: PackedByteArray, path: Array[Vector2i], success: bool, cost: float)
signal random_destination_found(entity_ulid: PackedByteArray, destination: Vector2i, found: bool)

# Terrain type enum (matches Rust TerrainType)
enum TerrainType {
	WATER = 0,  # Maps to TerrainType::Water in Rust
	LAND = 1,   # Maps to TerrainType::Land in Rust
}

# Reference to unified Rust pathfinding bridge
var pathfinding_bridge: Node = null

# DEBUG: Set to true to disable pathfinding for testing
const DISABLE_PATHFINDING = false

# DEBUG: Performance monitoring - DISABLED to reduce overhead
const ENABLE_PERF_LOGGING = false
var frame_count = 0
var perf_log_interval = 60  # Log every 60 frames

func _ready() -> void:
	call_deferred("_initialize_bridge")

func _initialize_bridge() -> void:
	if DISABLE_PATHFINDING:
		push_warning("UnifiedPathfindingBridge: Pathfinding DISABLED for testing!")
		return

	# Instantiate UnifiedPathfindingBridge from Rust
	pathfinding_bridge = ClassDB.instantiate("UnifiedPathfindingBridge")
	if not pathfinding_bridge:
		push_error("UnifiedPathfindingBridge: Failed to instantiate UnifiedPathfindingBridge from Rust!")
		return

	add_child(pathfinding_bridge)

	# Start worker threads (1 thread to avoid contention)
	pathfinding_bridge.start_workers(1)

	# Enable processing to poll for results
	set_process(true)

	print("UnifiedPathfindingBridge: Initialized with unified pathfinding system (poll-based)")

# No longer need pending callback dictionaries - using signals instead!

## Poll for pathfinding results every frame (GDScript-side polling)
func _process(_delta: float) -> void:
	if not pathfinding_bridge or not is_instance_valid(pathfinding_bridge):
		return

	var frame_start_time = Time.get_ticks_usec()
	var path_poll_time = 0
	var path_process_time = 0
	var random_poll_time = 0
	var random_process_time = 0

	# Poll for pathfinding results (non-blocking, returns null if no results)
	# Process up to 10 results per frame to avoid frame spikes
	var processed_count = 0
	while processed_count < 10:
		var poll_start = Time.get_ticks_usec()
		var result = pathfinding_bridge.poll_result()
		path_poll_time += Time.get_ticks_usec() - poll_start

		if result == null:
			break  # No more results

		processed_count += 1

		# Extract result data
		var process_start = Time.get_ticks_usec()
		var entity_ulid: PackedByteArray = result.get("entity_ulid")
		var path: Array = result.get("path")
		var success: bool = result.get("success")
		var cost: float = result.get("cost")

		# Process result
		_on_path_found(entity_ulid, path, success, cost)
		path_process_time += Time.get_ticks_usec() - process_start

	# Poll for random destination results
	processed_count = 0
	while processed_count < 10:
		var poll_start = Time.get_ticks_usec()
		var result = pathfinding_bridge.poll_random_dest_result()
		random_poll_time += Time.get_ticks_usec() - poll_start

		if result == null:
			break  # No more results

		processed_count += 1

		# Extract result data
		var process_start = Time.get_ticks_usec()
		var entity_ulid: PackedByteArray = result.get("entity_ulid")
		var found: bool = result.get("found")
		var destination: Vector2i = Vector2i.ZERO

		if found and result.has("destination"):
			var dest_dict = result.get("destination")
			destination = Vector2i(dest_dict.get("q"), dest_dict.get("r"))

		# Process result
		_on_random_dest_found(entity_ulid, destination, found)
		random_process_time += Time.get_ticks_usec() - process_start

	# Performance logging
	if ENABLE_PERF_LOGGING:
		frame_count += 1
		var total_time = Time.get_ticks_usec() - frame_start_time

		# Log if this frame took longer than 16ms (60 FPS threshold)
		if total_time > 16000:
			print("⚠️ SLOW FRAME: %d µs | Path poll: %d µs, Path process: %d µs | Random poll: %d µs, Random process: %d µs" % [
				total_time, path_poll_time, path_process_time, random_poll_time, random_process_time
			])

		# Periodic summary
		if frame_count % perf_log_interval == 0:
			print("PathfindingBridge _process() avg: Path poll=%d µs, Random poll=%d µs, Total=%d µs" % [
				path_poll_time, random_poll_time, total_time
			])

func _on_path_found(entity_ulid: PackedByteArray, path: Array, success: bool, cost: float) -> void:
	var callback_start = Time.get_ticks_usec()

	# Convert path to Vector2i array
	var conversion_start = Time.get_ticks_usec()
	var path_coords: Array[Vector2i] = []
	for coord_dict in path:
		path_coords.append(Vector2i(coord_dict["q"], coord_dict["r"]))
	var conversion_time = Time.get_ticks_usec() - conversion_start

	# Emit signal instead of calling callback
	var signal_start = Time.get_ticks_usec()
	path_found.emit(entity_ulid, path_coords, success, cost)
	var signal_time = Time.get_ticks_usec() - signal_start

	# Log if expensive
	var total_time = Time.get_ticks_usec() - callback_start
	if total_time > 5000:  # More than 5ms
		print("⚠️ SLOW path signal: %d µs (conversion: %d µs, signal emit: %d µs, path length: %d)" % [
			total_time, conversion_time, signal_time, path.size()
		])

func _on_random_dest_found(entity_ulid: PackedByteArray, destination: Vector2i, found: bool) -> void:
	var callback_start = Time.get_ticks_usec()

	# Emit signal instead of calling callback
	random_destination_found.emit(entity_ulid, destination, found)

	# Log if expensive
	var total_time = Time.get_ticks_usec() - callback_start
	if total_time > 5000:  # More than 5ms
		print("⚠️ SLOW random dest signal: %d µs" % total_time)

## === PUBLIC API ===

## Request pathfinding for any entity (water or land)
## Results will be emitted via the 'path_found' signal
func request_path(
	entity_ulid: PackedByteArray,
	terrain_type: int,
	start: Vector2i,
	goal: Vector2i,
	avoid_entities: bool = false
) -> void:
	if not pathfinding_bridge or not is_instance_valid(pathfinding_bridge):
		push_error("UnifiedPathfindingBridge: Pathfinding bridge not initialized or invalid!")
		# Emit failed signal
		path_found.emit(entity_ulid, [], false, 0.0)
		return

	# Request pathfinding from unified Rust system
	# Result will be emitted via 'path_found' signal when ready
	pathfinding_bridge.request_path(
		entity_ulid,
		terrain_type,
		start.x, start.y,
		goal.x, goal.y,
		avoid_entities
	)

## Update entity position (for collision avoidance)
func update_entity_position(entity_ulid: PackedByteArray, position: Vector2i, terrain_type: int) -> void:
	if pathfinding_bridge and is_instance_valid(pathfinding_bridge):
		pathfinding_bridge.update_entity_position(entity_ulid, position.x, position.y, terrain_type)

## Remove entity from tracking
func remove_entity(entity_ulid: PackedByteArray) -> void:
	if pathfinding_bridge and is_instance_valid(pathfinding_bridge):
		pathfinding_bridge.remove_entity(entity_ulid)

## Request random destination (ASYNC - uses signals)
## Results will be emitted via the 'random_destination_found' signal
func request_random_destination(
	entity_ulid: PackedByteArray,
	terrain_type: int,
	start: Vector2i,
	min_distance: int,
	max_distance: int
) -> void:
	if not pathfinding_bridge or not is_instance_valid(pathfinding_bridge):
		push_warning("request_random_destination: pathfinding_bridge is invalid!")
		# Emit failed signal
		random_destination_found.emit(entity_ulid, start, false)
		return

	# Queue request to worker thread
	# Result will be emitted via 'random_destination_found' signal when ready
	pathfinding_bridge.request_random_destination(
		entity_ulid,
		terrain_type,
		start.x, start.y,
		min_distance, max_distance
	)

## Check if tile is walkable for given terrain type
func is_tile_walkable(terrain_type: int, coord: Vector2i) -> bool:
	if not pathfinding_bridge or not is_instance_valid(pathfinding_bridge):
		push_warning("is_tile_walkable: pathfinding_bridge is invalid!")
		return false
	return pathfinding_bridge.is_tile_walkable(terrain_type, coord.x, coord.y)

## Get pathfinding statistics
func get_stats() -> Dictionary:
	if not pathfinding_bridge or not is_instance_valid(pathfinding_bridge):
		return {}
	return pathfinding_bridge.get_stats()

## Set world seed for procedural terrain generation
## IMPORTANT: Call this before pathfinding to ensure terrain cache can generate chunks on-demand
func set_world_seed(seed: int) -> void:
	if pathfinding_bridge and is_instance_valid(pathfinding_bridge):
		pathfinding_bridge.set_world_seed(seed)

## LEGACY COMPATIBILITY (deprecated - these now just call the unified API)

## Legacy: Initialize map (no-op for procedural world)
func init_map(_hex_map: Node) -> void:
	pass  # Procedural world - chunks loaded on demand

## Load chunk into terrain cache
func load_chunk(chunk_coords: Vector2i, tile_data: Array) -> void:
	if pathfinding_bridge and is_instance_valid(pathfinding_bridge):
		pathfinding_bridge.load_chunk(chunk_coords, tile_data)

## Legacy: Ship-specific API (redirects to unified API)
var ship_pathfinding: Node:
	get: return pathfinding_bridge

## Legacy: NPC-specific API (redirects to unified API)
var npc_pathfinding: Node:
	get: return pathfinding_bridge
