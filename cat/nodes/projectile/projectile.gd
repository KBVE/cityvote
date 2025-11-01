extends Node2D
class_name Projectile

## Pooled projectile for combat system
## Displays sprite from atlas using shader-based UV selection
## Travels from source to target with optional arc/rotation

# Projectile type enum (matches atlas indices)
enum Type {
	SPEAR = 0,
	GLAIVE = 1,
}

# Projectile metadata (hardcoded from projectile_atlas_metadata.json for performance)
# Atlas: 64x32 pixels (2 projectiles side by side)
const TILE_SIZE: int = 32
const ATLAS_WIDTH: int = 64
const ATLAS_HEIGHT: int = 32

# Projectile data: name, atlas_x, atlas_y, width, height
const PROJECTILE_DATA: Dictionary = {
	Type.SPEAR: {"name": "spear", "x": 0, "y": 0, "width": 32, "height": 32},
	Type.GLAIVE: {"name": "glaive", "x": 32, "y": 0, "width": 32, "height": 32},
}

# Reference to sprite with shader material
@onready var sprite: Sprite2D = $Sprite2D

# Projectile configuration
var projectile_type: Type = Type.SPEAR
var source_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.ZERO  # Normalized direction vector
var speed: float = 400.0  # Pixels per second
var arc_height: float = 0.0  # Pixels (0 = straight line)
var rotate_to_direction: bool = true
var max_range: float = 0.0  # Maximum travel distance (in pixels)

# Travel state
var is_active: bool = false
var travel_progress: float = 0.0  # 0.0 to 1.0
var travel_distance: float = 0.0
var distance_traveled: float = 0.0  # Actual distance traveled

# Callbacks
var on_hit: Callable  # Called when projectile reaches target
var on_return_to_pool: Callable  # Called when projectile finishes

func _ready() -> void:
	set_process(false)  # Disabled until fired

## Fire the projectile from source to target
## If max_range_tiles is > 0, projectile will travel that many tiles max (1 tile = 64px)
## Otherwise it travels directly to target
func fire(
	from: Vector2,
	to: Vector2,
	type: Type = Type.SPEAR,
	projectile_speed: float = 400.0,
	arc: float = 0.0,
	max_range_tiles: int = 8  # Default: 8 tiles max range
) -> void:
	# Set configuration
	source_pos = from
	projectile_type = type
	speed = projectile_speed
	arc_height = arc

	# Calculate direction and max range
	direction = (to - from).normalized()

	# If max_range_tiles is specified, use it; otherwise go to target
	if max_range_tiles > 0:
		const TILE_SIZE = 64  # Hex tile size in pixels
		max_range = max_range_tiles * TILE_SIZE

		# Target is either the intended target OR max range, whichever is closer
		var distance_to_target = from.distance_to(to)
		if distance_to_target <= max_range:
			target_pos = to
			travel_distance = distance_to_target
		else:
			# Projectile will travel max_range in the direction of target
			target_pos = from + (direction * max_range)
			travel_distance = max_range
	else:
		# No max range - go directly to target
		target_pos = to
		travel_distance = from.distance_to(to)
		max_range = travel_distance

	# Reset state
	travel_progress = 0.0
	distance_traveled = 0.0
	position = source_pos
	is_active = true

	# Update shader to display correct sprite
	_update_sprite()

	# Calculate initial rotation
	if rotate_to_direction:
		var angle = direction.angle()
		rotation = angle

	# Enable processing
	set_process(true)
	visible = true

## Update projectile sprite based on type
func _update_sprite() -> void:
	if not sprite or not sprite.material:
		return

	# Set shader parameter to select correct sprite from atlas
	sprite.material.set_shader_parameter("projectile_index", projectile_type)

func _process(delta: float) -> void:
	if not is_active:
		return

	# Move in direction
	var movement = speed * delta
	distance_traveled += movement

	# Check if reached max range or target
	if distance_traveled >= travel_distance:
		# Reached end of travel (hit target or max range)
		position = target_pos
		_on_reach_target()
		return

	# Update travel progress based on distance traveled
	travel_progress = distance_traveled / travel_distance

	# Calculate position along path with optional arc
	var linear_pos = source_pos.lerp(target_pos, travel_progress)

	if arc_height > 0:
		# Add parabolic arc (peak at midpoint)
		var arc_offset = 4.0 * arc_height * travel_progress * (1.0 - travel_progress)
		position = linear_pos + Vector2(0, -arc_offset)
	else:
		position = linear_pos

	# Update rotation to face direction of travel
	if rotate_to_direction:
		var next_progress = min(travel_progress + 0.01, 1.0)
		var next_pos = source_pos.lerp(target_pos, next_progress)

		if arc_height > 0:
			var next_arc_offset = 4.0 * arc_height * next_progress * (1.0 - next_progress)
			next_pos += Vector2(0, -next_arc_offset)

		var travel_direction = position.direction_to(next_pos)
		if travel_direction.length_squared() > 0.001:  # Avoid zero vector
			rotation = travel_direction.angle()

## Called when projectile reaches target
func _on_reach_target() -> void:
	is_active = false
	set_process(false)
	visible = false

	# Call hit callback
	if on_hit.is_valid():
		on_hit.call()

	# Return to pool
	if on_return_to_pool.is_valid():
		on_return_to_pool.call(self)
	else:
		# Fallback: queue free if not pooled
		queue_free()

## Reset projectile to default state (for pooling)
func reset() -> void:
	is_active = false
	travel_progress = 0.0
	distance_traveled = 0.0
	position = Vector2.ZERO
	rotation = 0.0
	visible = false
	direction = Vector2.ZERO
	max_range = 0.0
	set_process(false)
	on_hit = Callable()
	on_return_to_pool = Callable()
