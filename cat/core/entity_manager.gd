extends Node

## EntityManager - Centralized entity lifecycle management
## Handles spawning/despawning of all game entities (NPCs, Ships, etc.)
## Manages health bar pooling to ensure proper setup and cleanup
## Tracks all entities in a unified registry for movement and querying

## Signal emitted when an entity is spawned
signal entity_spawned(entity: Node, pool_key: String)

## Entity type definitions for spawn_multiple
## NOTE: These enum values MUST match Rust TerrainType values!
## Rust: Water=0, Land=1, Obstacle=2
enum TileType {
	WATER = 0,  # Water tiles (for ships like Vikings) - MUST be 0 to match Rust
	LAND = 1,   # Land tiles (for ground units like Jezzas) - MUST be 1 to match Rust
	ANY = 99    # Any tile (for flying units, etc.)
}

## Unified entity registry - tracks all spawned entities
## Each entry: {entity: Node, type: String, pool_key: String, move_timer: float, move_interval: float, tile: Vector2i}
var registered_entities: Array = []

## Occupied tiles - tracks which entity is on which tile (managed by EntityManager)
var occupied_tiles: Dictionary = {}

## References to game systems (set by main.gd on initialization)
var hex_map: Node = null
var tile_map = null

## Pending spawn contexts - tracks context data for async spawns
## Key: entity_type (String), Value: Array of context dictionaries
var pending_spawn_contexts: Dictionary = {}

## Movement update throttling (to avoid per-frame overhead)
var movement_update_accumulator: float = 0.0
const MOVEMENT_UPDATE_INTERVAL: float = 0.5  # Update every 0.5 seconds (2 updates/sec)

## Batch processing for entities (spread work across frames)
var entity_process_index: int = 0
const ENTITIES_PER_UPDATE: int = 30  # Process max 30 entities per update cycle (increased to handle all entities)

## Global handler for all spawn completions (called by signal)
## Handle successful entity spawn from UnifiedEventBridge
func _on_spawn_completed_global(ulid: PackedByteArray, position_q: int, position_r: int, terrain_type: int, entity_type: String):
	# Convert position from q/r to Vector2i
	var position = Vector2i(position_q, position_r)

	# Get spawn context for this entity_type
	if not pending_spawn_contexts.has(entity_type):
		push_error("EntityManager: No pending spawn context for %s! This shouldn't happen." % entity_type)
		return

	var contexts = pending_spawn_contexts[entity_type]
	if contexts.is_empty():
		push_error("EntityManager: Empty spawn context array for %s! This shouldn't happen." % entity_type)
		return

	# Pop the first context (FIFO queue)
	var context: Dictionary = contexts.pop_front()

	# Clean up context array if empty
	if contexts.is_empty():
		pending_spawn_contexts.erase(entity_type)

	# Extract context data
	var pool_key: String = context["pool_key"]
	var p_hex_map = context["hex_map"]
	var p_tile_map = context["tile_map"]
	var storage_array: Array = context["storage_array"]
	var player_ulid: PackedByteArray = context["player_ulid"]

	# Check for collision - allow "ghost" spawning (entities will move apart naturally)
	if occupied_tiles.has(position):
		var existing_entity = occupied_tiles[position]
		if existing_entity and is_instance_valid(existing_entity):
			# GHOST SPAWN: Allow temporary overlap, entities will move apart on next movement tick
			push_warning("EntityManager: Ghost spawn at %s (occupied by %s), spawning %s anyway - will resolve naturally" % [position, existing_entity.name, entity_type])
			# Don't return - continue with spawn
		else:
			# Stale reference, clean it up
			occupied_tiles.erase(position)

	# Acquire entity from pool
	var entity = Cluster.acquire(pool_key)
	if not entity:
		push_error("EntityManager: Failed to acquire %s from pool after successful Rust spawn!" % pool_key)
		return

	# CRITICAL: Set ULID from Rust BEFORE adding to scene tree
	# This prevents _ready() from generating a new ULID
	if "ulid" in entity:
		entity.ulid = ulid

	# Convert tile position to world position
	var world_pos = p_tile_map.map_to_local(position)

	# Configure entity
	var entity_config = {
		"player_ulid": player_ulid,
		"direction": randi() % 16,
		"occupied_tiles": occupied_tiles
	}

	# Spawn entity in scene (this triggers _ready() which will see the ULID we just set)
	var spawned = spawn_entity(entity, p_hex_map, world_pos, entity_config)
	if not spawned:
		push_error("EntityManager: Failed to spawn entity %s at %s" % [entity_type, position])
		# Return entity to pool
		Cluster.release(pool_key, entity)
		return

	# CRITICAL: Manually register stats and combat since _ready() already ran during pool init
	# The entity's _ready() returns early if _initialized is true, so we must register here
	# Combat registration is now automatic through stats - no separate call needed
	if entity.has_method("_register_stats"):
		entity.call_deferred("_register_stats")

	# Register entity with EntityManager
	register_entity(entity, pool_key, position)

	# Reveal chunk for fog of war
	if ChunkManager:
		ChunkManager.reveal_chunk_at_tile(position)

	# Mark tile as occupied (for ghost spawning, we store the LAST entity at this position)
	# Multiple entities can temporarily overlap - they'll move apart on next movement tick
	occupied_tiles[position] = entity

	# Store in tracking array if provided
	if storage_array != null:
		storage_array.append(entity)

	# Emit signal
	entity_spawned.emit(entity, pool_key)

