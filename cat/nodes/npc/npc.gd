extends Node2D
class_name NPC

# Base class for all NPCs (land and water-based) with 16-directional sprites and state management
#
# Unified entity system supporting both land and water pathfinding via terrain type flags.
# Uses critically-damped angular spring for smooth rotation and continuous path following.

## Signal emitted when pathfinding completes (for main.gd to update occupied_tiles)
signal pathfinding_completed(path: Array[Vector2i], success: bool)

## Signal emitted when entire path is complete
signal path_complete()

## Signal emitted when each waypoint is reached
signal waypoint_reached(tile: Vector2i)

## Signal emitted when pathfinding result is ready (replaces callbacks)
signal pathfinding_result(path: Array[Vector2i], success: bool)

@onready var sprite: Sprite2D = $Sprite2D
@onready var animation_mesh: MeshInstance2D = null  # Optional: For UV-baked animations (performance mode)

# Animation system
var use_animation_mesh: bool = false  # Set to true to use UV-baked animations instead of sprites
var current_animation: int = -1  # Current animation type (AnimationType enum)
var animation_frame: int = 0     # Current frame in animation
var animation_timer: float = 0.0 # Time elapsed in current frame
var animation_fps: float = 10.0  # Animation speed (frames per second)
var entity_type_for_animation: String = "martial_hero"  # Entity type for animation atlas lookup
var is_damaged: bool = false     # Flag for hurt animation trigger

# Animation atlas system (UV-baked meshes for high performance)
enum AnimationType {
	IDLE = 0,
	RUN = 1,
	ATTACK1 = 2,
	ATTACK2 = 3,
	TAKE_HIT = 4,
	DEATH = 5,
	JUMP = 6,
	FALL = 7
}

# Frame counts for each animation type
const ANIMATION_FRAMES = {
	AnimationType.IDLE: 8,      # 8 frames
	AnimationType.RUN: 8,       # 8 frames
	AnimationType.ATTACK1: 6,   # 6 frames
	AnimationType.ATTACK2: 6,   # 6 frames
	AnimationType.TAKE_HIT: 4,  # 4 frames
	AnimationType.DEATH: 6,     # 6 frames (was 10, corrected to match atlas)
	AnimationType.JUMP: 4,      # 4 frames (was 2, corrected to match atlas)
	AnimationType.FALL: 4       # 4 frames (was 2, corrected to match atlas)
}

# Atlas layout (1600x1600, each frame is 200x200)
const ATLAS_FRAME_SIZE = 200  # Each animation frame is 200x200 pixels
const ATLAS_WIDTH = 1600      # 8 frames per row
const ATLAS_HEIGHT = 1600     # 8 rows
const FRAMES_PER_ROW = 8      # 8 frames fit horizontally

# Mesh cache (class-level, shared across all instances)
static var _animation_meshes: Dictionary = {}  # "entity_type:animation_type:frame" -> ArrayMesh
static var _atlas_textures: Dictionary = {}    # "entity_type" -> Texture2D

# Terrain Type enum (matches Rust TerrainType and unified pathfinding system)
enum TerrainType {
	WATER = 0,  # Entity walks on water (ships, vikings)
	LAND = 1,   # Entity walks on land (ground NPCs, kings, warriors)
}

# NPC State enum (matches Rust bitwise flags pattern)
enum State {
	IDLE = 1 << 0,           # 1 - NPC is idle, can accept commands
	MOVING = 1 << 1,         # 2 - NPC is moving along a path
	PATHFINDING = 1 << 2,    # 4 - Pathfinding request in progress
	BLOCKED = 1 << 3,        # 8 - NPC is blocked (cannot move)
	INTERACTING = 1 << 4,    # 16 - NPC is interacting with object/player
	DEAD = 1 << 5,           # 32 - NPC is dead (no longer active)
	IN_COMBAT = 1 << 6,      # 64 - NPC is in combat
	ATTACKING = 1 << 7,      # 128 - NPC is attacking (playing attack animation)
	HURT = 1 << 8,           # 256 - NPC is hurt (playing hurt animation)
}

# Combat Type enum (matches Rust bitwise flags pattern)
enum CombatType {
	MELEE = 1 << 0,   # 1 - Close combat (1 hex range)
	RANGED = 1 << 1,  # 2 - Ranged physical attacks (bow, spear, etc.)
	BOW = 1 << 2,     # 4 - Bow/crossbow - uses ARROW/SPEAR projectiles
	MAGIC = 1 << 3,   # 8 - Magic attacks - uses spell projectiles (FIRE_BOLT, SHADOW_BOLT, etc.)
}

# Projectile Type enum (for BOW and MAGIC combat types)
enum ProjectileType {
	NONE = 0,
	ARROW = 1,
	SPEAR = 2,
	FIRE_BOLT = 3,
	SHADOW_BOLT = 4,
	ICE_SHARD = 5,
	LIGHTNING = 6,
}

# Cached state from Rust (updated via signal)
# NOTE: Rust EntityManagerBridge is the single source of truth for state
# This is just a local cache for performance
var current_state: int = State.IDLE

# Terrain type (set by child classes) - determines pathfinding behavior
var terrain_type: int = TerrainType.LAND  # Default to land

