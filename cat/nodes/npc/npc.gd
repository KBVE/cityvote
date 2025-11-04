extends Node2D
class_name NPC

# Base class for all NPCs (land and water-based) with 16-directional sprites and state management
#
# Unified entity system supporting both land and water pathfinding via terrain type flags.
# Uses critically-damped angular spring for smooth rotation and continuous path following.

## Signal emitted when pathfinding completes (for main.gd to update occupied_tiles)
signal pathfinding_completed(path: Array[Vector2i], success: bool)

@onready var sprite: Sprite2D = $Sprite2D

# Terrain Type enum (matches Rust TerrainType and unified pathfinding system)
enum TerrainType {
	WATER = 0,  # Entity walks on water (ships, vikings)
	LAND = 1,   # Entity walks on land (ground NPCs, kings, warriors)
}

# NPC State enum (matches Rust bitwise flags pattern)
enum State {
	IDLE = 0b0001,           # NPC is idle, can accept commands
	MOVING = 0b0010,         # NPC is moving along a path
	PATHFINDING = 0b0100,    # Pathfinding request in progress
	BLOCKED = 0b1000,        # NPC is blocked (cannot move)
	INTERACTING = 0b10000,   # NPC is interacting with object/player
	DEAD = 0b100000,         # NPC is dead (no longer active)
	IN_COMBAT = 0b1000000,   # NPC is in combat (0x40)
}

# Cached state from Rust (updated via signal)
# NOTE: Rust EntityManagerBridge is the single source of truth for state
# This is just a local cache for performance
var current_state: int = State.IDLE

# Terrain type (set by child classes) - determines pathfinding behavior
var terrain_type: int = TerrainType.LAND  # Default to land

# Reference to EntityManagerBridge (Rust source of truth)
var entity_manager: Node = null

# Pool management (set by child classes if pooled)
var pool_name: String = ""  # Name of the pool this entity belongs to (e.g., "viking", "king")
var attack_interval: float = 3.0  # Attack interval in seconds (can be overridden by child classes)

# Direction (0-15, where 0 is north, going counter-clockwise)
var direction: int = 0
var _last_sector: int = 0  # For hysteresis

# Continuous angular representation for smooth interpolation
var current_angle: float = 0.0  # Current facing angle in degrees (0-360)
var target_angle: float = 0.0   # Target angle we're steering toward
var angular_velocity: float = 0.0  # Current rate of rotation in degrees/sec

# Preloaded NPC sprites (to be set by child classes)
# Note: Legacy ship code may use 'ship_sprites' - both are supported for backwards compatibility
var npc_sprites: Array[Texture2D] = []
var ship_sprites: Array[Texture2D] = []  # Alias for water entities (backwards compatibility)

# Movement state
var is_moving: bool = false
var is_rotating_to_target: bool = false  # Rotating before moving (water entities only)
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 2.5  # Movement speed in tiles per second (default for land, water entities use 3.0)
var move_distance: float = 0.0  # Distance in pixels for current movement segment
var rotation_threshold: float = 5.0  # Degrees - how close to target angle before starting movement (water entities only)

# Path following
var current_path: Array[Vector2i] = []  # Tile coordinates of path to follow
var path_index: int = 0  # Current position in path
var on_path_complete: Callable  # Callback when entire path is complete
var on_waypoint_reached: Callable  # Callback when each waypoint is reached
var path_visualizer: Node2D = null  # Visual representation of path
var pending_path_callbacks: Dictionary = {}  # ULID hex -> callback for pathfinding results

# Critically-damped spring parameters for organic motion
var angular_stiffness: float = 18.0
var angular_damping_strength: float = 12.0
var steering_anticipation: float = 0.15
var sector_edge_buffer: float = 5.0

# Reference to occupied tiles for collision detection
var occupied_tiles: Dictionary = {}  # Shared reference set by main.gd

# ULID for persistent entity tracking
var ulid: PackedByteArray = PackedByteArray()

# Player ownership ULID (which player controls this NPC)
# Empty = AI-controlled, otherwise contains player's ULID
var player_ulid: PackedByteArray = PackedByteArray()

# Health bar reference (acquired from pool)
var health_bar: HealthBar = null

# Energy system for movement
var energy: int = 100
var max_energy: int = 100

# Flag to prevent re-initialization when reused from pool
var _initialized: bool = false

