extends Node

## EntityManager - Centralized entity lifecycle management
## Handles spawning/despawning of all game entities (NPCs, Ships, etc.)
## Manages health bar pooling to ensure proper setup and cleanup

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

## Despawn an entity, returning it to the pool
## @param entity: The entity to despawn
## @param pool_key: Pool key to return entity to (e.g., "jezza", "viking")
func despawn_entity(entity: Node, pool_key: String) -> void:
	if not entity or not is_instance_valid(entity):
		push_warning("EntityManager: Cannot despawn - entity is invalid!")
		return

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