# Combat type (set by child classes) - determines combat behavior and range
var combat_type: int = CombatType.MELEE  # Default to melee
var projectile_type: int = ProjectileType.NONE  # Set if using BOW or MAGIC
var combat_range: int = 1  # Attack range in hexes (1 for melee, higher for ranged/bow/magic)
var aggro_range: int = 8  # Detection/aggro range in hexes (how far unit can detect enemies)

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
# NOTE: Use has_state(State.MOVING) instead of boolean - state is managed by Actor
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
var path_visualizer: Node2D = null  # Visual representation of path

# Pathfinding timeout (prevents entities getting stuck in PATHFINDING state forever)
var pathfinding_timeout: float = 5.0  # 5 seconds max wait for pathfinding result
var pathfinding_timer: float = 0.0  # Current time spent waiting

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
var cached_max_hp: float = 100.0  # Cache for health bar updates

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

	# Initialize current angle based on initial direction
	current_angle = direction_to_godot_angle(direction)
	target_angle = current_angle
	_last_sector = direction

	# Initialize animation mesh if enabled (do this before ULID check so pool entities get initialized)
	if use_animation_mesh:
		_initialize_animation_mesh()
	_update_sprite()

	# ULID is set by Rust (UnifiedEventBridge) before EntityManager calls add_child()
	# During pool initialization, ULID will be empty - this is expected
	# Only register stats/combat if ULID is set (i.e., entity is actually spawned)
	if ulid.is_empty():
		# Pool initialization - skip registration, will be done on actual spawn
		return

	# Register entity stats with UnifiedEventBridge Actor (replaces old StatsManager)
	# Combat registration happens automatically through stats - no separate call needed
	call_deferred("_register_stats")

	# Acquire health bar from pool (deferred to ensure Cluster is ready)
	call_deferred("_setup_health_bar")

# === State Management (Rust as Source of Truth) ===

## Initialize entity manager reference (deferred to ensure UnifiedEventBridge is ready)
func _initialize_entity_manager() -> void:
	# Use cached UnifiedEventBridge reference for performance
	entity_manager = Cache.get_unified_event_bridge()
	if not entity_manager:
		# Retry after a short delay if UnifiedEventBridge isn't ready yet
		await get_tree().create_timer(0.1).timeout
		entity_manager = Cache.get_unified_event_bridge()
		# If still not ready, it's a real error - but don't spam, just fail silently
		# State management won't work but entity can still function

## Signal handler: Rust state changed
func _on_rust_state_changed(entity_ulid: PackedByteArray, new_state: int) -> void:
	# Only update if this is our entity
	if entity_ulid == ulid:
		current_state = new_state

## Set state (notifies Rust and updates local cache)
func set_state(new_state: int) -> void:
	current_state = new_state  # Update local cache immediately
	if entity_manager:
		entity_manager.set_entity_state(ulid, new_state)

## Add state flag (notifies Rust and updates local cache)
func add_state(state_flag: int) -> void:
	var new_state = current_state | state_flag
	current_state = new_state  # Update local cache immediately
	if entity_manager:
		entity_manager.set_entity_state(ulid, new_state)

## Remove state flag (notifies Rust and updates local cache)
func remove_state(state_flag: int) -> void:
	var new_state = current_state & ~state_flag
	current_state = new_state  # Update local cache immediately
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

# === Animation Atlas Functions (UV-baked mesh system) ===

## Get or create mesh for specific animation frame
static func get_animation_mesh(entity_type: String, animation_type: AnimationType, frame: int) -> Mesh:
	var key = "%s:%d:%d" % [entity_type, animation_type, frame]

	if _animation_meshes.has(key):
		return _animation_meshes[key]

	# Generate mesh on demand
	var mesh = _create_mesh_for_frame(entity_type, animation_type, frame)
	if mesh:
		_animation_meshes[key] = mesh
	return mesh

## Get atlas texture for entity type
static func get_atlas_texture(entity_type: String) -> Texture2D:
	if _atlas_textures.has(entity_type):
		return _atlas_textures[entity_type]

	# Load atlas texture based on entity type
	var texture_path = ""
	match entity_type:
		"martial_hero", "king", "warrior":
			texture_path = "res://nodes/npc/martialhero/martialhero_atlas.png"
		"raptor", "dino", "jezza":
			# TODO: Create raptor atlas or use individual frames
			texture_path = "res://nodes/npc/dino/jezza/sheets/raptor-idle.png"  # Temporary
		_:
			push_error("NPC: Unknown entity type '%s' for animation atlas" % entity_type)
			return null

	var texture = load(texture_path)
	if texture:
		_atlas_textures[entity_type] = texture
	else:
		push_error("NPC: Failed to load texture at %s" % texture_path)

	return texture

