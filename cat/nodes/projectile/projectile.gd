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

# Reference to sprite with shader material
@onready var sprite: Sprite2D = $Sprite2D

# Projectile configuration
var projectile_type: Type = Type.SPEAR
var source_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var speed: float = 400.0  # Pixels per second
var arc_height: float = 0.0  # Pixels (0 = straight line)
var rotate_to_direction: bool = true

# Travel state
var is_active: bool = false
var travel_progress: float = 0.0  # 0.0 to 1.0
var travel_distance: float = 0.0

# Callbacks
var on_hit: Callable  # Called when projectile reaches target
var on_return_to_pool: Callable  # Called when projectile finishes

func _ready() -> void:
	set_process(false)  # Disabled until fired

## Fire the projectile from source to target
func fire(
	from: Vector2,
	to: Vector2,
	type: Type = Type.SPEAR,
	projectile_speed: float = 400.0,
	arc: float = 0.0
) -> void:
	# Set configuration
	source_pos = from
	target_pos = to
	projectile_type = type
	speed = projectile_speed
	arc_height = arc

	# Reset state
	travel_progress = 0.0
	travel_distance = source_pos.distance_to(target_pos)
	position = source_pos
	is_active = true

	# Update shader to display correct sprite
	_update_sprite()

	# Calculate initial rotation
	if rotate_to_direction:
		var angle = source_pos.angle_to_point(target_pos)
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

	# Update travel progress
	if travel_distance > 0:
		travel_progress += (speed * delta) / travel_distance
	else:
		travel_progress = 1.0

	# Clamp to 1.0
	if travel_progress >= 1.0:
		travel_progress = 1.0
		_on_reach_target()
		return

	# Calculate position along path with optional arc
	var linear_pos = source_pos.lerp(target_pos, travel_progress)

	if arc_height > 0:
		# Add parabolic arc (peak at midpoint)
		var arc_offset = 4.0 * arc_height * travel_progress * (1.0 - travel_progress)
		position = linear_pos + Vector2(0, -arc_offset)
	else:
		position = linear_pos

	# Update rotation to face direction of travel
	if rotate_to_direction and travel_progress < 1.0:
		var next_progress = min(travel_progress + 0.01, 1.0)
		var next_pos = source_pos.lerp(target_pos, next_progress)

		if arc_height > 0:
			var next_arc_offset = 4.0 * arc_height * next_progress * (1.0 - next_progress)
			next_pos += Vector2(0, -next_arc_offset)

		var direction = position.direction_to(next_pos)
		rotation = direction.angle()

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
	position = Vector2.ZERO
	rotation = 0.0
	visible = false
	set_process(false)
	on_hit = Callable()
	on_return_to_pool = Callable()
