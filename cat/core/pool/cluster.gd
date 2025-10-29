extends Node

# Cluster manages all object pools in the game
# Singleton pattern for global access via autoload

static var instance

# Pool registry - holds all pools by name
var pools: Dictionary = {}

func _init():
	if instance == null:
		instance = self
	else:
		queue_free()

func _ready():
	# Initialize all pools
	_setup_pools()

# Set up all game object pools
func _setup_pools():
	# Viking ship pool
	var viking_scene = preload("res://nodes/ships/viking/viking.tscn")
	register_pool("viking", viking_scene, 20)

	# Jezza raptor NPC pool
	var jezza_scene = preload("res://nodes/npc/dino/jezza/jezza.tscn")
	register_pool("jezza", jezza_scene, 10)

	# Fantasy Warrior NPC pool
	var fantasy_warrior_scene = preload("res://nodes/npc/fantasy-warrior/fantasy_warrior.tscn")
	register_pool("fantasywarrior", fantasy_warrior_scene, 10)

	# Playing card pool (starts with MAX_HAND capacity)
	# Pool grows dynamically if needed. Deck stores CardData, not instances.
	var card_scene = preload("res://nodes/cards/pooled_card.tscn")
	register_pool("playing_card", card_scene, 12)  # MAX_HAND = 12

	# Health bar pool (large initial size for 1000+ entities)
	# Used by ships, NPCs, and any other entities that need health display
	var health_bar_scene = preload("res://view/hud/healthbar/health_bar.tscn")
	register_pool("health_bar", health_bar_scene, 100)  # Start with 100, will grow as needed

	# Add more pools here as needed
	# register_pool("city", city_scene, 10)
	# register_pool("unit", unit_scene, 50)

# Register a new pool
func register_pool(pool_name: String, packed_scene: PackedScene, initial_size: int = 10):
	if pool_name in pools:
		push_warning("Pool '%s' already exists, replacing..." % pool_name)
		pools[pool_name].clear()

	var pool = Pool.new(packed_scene, initial_size)
	pool.name = pool_name + "_pool"
	add_child(pool)
	pools[pool_name] = pool

# Get an object from a specific pool
func acquire(pool_name: String) -> Node:
	if pool_name not in pools:
		push_error("Pool '%s' does not exist!" % pool_name)
		return null

	return pools[pool_name].acquire()

# Return an object to its pool
func release(pool_name: String, instance: Node):
	if pool_name not in pools:
		push_error("Pool '%s' does not exist!" % pool_name)
		return

	pools[pool_name].release(instance)

# Get pool statistics
func get_pool_stats(pool_name: String) -> Dictionary:
	if pool_name not in pools:
		return {}

	var pool = pools[pool_name]
	return {
		"available": pool.get_available_count(),
		"active": pool.get_active_count(),
		"total": pool.get_available_count() + pool.get_active_count()
	}

# Get all pool names
func get_pool_names() -> Array:
	return pools.keys()

# Clear a specific pool
func clear_pool(pool_name: String):
	if pool_name in pools:
		pools[pool_name].clear()

# Clear all pools
func clear_all():
	for pool_name in pools:
		pools[pool_name].clear()

# Static helper for global access
static func get_instance():
	return instance
