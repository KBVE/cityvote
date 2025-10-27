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
var move_speed: float = 2.0  # Takes 0.5 seconds to move one tile

# Rotation state
var rotation_speed: float = 8.0  # How fast to interpolate between directions

# Reference to other ships for collision detection
var occupied_tiles: Dictionary = {}  # Shared reference set by main.gd

func _ready():
	_update_sprite()

# Set direction (0-15, counter-clockwise from north)
func set_direction(new_direction: int):
	target_direction = new_direction % 16

# Update sprite based on current direction
func _update_sprite():
	if direction >= 0 and direction < ship_sprites.size():
		sprite.texture = ship_sprites[direction]

# Convert angle in degrees to direction index (0-15)
func angle_to_direction(angle_degrees: float) -> int:
	# Normalize angle to 0-360
	angle_degrees = fmod(angle_degrees, 360.0)
	if angle_degrees < 0:
		angle_degrees += 360.0

	# Convert to direction index (0 = north = -90 degrees)
	# Counter-clockwise: 0=N, 1=NNW, 2=NW, 3=WNW, 4=W, etc.
	var adjusted_angle = angle_degrees + 90.0  # Adjust so 0 degrees = North
	var direction_index = int(round(adjusted_angle / 22.5)) % 16

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

	# Set target direction based on movement vector
	var direction_vec = target_pos - position
	if direction_vec.length() > 0:
		target_direction = vector_to_direction(direction_vec)

func _process(delta):
	# Smooth rotation interpolation
	if direction != target_direction:
		var dir_diff = target_direction - direction

		# Handle wraparound (shortest path)
		if abs(dir_diff) > 8:
			if dir_diff > 0:
				dir_diff -= 16
			else:
				dir_diff += 16

		# Interpolate direction
		var step = rotation_speed * delta
		if abs(dir_diff) < step:
			direction = target_direction
		else:
			direction = int(direction + sign(dir_diff) * step) % 16
			if direction < 0:
				direction += 16

		_update_sprite()

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