## Entity type configurations (movement intervals, etc.)
const ENTITY_CONFIGS = {
	"viking": {"move_interval": 2.0, "tile_type": TileType.WATER},
	"jezza": {"move_interval": 3.0, "tile_type": TileType.LAND},
	"fantasywarrior": {"move_interval": 2.5, "tile_type": TileType.LAND},
	"king": {"move_interval": 2.0, "tile_type": TileType.LAND},
	"skullwizard": {"move_interval": 2.8, "tile_type": TileType.LAND},
	"fireworm": {"move_interval": 2.2, "tile_type": TileType.LAND},
	"martialhero": {"move_interval": 2.3, "tile_type": TileType.LAND},
}

## ============================================================================
## DEFENSIVE PROGRAMMING HELPERS
## ============================================================================

## Validate that an entity is still valid and safe to access
## This is a critical defensive programming function to prevent crashes from:
## - Accessing freed entities
## - Using stale references after pool reuse
## - Race conditions with async operations (pathfinding, combat)
## @param entity: The entity to validate (can be Node or Dictionary entry)
## @return: Node - Valid entity, or null if invalid
static func get_valid_entity(entity) -> Node:
	# Handle dictionary entries (from registered_entities array)
	if typeof(entity) == TYPE_DICTIONARY:
		entity = entity.get("entity")

	# Validate entity exists and is valid
	if not entity:
		return null

	if not is_instance_valid(entity):
		return null

	# Check if entity is being freed (queued for deletion)
	if entity.is_queued_for_deletion():
		return null

	# Check if entity is in scene tree (not orphaned)
	if not entity.is_inside_tree():
		return null

	return entity

## Validate entity with ULID matching (prevents using pooled/reused entities)
## @param entity: The entity to validate
## @param expected_ulid: The ULID it should have
## @return: Node - Valid entity with matching ULID, or null if invalid/mismatch
static func get_valid_entity_with_ulid(entity, expected_ulid: PackedByteArray) -> Node:
	entity = get_valid_entity(entity)
	if not entity:
		return null

	# Verify ULID matches (prevents accessing reused pooled entities)
	if "ulid" in entity and entity.ulid != expected_ulid:
		return null  # Entity was pooled and reused with different ULID

	return entity

## ============================================================================
## ENTITY SPAWNING & LIFECYCLE
## ============================================================================

## Spawn an entity (NPC, Ship, etc.) with proper initialization
## @param entity: The entity node acquired from Cluster
## @param parent: Parent node to add entity to (usually hex_map)
## @param world_pos: World position to place entity
## @param config: Dictionary with optional config:
##   - player_ulid: PackedByteArray - Player ownership
##   - direction: int - Initial facing direction (0-15)
##   - occupied_tiles: Dictionary - Reference to occupied tiles dict
## @return: The configured entity, or null if setup failed
func spawn_entity(entity: Node, parent: Node, world_pos: Vector2, config: Dictionary = {}) -> Node:
	if not entity or not parent:
		push_error("EntityManager: Cannot spawn - entity or parent is null!")
		return null

	# Add entity to scene tree
	parent.add_child(entity)
	entity.position = world_pos

	# Set player ownership if specified
	if config.has("player_ulid") and "player_ulid" in entity:
		entity.player_ulid = config.get("player_ulid")

	# Set initial direction if specified
	if config.has("direction") and entity.has_method("set_direction"):
		entity.set_direction(config.get("direction"))

	# Share occupied tiles reference if specified
	if config.has("occupied_tiles") and "occupied_tiles" in entity:
		entity.occupied_tiles = config.get("occupied_tiles")

	# Setup health bar (critical - must happen after entity is in tree)
	_setup_entity_health_bar(entity)

	return entity

