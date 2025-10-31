extends Node

## EntityManager - Centralized entity lifecycle management
## Handles spawning/despawning of all game entities (NPCs, Ships, etc.)
## Manages health bar pooling to ensure proper setup and cleanup
## Tracks all entities in a unified registry for movement and querying

## Entity type definitions for spawn_multiple
enum TileType {
	LAND,   # Non-water tiles (for ground units like Jezzas)
	WATER,  # Water tiles (for ships like Vikings)
	ANY     # Any tile (for flying units, etc.)
}

## Unified entity registry - tracks all spawned entities
## Each entry: {entity: Node, type: String, pool_key: String, move_timer: float, move_interval: float, tile: Vector2i}
var registered_entities: Array = []

## Entity type configurations (movement intervals, etc.)
const ENTITY_CONFIGS = {
	"viking": {"move_interval": 2.0, "tile_type": TileType.WATER},
	"jezza": {"move_interval": 3.0, "tile_type": TileType.LAND},
	"fantasywarrior": {"move_interval": 2.5, "tile_type": TileType.LAND},
	"king": {"move_interval": 2.0, "tile_type": TileType.LAND},
}

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

	print("EntityManager: Spawned %s at %v" % [entity.get_class() if entity.has_method("get_class") else entity.name, world_pos])
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
	print("EntityManager: Registered %s (total entities: %d)" % [pool_key, registered_entities.size()])
	return true

## Unregister an entity from the registry
## @param entity: The entity to unregister
## @return: bool - True if found and unregistered
func unregister_entity(entity: Node) -> bool:
	for i in range(registered_entities.size()):
		if registered_entities[i]["entity"] == entity:
			registered_entities.remove_at(i)
			print("EntityManager: Unregistered entity (remaining: %d)" % registered_entities.size())
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
		print("EntityManager: Despawned %s, returned to pool '%s'" % [entity.name, pool_key])
	else:
		push_error("EntityManager: Cluster not available for despawn!")

## Setup health bar for an entity (acquires from pool and initializes)
func _setup_entity_health_bar(entity: Node) -> void:
	# Only setup if entity has health_bar property
	if not "health_bar" in entity:
		return

	# Check if health bar already exists and is valid
	if entity.health_bar and is_instance_valid(entity.health_bar):
		print("EntityManager: Entity already has valid health bar, skipping setup")
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
		print("EntityManager: Health bar initialized with HP: %d/%d" % [current_hp, max_hp])
	else:
		# Default values
		health_bar.initialize(100.0, 100.0)
		print("EntityManager: Health bar initialized with default HP: 100/100")

	# Configure appearance
	health_bar.set_bar_offset(Vector2(0, -30))  # Position above entity
	health_bar.set_auto_hide(false)  # Always visible

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
	print("EntityManager: Health bar cleaned up and returned to pool")

## Generic function to spawn multiple entities of a specific type
## This replaces the need for separate _spawn_jezza_for_player, _spawn_vikings_for_player, etc.
## @param spawn_config: Dictionary with required fields:
##   - pool_key: String - Pool key to acquire from (e.g., "jezza", "viking")
##   - count: int - Number of entities to spawn
##   - tile_type: TileType - What type of tiles to spawn on (LAND, WATER, ANY)
##   - hex_map: Node - Reference to hex map
##   - tile_map: TileMap - Reference to the tile map
##   - occupied_tiles: Dictionary - Reference to occupied tiles dict
##   - storage_array: Array - Array to store spawned entity data in
##   - player_ulid: PackedByteArray - Player ownership
##   - near_pos: Vector2i (optional) - Card position to spawn near (default: Vector2i(-1, -1))
##   - entity_name: String (optional) - Display name for logging (default: pool_key)
##   - post_spawn_callback: Callable (optional) - Function to call after each spawn (receives entity as parameter)
## @return: int - Number of entities successfully spawned
func spawn_multiple(spawn_config: Dictionary) -> int:
	# Validate required fields
	var required_fields = ["pool_key", "count", "tile_type", "hex_map", "tile_map", "occupied_tiles", "storage_array", "player_ulid"]
	for field in required_fields:
		if not spawn_config.has(field):
			push_error("EntityManager.spawn_multiple: Missing required field '%s'" % field)
			return 0

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
	var post_spawn_callback: Callable = spawn_config.get("post_spawn_callback", Callable())

	print("EntityManager: Spawning %d %s(s) for player %s%s" % [
		count,
		entity_name,
		UlidManager.to_hex(player_ulid),
		" near position %v" % near_pos if near_pos != Vector2i(-1, -1) else ""
	])

	# Find valid tiles based on tile_type
	var valid_tiles: Array = _find_valid_tiles(tile_type, tile_map, occupied_tiles, near_pos)

	if valid_tiles.size() < count:
		push_error("EntityManager: Not enough valid tiles to spawn %d %s(s) (found %d)" % [count, entity_name, valid_tiles.size()])
		return 0

	# Spawn entities
	var spawned_count = 0
	print("EntityManager: Starting spawn loop for %d %s(s)" % [count, entity_name])

	for i in range(count):
		var entity = Cluster.acquire(pool_key)

		if entity:
			# Get spawn tile (closest if near_pos provided, otherwise first available)
			var spawn_tile: Vector2i = valid_tiles[0]
			valid_tiles.remove_at(0)

			# Convert to world position
			var world_pos = tile_map.map_to_local(spawn_tile)

			# Configure entity
			var entity_config = {
				"player_ulid": player_ulid,
				"direction": randi() % 16,
				"occupied_tiles": occupied_tiles
			}

			# Spawn using base spawn_entity
			spawn_entity(entity, hex_map, world_pos, entity_config)

			# Register with EntityManager for movement tracking
			register_entity(entity, pool_key, spawn_tile)

			# Reveal chunk where entity spawned (for fog of war)
			if ChunkManager:
				ChunkManager.reveal_chunk_at_tile(spawn_tile)

			# Call post-spawn callback if provided (e.g., for wave shader on Vikings)
			if post_spawn_callback.is_valid():
				post_spawn_callback.call(entity)

			# Mark tile as occupied
			occupied_tiles[spawn_tile] = entity

			# Store in tracking array (using "entity" for both NPCs and Ships)
			storage_array.append({"entity": entity, "tile": spawn_tile})

			spawned_count += 1
			print("  -> Spawned %s %d/%d at tile %v" % [entity_name, i + 1, count, spawn_tile])
		else:
			push_error("EntityManager: Failed to acquire %s %d from pool '%s'" % [entity_name, i + 1, pool_key])

	print("EntityManager: Finished spawning. %d %s(s) spawned. Total in storage: %d" % [spawned_count, entity_name, storage_array.size()])
	return spawned_count