func _ready():
	# Skip re-initialization if entity is being reused from pool
	if _initialized:
		# Just update visual state and return
		_update_z_index()
		_update_sprite()
		return

	_initialized = true

	# Enable _process() for movement updates
	set_process(true)

	# Set initial z-index based on spawn position
	_update_z_index()

	# Get reference to EntityManagerBridge (Rust source of truth)
	# Note: EntityManagerBridge is created as StatsManager.rust_bridge
	call_deferred("_initialize_entity_manager")

	# Register with ULID system (use terrain-specific type for backwards compatibility)
	if ulid.is_empty():
		var ulid_type = UlidManager.TYPE_SHIP if terrain_type == TerrainType.WATER else UlidManager.TYPE_NPC
		ulid = UlidManager.register_entity(self, ulid_type, {
			"entity_type": get_class(),
			"position": position,
			"state": current_state,
			"terrain_type": terrain_type
		})

	# Register with stats system (deferred to ensure StatsManager is ready)
	if StatsManager:
		call_deferred("_register_stats")

	# Register with combat system (deferred to ensure CombatManager is ready)
	if CombatManager:
		call_deferred("_register_combat")

	# Initialize current angle based on initial direction
	current_angle = direction_to_godot_angle(direction)
	target_angle = current_angle
	_last_sector = direction
	_update_sprite()

	# Acquire health bar from pool (deferred to ensure Cluster is ready)
	call_deferred("_setup_health_bar")

# === State Management (Rust as Source of Truth) ===

## Initialize entity manager reference (deferred to ensure StatsManager is ready)
func _initialize_entity_manager() -> void:
	if StatsManager and StatsManager.rust_bridge:
		entity_manager = StatsManager.rust_bridge
		# Connect to Rust state change signal
		entity_manager.entity_state_changed.connect(_on_rust_state_changed)
	else:
		# Retry after a short delay if StatsManager isn't ready yet
		await get_tree().create_timer(0.1).timeout
		if StatsManager and StatsManager.rust_bridge:
			entity_manager = StatsManager.rust_bridge
			entity_manager.entity_state_changed.connect(_on_rust_state_changed)
		# If still not ready, it's a real error - but don't spam, just fail silently
		# State management won't work but entity can still function

## Signal handler: Rust state changed
func _on_rust_state_changed(entity_ulid: PackedByteArray, new_state: int) -> void:
	# Only update if this is our entity
	if entity_ulid == ulid:
		current_state = new_state

## Set state (notifies Rust - DO NOT use for local changes)
func set_state(new_state: int) -> void:
	if entity_manager:
		entity_manager.set_entity_state(ulid, new_state)
	# Cache will be updated via signal

## Add state flag (notifies Rust)
func add_state(state_flag: int) -> void:
	var new_state = current_state | state_flag
	if entity_manager:
		entity_manager.set_entity_state(ulid, new_state)

## Remove state flag (notifies Rust)
func remove_state(state_flag: int) -> void:
	var new_state = current_state & ~state_flag
	if entity_manager:
		entity_manager.set_entity_state(ulid, new_state)

## Check if entity has state flag (reads from cache)
func has_state(state_flag: int) -> bool:
	return (current_state & state_flag) != 0

## Check if entity is idle (reads from cache)
func is_idle() -> bool:
	return has_state(State.IDLE)

func is_moving_state() -> bool:
	return has_state(State.MOVING)

func can_accept_command() -> bool:
	return is_idle() and not has_state(State.PATHFINDING) and not has_state(State.BLOCKED)

# === Angular/Direction Functions ===

func direction_to_godot_angle(dir: int) -> float:
	return fmod(270.0 - (dir * 22.5) + 360.0, 360.0)

func shortest_angle_deg(from_angle: float, to_angle: float) -> float:
	var diff = fmod((to_angle - from_angle + 540.0), 360.0) - 180.0
	return diff

func set_direction(new_direction: int):
	direction = new_direction % 16
	target_angle = direction_to_godot_angle(direction)

