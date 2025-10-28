extends Node2D
class_name Ship

# Base class for all ships with 16-directional sprites

@onready var sprite: Sprite2D = $Sprite2D

# Direction (0-15, where 0 is north, going counter-clockwise)
var direction: int = 0
var target_direction: int = 0

# Continuous angular representation for smooth interpolation
var current_angle: float = 0.0  # Current facing angle in degrees (0-360)
var target_angle: float = 0.0   # Target angle we're steering toward
var angular_velocity: float = 0.0  # Current rate of rotation

# Preloaded ship sprites (to be set by child classes)
var ship_sprites: Array[Texture2D] = []

# Movement state
var is_moving: bool = false
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 3.0  # Movement speed multiplier

# Inertial steering parameters for organic motion
var max_angular_velocity: float = 90.0   # Max rotation speed in degrees/sec (reduced for smoother feel)
var angular_acceleration: float = 120.0  # How quickly rotation speeds up (reduced for less snap)
var angular_damping: float = 0.92       # Friction/water resistance (0-1, higher = less friction, increased for smoother)
var steering_anticipation: float = 0.2   # How much to lead the turn (0-1, reduced for less twitchy)

# Reference to other ships for collision detection
var occupied_tiles: Dictionary = {}  # Shared reference set by main.gd

func _ready():
	# Initialize current angle based on initial direction
	# Direction 0 = North = 270° in Godot, Direction 4 = West = 180°, etc.
	# Convert our direction to Godot angle: angle = 270 - (direction * 22.5)
	current_angle = fmod(270.0 - (direction * 22.5), 360.0)
	if current_angle < 0:
		current_angle += 360.0
	target_angle = current_angle
	_update_sprite()

# Set direction (0-15, counter-clockwise from north)
func set_direction(new_direction: int):
	target_direction = new_direction % 16

# Update sprite based on current direction
func _update_sprite():
	if direction >= 0 and direction < 16:
		# Check if using AtlasTexture (for shader-based atlas)
		if sprite.texture and sprite.texture is AtlasTexture:
			var atlas_tex = sprite.texture as AtlasTexture
			# Calculate which cell in the 4x4 atlas (each cell is 64x64)
			var col = direction % 4
			var row = direction / 4
			atlas_tex.region = Rect2(col * 64, row * 64, 64, 64)
		elif sprite.material and sprite.material is ShaderMaterial:
			# Fallback: shader-based direction (not used with AtlasTexture approach)
			var shader_mat = sprite.material as ShaderMaterial
			shader_mat.set_shader_parameter("direction", direction)
		elif direction < ship_sprites.size():
			# Fallback to texture swapping if no shader
			sprite.texture = ship_sprites[direction]

# Convert angle in degrees to direction index (0-15)
func angle_to_direction(angle_degrees: float) -> int:
	# Normalize angle to 0-360
	angle_degrees = fmod(angle_degrees, 360.0)
	if angle_degrees < 0:
		angle_degrees += 360.0

	# In Godot: 0° = East, 90° = South, 180° = West, 270° = North (clockwise from East)
	# Our sprites: 0=N, 4=W, 8=S, 12=E (counter-clockwise from North, in steps of 22.5°)

	# Convert Godot angle to our direction system:
	# Godot 0°(E) → our 12(E), Godot 90°(S) → our 8(S), Godot 180°(W) → our 4(W), Godot 270°(N) → our 0(N)
	var direction_index = (12 - int(round(angle_degrees / 22.5))) % 16
	if direction_index < 0:
		direction_index += 16

	return direction_index

# Get direction from a vector
func vector_to_direction(vec: Vector2) -> int:
	var angle = rad_to_deg(vec.angle())
	return angle_to_direction(angle)

# Smoothly interpolate between two angles (handles wraparound)
func lerp_angle(from: float, to: float, weight: float) -> float:
	var diff = fmod(to - from, 360.0)
	if diff > 180.0:
		diff -= 360.0
	elif diff < -180.0:
		diff += 360.0
	return from + diff * weight