## Create mesh with baked UVs for specific animation frame
static func _create_mesh_for_frame(entity_type: String, animation_type: AnimationType, frame: int) -> ArrayMesh:
	var atlas_texture = get_atlas_texture(entity_type)
	if not atlas_texture:
		return null

	# Validate frame index
	var max_frames = ANIMATION_FRAMES.get(animation_type, 1)
	if frame < 0 or frame >= max_frames:
		push_error("NPC: Invalid frame %d for animation %d (max: %d)" % [frame, animation_type, max_frames])
		return null

	# Calculate atlas position based on animation type and frame
	var atlas_position = _get_atlas_position(animation_type, frame)
	var atlas_col = atlas_position.x
	var atlas_row = atlas_position.y

	# Atlas texture dimensions
	var tex_w = float(atlas_texture.get_width())
	var tex_h = float(atlas_texture.get_height())

	# Calculate UV coordinates for this frame
	var frame_width = float(ATLAS_FRAME_SIZE)
	var frame_height = float(ATLAS_FRAME_SIZE)

	var u0 = (atlas_col * frame_width) / tex_w
	var v0 = (atlas_row * frame_height) / tex_h
	var u1 = u0 + (frame_width / tex_w)
	var v1 = v0 + (frame_height / tex_h)

	# No inset needed with nearest-neighbor filtering
	var inset_px = 0.0
	var du = inset_px / tex_w
	var dv = inset_px / tex_h

	u0 += du
	v0 += dv
	u1 -= du
	v1 -= dv

	# Create ArrayMesh with custom UV coordinates
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)

	# Vertices (quad corners) - centered at origin
	var half_width = frame_width / 2.0   # 100
	var half_height = frame_height / 2.0  # 100

	var vertices = PackedVector3Array([
		Vector3(-half_width, -half_height, 0),  # Top-left
		Vector3(half_width, -half_height, 0),   # Top-right
		Vector3(-half_width, half_height, 0),   # Bottom-left
		Vector3(half_width, half_height, 0)     # Bottom-right
	])

	# UV coordinates for this specific frame
	var uvs = PackedVector2Array([
		Vector2(u0, v0),  # Top-left
		Vector2(u1, v0),  # Top-right
		Vector2(u0, v1),  # Bottom-left
		Vector2(u1, v1)   # Bottom-right
	])

	# Indices (two triangles forming a quad)
	var indices = PackedInt32Array([
		0, 1, 2,  # First triangle
		2, 1, 3   # Second triangle
	])

	# Normals (all pointing toward camera)
	var normals = PackedVector3Array([
		Vector3(0, 0, 1),
		Vector3(0, 0, 1),
		Vector3(0, 0, 1),
		Vector3(0, 0, 1)
	])

	# Build the surface array
	surface_array[Mesh.ARRAY_VERTEX] = vertices
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_INDEX] = indices

	# Create the mesh
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)

	return array_mesh

## Calculate atlas position (col, row) for animation type and frame
static func _get_atlas_position(animation_type: AnimationType, frame: int) -> Vector2i:
	var row = 0
	var col = frame

	match animation_type:
		AnimationType.IDLE:
			row = 0
			col = frame  # 0-7
		AnimationType.RUN:
			row = 1
			col = frame  # 0-7
		AnimationType.JUMP:
			row = 2
			col = frame  # 0-3
		AnimationType.FALL:
			row = 3
			col = frame  # 0-3
		AnimationType.ATTACK1:
			row = 4
			col = frame  # 0-5
		AnimationType.ATTACK2:
			row = 5
			col = frame  # 0-5
		AnimationType.TAKE_HIT:
			row = 6
			col = frame  # 0-3
		AnimationType.DEATH:
			row = 7
			col = frame  # 0-5

	return Vector2i(col, row)

## Get frame count for animation type
static func get_frame_count(animation_type: AnimationType) -> int:
	return ANIMATION_FRAMES.get(animation_type, 1)

## Map game state to animation type
static func state_to_animation(state: int, is_damaged: bool = false) -> AnimationType:
	# State enum: IDLE = 1<<0, MOVING = 1<<1, IN_COMBAT = 1<<6, ATTACKING = 1<<7, HURT = 1<<8

	# Priority order: Hurt > Attacking > Combat > Moving > Idle
	if state & State.HURT:
		return AnimationType.TAKE_HIT

	if state & State.ATTACKING:
		return AnimationType.ATTACK1

	if state & State.IN_COMBAT:  # Combat ready stance (not actively attacking)
		return AnimationType.IDLE

	if state & State.MOVING:
		return AnimationType.RUN

	# Default to idle
	return AnimationType.IDLE

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
	if has_state(State.MOVING) or is_rotating_to_target:
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
			# State will be set to MOVING later in _process() when rotation completes (for water)
			# or immediately for land entities (no rotation phase)

			# Water entities rotate before moving (ships/vikings)
			if terrain_type == TerrainType.WATER:
				var angle_diff = abs(shortest_angle_deg(current_angle, target_angle))
				if angle_diff > rotation_threshold:
					# Start rotating phase - don't move yet
					is_rotating_to_target = true
					# Don't set MOVING state yet - waiting for rotation
				else:
					# Close enough, start moving immediately
					is_rotating_to_target = false
					add_state(State.MOVING)
			else:
				# Land entities move immediately
				add_state(State.MOVING)

func follow_path(path: Array[Vector2i], tile_map):
	if path.size() == 0:
		return

	# NOTE: Path validation is now handled by UnifiedEventBridge's Rust Actor
	# The Actor ensures all paths are valid before sending them to GDScript

	current_path = path
	# If path has only 1 element, it's just the destination
	# If path has 2+ elements, index 0 is current position, so start at 1
	path_index = 1 if path.size() > 1 else 0

	# Create path visualizer
	_create_path_visualizer(path, tile_map)

	_advance_to_next_waypoint()