func _update_sprite():
	if direction >= 0 and direction < 16:
		# Check if using Sprite2D region mode (for atlas with shader)
		if sprite.region_enabled:
			# Calculate which cell in the 4x4 atlas (each cell is 64x64)
			var col = direction % 4
			var row = direction >> 2  # Bit shift for integer division by 4
			sprite.region_rect = Rect2(col * 64, row * 64, 64, 64)
		# Check if using shader-based direction (for shader UV remapping)
		elif sprite.material and sprite.material is ShaderMaterial:
			var shader_mat = sprite.material as ShaderMaterial
			shader_mat.set_shader_parameter("direction", direction)
		# Check if using AtlasTexture (for non-shader atlas approach)
		elif sprite.texture and sprite.texture is AtlasTexture:
			var atlas_tex = sprite.texture as AtlasTexture
			# Calculate which cell in the 4x4 atlas (each cell is 64x64)
			var col = direction % 4
			var row = direction >> 2  # Bit shift for integer division by 4
			atlas_tex.region = Rect2(col * 64, row * 64, 64, 64)
		elif direction < ship_sprites.size():
			# Fallback to texture swapping (ship sprites)
			sprite.texture = ship_sprites[direction]
		elif direction < npc_sprites.size():
			# Fallback to texture swapping (npc sprites)
			sprite.texture = npc_sprites[direction]

func _apply_residual_pivot():
	var dir_center = direction_to_godot_angle(direction)
	var residual = shortest_angle_deg(dir_center, current_angle)
	residual = clamp(residual, -8.0, 8.0)
	sprite.rotation_degrees = residual

func angle_to_direction_stable(angle: float) -> int:
	angle = fmod(angle + 360.0, 360.0)
	var godot_sector = int(floor((angle + 11.25) / 22.5)) % 16
	var idx = (12 - godot_sector) & 15

	# Hysteresis
	if idx != _last_sector:
		var center_prev = direction_to_godot_angle(_last_sector)
		var diff_prev = abs(shortest_angle_deg(center_prev, angle))
		if diff_prev < (11.25 + sector_edge_buffer):
			return _last_sector

	_last_sector = idx
	return idx

func vector_to_direction(vec: Vector2) -> int:
	var angle = rad_to_deg(vec.angle())
	return angle_to_direction_stable(angle)

func lerp_angle_deg(from: float, to: float, weight: float) -> float:
	var diff = shortest_angle_deg(from, to)
	return fmod(from + diff * weight + 360.0, 360.0)

func _update_angular_motion(delta: float):
	var angle_err = shortest_angle_deg(current_angle, target_angle)
	angular_velocity += (angular_stiffness * angle_err - angular_damping_strength * angular_velocity) * delta
	current_angle = fmod(current_angle + angular_velocity * delta + 360.0, 360.0)

	var old_direction = direction
	direction = angle_to_direction_stable(current_angle)

	if direction != old_direction:
		_update_sprite()

	_apply_residual_pivot()

# === Movement Functions ===

func move_to(target_pos: Vector2):
	if is_moving or is_rotating_to_target:
		return  # Already moving or rotating

	# Set up new movement segment
	move_start_pos = position
	move_target_pos = target_pos
	move_progress = 0.0

	# Calculate distance for this movement segment (in pixels)
	move_distance = move_start_pos.distance_to(move_target_pos)

	# Set initial target angle based on movement vector
	var direction_vec = target_pos - position
	if direction_vec.length() > 0:
		target_angle = fmod(rad_to_deg(direction_vec.angle()) + 360.0, 360.0)

		# Get tile positions for Rust notification (use Cache singleton)
		var tile_map = Cache.get_tile_map()
		if tile_map:
			var start_tile = tile_map.local_to_map(move_start_pos)
			var target_tile = tile_map.local_to_map(move_target_pos)

			# Notify Rust: movement started (do this BEFORE setting is_moving for proper state sync)
			if entity_manager:
				entity_manager.notify_movement_started(ulid, start_tile.x, start_tile.y, target_tile.x, target_tile.y)
			else:
				# Warning: State won't sync to Rust without entity_manager
				var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"
				push_warning("NPC %s: entity_manager is null, state won't sync to Rust!" % ulid_hex)

			# Water entities rotate before moving (ships/vikings)
			if terrain_type == TerrainType.WATER:
				var angle_diff = abs(shortest_angle_deg(current_angle, target_angle))
				if angle_diff > rotation_threshold:
					# Start rotating phase - don't move yet
					is_rotating_to_target = true
					is_moving = false
				else:
					# Close enough, start moving immediately
					is_rotating_to_target = false
					is_moving = true
			else:
				# Land entities move immediately
				is_moving = true