## Register an entity in the unified registry for tracking and movement
## @param entity: The entity node to register
## @param pool_key: Pool key (e.g., "viking", "jezza", "king")
## @param tile: Current tile coordinates
## @return: bool - True if registered successfully
func register_entity(entity: Node, pool_key: String, tile: Vector2i) -> bool:
	if not entity or not is_instance_valid(entity):
		push_error("EntityManager: Cannot register invalid entity")
		return false

	# Get entity config
	var config = ENTITY_CONFIGS.get(pool_key, {"move_interval": 2.0})

	# Create registry entry
	var entry = {
		"entity": entity,
		"type": pool_key,
		"pool_key": pool_key,
		"move_timer": 0.0,
		"move_interval": config.get("move_interval", 2.0),
		"tile": tile
	}

	registered_entities.append(entry)

	# NOTE: Combat registration is now automatic through stats
	# Entity's _register_stats() call handles everything

	return true

## Unregister an entity from the registry
## @param entity: The entity to unregister
## @return: bool - True if found and unregistered
func unregister_entity(entity: Node) -> bool:
	for i in range(registered_entities.size()):
		if registered_entities[i]["entity"] == entity:
			# NOTE: Combat unregistration handled automatically by UnifiedEventBridge
			# when RemoveEntity request is sent (Actor cleans up all state)

			registered_entities.remove_at(i)
			return true
	return false

## Get all registered entities (for debugging/inspection)
func get_registered_entities() -> Array:
	return registered_entities

## Get registered entities by type
## @param pool_key: Type to filter by (e.g., "viking", "jezza")
## @return: Array of entity nodes
func get_entities_by_type(pool_key: String) -> Array:
	var result: Array = []
	for entry in registered_entities:
		if entry["pool_key"] == pool_key:
			result.append(entry["entity"])
	return result

## Despawn an entity, returning it to the pool
## @param entity: The entity to despawn
## @param pool_key: Pool key to return entity to (e.g., "jezza", "viking")
func despawn_entity(entity: Node, pool_key: String) -> void:
	if not entity or not is_instance_valid(entity):
		push_warning("EntityManager: Cannot despawn - entity is invalid!")
		return

	# CRITICAL: Clean up occupied_tiles to prevent desync
	# Find which tile this entity occupies and clear it
	for tile in occupied_tiles.keys():
		if occupied_tiles[tile] == entity:
			occupied_tiles.erase(tile)
			break

	# Unregister from tracking
	unregister_entity(entity)

	# Remove and reset health bar BEFORE returning to pool
	_cleanup_entity_health_bar(entity)

	# Remove from parent
	if entity.get_parent():
		entity.get_parent().remove_child(entity)

	# Return to pool
	if Cluster:
		Cluster.release(pool_key, entity)
	else:
		push_error("EntityManager: Cluster not available for despawn!")

## Setup health bar for an entity (acquires from pool and initializes)
func _setup_entity_health_bar(entity: Node) -> void:
	# Only setup if entity has health_bar property
	if not "health_bar" in entity:
		return

	# Check if health bar already exists and is valid
	if entity.health_bar and is_instance_valid(entity.health_bar):
		return

	# Acquire health bar from pool
	var health_bar = Cluster.acquire("health_bar")
	if not health_bar:
		push_error("EntityManager: Failed to acquire health bar from pool!")
		return

	# Store reference
	entity.health_bar = health_bar

	# Add as child of entity
	entity.add_child(health_bar)

	# Get stats from StatsManager if available
	if StatsManager and "ulid" in entity and entity.ulid.size() > 0:
		var current_hp = StatsManager.get_stat(entity.ulid, StatsManager.STAT.HP)
		var max_hp = StatsManager.get_stat(entity.ulid, StatsManager.STAT.MAX_HP)
		health_bar.initialize(current_hp, max_hp)
	else:
		# Default values
		health_bar.initialize(100.0, 100.0)

	# Configure appearance
	health_bar.set_bar_offset(Vector2(0, -25))  # Position above entity (5px closer than before)
	health_bar.set_auto_hide(false)  # Always visible

	# Set flag based on player ownership
	_setup_health_bar_flag(entity, health_bar)