## Request random movement within a distance range
## This is the preferred method for AI-controlled entities
## @param tile_map: The tile map reference for coordinate conversion
## @param min_distance: Minimum distance in tiles
## @param max_distance: Maximum distance in tiles
func request_random_movement(tile_map, min_distance: int, max_distance: int) -> void:
	# Validate ULID
	if ulid.is_empty():
		push_error("request_random_movement: Entity has no ULID!")
		return

	# Get current tile position
	var current_tile = tile_map.local_to_map(position)

	# Get unified event bridge
	var bridge = get_node_or_null("/root/UnifiedEventBridge")
	if not bridge:
		push_error("request_random_movement: UnifiedEventBridge not found!")
		return

	# Connect to random_dest_found signal if not already connected
	if not bridge.random_dest_found.is_connected(_on_random_dest_found):
		bridge.random_dest_found.connect(_on_random_dest_found)

	# Request random destination (ASYNC - result via signal)
	bridge.request_random_destination(
		ulid,
		terrain_type,
		current_tile.x,
		current_tile.y,
		min_distance,
		max_distance
	)

## Request pathfinding to a target tile (uses unified pathfinding bridge)
func request_pathfinding(target_tile: Vector2i, tile_map):
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
	pathfinding_timer = 0.0  # Reset timeout timer

	# Get unified event bridge
	var bridge = get_node_or_null("/root/UnifiedEventBridge")
	if not bridge:
		push_error("request_pathfinding: UnifiedEventBridge not found! Make sure it's added as an autoload.")
		remove_state(State.PATHFINDING)
		return

	# All entities use ULID for persistent tracking
	var entity_id = ulid  # PackedByteArray for both water and land entities
	var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"

	# CRITICAL: Prevent signal connection leaks
	# Disconnect first to ensure we don't accumulate duplicate connections when entity is pooled/reused
	if bridge.path_found.is_connected(_on_path_found):
		bridge.path_found.disconnect(_on_path_found)
	if bridge.path_failed.is_connected(_on_path_failed):
		bridge.path_failed.disconnect(_on_path_failed)

	bridge.path_found.connect(_on_path_found)
	bridge.path_failed.connect(_on_path_failed)

	# Request path through unified bridge (result comes via signal)
	# UnifiedEventBridge expects: request_path(ulid, terrain_type, start_q, start_r, goal_q, goal_r, avoid_entities)
	bridge.request_path(entity_id, terrain_type, current_tile.x, current_tile.y, target_tile.x, target_tile.y, true)

## Handle path_found signal from UnifiedEventBridge
func _on_path_found(entity_ulid: PackedByteArray, path: Array, cost: float) -> void:
	var ulid_hex = UlidManager.to_hex(entity_ulid)

	# Check if this path is for this entity
	if entity_ulid != ulid:
		return  # Not for this entity

	# CRITICAL: Validate entity is still valid before proceeding
	# Entity may have been freed (death, despawn) during async pathfinding
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		# Entity is being freed - don't process pathfinding result
		return

	# Remove pathfinding state
	remove_state(State.PATHFINDING)

	# Convert Array to Array[Vector2i] for type safety
	var typed_path: Array[Vector2i] = []
	for point in path:
		if point is Vector2i:
			typed_path.append(point)
		elif point is Dictionary:
			# Handle case where path might be serialized as {x, y}
			typed_path.append(Vector2i(point.get("x", 0), point.get("y", 0)))

	var success = typed_path.size() > 0

	# Emit signals for external listeners
	pathfinding_completed.emit(typed_path, success)
	pathfinding_result.emit(typed_path, success)

	# Handle path internally
	if success:
		follow_path(typed_path, Cache.get_tile_map())
	else:
		add_state(State.BLOCKED)
		push_error("NPC %s: Path FAILED - empty path returned" % [ulid_hex])

## Handle path_failed signal from UnifiedEventBridge
func _on_path_failed(entity_ulid: PackedByteArray) -> void:
	var ulid_hex = UlidManager.to_hex(entity_ulid)

	# Check if this path is for this entity
	if entity_ulid != ulid:
		return  # Not for this entity

	# CRITICAL: Validate entity is still valid before proceeding
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# Remove pathfinding state
	remove_state(State.PATHFINDING)
	add_state(State.BLOCKED)

	# Emit signals for external listeners
	var empty_path: Array[Vector2i] = []
	pathfinding_completed.emit(empty_path, false)
	pathfinding_result.emit(empty_path, false)

	push_error("NPC %s: Pathfinding FAILED - no path found" % [ulid_hex])

## Handle random_dest_found signal from UnifiedEventBridge
func _on_random_dest_found(entity_ulid: PackedByteArray, destination_q: int, destination_r: int, found: bool) -> void:
	# Check if this is for this entity
	if entity_ulid != ulid:
		return

	# CRITICAL: Validate entity is still valid before proceeding
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# If no destination found, do nothing
	if not found:
		return

	var destination = Vector2i(destination_q, destination_r)
	var current_tile = Cache.get_tile_map().local_to_map(position)

	# If destination is same as current position, do nothing
	if destination == current_tile:
		return

	# Request pathfinding to the random destination
	request_pathfinding(destination, Cache.get_tile_map())

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
		# NOTE: Path validation is handled by UnifiedEventBridge's Rust Actor
		# All waypoints in the path are pre-validated for the entity's terrain type
		var next_pos = tile_map.map_to_local(next_tile)
		move_to(next_pos)