func follow_path(path: Array[Vector2i], tile_map, complete_callback: Callable = Callable(), waypoint_callback: Callable = Callable()):
	if path.size() < 2:
		return

	# DEBUG: Verify path terrain types match entity terrain_type
	var bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
	if bridge:
		var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"
		var terrain_name = "WATER" if terrain_type == 0 else "LAND"

		# Check each waypoint for terrain validity
		var mismatches: Array = []
		for i in range(path.size()):
			var tile = path[i]
			var is_walkable = bridge.is_tile_walkable(terrain_type, tile)

			# Also get the actual terrain at this tile for comparison
			var tile_terrain = "UNKNOWN"
			if bridge.is_tile_walkable(0, tile):
				tile_terrain = "WATER"
			elif bridge.is_tile_walkable(1, tile):
				tile_terrain = "LAND"

			if not is_walkable:
				mismatches.append("%s(actual:%s)" % [str(tile), tile_terrain])

		if mismatches.size() > 0:
			push_error("NPC %s (terrain=%s): Path contains %d UNWALKABLE tiles: %s" % [ulid_hex, terrain_name, mismatches.size(), ", ".join(mismatches)])

	current_path = path
	path_index = 1  # Start at index 1 (0 is current position)
	on_path_complete = complete_callback
	on_waypoint_reached = waypoint_callback

	# Create path visualizer
	_create_path_visualizer(path, tile_map)

	_advance_to_next_waypoint()

## Request random movement within a distance range
## This is the preferred method for AI-controlled entities
## @param tile_map: The tile map reference for coordinate conversion
## @param min_distance: Minimum distance in tiles
## @param max_distance: Maximum distance in tiles
## @param callback: Optional callback when movement completes
func request_random_movement(tile_map, min_distance: int, max_distance: int, callback: Callable = Callable()) -> void:
	# Validate ULID
	if ulid.is_empty():
		push_error("request_random_movement: Entity has no ULID!")
		return

	# Get current tile position
	var current_tile = tile_map.local_to_map(position)

	# Get unified pathfinding bridge
	var bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
	if not bridge:
		push_error("request_random_movement: UnifiedPathfindingBridge not found!")
		return

	# Find random destination
	var destination = bridge.find_random_destination(
		ulid,
		terrain_type,
		current_tile,
		min_distance,
		max_distance
	)

	# If no destination found, stay put
	if destination == current_tile:
		return

	# Request pathfinding to that destination
	request_pathfinding(destination, tile_map, callback)

## Request pathfinding to a target tile (uses unified pathfinding bridge)
func request_pathfinding(target_tile: Vector2i, tile_map, callback: Callable = Callable()):
	# Validate ULID
	if ulid.is_empty():
		push_error("request_pathfinding: Entity has no ULID! Cannot request pathfinding.")
		return

	# Get current tile position
	var current_tile = tile_map.local_to_map(position)

	# Defensive: Check if destination is same as current position
	if target_tile == current_tile:
		# Already at destination - no pathfinding needed
		return

	# Set state to pathfinding
	add_state(State.PATHFINDING)

	# Get unified pathfinding bridge
	var bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
	if not bridge:
		push_error("request_pathfinding: UnifiedPathfindingBridge not found! Make sure it's added as an autoload.")
		remove_state(State.PATHFINDING)
		return

	# All entities use ULID for persistent tracking
	var entity_id = ulid  # PackedByteArray for both water and land entities
	var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"

	# Defensive: Check if target tile is walkable for this terrain type
	if not bridge.is_tile_walkable(terrain_type, target_tile):
		push_error("NPC %s: Target tile %s is NOT walkable for terrain_type=%d! Aborting pathfinding." % [ulid_hex, target_tile, terrain_type])
		remove_state(State.PATHFINDING)
		add_state(State.BLOCKED)
		if callback.is_valid():
			callback.call([] as Array[Vector2i], false)
		return

	# DIAGNOSTIC: Check if start tile is also walkable
	if not bridge.is_tile_walkable(terrain_type, current_tile):
		push_error("NPC %s: START tile %s is NOT walkable for terrain_type=%d! Current position is invalid!" % [ulid_hex, current_tile, terrain_type])
		remove_state(State.PATHFINDING)
		add_state(State.BLOCKED)
		if callback.is_valid():
			callback.call([] as Array[Vector2i], false)
		return

	print("NPC %s (%s): Requesting path from %s to %s (terrain_type=%d, expected=%s)" % [ulid_hex, get_class(), current_tile, target_tile, terrain_type, "WATER" if terrain_type == 0 else "LAND"])

	# Store the callback for when path_found signal is emitted
	pending_path_callbacks[ulid_hex] = callback

	# Connect to path_found signal if not already connected
	if not bridge.path_found.is_connected(_on_path_found):
		bridge.path_found.connect(_on_path_found)

	# Request path through unified bridge (result comes via signal)
	bridge.request_path(entity_id, terrain_type, current_tile, target_tile)

