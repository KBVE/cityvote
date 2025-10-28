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
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 3.0  # Movement speed multiplier

# Critically-damped spring parameters for organic motion
var angular_stiffness: float = 18.0  # How strongly we pull toward target_angle (reduced for smoother)
var angular_damping_strength: float = 12.0  # How strongly we damp angular_velocity (increased for less jitter)
var steering_anticipation: float = 0.15   # How much to lead the turn (reduced for smoother)
var sector_edge_buffer: float = 5.0  # Degrees of hysteresis to prevent frame jitter (increased)

# Reference to other ships for collision detection
var occupied_tiles: Dictionary = {}  # Shared reference set by main.gd

func _ready():
	# Initialize current angle based on initial direction
	current_angle = direction_to_godot_angle(direction)
	target_angle = current_angle
	_last_sector = direction
	_update_sprite()

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

	# Debug output - show every 30 frames when moving
	if is_moving and Engine.get_frames_drawn() % 30 == 0:
		print("Angular: cur=%.1f° tgt=%.1f° err=%.1f° vel=%.1f°/s dir=%d" % [current_angle, target_angle, angle_err, angular_velocity, direction])

	# Update sprite frame if direction changed
	if direction != old_direction:
		_update_sprite()

	# Apply residual pivot for smooth sub-frame rotation
	_apply_residual_pivot()

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
		target_angle = fmod(rad_to_deg(direction_vec.angle()) + 360.0, 360.0)
		var expected_dir = angle_to_direction_stable(target_angle)
		print("Ship moving - Vec: ", direction_vec, " Godot angle: %.1f°, Target angle: %.1f°, Expected direction: %d, Current: %d" % [rad_to_deg(direction_vec.angle()), target_angle, expected_dir, direction])

func _process(delta):
	# Smooth movement interpolation
	if is_moving:
		move_progress += delta * move_speed

		if move_progress >= 1.0:
			# Movement complete
			position = move_target_pos
			is_moving = false
			move_progress = 1.0
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
