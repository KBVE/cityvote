extends Node2D
class_name Projectile

## Pooled projectile for combat system
## Displays sprite from multi-row atlas using shader-based UV selection
## Supports animated projectiles (e.g., shadow bolt)
## Travels from source to target with optional arc/rotation
##
## Behavior Flags System:
##   Projectiles use i64 bitwise flags to define behaviors (EXPLODES, AOE, PASS_THROUGH, etc.)
##   Each projectile type has default behaviors defined in PROJECTILE_DATA
##   Custom behaviors can be set via fire() or modified with has_behavior/add_behavior/remove_behavior
##   Current implementation supports: EXPLODES (explosion animation), AOE (area damage)
##   Future: PASS_THROUGH, PIERCING, HOMING, BOUNCES, SPLITS, LIFESTEAL, BURN, FREEZE, etc.

# Projectile type enum (matches atlas rows)
enum Type {
	SPEAR = 0,      # Row 0: Static spear
	GLAIVE = 1,     # Row 1: Static glaive
	SHADOWBOLT = 2, # Row 2: Animated shadow bolt (11 frames)
	FIREBOLT = 3,   # Row 3: Animated fire bolt (13 frames)
}

# Animation states for shadow bolt
enum ShadowBoltState {
	MOVING = 0,   # Frames 0-3 (4 frames)
	EXPLODING = 1 # Frames 4-10 (7 frames)
}

# Projectile behavior flags (bitwise)
# Use i64 for future-proofing and consistency with other game systems
enum BehaviorFlags {
	NONE = 0,
	EXPLODES = 1 << 0,          # Projectile explodes on impact (shows explosion animation)
	AOE = 1 << 1,               # Deals area-of-effect damage
	PASS_THROUGH = 1 << 2,      # Passes through targets (doesn't stop on first hit)
	PIERCING = 1 << 3,          # Ignores armor/defense
	HOMING = 1 << 4,            # Tracks moving targets
	BOUNCES = 1 << 5,           # Bounces off terrain/targets
	SPLITS = 1 << 6,            # Splits into multiple projectiles on impact
	LIFESTEAL = 1 << 7,         # Heals owner for % of damage dealt
	BURN = 1 << 8,              # Applies burning damage over time
	FREEZE = 1 << 9,            # Slows/freezes targets
	POISON = 1 << 10,           # Applies poison damage over time
	STUN = 1 << 11,             # Stuns targets briefly
	KNOCKBACK = 1 << 12,        # Pushes targets away from impact
	IGNORE_FRIENDLY_FIRE = 1 << 13,  # Won't damage owner's allies
	CRITICAL = 1 << 14,         # Can deal critical damage
	CHAIN = 1 << 15,            # Chains to nearby targets
}

# Projectile metadata (from projectile_atlas_metadata.json)
# Atlas: 416x128 pixels (13 columns × 4 rows @ 32x32 per tile)
const TILE_SIZE: int = 32
const ATLAS_WIDTH: int = 416
const ATLAS_HEIGHT: int = 128
const TOTAL_ROWS: int = 4
const MAX_FRAMES: int = 13