## Handle path_found signal from pathfinding bridge
func _on_path_found(entity_ulid: PackedByteArray, path: Array[Vector2i], success: bool, cost: float) -> void:
	var ulid_hex = UlidManager.to_hex(entity_ulid)

	# Check if this path is for this entity
	if entity_ulid != ulid:
		return  # Not for this entity

	# Remove pathfinding state
	remove_state(State.PATHFINDING)

	# Emit signal for external listeners (like main.gd)
	pathfinding_completed.emit(path, success)

	# Find and call the pending callback (if any)
	if ulid_hex in pending_path_callbacks:
		var callback = pending_path_callbacks[ulid_hex]
		pending_path_callbacks.erase(ulid_hex)

		if success and path.size() > 0:
			print("NPC %s: Path SUCCESS - %d waypoints, starting movement" % [ulid_hex, path.size()])
			follow_path(path, Cache.get_tile_map())
			if callback.is_valid():
				callback.call(path, success)
		else:
			add_state(State.BLOCKED)
			# Get bridge for diagnostics
			var bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
			if bridge:
				var current_tile = Cache.get_tile_map().local_to_map(position)
				var start_walkable = bridge.is_tile_walkable(terrain_type, current_tile)
				push_error("NPC %s: Path FAILED (success=%s, path_size=%d, start_walkable=%s)" %
					[ulid_hex, success, path.size(), start_walkable])
			if callback.is_valid():
				callback.call([] as Array[Vector2i], false)
	else:
		# No callback - just handle path internally
		if success and path.size() > 0:
			print("NPC %s: Path SUCCESS - %d waypoints, starting movement" % [ulid_hex, path.size()])
			follow_path(path, Cache.get_tile_map())
		else:
			add_state(State.BLOCKED)
			var bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
			if bridge:
				var current_tile = Cache.get_tile_map().local_to_map(position)
				var start_walkable = bridge.is_tile_walkable(terrain_type, current_tile)
				push_error("NPC %s: Path FAILED (success=%s, path_size=%d, start_walkable=%s)" %
					[ulid_hex, success, path.size(), start_walkable])

func _create_path_visualizer(path: Array[Vector2i], tile_map) -> void:
	# Remove old visualizer if exists
	if path_visualizer:
		path_visualizer.queue_free()
		path_visualizer = null

	# Load PathVisualizer
	var PathVisualizerScript = load("res://view/hud/waypoint/path_visualizer.gd")
	if PathVisualizerScript:
		path_visualizer = Node2D.new()
		path_visualizer.set_script(PathVisualizerScript)

		# Set z-index above all entities for visibility
		path_visualizer.z_index = Cache.Z_INDEX_WAYPOINTS

		# Add to parent so it's visible
		var parent = get_parent()
		if parent:
			parent.add_child(path_visualizer)
			path_visualizer.show_path(path, tile_map, self)

func _advance_to_next_waypoint():
	if path_index >= current_path.size():
		return

	var next_tile = current_path[path_index]
	var tile_map = Cache.get_tile_map()
	if tile_map:
		# CRITICAL: Check if this waypoint is walkable for our terrain type
		var bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
		if bridge and not bridge.is_tile_walkable(terrain_type, next_tile):
			var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"
			push_error("NPC %s (terrain_type=%d): BLOCKING movement to UNWALKABLE tile %s! Canceling path." % [ulid_hex, terrain_type, next_tile])

			# STOP the path immediately - don't move to invalid tile!
			current_path.clear()
			path_index = 0
			is_moving = false
			remove_state(State.MOVING)
			add_state(State.BLOCKED)

			# Clean up path visualizer
			if path_visualizer:
				path_visualizer.queue_free()
				path_visualizer = null
			return

		var next_pos = tile_map.map_to_local(next_tile)
		move_to(next_pos)

## Update z-index based on current tile position for proper isometric layering
func _update_z_index() -> void:
	# Use terrain-specific z-index
	if terrain_type == TerrainType.WATER:
		z_index = Cache.Z_INDEX_SHIPS  # Water entities (ships)
	else:
		z_index = Cache.Z_INDEX_NPCS   # Land entities (ground NPCs)

