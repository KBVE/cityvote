extends Node2D
class_name Ship

# Base class for all ships with 16-directional sprites
#
# Uses a 16-direction sprite atlas with continuous facing driven by a critically-damped
# angular spring toward target_angle. Selects the nearest 22.5° sector for the frame,
# but applies a residual pivot (sprite local rotation) equal to the short angular
# difference between the continuous angle and the sector center, clamped to ~±10°.
# Adds sector hysteresis (~4°) to prevent jitter at boundaries. All damping is
# framerate-independent via exponential decay.

@onready var sprite: Sprite2D = $Sprite2D

# Direction (0-15, where 0 is north, going counter-clockwise)
var direction: int = 0
var _last_sector: int = 0  # For hysteresis

# Continuous angular representation for smooth interpolation
var current_angle: float = 0.0  # Current facing angle in degrees (0-360)
var target_angle: float = 0.0   # Target angle we're steering toward
var angular_velocity: float = 0.0  # Current rate of rotation in degrees/sec

# Preloaded ship sprites (to be set by child classes)
var ship_sprites: Array[Texture2D] = []

# Movement state
var is_moving: bool = false
var is_rotating_to_target: bool = false  # Rotating before moving
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 3.0  # Movement speed multiplier
var rotation_threshold: float = 5.0  # Degrees - how close to target angle before starting movement

# Path following
var current_path: Array[Vector2i] = []  # Tile coordinates of path to follow
var path_index: int = 0  # Current position in path
var on_path_complete: Callable  # Callback when entire path is complete
var on_waypoint_reached: Callable  # Callback when each waypoint is reached
var path_visualizer: Node2D = null  # Visual representation of path

# Critically-damped spring parameters for organic motion
var angular_stiffness: float = 18.0  # How strongly we pull toward target_angle (reduced for smoother)
var angular_damping_strength: float = 12.0  # How strongly we damp angular_velocity (increased for less jitter)
var steering_anticipation: float = 0.15   # How much to lead the turn (reduced for smoother)
var sector_edge_buffer: float = 5.0  # Degrees of hysteresis to prevent frame jitter (increased)

# Reference to other ships for collision detection
var occupied_tiles: Dictionary = {}  # Shared reference set by main.gd

# ULID for persistent entity tracking
var ulid: PackedByteArray = PackedByteArray()

# Player ownership ULID (which player controls this ship)
# Empty = AI-controlled, otherwise contains player's ULID
var player_ulid: PackedByteArray = PackedByteArray()

# Health bar reference (acquired from pool)
var health_bar: HealthBar = null

func _ready():
	# Register with ULID system
	if ulid.is_empty():
		ulid = UlidManager.register_entity(self, UlidManager.TYPE_SHIP, {
			"ship_type": get_class(),
			"position": position
		})
		print("Ship registered with ULID: %s" % UlidManager.to_hex(ulid))

	# Register with stats system (deferred to ensure StatsManager is ready)
	if StatsManager:
		call_deferred("_register_stats")

	# Initialize current angle based on initial direction
	current_angle = direction_to_godot_angle(direction)
	target_angle = current_angle
	_last_sector = direction
	_update_sprite()

	# Acquire health bar from pool (deferred to ensure Cluster is ready)
	call_deferred("_setup_health_bar")

# Convert direction index to Godot angle (inverse of angle_to_direction)
func direction_to_godot_angle(dir: int) -> float:
	# dir 0=N=270°, dir 4=W=180°, dir 8=S=90°, dir 12=E=0°
	return fmod(270.0 - (dir * 22.5) + 360.0, 360.0)

# Calculate shortest angular difference (handles wraparound)
func shortest_angle_deg(from_angle: float, to_angle: float) -> float:
	var diff = fmod((to_angle - from_angle + 540.0), 360.0) - 180.0
	return diff

# Set direction (0-15, counter-clockwise from north)
func set_direction(new_direction: int):
	direction = new_direction % 16
	target_angle = direction_to_godot_angle(direction)