## Setup health bar flag based on entity ownership
func _setup_health_bar_flag(entity: Node, health_bar: Node) -> void:
	if not health_bar or not health_bar.has_method("set_flag"):
		return

	# Check if entity has player_ulid property
	if not "player_ulid" in entity:
		return

	# Determine flag based on player ownership
	var flag_name: String
	if entity.player_ulid.is_empty():
		# AI-controlled NPC - use Bavaria flag
		flag_name = "bavaria"
	else:
		# Player-controlled NPC - get player's selected language/flag
		if I18n:
			var current_language = I18n.get_current_language()
			var flag_info = I18n.get_flag_info(current_language)
			flag_name = flag_info["flag"]
		else:
			# Fallback to British flag if I18n not available
			flag_name = "british"

	# Set the flag on the health bar
	health_bar.set_flag(flag_name)

## Cleanup health bar when despawning entity (returns to pool)
func _cleanup_entity_health_bar(entity: Node) -> void:
	if not "health_bar" in entity:
		return

	var health_bar = entity.health_bar
	if not health_bar or not is_instance_valid(health_bar):
		entity.health_bar = null
		return

	# Remove from entity
	if health_bar.get_parent() == entity:
		entity.remove_child(health_bar)

	# Reset health bar to full (for next use)
	health_bar.initialize(100.0, 100.0)

	# Return to pool
	if Cluster:
		Cluster.release("health_bar", health_bar)

	# Clear reference
	entity.health_bar = null

## Generic function to spawn multiple entities of a specific type
## Uses Rust-authoritative UnifiedEventBridge for all spawning
## @param spawn_config: Dictionary with required fields:
##   - pool_key: String - Pool key to acquire from (e.g., "jezza", "viking")
##   - count: int - Number of entities to spawn
##   - tile_type: TileType - What type of tiles to spawn on (LAND, WATER, ANY)
##   - hex_map: Node - Reference to hex map
##   - tile_map: TileMapCompat - Reference to the tile map wrapper
##   - occupied_tiles: Dictionary - Reference to occupied tiles dict
##   - storage_array: Array - Array to store spawned entity data in
##   - player_ulid: PackedByteArray - Player ownership
##   - near_pos: Vector2i (optional) - Card position to spawn near (default: Vector2i(-1, -1))
##   - entity_name: String (optional) - Display name for logging (default: pool_key)
## @return: void - Non-blocking, results handled asynchronously
func spawn_multiple(spawn_config: Dictionary) -> void:
	# Validate required fields
	var required_fields = ["pool_key", "count", "tile_type", "hex_map", "tile_map", "occupied_tiles", "storage_array", "player_ulid"]
	for field in required_fields:
		if not spawn_config.has(field):
			push_error("EntityManager.spawn_multiple: Missing required field '%s'" % field)
			return

	# Extract config
	var pool_key: String = spawn_config["pool_key"]
	var count: int = spawn_config["count"]
	var tile_type: TileType = spawn_config["tile_type"]
	var hex_map = spawn_config["hex_map"]
	var tile_map = spawn_config["tile_map"]
	var occupied_tiles: Dictionary = spawn_config["occupied_tiles"]
	var storage_array: Array = spawn_config["storage_array"]
	var player_ulid: PackedByteArray = spawn_config["player_ulid"]
	var near_pos: Vector2i = spawn_config.get("near_pos", Vector2i(-1, -1))
	var entity_name: String = spawn_config.get("entity_name", pool_key)

	# Convert TileType to Rust terrain_type (0=Water, 1=Land)
	var terrain_type: int = -1
	match tile_type:
		TileType.WATER:
			terrain_type = 0
		TileType.LAND:
			terrain_type = 1
		TileType.ANY:
			push_error("EntityManager.spawn_multiple: TileType.ANY not supported with Rust spawning")
			return

	# Determine preferred location (use near_pos if provided, otherwise use camera position)
	var preferred_location = near_pos if near_pos != Vector2i(-1, -1) else Vector2i(0, 0)

	# Initialize context array for this entity_type if not exists
	if not pending_spawn_contexts.has(pool_key):
		pending_spawn_contexts[pool_key] = []

	# Queue all spawn requests (non-blocking) - results will come via global signal handler
	for i in range(count):
		# Store spawn context for this request
		var context = {
			"pool_key": pool_key,
			"hex_map": hex_map,
			"tile_map": tile_map,
			"storage_array": storage_array,
			"player_ulid": player_ulid
		}
		pending_spawn_contexts[pool_key].append(context)

		# Queue spawn request to Rust via UnifiedEventBridge
		var bridge = get_node("/root/UnifiedEventBridge")
		if bridge:
			bridge.spawn_entity(
				pool_key,
				terrain_type,
				preferred_location.x,
				preferred_location.y,
				50  # search_radius (larger for card spawns)
			)
		else:
			push_error("EntityManager: UnifiedEventBridge not found at /root/UnifiedEventBridge")

	# That's it! Results handled by _on_spawn_completed_global