func _process(delta):
	# Update z-index for proper layering as NPC moves
	_update_z_index()

	# Pause movement if in combat
	if current_state & State.IN_COMBAT:
		return

	# Handle rotation phase (before moving) - water entities only
	if is_rotating_to_target:
		var angle_diff = abs(shortest_angle_deg(current_angle, target_angle))
		if angle_diff <= rotation_threshold:
			# Rotation complete, start moving
			is_rotating_to_target = false
			is_moving = true
			add_state(State.MOVING)
			remove_state(State.IDLE)

	# Smooth movement interpolation
	if is_moving:
		# Calculate progress based on actual distance and desired speed (tiles per second)
		# Average hex tile size is approximately 30 pixels (32x28)
		const AVERAGE_TILE_SIZE_PIXELS = 30.0
		var tiles_per_second = move_speed
		var progress_per_second = tiles_per_second * AVERAGE_TILE_SIZE_PIXELS / max(move_distance, 1.0)
		move_progress += delta * progress_per_second

		if move_progress >= 1.0:
			# Movement complete - reached waypoint
			position = move_target_pos
			is_moving = false
			move_progress = 1.0

			# Update combat system with new position (if registered)
			_update_combat_position()

			# Remove waypoint marker
			if path_visualizer and path_visualizer.has_method("remove_first_waypoint"):
				path_visualizer.remove_first_waypoint()

			# Notify waypoint reached
			if current_path.size() > 0 and path_index >= 0 and path_index < current_path.size() and on_waypoint_reached.is_valid():
				var reached_tile = current_path[path_index]
				on_waypoint_reached.call(reached_tile)

			# If following a path, move to next waypoint
			if current_path.size() > 0 and path_index < current_path.size() - 1:
				path_index += 1
				_advance_to_next_waypoint()
			else:
				# Path complete - notify Rust
				var tile_map = Cache.get_tile_map()
				if tile_map and entity_manager:
					# Use the last waypoint from the path (more reliable than local_to_map)
					var final_tile: Vector2i
					if current_path.size() > 0:
						final_tile = current_path[current_path.size() - 1]
					else:
						final_tile = tile_map.local_to_map(position)

					# CRITICAL: Validate final tile is walkable for our terrain type
					var bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
					if bridge and is_instance_valid(bridge):
						if not bridge.is_tile_walkable(terrain_type, final_tile):
							var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"
							push_error("NPC %s (terrain_type=%d): Movement completed at UNWALKABLE tile %s! This should never happen!" % [ulid_hex, terrain_type, final_tile])
							# Don't notify Rust of invalid position
							current_path.clear()
							path_index = 0
							return

						# Update entity position in Rust's ENTITY_DATA (critical for collision detection)
						if not ulid.is_empty():
							bridge.update_entity_position(ulid, final_tile, terrain_type)

				var was_following_path = current_path.size() > 0
				current_path.clear()
				path_index = 0

				# Clear movement state
				is_moving = false
				remove_state(State.MOVING)
				add_state(State.IDLE)

				# Clean up visualizer
				if path_visualizer:
					path_visualizer.queue_free()
					path_visualizer = null

				# Notify completion
				if was_following_path and on_path_complete.is_valid():
					on_path_complete.call()
		else:
			# Smooth interpolation - terrain-specific easing
			var t = move_progress

			if terrain_type == TerrainType.WATER:
				# Water entities: always use ease-in-out (ships)
				t = ease(move_progress, -2.0)
			else:
				# Land entities: smart easing (only at path start/end)
				if current_path.size() > 0:
					# Following a path - use linear or slight easing
					if path_index == 1 and move_progress < 0.2:
						# Ease-in at very start of path
						t = ease(move_progress / 0.2, -0.5) * 0.2
					elif path_index == current_path.size() - 1 and move_progress > 0.8:
						# Ease-out at very end of path
						var end_progress = (move_progress - 0.8) / 0.2
						t = 0.8 + ease(end_progress, -0.5) * 0.2
					# else: use linear t (no easing in middle)
				else:
					# Single move - use full ease-in-out
					t = ease(move_progress, -2.0)

			position = move_start_pos.lerp(move_target_pos, t)

			# Use overall movement direction, not frame-by-frame velocity
			var movement_vec = move_target_pos - move_start_pos
			if movement_vec.length_squared() > 0.01:
				var movement_angle = fmod(rad_to_deg(movement_vec.angle()) + 360.0, 360.0)
				target_angle = lerp_angle_deg(target_angle, movement_angle, steering_anticipation * 2.0)

	# Inertial angular steering with damping
	_update_angular_motion(delta)