# Update sprite based on current direction
func _update_sprite():
	if direction >= 0 and direction < 16:
		# Check if using AtlasTexture (for shader-based atlas)
		if sprite.texture and sprite.texture is AtlasTexture:
			var atlas_tex = sprite.texture as AtlasTexture
			# Calculate which cell in the 4x4 atlas (each cell is 64x64)
			var col = direction % 4
			var row = direction >> 2  # Bit shift for integer division by 4
			atlas_tex.region = Rect2(col * 64, row * 64, 64, 64)
		elif sprite.material and sprite.material is ShaderMaterial:
			# Fallback: shader-based direction (not used with AtlasTexture approach)
			var shader_mat = sprite.material as ShaderMaterial
			shader_mat.set_shader_parameter("direction", direction)
		elif direction < ship_sprites.size():
			# Fallback to texture swapping if no shader
			sprite.texture = ship_sprites[direction]

# Apply residual pivot for smooth rotation between sprite frames
func _apply_residual_pivot():
	var dir_center = direction_to_godot_angle(direction)
	var residual = shortest_angle_deg(dir_center, current_angle)
	# Clamp to prevent rubbery appearance (reduced range for smoother look)
	residual = clamp(residual, -8.0, 8.0)
	sprite.rotation_degrees = residual

# Convert angle to direction with hysteresis to prevent jitter
func angle_to_direction_stable(angle: float) -> int:
	# Normalize angle to 0-360
	angle = fmod(angle + 360.0, 360.0)

	# Map to 0..15 by flooring with half-step bias
	# Add 11.25° offset so sectors align: 0=E, 4=S, 8=W, 12=N in Godot coordinates
	var godot_sector = int(floor((angle + 11.25) / 22.5)) % 16

	# Convert Godot sectors to our direction system: 0=N, 4=W, 8=S, 12=E
	var idx = (12 - godot_sector) & 15

	# Hysteresis: if trying to change sector, require clearing a small buffer
	if idx != _last_sector:
		var center_prev = direction_to_godot_angle(_last_sector)
		var diff_prev = abs(shortest_angle_deg(center_prev, angle))
		if diff_prev < (11.25 + sector_edge_buffer):
			return _last_sector

	_last_sector = idx
	return idx

# Get direction from a vector
func vector_to_direction(vec: Vector2) -> int:
	var angle = rad_to_deg(vec.angle())
	return angle_to_direction_stable(angle)

# Smoothly interpolate between two angles (handles wraparound)
func lerp_angle_deg(from: float, to: float, weight: float) -> float:
	var diff = shortest_angle_deg(from, to)
	return fmod(from + diff * weight + 360.0, 360.0)

# Update angular motion with critically-damped spring (framerate-independent)
func _update_angular_motion(delta: float):
	# Critically-damped spring for natural approach/settle without overshoot
	var angle_err = shortest_angle_deg(current_angle, target_angle)

	# Spring force: stiffness pulls toward target, damping resists velocity
	angular_velocity += (angular_stiffness * angle_err - angular_damping_strength * angular_velocity) * delta

	# Update current angle
	current_angle = fmod(current_angle + angular_velocity * delta + 360.0, 360.0)

	# Convert continuous angle to discrete direction with hysteresis
	var old_direction = direction
	direction = angle_to_direction_stable(current_angle)

	# Update sprite frame if direction changed
	if direction != old_direction:
		_update_sprite()

	# Apply residual pivot for smooth sub-frame rotation
	_apply_residual_pivot()

# Start moving to a target position
func move_to(target_pos: Vector2):
	if is_moving or is_rotating_to_target:
		return  # Already moving or rotating

	move_start_pos = position
	move_target_pos = target_pos
	move_progress = 0.0

	# Set target angle based on movement vector
	var direction_vec = target_pos - position
	if direction_vec.length() > 0:
		target_angle = fmod(rad_to_deg(direction_vec.angle()) + 360.0, 360.0)

		# Check if we need to rotate first
		var angle_diff = abs(shortest_angle_deg(current_angle, target_angle))
		if angle_diff > rotation_threshold:
			# Start rotating phase - don't move yet
			is_rotating_to_target = true
			is_moving = false
		else:
			# Close enough, start moving immediately
			is_rotating_to_target = false
			is_moving = true

# Start following a path (array of tile coordinates)
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

# Create visual representation of path
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

		# Add to parent (hex_map) so it's visible
		var parent = get_parent()
		if parent:
			parent.add_child(path_visualizer)
			path_visualizer.show_path(path, tile_map, self)