## Helper: Find valid tiles for spawning based on tile type
## Uses optimized spatial sampling instead of full map scan
## @param tile_type: TileType - What type of tiles to find
## @param hex_map: Node - The hex map node (contains map_data array)
## @param occupied_tiles: Dictionary - Tiles that are already occupied
## @param near_pos: Vector2i - Optional position to spawn near (uses radial search)
## @return: Array of Vector2i - Valid spawn tiles (sorted by distance if near_pos provided)
func _find_valid_tiles(tile_type: TileType, hex_map, occupied_tiles: Dictionary, near_pos: Vector2i) -> Array:
	var has_near_pos = near_pos != Vector2i(-1, -1)

	# If we have a specific position, use radial search
	if has_near_pos:
		return _find_tiles_radial(tile_type, hex_map, occupied_tiles, near_pos)
	else:
		# Otherwise use chunk-based random sampling
		return _find_tiles_chunk_sampling(tile_type, hex_map, occupied_tiles)

## Radial search from a specific position (for spawning near a card)
## Searches in expanding rings until enough tiles are found
func _find_tiles_radial(tile_type: TileType, hex_map, occupied_tiles: Dictionary, center: Vector2i, max_tiles: int = 100) -> Array:
	var tiles_with_distance: Array = []
	var max_radius = 50  # Search up to 50 tiles away
	var world_generator = hex_map.world_generator  # Use WorldGenerator for procedural terrain

	# Helper for hex distance calculation
	var hex_distance = func(a: Vector2i, b: Vector2i) -> int:
		var dx = abs(a.x - b.x)
		var dy = abs(a.y - b.y)
		var dz = abs(dx + dy)
		return (dx + dy + dz) / 2

	# Expand search radius until we find enough tiles
	for radius in range(1, max_radius + 1):
		# Check tiles in a ring at this radius
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var tile_coords = Vector2i(center.x + dx, center.y + dy)

				# Only check tiles roughly at this radius (not every tile in the square)
				var dist = hex_distance.call(center, tile_coords)
				if dist != radius:
					continue

				# NOTE: Bounds check removed - infinite world has no bounds

				# Skip occupied tiles
				if occupied_tiles.has(tile_coords):
					continue

				# PROCEDURAL WORLD: Use WorldGenerator to check terrain type
				# Use proper hex tile-to-world conversion (accounts for hex offset pattern)
				var world_pos = hex_map.tile_renderer._tile_to_world_pos(tile_coords)
				var is_water = world_generator.is_water(world_pos.x, world_pos.y) if world_generator else false

				# Check if tile matches the required type
				var is_valid = _is_tile_type_match_procedural(is_water, tile_type)

				if is_valid:
					tiles_with_distance.append({"pos": tile_coords, "dist": dist})

					# Early exit if we have enough tiles
					if tiles_with_distance.size() >= max_tiles:
						tiles_with_distance.sort_custom(func(a, b): return a["dist"] < b["dist"])
						var result: Array = []
						for tile_data in tiles_with_distance:
							result.append(tile_data["pos"])
						return result

	# Sort by distance
	tiles_with_distance.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var result: Array = []
	for tile_data in tiles_with_distance:
		result.append(tile_data["pos"])
	return result