# Helper function to register stats (called deferred to ensure StatsManager is ready)
func _register_stats() -> void:
	if StatsManager:
		var entity_type = "ship" if terrain_type == TerrainType.WATER else "npc"

		# Register with StatsManager (this will call Rust EntityManagerBridge internally)
		# StatsManager.register_entity() now handles both ENTITY_DATA and ENTITY_STATS creation
		StatsManager.register_entity(self, entity_type)

		# Connect to stat changes to update health bar
		StatsManager.stat_changed.connect(_on_stat_changed)
		StatsManager.entity_died.connect(_on_entity_died)

# Helper function to register with combat system (called deferred to ensure CombatManager is ready)
func _register_combat() -> void:
	if not CombatManager or not CombatManager.combat_bridge:
		push_warning("NPC: CombatManager not ready for combat registration")
		return

	if ulid.is_empty():
		push_error("NPC: Cannot register for combat without ULID")
		return

	# Get current hex position from global position
	var hex_pos: Vector2i = Vector2i(0, 0)
	if Cache.tile_map:
		hex_pos = Cache.tile_map.local_to_map(global_position)

	# Register as combatant with configured attack interval
	CombatManager.combat_bridge.register_combatant(
		ulid,
		player_ulid,  # Team affiliation
		hex_pos,
		attack_interval  # Attack interval (set by child class, default 3.0 seconds)
	)

# Update combat system with current position (called when entity moves)
func _update_combat_position() -> void:
	if not CombatManager or not CombatManager.combat_bridge:
		return

	if ulid.is_empty():
		return

	# Get current hex position from global position
	if not Cache.tile_map:
		return

	var hex_coords = Cache.tile_map.local_to_map(global_position)
	CombatManager.combat_bridge.update_position(ulid, hex_coords)

# Set up health bar (called deferred to ensure Cluster is ready)
func _setup_health_bar() -> void:
	if not Cluster:
		push_error("NPC: Cluster not found! Health bar cannot be created.")
		return

	# Acquire health bar from pool
	health_bar = Cluster.acquire("health_bar") as HealthBar
	if not health_bar:
		push_error("NPC: Failed to acquire health bar from pool!")
		return

	# Add as child so it follows the NPC
	add_child(health_bar)

	# Get current health values from StatsManager
	if StatsManager and not ulid.is_empty():
		var current_hp = StatsManager.get_stat(ulid, StatsManager.STAT.HP)
		var max_hp = StatsManager.get_stat(ulid, StatsManager.STAT.MAX_HP)
		health_bar.initialize(current_hp, max_hp, energy, max_energy)
	else:
		# Default values if no stats available yet
		health_bar.initialize(100.0, 100.0, energy, max_energy)

	# Configure appearance (optional - adjust as needed)
	health_bar.set_bar_offset(Vector2(0, -30))  # Position above NPC
	health_bar.set_auto_hide(false)  # Show health bar even at full health (for visibility)

	# Set flag based on ownership
	_update_health_bar_flag()

# Release health bar back to pool (call before destroying NPC or returning to pool)
func _release_health_bar() -> void:
	if health_bar and Cluster:
		# Remove from NPC
		if health_bar.get_parent() == self:
			remove_child(health_bar)

		# Reset and return to pool
		health_bar.reset_for_pool()
		Cluster.release("health_bar", health_bar)
		health_bar = null

# Update health bar flag based on ownership
func _update_health_bar_flag() -> void:
	if not health_bar:
		return

	# Determine flag based on player ownership
	var flag_name: String
	if player_ulid.is_empty():
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

# Handle stat changes from StatsManager
func _on_stat_changed(entity_ulid: PackedByteArray, stat_type: int, new_value: float) -> void:
	# Only update if this is our entity and the stat is HP or MAX_HP
	if entity_ulid != ulid:
		return

	if not health_bar:
		return

	# Update health bar based on stat type
	if stat_type == StatsManager.STAT.HP:
		var max_hp = StatsManager.get_stat(ulid, StatsManager.STAT.MAX_HP)
		health_bar.set_health_values(new_value, max_hp)
	elif stat_type == StatsManager.STAT.MAX_HP:
		var current_hp = StatsManager.get_stat(ulid, StatsManager.STAT.HP)
		health_bar.set_health_values(current_hp, new_value)