## Update z-index based on current tile position for proper isometric layering
func _update_z_index() -> void:
	# Use terrain-specific z-index
	if terrain_type == TerrainType.WATER:
		z_index = Cache.Z_INDEX_SHIPS  # Water entities (ships)
	else:
		z_index = Cache.Z_INDEX_NPCS   # Land entities (ground NPCs)

## Initialize animation mesh for UV-baked animations
func _initialize_animation_mesh() -> void:
	# Create MeshInstance2D if it doesn't exist
	if not animation_mesh:
		animation_mesh = MeshInstance2D.new()
		add_child(animation_mesh)
		animation_mesh.name = "AnimationMesh"

	# Load initial animation (IDLE, frame 0) using class static functions
	var initial_mesh = NPC.get_animation_mesh(entity_type_for_animation, AnimationType.IDLE, 0)
	var initial_texture = NPC.get_atlas_texture(entity_type_for_animation)

	if initial_mesh and initial_texture:
		animation_mesh.mesh = initial_mesh
		animation_mesh.texture = initial_texture
		animation_mesh.visible = true
		sprite.visible = false  # Hide directional sprite when using animation mesh
		current_animation = AnimationType.IDLE
		animation_frame = 0

		# Scale down the animation mesh to match tile size
		# Frame is 200x200, scale to approximately 30% to match hex tiles (~60 pixels)
		animation_mesh.scale = Vector2(0.3, 0.3)
	else:
		push_error("NPC: Failed to load initial animation mesh!")
		use_animation_mesh = false

## Update sprite/animation based on current state
func _update_animation() -> void:
	if use_animation_mesh and animation_mesh:
		# Use UV-baked animation mesh system (high performance)
		_update_animation_mesh()
	else:
		# Fallback: Use color modulation to indicate state
		if has_state(State.IN_COMBAT):
			modulate = Color(1.2, 0.9, 0.9, 1.0)  # Reddish
		elif has_state(State.MOVING):
			modulate = Color.WHITE
		elif has_state(State.BLOCKED):
			modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellowish
		elif has_state(State.IDLE):
			modulate = Color.WHITE
		else:
			modulate = Color.WHITE

## Update animation mesh based on current state
func _update_animation_mesh() -> void:
	# Determine target animation based on state using class static function
	var target_animation = NPC.state_to_animation(current_state, is_damaged)

	# If animation changed, reset frame counter
	if target_animation != current_animation:
		current_animation = target_animation
		animation_frame = 0
		animation_timer = 0.0

	# Get frame count for current animation
	var frame_count = NPC.get_frame_count(current_animation)

	# Update animation mesh with current frame
	var mesh = NPC.get_animation_mesh(entity_type_for_animation, current_animation, animation_frame)
	if mesh:
		animation_mesh.mesh = mesh

	# Flip animation mesh based on movement direction (similar to shader-based NPCs)
	if has_state(State.MOVING):
		var movement_vec = move_target_pos - move_start_pos
		if movement_vec.length_squared() > 0.01:
			if movement_vec.x < 0:
				animation_mesh.scale.x = -abs(animation_mesh.scale.x)  # Face left
			else:
				animation_mesh.scale.x = abs(animation_mesh.scale.x)   # Face right

	# Clear damaged flag after hurt animation completes one cycle
	if is_damaged and current_animation == AnimationType.TAKE_HIT:
		if animation_frame >= frame_count - 1:
			is_damaged = false

## Advance animation frame based on time
func _advance_animation_frame(delta: float) -> void:
	# Get frame count for current animation using class static function
	var frame_count = NPC.get_frame_count(current_animation)
	if frame_count <= 0:
		return

	# Advance timer
	animation_timer += delta

	# Check if we should advance to next frame
	var frame_duration = 1.0 / animation_fps
	if animation_timer >= frame_duration:
		animation_timer -= frame_duration

		# Advance to next frame (loop back to 0)
		animation_frame = (animation_frame + 1) % frame_count