## Chunk-based random sampling (for spawning without specific position)
## Samples random chunks and checks tiles within them
func _find_tiles_chunk_sampling(tile_type: TileType, hex_map, occupied_tiles: Dictionary, max_tiles: int = 100) -> Array:
	var valid_tiles: Array = []
	var max_attempts = max_tiles * 3  # Try 3x the needed tiles to account for occupied/wrong type
	var world_generator = hex_map.world_generator  # Use WorldGenerator for procedural terrain

	# PROCEDURAL WORLD: Sample from visible/loaded chunks instead of random chunks
	# Get loaded chunks from ChunkPool
	var loaded_chunks = hex_map.chunk_pool.get_loaded_chunks() if hex_map.chunk_pool else []

	# If no chunks loaded yet, search near origin (0,0)
	if loaded_chunks.is_empty():
		var camera = hex_map.camera if hex_map.has("camera") else null
		var center = Vector2i(0, 0)
		if camera:
			var camera_tile = hex_map.tile_renderer.world_to_tile(camera.position)
			center = camera_tile
		return _find_tiles_radial(tile_type, hex_map, occupied_tiles, center, max_tiles)

	for i in range(max_attempts):
		# Pick a random loaded chunk
		var random_chunk = loaded_chunks[randi() % loaded_chunks.size()]
		var chunk_start = MapConfig.chunk_to_tile(random_chunk)

		# Pick a random tile within that chunk
		var local_x = randi() % MapConfig.CHUNK_SIZE
		var local_y = randi() % MapConfig.CHUNK_SIZE
		var tile_coords = Vector2i(chunk_start.x + local_x, chunk_start.y + local_y)

		# Skip occupied tiles
		if occupied_tiles.has(tile_coords):
			continue

		# Skip if we already found this tile
		if tile_coords in valid_tiles:
			continue

		# PROCEDURAL WORLD: Use WorldGenerator to check terrain type
		# Use proper hex tile-to-world conversion (accounts for hex offset pattern)
		var world_pos = hex_map.tile_renderer._tile_to_world_pos(tile_coords)
		var is_water = world_generator.is_water(world_pos.x, world_pos.y) if world_generator else false

		# Check if tile matches the required type
		var is_valid = _is_tile_type_match_procedural(is_water, tile_type)

		if is_valid:
			valid_tiles.append(tile_coords)

			# Early exit if we have enough tiles
			if valid_tiles.size() >= max_tiles:
				break

	return valid_tiles

## Helper to check if a source_id matches the required tile type (DEPRECATED - use _is_tile_type_match_str)
func _is_tile_type_match(source_id: int, tile_type: TileType) -> bool:
	match tile_type:
		TileType.LAND:
			return source_id != MapConfig.SOURCE_ID_WATER
		TileType.WATER:
			return source_id == MapConfig.SOURCE_ID_WATER
		TileType.ANY:
			return true
	return false

## Helper to check if a tile_type string matches the required tile type
## Reads from map_data array instead of TileMap (DEPRECATED - use _is_tile_type_match_procedural)
func _is_tile_type_match_str(tile_type_str: String, tile_type: TileType) -> bool:
	match tile_type:
		TileType.LAND:
			return tile_type_str != "water"
		TileType.WATER:
			return tile_type_str == "water"
		TileType.ANY:
			return true
	return false

## Helper to check if procedurally generated terrain matches the required tile type
## Uses WorldGenerator.is_water() result instead of map_data
func _is_tile_type_match_procedural(is_water: bool, tile_type: TileType) -> bool:
	match tile_type:
		TileType.LAND:
			return not is_water
		TileType.WATER:
			return is_water
		TileType.ANY:
			return true
	return false

## Find entity near a world position (spatial query)
## @param world_pos: World position to search near
## @param search_radius: Search radius in pixels
## @return: Node - Closest entity within radius, or null
func find_entity_near_position(world_pos: Vector2, search_radius: float) -> Node:
	var closest_entity = null
	var closest_distance = search_radius

	for entry in registered_entities:
		var entity = entry["entity"]
		if entity and is_instance_valid(entity):
			var distance = entity.position.distance_to(world_pos)
			if distance < closest_distance:
				closest_distance = distance
				closest_entity = entity

	return closest_entity

## Update an entity's tile position in the registry
## Call this after an entity completes movement
## @param entity: The entity that moved
## @param new_tile: The new tile coordinates
func update_entity_tile(entity: Node, new_tile: Vector2i) -> bool:
	for entry in registered_entities:
		if entry["entity"] == entity:
			entry["tile"] = new_tile

			# Update position in UnifiedEventBridge Actor (for combat targeting)
			if "ulid" in entity and not entity.ulid.is_empty():
				var bridge = Cache.get_unified_event_bridge()
				if bridge:
					bridge.update_entity_position(entity.ulid, new_tile.x, new_tile.y)

			# Reveal chunk where entity moved to (for fog of war exploration)
			if ChunkManager:
				ChunkManager.reveal_chunk_at_tile(new_tile)

			return true
	return false

