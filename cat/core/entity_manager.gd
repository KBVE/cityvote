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

	# Register with combat system if entity has ULID and player_ulid
	if "ulid" in entity and "player_ulid" in entity:
		_register_combat(entity, tile)

	return true

## Unregister an entity from the registry
## @param entity: The entity to unregister
## @return: bool - True if found and unregistered
func unregister_entity(entity: Node) -> bool:
	for i in range(registered_entities.size()):
		if registered_entities[i]["entity"] == entity:
			# Unregister from combat system
			if "ulid" in entity:
				_unregister_combat(entity)

			registered_entities.remove_at(i)
			print("EntityManager: Unregister entity (remaining: %d)" % registered_entities.size())
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
##   - tile_map: TileMapCompat - Reference to the tile map wrapper
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
	var valid_tiles: Array = _find_valid_tiles(tile_type, hex_map, occupied_tiles, near_pos)

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
						print("EntityManager: Found %d valid tiles near %v using radial search (radius %d)" % [result.size(), center, radius])
						return result

	# Sort by distance
	tiles_with_distance.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var result: Array = []
	for tile_data in tiles_with_distance:
		result.append(tile_data["pos"])
	print("EntityManager: Found %d valid tiles near %v using radial search" % [result.size(), center])
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
		print("EntityManager: No chunks loaded yet, searching near origin")
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

	print("EntityManager: Found %d valid tiles using chunk sampling" % valid_tiles.size())
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

			# Update position in combat system
			if "ulid" in entity:
				_update_combat_position(entity, new_tile)

			# Reveal chunk where entity moved to (for fog of war exploration)
			if ChunkManager:
				ChunkManager.reveal_chunk_at_tile(new_tile)

			return true
	return false

## Internal: Register entity with combat system
func _register_combat(entity: Node, tile: Vector2i) -> void:
	if not CombatManager or not CombatManager.combat_bridge:
		push_warning("EntityManager: CombatManager not ready, skipping combat registration")
		return

	if not "ulid" in entity or entity.ulid.is_empty():
		push_error("EntityManager: Cannot register entity for combat - missing or invalid ULID")
		return

	var ulid: PackedByteArray = entity.ulid
	var player_ulid: PackedByteArray = entity.player_ulid if "player_ulid" in entity else PackedByteArray()
	var attack_interval: float = 2.5  # Default attack interval

	# Register with Rust combat system
	CombatManager.combat_bridge.register_combatant(ulid, player_ulid, tile, attack_interval)

## Internal: Unregister entity from combat system
func _unregister_combat(entity: Node) -> void:
	if not CombatManager or not CombatManager.combat_bridge:
		return  # Silent fail - combat system may not be initialized yet

	if not "ulid" in entity or entity.ulid.is_empty():
		return  # Silent fail - entity doesn't have ULID

	var ulid: PackedByteArray = entity.ulid
	CombatManager.combat_bridge.unregister_combatant(ulid)

## Internal: Update entity position in combat system
func _update_combat_position(entity: Node, tile: Vector2i) -> void:
	if not CombatManager or not CombatManager.combat_bridge:
		return  # Silent fail - combat system may not be initialized

	if not "ulid" in entity or entity.ulid.is_empty():
		return  # Silent fail - entity doesn't have ULID

	var ulid: PackedByteArray = entity.ulid
	CombatManager.combat_bridge.update_position(ulid, tile)