## Helper: Find valid tiles for spawning based on tile type
## @param tile_type: TileType - What type of tiles to find
## @param tile_map: TileMap - The tile map to search
## @param occupied_tiles: Dictionary - Tiles that are already occupied
## @param near_pos: Vector2i - Optional position to sort tiles by distance from
## @return: Array of Vector2i - Valid spawn tiles (sorted by distance if near_pos provided)
func _find_valid_tiles(tile_type: TileType, tile_map, occupied_tiles: Dictionary, near_pos: Vector2i) -> Array:
	var tiles_with_distance: Array = []
	var has_near_pos = near_pos != Vector2i(-1, -1)

	# Helper for hex distance calculation
	var hex_distance = func(a: Vector2i, b: Vector2i) -> int:
		var dx = abs(a.x - b.x)
		var dy = abs(a.y - b.y)
		var dz = abs(dx + dy)
		return (dx + dy + dz) / 2

	# Scan all tiles
	for x in range(MapConfig.MAP_WIDTH):
		for y in range(MapConfig.MAP_HEIGHT):
			var tile_coords = Vector2i(x, y)

			# Skip occupied tiles
			if occupied_tiles.has(tile_coords):
				continue

			# Get tile source
			var source_id = tile_map.get_cell_source_id(0, tile_coords)

			# Check if tile matches the required type
			var is_valid = false
			match tile_type:
				TileType.LAND:
					is_valid = source_id != MapConfig.SOURCE_ID_WATER
				TileType.WATER:
					is_valid = source_id == MapConfig.SOURCE_ID_WATER
				TileType.ANY:
					is_valid = true

			if is_valid:
				if has_near_pos:
					var distance = hex_distance.call(near_pos, tile_coords)
					tiles_with_distance.append({"pos": tile_coords, "dist": distance})
				else:
					tiles_with_distance.append({"pos": tile_coords, "dist": 0})

	# Sort by distance if near_pos provided
	if has_near_pos:
		tiles_with_distance.sort_custom(func(a, b): return a["dist"] < b["dist"])
		print("EntityManager: Found %d valid tiles sorted by distance from %v" % [tiles_with_distance.size(), near_pos])
	else:
		print("EntityManager: Found %d valid tiles (no sorting)" % tiles_with_distance.size())

	# Extract just the positions
	var result: Array = []
	for tile_data in tiles_with_distance:
		result.append(tile_data["pos"])

	return result

## Update all registered entities (movement timers)
## Call this from main scene's _process(delta)
## @param delta: Time since last frame
## @param movement_callback: Callable that handles pathfinding for an entity
##   Signature: func(entity: Node, current_tile: Vector2i, pool_key: String)
func update_entities(delta: float, movement_callback: Callable) -> void:
	var culled_count = 0
	var active_count = 0

	for entry in registered_entities:
		var entity = entry["entity"]

		# Skip invalid entities
		if not entity or not is_instance_valid(entity):
			continue

		# Skip entities in non-visible chunks (chunk culling optimization)
		if ChunkManager and ChunkManager.chunk_culling_enabled:
			var entity_chunk = MapConfig.tile_to_chunk(entry["tile"])
			var chunk_index = MapConfig.chunk_coords_to_index(entity_chunk)

			# Only update entities in visible chunks
			if not chunk_index in ChunkManager.visible_chunk_indices:
				culled_count += 1
				continue

		active_count += 1

		# Update movement timer
		entry["move_timer"] += delta

		# Check if it's time to move
		if entry["move_timer"] >= entry["move_interval"]:
			entry["move_timer"] = 0.0

			# Call the movement callback to handle pathfinding
			if movement_callback.is_valid():
				movement_callback.call(entity, entry["tile"], entry["pool_key"], entry)

	# Update statistics for debugging
	if ChunkManager:
		ChunkManager.culled_entities_count = culled_count
		ChunkManager.active_entities_count = active_count

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

			# Reveal chunk where entity moved to (for fog of war exploration)
			if ChunkManager:
				ChunkManager.reveal_chunk_at_tile(new_tile)

			return true
	return false