# Calculate shortest angular difference (handles wraparound)
func angle_difference(from: float, to: float) -> float:
	var diff = fmod(to - from, 360.0)
	if diff > 180.0:
		diff -= 360.0
	elif diff < -180.0:
		diff += 360.0
	return diff

# Update angular motion with inertia and damping
func _update_angular_motion(delta: float):
	# Calculate angular difference (shortest path)
	var angle_diff = angle_difference(current_angle, target_angle)

	# Apply angular acceleration toward target
	var desired_velocity = sign(angle_diff) * max_angular_velocity
	var velocity_change = (desired_velocity - angular_velocity) * angular_acceleration * delta
	angular_velocity += velocity_change

	# Clamp to max angular velocity
	angular_velocity = clamp(angular_velocity, -max_angular_velocity, max_angular_velocity)

	# Apply damping (water resistance)
	angular_velocity *= angular_damping

	# If close to target, apply stronger damping to settle smoothly
	if abs(angle_diff) < 30.0:
		var settle_factor = abs(angle_diff) / 30.0  # 0 to 1 as we approach target
		angular_velocity *= 0.5 + settle_factor * 0.5  # Extra damping when close

	# Update current angle
	current_angle += angular_velocity * delta

	# Normalize angle to 0-360
	current_angle = fmod(current_angle, 360.0)
	if current_angle < 0:
		current_angle += 360.0

	# Convert continuous angle to discrete direction for sprite selection
	var old_direction = direction
	direction = angle_to_direction(current_angle)

	# Debug output - always show when moving
	if is_moving and Engine.get_frames_drawn() % 30 == 0:  # Every 30 frames (~0.5 sec)
		print("Angular: cur=%.1f° tgt=%.1f° diff=%.1f° vel=%.1f°/s dir=%d" % [current_angle, target_angle, angle_diff, angular_velocity, direction])

	# Only update sprite if direction changed (optimization)
	if direction != old_direction:
		_update_sprite()

# Start moving to a target position
func move_to(target_pos: Vector2):
	if is_moving:
		return  # Already moving

	move_start_pos = position
	move_target_pos = target_pos
	move_progress = 0.0
	is_moving = true

	# Set initial target angle based on movement vector
	var direction_vec = target_pos - position
	if direction_vec.length() > 0:
		target_angle = rad_to_deg(direction_vec.angle())
		# Normalize to 0-360
		if target_angle < 0:
			target_angle += 360.0
		var expected_dir = angle_to_direction(target_angle)
		print("Ship moving - Vec: ", direction_vec, " Godot angle: %.1f°, Target angle: %.1f°, Expected direction: %d, Current: %d" % [rad_to_deg(direction_vec.angle()), target_angle, expected_dir, direction])

func _process(delta):
	# Smooth movement interpolation
	if is_moving:
		var old_progress = move_progress
		move_progress += delta * move_speed

		if move_progress >= 1.0:
			# Movement complete
			position = move_target_pos
			is_moving = false
			move_progress = 1.0
		else:
			# Lerp position with ease-in-out
			var t = ease(move_progress, -2.0)  # Ease in-out
			var old_t = ease(old_progress, -2.0)
			var new_pos = move_start_pos.lerp(move_target_pos, t)
			var old_pos = move_start_pos.lerp(move_target_pos, old_t)

			# Calculate actual velocity direction from position change
			var velocity = new_pos - old_pos
			if velocity.length_squared() > 0.01:  # Only update if moving significantly
				var velocity_angle = rad_to_deg(velocity.angle())

				# Add anticipation - blend between current heading and velocity direction
				# This makes the ship "lean into" turns before the velocity fully changes
				var anticipated_angle = lerp_angle(current_angle, velocity_angle, steering_anticipation)
				target_angle = anticipated_angle

			position = new_pos

	# Inertial angular steering with damping
	_update_angular_motion(delta)