func _process(delta):
	# Update z-index for proper layering as NPC moves
	_update_z_index()

	# Advance animation frames if using animation mesh
	if use_animation_mesh and animation_mesh:
		_advance_animation_frame(delta)

	# Update sprite/animation based on state
	_update_animation()

	# CRITICAL: Check pathfinding timeout to prevent stuck state
	if has_state(State.PATHFINDING):
		pathfinding_timer += delta
		if pathfinding_timer > pathfinding_timeout:
			var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"
			push_warning("NPC %s: Pathfinding timeout! Resetting to BLOCKED state." % ulid_hex)
			remove_state(State.PATHFINDING)
			add_state(State.BLOCKED)
			pathfinding_timer = 0.0

	# Pause movement ONLY when actively attacking or hurt (not just IN_COMBAT)
	# Entities should be able to move while IN_COMBAT to chase enemies or reposition
	if has_state(State.ATTACKING) or has_state(State.HURT):
		# Stop any ongoing movement
		if has_state(State.MOVING):
			remove_state(State.MOVING)
			move_progress = 0.0
		if is_rotating_to_target:
			is_rotating_to_target = false
		return

	# Handle rotation phase (before moving) - water entities only
	if is_rotating_to_target:
		var angle_diff = abs(shortest_angle_deg(current_angle, target_angle))
		if angle_diff <= rotation_threshold:
			# Rotation complete, start moving
			is_rotating_to_target = false
			# Atomic state transition: IDLE -> MOVING (single Rust call)
			set_state((current_state & ~State.IDLE) | State.MOVING)

	# Smooth movement interpolation
	if has_state(State.MOVING):
		# Calculate progress based on actual distance and desired speed (tiles per second)
		# Average hex tile size is approximately 30 pixels (32x28)
		const AVERAGE_TILE_SIZE_PIXELS = 30.0
		var tiles_per_second = move_speed
		var progress_per_second = tiles_per_second * AVERAGE_TILE_SIZE_PIXELS / max(move_distance, 1.0)
		move_progress += delta * progress_per_second

		if move_progress >= 1.0:
			# Movement complete - reached waypoint
			position = move_target_pos
			remove_state(State.MOVING)
			move_progress = 1.0

			# Update combat system with new position (if registered)
			_update_combat_position()

			# Remove waypoint marker
			if path_visualizer and path_visualizer.has_method("remove_first_waypoint"):
				path_visualizer.remove_first_waypoint()

			# Notify waypoint reached via signal
			if current_path.size() > 0 and path_index >= 0 and path_index < current_path.size():
				var reached_tile = current_path[path_index]
				waypoint_reached.emit(reached_tile)

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

					# Update entity position in Rust's Actor state (critical for collision detection)
					# NOTE: Path validation is handled by UnifiedEventBridge's Rust Actor
					if not ulid.is_empty():
						var bridge = get_node_or_null("/root/UnifiedEventBridge")
						if bridge:
							bridge.update_entity_position(ulid, final_tile.x, final_tile.y)

				var was_following_path = current_path.size() > 0
				current_path.clear()
				path_index = 0

				# Atomic state transition: MOVING -> IDLE (single Rust call)
				set_state((current_state & ~State.MOVING) | State.IDLE)

				# Clean up visualizer
				if path_visualizer:
					path_visualizer.queue_free()
					path_visualizer = null

				# Notify completion via signal
				if was_following_path:
					path_complete.emit()
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

# Helper function to register stats (called deferred to ensure UnifiedEventBridge is ready)
func _register_stats() -> void:
	var bridge = get_node_or_null("/root/UnifiedEventBridge")
	if not bridge:
		push_error("_register_stats: UnifiedEventBridge not found!")
		return

	if ulid.is_empty():
		push_warning("_register_stats: Entity has no ULID, skipping stats registration")
		return

	# Determine entity type based on terrain
	var entity_type = "ship" if terrain_type == TerrainType.WATER else "npc"

	# CRITICAL: Connect to signals BEFORE registering stats
	# This ensures we receive the initial stat values that Rust emits during registration
	if not bridge.stat_changed.is_connected(_on_stat_changed):
		bridge.stat_changed.connect(_on_stat_changed)
	if not bridge.entity_died.is_connected(_on_entity_died):
		bridge.entity_died.connect(_on_entity_died)
	if not bridge.entity_damaged.is_connected(_on_entity_damaged):
		bridge.entity_damaged.connect(_on_entity_damaged)
	if not bridge.entity_healed.is_connected(_on_entity_healed):
		bridge.entity_healed.connect(_on_entity_healed)
	if not bridge.damage_dealt.is_connected(_on_damage_dealt):
		bridge.damage_dealt.connect(_on_damage_dealt)
	if not bridge.combat_started.is_connected(_on_combat_started):
		bridge.combat_started.connect(_on_combat_started)
	if not bridge.combat_ended.is_connected(_on_combat_ended):
		bridge.combat_ended.connect(_on_combat_ended)

	# Get current hex position
	var hex_pos: Vector2i
	if Cache and Cache.tile_map:
		hex_pos = Cache.tile_map.local_to_map(position)
	else:
		hex_pos = Vector2i(int(position.x / 128.0), int(position.y / 128.0))

	# Register entity stats with Actor (including player_ulid for team detection and combat info)
	# This will trigger Rust to emit StatChanged events for all initial stat values
	bridge.register_entity_stats(ulid, player_ulid, entity_type, terrain_type, hex_pos.x, hex_pos.y, combat_type, projectile_type, combat_range, aggro_range)

# NOTE: Combat registration removed - now automatic through stats registration
# The UnifiedEventBridge Actor tracks combat-relevant entities automatically
# when RegisterEntityStats is called in _register_stats()
# No separate combat registration needed!