# Projectile data: row, frame_count, animated, default_behaviors
const PROJECTILE_DATA: Dictionary = {
	Type.SPEAR: {
		"name": "spear",
		"row": 0,
		"frames": 1,
		"animated": false,
		"default_behaviors": BehaviorFlags.NONE
	},
	Type.GLAIVE: {
		"name": "glaive",
		"row": 1,
		"frames": 1,
		"animated": false,
		"default_behaviors": BehaviorFlags.NONE
	},
	Type.SHADOWBOLT: {
		"name": "shadowbolt",
		"row": 2,
		"frames": 11,
		"animated": true,
		"animations": {
			"moving": {"start": 0, "end": 3, "fps": 10},
			"explode": {"start": 4, "end": 10, "fps": 15}
		},
		"default_behaviors": BehaviorFlags.EXPLODES | BehaviorFlags.AOE
	},
	Type.FIREBOLT: {
		"name": "firebolt",
		"row": 3,
		"frames": 13,
		"animated": true,
		"animations": {
			"moving": {"start": 0, "end": 5, "fps": 10},
			"explode": {"start": 6, "end": 12, "fps": 15}
		},
		"default_behaviors": BehaviorFlags.EXPLODES | BehaviorFlags.AOE | BehaviorFlags.BURN
	}
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

# Ownership and damage
var owner_ulid: PackedByteArray = PackedByteArray()  # ULID of entity that fired this projectile
var behavior_flags: int = BehaviorFlags.NONE  # Bitwise flags for projectile behavior
var is_aoe: bool = false  # If true, deals damage to all entities in radius (except owner)
var aoe_radius: float = 64.0  # AOE damage radius (in pixels) - 1 hex tile
var damage: float = 10.0  # Damage to deal on hit
var hit_entities: Array[Node] = []  # Track entities already hit (to prevent multi-hit)

# Travel state
var is_active: bool = false
var travel_progress: float = 0.0  # 0.0 to 1.0
var travel_distance: float = 0.0
var distance_traveled: float = 0.0  # Actual distance traveled

# Animation state (for animated projectiles like shadow bolt)
var current_frame: int = 0
var animation_timer: float = 0.0
var current_animation: String = "moving"  # "moving" or "explode"
var is_exploding: bool = false

# Callbacks
var on_hit: Callable  # Called when projectile reaches target
var on_return_to_pool: Callable  # Called when projectile finishes

func _ready() -> void:
	set_process(false)  # Disabled until fired

## Check if projectile has a specific behavior flag
func has_behavior(flag: int) -> bool:
	return (behavior_flags & flag) != 0

## Add a behavior flag to the projectile
func add_behavior(flag: int) -> void:
	behavior_flags |= flag

## Remove a behavior flag from the projectile
func remove_behavior(flag: int) -> void:
	behavior_flags &= ~flag

## Set multiple behavior flags at once
func set_behaviors(flags: int) -> void:
	behavior_flags = flags

## Fire the projectile from source to target
## If max_range_tiles is > 0, projectile will travel that many tiles max (1 tile = 64px)
## Otherwise it travels directly to target
## custom_behaviors: Optional custom behavior flags (if 0, uses default from PROJECTILE_DATA)
func fire(
	from: Vector2,
	to: Vector2,
	type: Type = Type.SPEAR,
	projectile_speed: float = 400.0,
	arc: float = 0.0,
	max_range_tiles: int = 8,  # Default: 8 tiles max range
	owner_id: PackedByteArray = PackedByteArray(),  # ULID of owner (empty = AI/bot)
	proj_damage: float = 10.0,  # Damage to deal
	is_area_damage: bool = false,  # Is this AOE? (deprecated: use behavior_flags)
	area_radius: float = 64.0,  # AOE radius in pixels
	custom_behaviors: int = 0  # Custom behavior flags (0 = use defaults)
) -> void:
	# Set configuration
	source_pos = from
	projectile_type = type
	speed = projectile_speed
	arc_height = arc
	owner_ulid = owner_id
	damage = proj_damage
	aoe_radius = area_radius
	hit_entities.clear()

	# Set behavior flags (use custom or default from projectile data)
	if custom_behaviors != 0:
		behavior_flags = custom_behaviors
	else:
		behavior_flags = PROJECTILE_DATA[type].get("default_behaviors", BehaviorFlags.NONE)

	# Update is_aoe from behavior flags (backward compatibility)
	is_aoe = has_behavior(BehaviorFlags.AOE) or is_area_damage

	# Calculate direction and max range
	direction = (to - from).normalized()

	# If max_range_tiles is specified, use it; otherwise go to target
	if max_range_tiles > 0:
		const HEX_TILE_SIZE = 64  # Hex tile size in pixels
		max_range = max_range_tiles * HEX_TILE_SIZE

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
	is_exploding = false

	# Reset animation state
	current_frame = 0
	animation_timer = 0.0
	current_animation = "moving"

	# Update shader to display correct sprite
	_update_sprite()

	# Calculate initial rotation
	if rotate_to_direction:
		var angle = direction.angle()
		rotation = angle

	# Enable processing
	set_process(true)
	visible = true

## Update projectile sprite based on type and current frame
func _update_sprite() -> void:
	if not sprite or not sprite.material:
		return

	var proj_data = PROJECTILE_DATA[projectile_type]

	# Set shader parameters for row and frame
	sprite.material.set_shader_parameter("projectile_row", proj_data["row"])
	sprite.material.set_shader_parameter("frame_index", current_frame)
	sprite.material.set_shader_parameter("total_rows", TOTAL_ROWS)
	sprite.material.set_shader_parameter("max_frames", MAX_FRAMES)

func _process(delta: float) -> void:
	if not is_active:
		return

	# Handle animation for animated projectiles
	if PROJECTILE_DATA[projectile_type]["animated"]:
		_update_animation(delta)

	# Handle explosion state (shadow bolt stops moving when exploding)
	if is_exploding:
		# Stay at target position while exploding
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

## Update animation frames for animated projectiles
func _update_animation(delta: float) -> void:
	var proj_data = PROJECTILE_DATA[projectile_type]
	if not proj_data.has("animations"):
		return

	var animations = proj_data["animations"]
	var anim_data = animations[current_animation]

	# Update animation timer
	animation_timer += delta
	var frame_duration = 1.0 / anim_data["fps"]

	if animation_timer >= frame_duration:
		animation_timer = 0.0

		# Advance to next frame
		current_frame += 1

		# Check if animation finished
		if current_frame > anim_data["end"]:
			if current_animation == "explode":
				# Explosion animation finished - return to pool
				_finish_explosion()
				return
			else:
				# Loop moving animation
				current_frame = anim_data["start"]

		_update_sprite()

## Called when projectile reaches target
func _on_reach_target() -> void:
	# Deal damage based on projectile type
	if is_aoe:
		_deal_aoe_damage()
	else:
		_deal_single_target_damage()

	# For projectiles with EXPLODES behavior, start explosion animation
	if has_behavior(BehaviorFlags.EXPLODES) and PROJECTILE_DATA[projectile_type]["animated"]:
		_start_explosion()
	else:
		# Non-exploding projectiles finish immediately
		_finish_projectile()

## Deal damage to single target at impact point
func _deal_single_target_damage() -> void:
	# Find entity at target position (if any)
	var hit_entity = _find_entity_at_position(target_pos, 32.0)  # 32px search radius
	if hit_entity:
		_apply_damage_to_entity(hit_entity)

## Deal AOE damage to all entities in radius (except owner)
func _deal_aoe_damage() -> void:
	# Find all entities within AOE radius
	var entities_in_range = _find_entities_in_radius(target_pos, aoe_radius)

	for entity in entities_in_range:
		_apply_damage_to_entity(entity)

## Find entity at a specific position
func _find_entity_at_position(pos: Vector2, search_radius: float) -> Node:
	# Get all registered entities from EntityManager
	if not EntityManager:
		return null

	var entities = EntityManager.get_registered_entities()
	var closest_entity = null
	var closest_distance = search_radius

	for entity in entities:
		if not is_instance_valid(entity):
			continue

		# Skip if this is the owner (no friendly fire)
		if _is_same_owner(entity):
			continue

		# Check distance
		var distance = entity.global_position.distance_to(pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_entity = entity

	return closest_entity

## Find all entities within radius
func _find_entities_in_radius(pos: Vector2, radius: float) -> Array[Node]:
	var result: Array[Node] = []

	if not EntityManager:
		return result

	var entities = EntityManager.get_registered_entities()

	for entity in entities:
		if not is_instance_valid(entity):
			continue

		# Skip if this is the owner (no friendly fire)
		if _is_same_owner(entity):
			continue

		# Check if in radius
		var distance = entity.global_position.distance_to(pos)
		if distance <= radius:
			result.append(entity)

	return result

## Check if entity has same owner as projectile
func _is_same_owner(entity: Node) -> bool:
	# If projectile has no owner (AI/bot), only check entity owner
	if owner_ulid.is_empty():
		# Projectile is from AI - only hit player entities
		if entity.has("owner_ulid"):
			return entity.owner_ulid.is_empty()  # Don't hit other AI
		return false

	# Projectile has owner - don't hit entities with same owner
	if entity.has("owner_ulid"):
		return entity.owner_ulid == owner_ulid

	return false

## Apply damage to an entity
func _apply_damage_to_entity(entity: Node) -> void:
	# Prevent hitting same entity multiple times
	if entity in hit_entities:
		return

	hit_entities.append(entity)

	# Apply damage if entity has health
	if entity.has_method("take_damage"):
		entity.take_damage(damage)
		print("Projectile hit %s for %.1f damage" % [entity.name, damage])

## Start explosion animation (for shadow bolt)
func _start_explosion() -> void:
	is_exploding = true
	current_animation = "explode"

	var anim_data = PROJECTILE_DATA[projectile_type]["animations"]["explode"]
	current_frame = anim_data["start"]
	animation_timer = 0.0

	_update_sprite()

	# Call hit callback when explosion starts
	if on_hit.is_valid():
		on_hit.call()

## Finish explosion and return to pool
func _finish_explosion() -> void:
	_finish_projectile()

## Finish projectile and return to pool
func _finish_projectile() -> void:
	is_active = false
	set_process(false)
	visible = false

	# Call hit callback if not already called
	if not is_exploding and on_hit.is_valid():
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
	current_frame = 0
	animation_timer = 0.0
	current_animation = "moving"
	is_exploding = false
	owner_ulid = PackedByteArray()
	behavior_flags = BehaviorFlags.NONE
	is_aoe = false
	aoe_radius = 64.0
	damage = 10.0
	hit_entities.clear()
	set_process(false)
	on_hit = Callable()
	on_return_to_pool = Callable()
