extends Node2D
class_name NPC

# Base class for all ground-based NPCs with 16-directional sprites and state management
#
# NPCs move on land tiles (anything except water) and use the same smooth movement
# and angular interpolation system as ships, but adapted for ground pathfinding.

@onready var sprite: Sprite2D = $Sprite2D

# NPC State enum (matches Rust bitwise flags pattern)
enum State {
	IDLE = 0b0001,           # NPC is idle, can accept commands
	MOVING = 0b0010,         # NPC is moving along a path
	PATHFINDING = 0b0100,    # Pathfinding request in progress
	BLOCKED = 0b1000,        # NPC is blocked (cannot move)
	INTERACTING = 0b10000,   # NPC is interacting with object/player
	DEAD = 0b100000,         # NPC is dead (no longer active)
}

# Current state
var current_state: int = State.IDLE

# Direction (0-15, where 0 is north, going counter-clockwise)
var direction: int = 0
var _last_sector: int = 0  # For hysteresis

# Continuous angular representation for smooth interpolation
var current_angle: float = 0.0  # Current facing angle in degrees (0-360)
var target_angle: float = 0.0   # Target angle we're steering toward
var angular_velocity: float = 0.0  # Current rate of rotation in degrees/sec

# Preloaded NPC sprites (to be set by child classes)
var npc_sprites: Array[Texture2D] = []

# Movement state
var is_moving: bool = false
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 2.5  # Movement speed (slightly slower than ships)

# Path following
var current_path: Array[Vector2i] = []  # Tile coordinates of path to follow
var path_index: int = 0  # Current position in path
var on_path_complete: Callable  # Callback when entire path is complete
var on_waypoint_reached: Callable  # Callback when each waypoint is reached
var path_visualizer: Node2D = null  # Visual representation of path

# Critically-damped spring parameters for organic motion
var angular_stiffness: float = 18.0
var angular_damping_strength: float = 12.0
var steering_anticipation: float = 0.15
var sector_edge_buffer: float = 5.0

# Reference to occupied tiles for collision detection
var occupied_tiles: Dictionary = {}  # Shared reference set by main.gd

# ULID for persistent entity tracking
var ulid: PackedByteArray = PackedByteArray()

func _ready():
	# Register with ULID system
	if ulid.is_empty():
		ulid = UlidManager.register_entity(self, UlidManager.TYPE_NPC, {
			"npc_type": get_class(),
			"position": position,
			"state": current_state
		})
		print("NPC registered with ULID: %s" % UlidManager.to_hex(ulid))

	# Register with stats system (deferred to ensure StatsManager is ready)
	if StatsManager:
		call_deferred("_register_stats")

	# Initialize current angle based on initial direction
	current_angle = direction_to_godot_angle(direction)
	target_angle = current_angle
	_last_sector = direction
	_update_sprite()

# === State Management ===

func set_state(new_state: int) -> void:
	current_state = new_state

func add_state(state_flag: int) -> void:
	current_state |= state_flag

func remove_state(state_flag: int) -> void:
	current_state &= ~state_flag

func has_state(state_flag: int) -> bool:
	return (current_state & state_flag) != 0

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
		# Check if using AtlasTexture (for shader-based atlas)
		if sprite.texture and sprite.texture is AtlasTexture:
			var atlas_tex = sprite.texture as AtlasTexture
			# Calculate which cell in the 4x4 atlas (each cell is 64x64)
			var col = direction % 4
			var row = direction >> 2
			atlas_tex.region = Rect2(col * 64, row * 64, 64, 64)
		elif sprite.material and sprite.material is ShaderMaterial:
			var shader_mat = sprite.material as ShaderMaterial
			shader_mat.set_shader_parameter("direction", direction)
		elif direction < npc_sprites.size():
			# Fallback to texture swapping
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
	if is_moving:
		return

	move_start_pos = position
	move_target_pos = target_pos
	move_progress = 0.0
	is_moving = true
	add_state(State.MOVING)
	remove_state(State.IDLE)

	# Set initial target angle based on movement vector
	var direction_vec = target_pos - position
	if direction_vec.length() > 0:
		target_angle = fmod(rad_to_deg(direction_vec.angle()) + 360.0, 360.0)

func follow_path(path: Array[Vector2i], tile_map: TileMap, complete_callback: Callable = Callable(), waypoint_callback: Callable = Callable()):
	if path.size() < 2:
		return

	current_path = path
	path_index = 1  # Start at index 1 (0 is current position)
	on_path_complete = complete_callback
	on_waypoint_reached = waypoint_callback

	# Create path visualizer
	_create_path_visualizer(path, tile_map)

	_advance_to_next_waypoint()

## Request pathfinding to a target tile (uses NPC pathfinding bridge)
func request_pathfinding(target_tile: Vector2i, tile_map: TileMap, callback: Callable = Callable()):
	# Get pathfinding bridge from /root/NpcPathfindingBridge
	var bridge = get_node_or_null("/root/NpcPathfindingBridge")
	if not bridge:
		push_error("NPC: NpcPathfindingBridge not found! Make sure it's added as an autoload.")
		return

	# Get current tile position
	var current_tile = tile_map.local_to_map(position)

	# Set state to pathfinding
	add_state(State.PATHFINDING)

	# Request path
	var npc_id = get_instance_id()
	bridge.request_path(npc_id, current_tile, target_tile, func(path: Array[Vector2i], success: bool):
		# Clear pathfinding state
		remove_state(State.PATHFINDING)

		if success and path.size() > 0:
			# Follow the path
			follow_path(path, tile_map)

			# Call user callback
			if callback.is_valid():
				callback.call(path, success)
		else:
			# No path found - mark as blocked
			add_state(State.BLOCKED)
			push_warning("NPC: No path found to ", target_tile)

			# Call user callback
			if callback.is_valid():
				callback.call([], false)
	)

func _create_path_visualizer(path: Array[Vector2i], tile_map: TileMap) -> void:
	# Remove old visualizer if exists
	if path_visualizer:
		path_visualizer.queue_free()
		path_visualizer = null

	# Load PathVisualizer
	var PathVisualizerScript = load("res://view/hud/waypoint/path_visualizer.gd")
	if PathVisualizerScript:
		path_visualizer = Node2D.new()
		path_visualizer.set_script(PathVisualizerScript)

		# Add to parent so it's visible
		var parent = get_parent()
		if parent:
			parent.add_child(path_visualizer)
			path_visualizer.show_path(path, tile_map, self)

func _advance_to_next_waypoint():
	if path_index >= current_path.size():
		return

	var next_tile = current_path[path_index]
	var tile_map = get_parent()
	if tile_map and tile_map.has_node("TileMap"):
		var tm = tile_map.get_node("TileMap")
		var next_pos = tm.map_to_local(next_tile)
		move_to(next_pos)

func _process(delta):
	# Smooth movement interpolation
	if is_moving:
		move_progress += delta * move_speed

		if move_progress >= 1.0:
			# Movement complete
			position = move_target_pos
			is_moving = false
			move_progress = 1.0

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
				# Path complete
				var was_following_path = current_path.size() > 0
				current_path.clear()
				path_index = 0

				# Clean up visualizer
				if path_visualizer:
					path_visualizer.queue_free()
					path_visualizer = null

				# Update state
				remove_state(State.MOVING)
				add_state(State.IDLE)

				# Notify completion
				if was_following_path and on_path_complete.is_valid():
					on_path_complete.call()
		else:
			# Lerp position with ease-in-out
			var t = ease(move_progress, -2.0)
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
		StatsManager.register_entity(self, "npc")