# Update combat system with current position (called when entity moves)
func _update_combat_position() -> void:
	if ulid.is_empty():
		return

	# Get current hex position from global position
	if not Cache.tile_map:
		return

	var hex_coords = Cache.tile_map.local_to_map(global_position)

	# Update position in UnifiedEventBridge Actor
	var bridge = Cache.get_unified_event_bridge()
	if bridge:
		bridge.update_entity_position(ulid, hex_coords.x, hex_coords.y)
	else:
		push_warning("NPC: UnifiedEventBridge not available for position update")

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

	# Initialize health bar with default values based on terrain type
	# Stats will be updated via signals from UnifiedEventBridge Actor
	var default_hp = 100.0 if terrain_type == TerrainType.WATER else 50.0
	var default_max_hp = 100.0 if terrain_type == TerrainType.WATER else 50.0
	cached_max_hp = default_max_hp  # Cache for health bar updates
	health_bar.initialize(default_hp, default_max_hp, energy, max_energy)

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
	# Only update if this is our entity
	if entity_ulid != ulid:
		return

	# CRITICAL: Validate entity still valid (not being freed)
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# Handle HP stat changes (includes initial registration values)
	# StatType enum from Rust: HP = 0, MaxHP = 1, Mana = 7, MaxMana = 8
	const STAT_HP = 0
	const STAT_MAX_HP = 1
	const STAT_MANA = 7
	const STAT_MAX_MANA = 8

	if stat_type == STAT_MAX_HP:
		# Update cached max HP for health bar
		cached_max_hp = new_value
		# Validate: MaxHP should never be 0 on spawn
		if new_value <= 0:
			var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"
			push_error("[NPC] Entity %s (ULID: %s) spawned with invalid MaxHP: %f" % [entity_type_for_animation, ulid_hex, new_value])
		# Update health bar if it exists
		if health_bar and is_instance_valid(health_bar):
			health_bar.max_health = new_value
	elif stat_type == STAT_HP:
		# Validate: HP should never be 0 on initial spawn (unless entity is dead)
		if new_value <= 0 and not has_state(State.DEAD):
			var ulid_hex = UlidManager.to_hex(ulid) if not ulid.is_empty() else "NO_ULID"
			push_error("[NPC] Entity %s (ULID: %s) has 0 HP but is not marked DEAD (cached_max_hp: %f)" % [entity_type_for_animation, ulid_hex, cached_max_hp])
		# Update current HP in health bar
		if health_bar and is_instance_valid(health_bar):
			health_bar.set_health_values(new_value, cached_max_hp)

# Handle entity death
func _on_entity_died(entity_ulid: PackedByteArray) -> void:
	if entity_ulid != ulid:
		return

	# CRITICAL: Validate entity still valid before cleanup
	# Prevents double-free if signal fires multiple times
	if not is_instance_valid(self) or is_queued_for_deletion():
		return

	# Release health bar before dying
	_release_health_bar()

	# Clean up path visualizer (waypoints)
	if path_visualizer:
		# Remove from parent first, then free
		if path_visualizer.get_parent():
			path_visualizer.get_parent().remove_child(path_visualizer)
		# Free regardless of parent status (fix potential memory leak)
		path_visualizer.queue_free()
		path_visualizer = null

	# Cleanup entity from UnifiedEventBridge Actor state
	var bridge = get_node_or_null("/root/UnifiedEventBridge")
	if bridge:
		bridge.remove_entity(ulid)  # NOTE: This handles combat unregistration in Actor

	# Unregister from ULID manager
	UlidManager.unregister_entity(ulid)

	# CRITICAL: Clear ULID before returning to pool to prevent stale references
	var old_ulid = ulid
	ulid = PackedByteArray()

	# Return entity to pool or despawn
	if Cluster and pool_name != "":
		# Entity came from pool - return it
		if is_inside_tree():
			get_parent().remove_child(self)
		Cluster.release(pool_name, self)
	else:
		# Entity not pooled - queue free
		queue_free()

# Handle entity taking damage
func _on_entity_damaged(entity_ulid: PackedByteArray, damage: float, new_hp: float) -> void:
	if entity_ulid != ulid:
		return

	# CRITICAL: Validate entity still valid
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# Trigger hurt animation if using animation mesh
	if use_animation_mesh:
		is_damaged = true

	# Remove mutually exclusive states before adding HURT
	# Entity cannot be ATTACKING, MOVING, IDLE, or PATHFINDING while hurt
	remove_state(State.ATTACKING)
	remove_state(State.MOVING)
	remove_state(State.IDLE)
	remove_state(State.PATHFINDING)

	# Add HURT state for shader-based animation entities (like Jezza)
	add_state(State.HURT)

	# Clear HURT state after hurt animation duration (~0.5s for most entities)
	var hurt_duration = 0.5
	await get_tree().create_timer(hurt_duration).timeout
	if is_instance_valid(self):
		remove_state(State.HURT)
		# After hurt animation completes, entity returns to IN_COMBAT (if still in combat)
		# The IN_COMBAT state is already set by Rust, so we don't need to add it

	# Update health bar if it exists
	if health_bar and is_instance_valid(health_bar):
		health_bar.set_health_values(new_hp, cached_max_hp)

# Handle combat started event (sets IN_COMBAT state)
func _on_combat_started(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray) -> void:
	# Check if this entity is involved in combat (as attacker or defender)
	if attacker_ulid != ulid and defender_ulid != ulid:
		return

	# CRITICAL: Validate entity still valid
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# Add IN_COMBAT state
	add_state(State.IN_COMBAT)

