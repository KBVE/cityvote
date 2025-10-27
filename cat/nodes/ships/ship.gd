extends Node2D
class_name Ship

# Base class for all ships with 16-directional sprites

@onready var sprite: Sprite2D = $Sprite2D

# Direction (0-15, where 0 is north, going counter-clockwise)
var direction: int = 0
var target_direction: int = 0

# Preloaded ship sprites (to be set by child classes)
var ship_sprites: Array[Texture2D] = []

# Movement state
var is_moving: bool = false
var move_start_pos: Vector2 = Vector2.ZERO
var move_target_pos: Vector2 = Vector2.ZERO
var move_progress: float = 0.0
var move_speed: float = 3.0  # Faster movement - 0.33 seconds per tile

# Rotation state
var rotation_speed: float = 12.0  # Faster, smoother rotation to track velocity changes

# Reference to other ships for collision detection
var occupied_tiles: Dictionary = {}  # Shared reference set by main.gd

func _ready():
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
	# Formula: direction = (12 - (angle / 22.5)) % 16
	var direction_index = (12 - int(round(angle_degrees / 22.5))) % 16
	if direction_index < 0:
		direction_index += 16

	return direction_index

# Get direction from a vector
func vector_to_direction(vec: Vector2) -> int:
	var angle = rad_to_deg(vec.angle())
	return angle_to_direction(angle)

# Start moving to a target position
func move_to(target_pos: Vector2):
	if is_moving:
		return  # Already moving

	move_start_pos = position
	move_target_pos = target_pos
	move_progress = 0.0
	is_moving = true

	# Set initial target direction based on movement vector
	var direction_vec = target_pos - position
	if direction_vec.length() > 0:
		target_direction = vector_to_direction(direction_vec)

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
				target_direction = vector_to_direction(velocity)

			position = new_pos

	# Smooth rotation interpolation toward target direction
	if direction != target_direction:
		var dir_diff = target_direction - direction

		# Handle wraparound (shortest path)
		if abs(dir_diff) > 8:
			if dir_diff > 0:
				dir_diff -= 16
			else:
				dir_diff += 16

		# Interpolate direction (ensure at least 1 step per frame)
		var step = max(1.0, rotation_speed * delta)
		if abs(dir_diff) <= step:
			direction = target_direction
		else:
			direction = int(direction + sign(dir_diff) * step) % 16
			if direction < 0:
				direction += 16

		_update_sprite()