## ============================================================================
## INITIALIZATION & SIGNAL SETUP
## ============================================================================

func _ready() -> void:
	# Wait for Cache to initialize
	await get_tree().process_frame

	# Connect to UnifiedEventBridge signals
	var bridge = get_node_or_null("/root/UnifiedEventBridge")
	if bridge:
		bridge.entity_spawned.connect(_on_spawn_completed_global)
		bridge.spawn_failed.connect(_on_spawn_failed)
		bridge.random_dest_found.connect(_on_random_destination_found)
	else:
		push_error("EntityManager: UnifiedEventBridge not found!")

	# Connect to game timer for turn-based updates
	if GameTimer:
		GameTimer.turn_changed.connect(_on_turn_changed)

## Initialize EntityManager with game references (called by main.gd)
func initialize(p_hex_map: Node, p_tile_map) -> void:
	hex_map = p_hex_map
	tile_map = p_tile_map

## ============================================================================
## REAL-TIME ENTITY UPDATES (per-frame with throttling)
## ============================================================================

## Called once per turn by GameTimer signal (kept for compatibility)
func _on_turn_changed(_turn: int) -> void:
	pass  # No longer using turn-based updates

## Update all registered entities every frame (with per-entity move timers)
func _process(delta: float) -> void:
	# Throttle movement updates to avoid per-frame overhead
	movement_update_accumulator += delta

	if movement_update_accumulator >= MOVEMENT_UPDATE_INTERVAL:
		movement_update_accumulator = 0.0
		_update_all_entities(delta)

## Update all registered entities (called every 0.5 seconds, not every frame!)
func _update_all_entities(delta: float) -> void:
	var culled_count = 0
	var active_count = 0
	var processed_count = 0

	# Process entities in batches (round-robin) to spread work
	var total_entities = registered_entities.size()
	if total_entities == 0:
		return

	for i in range(ENTITIES_PER_UPDATE):
		var idx = (entity_process_index + i) % total_entities
		var entry = registered_entities[idx]
		var entity = entry["entity"]

		# Skip invalid entities
		if not entity or not is_instance_valid(entity):
			continue

		# Skip entities in combat (they shouldn't move)
		if "current_state" in entity:
			var IN_COMBAT_FLAG = 0b1000000  # 0x40
			if entity.current_state & IN_COMBAT_FLAG:
				continue

		# Skip entities in non-visible chunks (chunk culling optimization)
		if ChunkManager and ChunkManager.chunk_culling_enabled:
			var entity_chunk = MapConfig.tile_to_chunk(entry["tile"])

			# PROCEDURAL WORLD: Use visible_chunks (Array of Vector2i) instead of visible_chunk_indices
			if not entity_chunk in ChunkManager.visible_chunks:
				culled_count += 1
				continue

		active_count += 1
		processed_count += 1

		# Update entity's move timer (accumulate time since last check)
		entry["move_timer"] += MOVEMENT_UPDATE_INTERVAL

		# Check if it's time for this entity to move
		if entry["move_timer"] >= entry["move_interval"]:
			entry["move_timer"] = 0.0  # Reset timer
			# Trigger entity movement (real-time with per-entity intervals)
			_handle_entity_movement(entity, entry["tile"], entry["pool_key"], entry)

	# Advance the round-robin index for next update
	entity_process_index = (entity_process_index + ENTITIES_PER_UPDATE) % max(total_entities, 1)

## ============================================================================
## ENTITY MOVEMENT & PATHFINDING (moved from main.gd)
## ============================================================================

