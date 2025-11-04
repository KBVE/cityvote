extends Node
class_name Pool

# Generic object pool for efficient resource management
# Pools pre-instantiate objects and reuse them instead of creating/destroying

var packed_scene: PackedScene
var pool_size: int = 10
var available: Array[Node] = []
var active: Array[Node] = []

func _init(scene: PackedScene, initial_size: int = 10):
	packed_scene = scene
	pool_size = initial_size

func _ready():
	# Pre-instantiate pool objects
	_grow_pool(pool_size)

# Grow the pool by creating more instances
func _grow_pool(count: int):
	for i in range(count):
		var instance = packed_scene.instantiate()
		instance.set_process(false)
		instance.set_physics_process(false)
		instance.hide()
		add_child(instance)
		available.append(instance)

# Get an object from the pool
func acquire() -> Node:
	if available.is_empty():
		# Pool exhausted, grow it
		_grow_pool(pool_size / 2)

	var instance = available.pop_back()
	active.append(instance)

	# Remove from pool so it can be reparented
	remove_child(instance)

	instance.show()
	instance.set_process(true)
	instance.set_physics_process(true)

	return instance

# Return an object to the pool
func release(instance: Node):
	if instance in active:
		active.erase(instance)
		available.append(instance)

		# Remove from current parent and add back to pool
		if instance.get_parent():
			instance.get_parent().remove_child(instance)
		add_child(instance)

		instance.hide()
		instance.set_process(false)
		instance.set_physics_process(false)

		# Reset position
		instance.global_position = Vector2.ZERO

		# Reset transform properties for pool reuse
		instance.scale = Vector2(1.0, 1.0)
		instance.rotation = 0.0

		# CRITICAL: Call reset_for_pool() to clear ALL internal state
		# This prevents stale data (signals, references, state flags) across pool reuse
		if instance.has_method("reset_for_pool"):
			instance.reset_for_pool()

# Get count of available objects
func get_available_count() -> int:
	return available.size()

# Get count of active objects
func get_active_count() -> int:
	return active.size()

# Clear all objects
func clear():
	for instance in active:
		instance.queue_free()
	for instance in available:
		instance.queue_free()
	active.clear()
	available.clear()