# Handle entity death
func _on_entity_died(entity_ulid: PackedByteArray) -> void:
	if entity_ulid == ulid:
		# Release health bar before dying
		_release_health_bar()

		# Clean up path visualizer (waypoints)
		if path_visualizer:
			# Remove from parent first, then free
			var parent = path_visualizer.get_parent()
			if parent:
				parent.remove_child(path_visualizer)
				path_visualizer.queue_free()
				path_visualizer = null
			else:
				push_error("NPC: Failed to remove path visualizer - no parent found for ULID: %s" % UlidManager.to_hex(ulid))

		# Cleanup pathfinding using unified bridge (all entities use ULID)
		var pathfinding = get_node_or_null("/root/UnifiedPathfindingBridge")
		if pathfinding:
			pathfinding.remove_entity(ulid, terrain_type)

		# Unregister from combat system
		if CombatManager and CombatManager.combat_bridge:
			CombatManager.combat_bridge.unregister_combatant(ulid)

		# Unregister from stats system
		if StatsManager:
			StatsManager.unregister_entity(ulid)

		# Unregister from ULID manager
		UlidManager.unregister_entity(ulid)

		# Return entity to pool or despawn
		if Cluster and pool_name != "":
			# Entity came from pool - return it
			if is_inside_tree():
				get_parent().remove_child(self)
			Cluster.release(pool_name, self)
		else:
			# Entity not pooled - queue free
			queue_free()

# Override _exit_tree to ensure cleanup
func _exit_tree() -> void:
	_release_health_bar()

	# Clean up path visualizer
	if path_visualizer:
		path_visualizer.queue_free()
		path_visualizer = null

	# Unregister from combat system
	if CombatManager and CombatManager.combat_bridge and not ulid.is_empty():
		CombatManager.combat_bridge.unregister_combatant(ulid)

# ============================================================================
# COMBAT SYSTEM
# ============================================================================
# NOTE: Combat is handled automatically by the Rust combat system (CombatBridge)
# NPCs register with CombatManager on spawn, which handles:
# - Automatic target finding (closest enemy within range)
# - Attack timing (based on attack_interval)
# - Damage calculation (based on ATK/DEF stats)
# - Projectile spawning (visual feedback for attacks)
#
# The Rust system runs in a worker thread and emits signals when:
# - Combat starts (combat_started)
# - Damage is dealt (damage_dealt) - triggers projectile spawn
# - Combat ends (combat_ended)
# - Entity dies (entity_died)
#
# Manual attacks can still be triggered using ranged_attack() for special abilities/cards

## Manual ranged attack (for special abilities, not used by automatic combat)
## The automatic Rust combat system handles regular attacks
func ranged_attack(target: Node2D, projectile_type: int = Projectile.Type.SPEAR) -> void:
	if not Cluster:
		push_error("NPC: Cannot perform ranged attack - Cluster not available")
		return

	if not target:
		push_error("NPC: Cannot perform ranged attack - target is null")
		return

	# Get attack stats from StatsManager
	var attack_power: float = 10.0
	var attack_range: float = 3.0

	if StatsManager and not ulid.is_empty():
		attack_power = StatsManager.get_stat(ulid, StatsManager.STAT.ATTACK)
		attack_range = StatsManager.get_stat(ulid, StatsManager.STAT.RANGE)

	# Check if target is in range
	var distance_to_target = global_position.distance_to(target.global_position)
	var tile_distance = distance_to_target / 64.0  # Approximate tiles (assuming ~64px per tile)

	if tile_distance > attack_range:
		push_warning("NPC: Target out of range (%.1f tiles, max %.1f)" % [tile_distance, attack_range])
		return

	# Acquire projectile from pool
	var projectile: Projectile = Cluster.acquire("projectile") as Projectile
	if not projectile:
		push_error("NPC: Failed to acquire projectile from pool")
		return

	# Add projectile to scene (as child of parent to avoid following entity)
	if get_parent():
		get_parent().add_child(projectile)

	# Calculate projectile arc based on distance (farther = higher arc)
	var arc_height = min(distance_to_target * 0.15, 50.0)  # Max 50px arc

	# Set up hit callback to deal damage
	var target_ulid: PackedByteArray
	if "ulid" in target and target.ulid is PackedByteArray:
		target_ulid = target.ulid

	projectile.on_hit = func():
		# Deal damage through StatsManager
		if StatsManager and not target_ulid.is_empty():
			var damage_dealt = StatsManager.take_damage(target_ulid, attack_power)

	# Set up pool return callback
	projectile.on_return_to_pool = func(proj: Projectile):
		if proj.get_parent():
			proj.get_parent().remove_child(proj)
		if Cluster:
			Cluster.release("projectile", proj)

	# Fire projectile
	projectile.fire(
		global_position,
		target.global_position,
		projectile_type,
		400.0,  # Speed in pixels/sec
		arc_height
	)