## Handle entity movement by requesting pathfinding
func _handle_entity_movement(entity: Node, current_tile: Vector2i, pool_key: String, registry_entry: Dictionary) -> void:
	# Defensive: Validate entity exists
	if not entity or not is_instance_valid(entity):
		return

	# CRITICAL: Don't request new movement if entity is already moving or pathfinding
	# Use state flags as single source of truth (no redundant is_moving boolean)
	if "current_state" in entity and entity.has_method("has_state"):
		# Use the NPC's State enum constants directly (not hardcoded hex values)
		const State = preload("res://nodes/npc/npc.gd").State

		# Don't interrupt if entity is moving, pathfinding, or blocked
		if entity.has_state(State.MOVING) or \
		   entity.has_state(State.PATHFINDING) or \
		   entity.has_state(State.BLOCKED):
			return

	# Double-check: if entity has waypoints remaining in path, don't interrupt
	if "current_path" in entity and "path_index" in entity:
		if entity.current_path.size() > 0 and entity.path_index < entity.current_path.size():
			return  # Entity still has waypoints to follow

	# Unified pathfinding for ALL entity types (water and land)
	# Determine random destination distance based on entity type
	var min_distance = 2 if pool_key == "viking" else 3
	var max_distance = 5 if pool_key == "viking" else 8

	# Request random destination (ASYNC - uses signals)
	# Result will be handled by _on_random_destination_found signal handler via UnifiedEventBridge
	var bridge = Cache.get_unified_event_bridge()
	if bridge:
		bridge.request_random_destination(
			entity.ulid,
			entity.terrain_type,
			current_tile.x,
			current_tile.y,
			min_distance,
			max_distance
		)

## Handle random destination found signal from pathfinding bridge
## Handle spawn failure from UnifiedEventBridge
func _on_spawn_failed(entity_type: String, error: String) -> void:
	push_warning("EntityManager: Spawn failed for %s: %s" % [entity_type, error])
	# Remove pending context
	if pending_spawn_contexts.has(entity_type) and not pending_spawn_contexts[entity_type].is_empty():
		pending_spawn_contexts[entity_type].pop_front()

## Handle random destination found from UnifiedEventBridge
func _on_random_destination_found(entity_ulid: PackedByteArray, destination_q: int, destination_r: int, found: bool) -> void:
	if not found:
		return  # No valid destination found

	# Convert destination from q/r to Vector2i
	var destination = Vector2i(destination_q, destination_r)

	# Find the entity by ULID
	var entity = _find_entity_by_ulid(entity_ulid)
	if not entity or not is_instance_valid(entity):
		return

	# Get current tile
	if not tile_map:
		push_error("EntityManager: tile_map not initialized!")
		return

	var current_tile = tile_map.local_to_map(entity.position)
	if destination == current_tile:
		return  # Destination is same as current position

	# Free up current tile (we'll put it back if pathfinding fails)
	occupied_tiles.erase(current_tile)

	# Request pathfinding - connect to entity's signal to update occupied_tiles
	# The NPC will emit pathfinding_completed signal when done
	if entity.has_method("request_pathfinding"):
		# Check if already connected (entity still pathfinding from previous request)
		if not entity.pathfinding_completed.is_connected(_on_entity_pathfinding_completed):
			# Connect to entity's pathfinding_completed signal (ONE_SHOT auto-disconnects)
			entity.pathfinding_completed.connect(_on_entity_pathfinding_completed.bind(entity, current_tile), CONNECT_ONE_SHOT)
		else:
			# Entity is still pathfinding - skip this movement request
			occupied_tiles[current_tile] = entity  # Put it back
			return

		# Request pathfinding without callback - signal will handle it
		entity.request_pathfinding(destination, tile_map)
	else:
		occupied_tiles[current_tile] = entity  # Put it back

## Handle entity pathfinding completed signal
func _on_entity_pathfinding_completed(path: Array[Vector2i], success: bool, entity: Node, original_tile: Vector2i) -> void:
	# CRITICAL: Use defensive validation helper
	entity = get_valid_entity(entity)
	if not entity:
		# Entity was freed - clean up occupied_tiles
		occupied_tiles.erase(original_tile)
		return

	# NOTE: Position syncing is handled by the NPC class when movement completes
	# Path validation is handled by UnifiedEventBridge's Rust Actor

	if success and path.size() > 0:
		var final_destination = path[path.size() - 1]

		# Update occupied tiles
		occupied_tiles[final_destination] = entity
		# Update EntityManager registry
		update_entity_tile(entity, final_destination)
	else:
		# Pathfinding failed - entity stays at current tile
		occupied_tiles[original_tile] = entity

## Find entity by ULID
func _find_entity_by_ulid(ulid: PackedByteArray) -> Node:
	for entry in registered_entities:
		var entity = entry.get("entity")
		if entity and "ulid" in entity:
			if entity.ulid == ulid:
				return entity
	return null