# Handle combat ended event (clears IN_COMBAT state and returns to IDLE)
func _on_combat_ended(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray) -> void:
	# Check if this entity was involved in combat (as attacker or defender)
	if attacker_ulid != ulid and defender_ulid != ulid:
		return

	# CRITICAL: Validate entity still valid
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# Remove IN_COMBAT state
	remove_state(State.IN_COMBAT)

	# Clear any lingering ATTACKING or HURT states
	remove_state(State.ATTACKING)
	remove_state(State.HURT)

	# Return to IDLE state (Rust source of truth will maintain this)
	add_state(State.IDLE)

# Handle damage dealt event (for ATTACKING state management)
func _on_damage_dealt(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray, damage: int) -> void:
	# Check if this entity is the attacker
	if attacker_ulid != ulid:
		return

	# CRITICAL: Validate entity still valid
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# Remove mutually exclusive states before adding ATTACKING
	# Entity cannot be MOVING, IDLE, or PATHFINDING while attacking
	remove_state(State.MOVING)
	remove_state(State.IDLE)
	remove_state(State.PATHFINDING)

	# Add ATTACKING state to trigger attack animation
	add_state(State.ATTACKING)

	# Clear ATTACKING state after attack animation duration
	# Duration varies by entity - for Jezza bite is 10 frames @ 10fps = 1.0s
	var attack_duration = 1.0
	await get_tree().create_timer(attack_duration).timeout
	if is_instance_valid(self):
		remove_state(State.ATTACKING)
		# After attack completes, entity returns to IN_COMBAT (idle combat stance)
		# The IN_COMBAT state is already set by combat_started event

# Handle entity being healed
func _on_entity_healed(entity_ulid: PackedByteArray, heal_amount: float, new_hp: float) -> void:
	if entity_ulid != ulid:
		return

	# CRITICAL: Validate entity still valid
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree():
		return

	# Update health bar if it exists
	if health_bar and is_instance_valid(health_bar):
		health_bar.set_health_values(new_hp, cached_max_hp)

# Override _exit_tree to ensure cleanup
func _exit_tree() -> void:
	# CRITICAL: Disconnect all signals first to prevent signal leaks
	var bridge = get_node_or_null("/root/UnifiedEventBridge")
	if bridge:
		if bridge.path_found.is_connected(_on_path_found):
			bridge.path_found.disconnect(_on_path_found)
		if bridge.path_failed.is_connected(_on_path_failed):
			bridge.path_failed.disconnect(_on_path_failed)
		if bridge.random_dest_found.is_connected(_on_random_dest_found):
			bridge.random_dest_found.disconnect(_on_random_dest_found)

	# DISABLED: StatsManager causes lock contention with UnifiedEventBridge Actor
	# if StatsManager:
	# 	if StatsManager.stat_changed.is_connected(_on_stat_changed):
	# 		StatsManager.stat_changed.disconnect(_on_stat_changed)
	# 	if StatsManager.entity_died.is_connected(_on_entity_died):
	# 		StatsManager.entity_died.disconnect(_on_entity_died)

	# Release health bar
	_release_health_bar()

	# Clean up path visualizer
	if path_visualizer:
		path_visualizer.queue_free()
		path_visualizer = null

	# NOTE: Combat unregistration handled by bridge.remove_entity() in cleanup()
	# No separate call needed

## Reset entity state for pool reuse (called by Pool.release())
## CRITICAL: Clears ALL internal state to prevent stale data across pool reuse
func reset_for_pool() -> void:
	# Reset movement state (state flags reset below)
	is_rotating_to_target = false
	move_start_pos = Vector2.ZERO
	move_target_pos = Vector2.ZERO
	move_progress = 0.0
	move_distance = 0.0

	# Reset path following
	current_path.clear()
	path_index = 0

	# Clear path visualizer (should already be freed, but defensive)
	if path_visualizer:
		if path_visualizer.get_parent():
			path_visualizer.get_parent().remove_child(path_visualizer)
		path_visualizer.queue_free()
		path_visualizer = null

	# Reset state flags
	current_state = State.IDLE

	# Reset pathfinding timeout
	pathfinding_timer = 0.0

	# Clear ULID and player ownership (will be set on next spawn)
	ulid = PackedByteArray()
	player_ulid = PackedByteArray()

	# Reset direction and angles
	direction = 0
	current_angle = 0.0
	target_angle = 0.0
	angular_velocity = 0.0

	# Clear occupied tiles reference
	occupied_tiles.clear()

	# Health bar should already be released, but ensure it's cleared
	health_bar = null

	# Energy reset
	energy = max_energy

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

	# Set up signal connections for hit and pool return
	var target_ulid: PackedByteArray
	if "ulid" in target and target.ulid is PackedByteArray:
		target_ulid = target.ulid

	# Connect to projectile_hit signal to deal damage
	projectile.projectile_hit.connect(func():
		# Deal damage through StatsManager
		if StatsManager and not target_ulid.is_empty():
			var damage_dealt = StatsManager.take_damage(target_ulid, attack_power)
	, CONNECT_ONE_SHOT)

	# Connect to ready_for_pool signal to return projectile
	projectile.ready_for_pool.connect(func(proj: Projectile):
		if proj.get_parent():
			proj.get_parent().remove_child(proj)
		if Cluster:
			Cluster.release("projectile", proj)
	, CONNECT_ONE_SHOT)

	# Fire projectile
	projectile.fire(
		global_position,
		target.global_position,
		projectile_type,
		400.0,  # Speed in pixels/sec
		arc_height
	)