# Internal: Move to next waypoint in path
func _advance_to_next_waypoint():
	if path_index >= current_path.size():
		return

	var next_tile = current_path[path_index]
	var tile_map = get_parent()  # Assuming ship is child of hex_map
	if tile_map and tile_map.has_node("TileMap"):
		var tm = tile_map.get_node("TileMap")
		var next_pos = tm.map_to_local(next_tile)
		move_to(next_pos)

func _process(delta):
	# Handle rotation phase (before moving)
	if is_rotating_to_target:
		var angle_diff = abs(shortest_angle_deg(current_angle, target_angle))
		if angle_diff <= rotation_threshold:
			# Rotation complete, start moving
			is_rotating_to_target = false
			is_moving = true

	# Smooth movement interpolation
	if is_moving:
		move_progress += delta * move_speed

		if move_progress >= 1.0:
			# Movement complete
			position = move_target_pos
			is_moving = false
			move_progress = 1.0

			# Remove waypoint marker (visual feedback)
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

				# Notify completion
				if was_following_path and on_path_complete.is_valid():
					on_path_complete.call()
		else:
			# Lerp position with ease-in-out
			var t = ease(move_progress, -2.0)  # Ease in-out
			position = move_start_pos.lerp(move_target_pos, t)

			# Use overall movement direction, not frame-by-frame velocity
			# This prevents jitter from small delta movements during ease-in/out
			var movement_vec = move_target_pos - move_start_pos
			if movement_vec.length_squared() > 0.01:
				var movement_angle = fmod(rad_to_deg(movement_vec.angle()) + 360.0, 360.0)

				# Smoothly interpolate target angle toward movement direction
				# Use anticipation to create organic "lean into turn" behavior
				target_angle = lerp_angle_deg(target_angle, movement_angle, steering_anticipation * 2.0)

	# Inertial angular steering with damping
	_update_angular_motion(delta)

# Helper function to register stats (called deferred to ensure StatsManager is ready)
func _register_stats() -> void:
	if StatsManager:
		StatsManager.register_entity(self, "ship")
		# Connect to stat changes to update health bar
		StatsManager.stat_changed.connect(_on_stat_changed)
		StatsManager.entity_died.connect(_on_entity_died)

# Set up health bar (called deferred to ensure Cluster is ready)
func _setup_health_bar() -> void:
	if not Cluster:
		push_error("Ship: Cluster not found! Health bar cannot be created.")
		return

	# Acquire health bar from pool
	health_bar = Cluster.acquire("health_bar") as HealthBar
	if not health_bar:
		push_error("Ship: Failed to acquire health bar from pool!")
		return

	print("Ship: Health bar acquired successfully for ULID: %s" % UlidManager.to_hex(ulid))

	# Add as child so it follows the ship
	add_child(health_bar)

	# Get current health values from StatsManager
	var current_hp: float = 100.0
	var max_hp: float = 100.0

	if StatsManager and not ulid.is_empty():
		current_hp = StatsManager.get_stat(ulid, StatsManager.STAT.HP)
		max_hp = StatsManager.get_stat(ulid, StatsManager.STAT.MAX_HP)
		print("Ship: Health from StatsManager: %d/%d" % [current_hp, max_hp])
	else:
		print("Ship: Using default health values: %d/%d" % [current_hp, max_hp])

	health_bar.initialize(current_hp, max_hp)

	# Configure appearance (optional - adjust as needed)
	health_bar.set_bar_offset(Vector2(0, -30))  # Position above ship
	health_bar.set_auto_hide(false)  # Show health bar even at full health (for visibility)

	print("Ship: Health bar setup complete. Visible=%s, Position=%s" % [health_bar.visible, health_bar.position])

# Release health bar back to pool (call before destroying ship or returning to pool)
func _release_health_bar() -> void:
	if health_bar and Cluster:
		# Remove from ship
		if health_bar.get_parent() == self:
			remove_child(health_bar)

		# Reset and return to pool
		health_bar.reset_for_pool()
		Cluster.release("health_bar", health_bar)
		health_bar = null

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

		# Additional death logic can go here
		# For now, just hide the ship
		visible = false

# Override _exit_tree to ensure health bar is released
func _exit_tree() -> void:
	_release_health_bar()
