extends NPC
class_name FireWorm

# Fire Worm - ground-based animated worm NPC with shader-driven animations
# 90x90 pixel character animated via shader atlas system
# Controls the UV shader to display different animation frames

# Animation types (matches rows in texture atlas)
enum AnimType {
	IDLE = 0,
	WALK = 1,
	ATTACK = 2,
	TAKE_HIT = 3,
	DEATH = 4,
}

# Animation frame counts (matches actual atlas - 90x90 frames)
const ANIMATION_FRAME_COUNTS = {
	AnimType.IDLE: 9,        # Idle.png: 9 frames
	AnimType.WALK: 9,        # Walk.png: 9 frames
	AnimType.ATTACK: 16,     # Attack.png: 16 frames
	AnimType.TAKE_HIT: 3,    # Take hit.png: 3 frames
	AnimType.DEATH: 8,       # Death.png: 8 frames
}

# Animation speeds (frames per second)
const ANIMATION_SPEEDS = {
	AnimType.IDLE: 8.0,      # Idle animation
	AnimType.WALK: 10.0,     # Walking pace
	AnimType.ATTACK: 12.0,   # Fast attack animation
	AnimType.TAKE_HIT: 8.0,  # Hit reaction
	AnimType.DEATH: 10.0,    # Death animation
}

# Current shader animation state (separate from parent's UV-baked animation system)
var shader_animation: int = AnimType.IDLE
var shader_frame: float = 0.0  # Float for smooth interpolation
var shader_animation_playing: bool = true
var shader_animation_loop: bool = true

# Shader material reference
var shader_material: ShaderMaterial = null

func _ready():
	# Configure terrain type for land pathfinding
	terrain_type = TerrainType.LAND

	# Combat configuration - Ranged magical attacker (fire)
	combat_type = CombatType.MAGIC
	projectile_type = ProjectileType.FIRE_BOLT
	combat_range = 6  # Magic range (6 hexes)
	aggro_range = 8  # Magic units can use their combat_range for aggro (6-8 hexes is good)

	super._ready()  # Call parent NPC _ready

	# Setup shader material
	_setup_shader()

	# Start with idle animation
	play_animation(AnimType.IDLE, true)

## Override parent's _update_sprite since we use animation-based sprites, not direction-based
func _update_sprite():
	# Fire Worm uses animation frames, not directional sprites
	# The shader handles frame display via frame_index and animation_row
	pass

func _setup_shader():
	# Load the shader
	var shader = load("res://nodes/npc/fireworm/fireworm.gdshader")
	if not shader:
		push_error("FireWorm: Failed to load shader")
		return

	# Create shader material
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader

	# Load the atlas texture
	var atlas_texture = load("res://nodes/npc/fireworm/fireworm_atlas.png")
	if not atlas_texture:
		push_error("FireWorm: Failed to load atlas texture")
		return

	# Set shader parameters
	# Atlas: 1440x450 (16 columns × 5 rows @ 90x90 each)
	shader_material.set_shader_parameter("atlas_texture", atlas_texture)
	shader_material.set_shader_parameter("frame_size", Vector2(90, 90))
	shader_material.set_shader_parameter("atlas_size", Vector2(1440, 450))
	shader_material.set_shader_parameter("frames_per_row", 16)  # Max frames in any row (Attack)
	shader_material.set_shader_parameter("animation_row", 0)
	shader_material.set_shader_parameter("frame_index", 0)

	# Apply to sprite
	if has_node("Sprite2D"):
		var sprite = $Sprite2D

		# Create a simple 90x90 white texture for the sprite
		# The shader will handle drawing the correct atlas frame
		var placeholder = Image.create(90, 90, false, Image.FORMAT_RGBA8)
		placeholder.fill(Color.WHITE)
		var placeholder_texture = ImageTexture.create_from_image(placeholder)

		sprite.texture = placeholder_texture
		sprite.material = shader_material
		sprite.centered = true

		# Scale down the sprite to fit better on the tile map
		# Fire Worm is 90x90 pixels - scale to approximately 70% to match tile size better
		sprite.scale = Vector2(0.7, 0.7)
	else:
		push_error("FireWorm: No Sprite2D node found")

func _process(delta: float):
	super._process(delta)

	# Update sprite flipping based on movement direction
	_update_sprite_flip()

	# Auto-select animations based on state
	_auto_select_animation()

	if not shader_animation_playing or not shader_material:
		return

	# Get current animation settings
	var frame_count = ANIMATION_FRAME_COUNTS.get(shader_animation, 1)
	var anim_speed = ANIMATION_SPEEDS.get(shader_animation, 8.0)

	# Advance frame
	shader_frame += anim_speed * delta

	# Handle looping
	if shader_frame >= frame_count:
		if shader_animation_loop:
			shader_frame = fmod(shader_frame, float(frame_count))
		else:
			shader_frame = frame_count - 1
			shader_animation_playing = false

	# Update shader parameters
	shader_material.set_shader_parameter("frame_index", int(shader_frame))
	shader_material.set_shader_parameter("animation_row", shader_animation)
	shader_material.set_shader_parameter("frames_per_row", frame_count)

func _auto_select_animation():
	# Automatically select animation based on NPC state (from Rust)
	# Priority: Dead > Hurt > Attacking > Combat > Moving > Idle
	if has_state(State.DEAD) or shader_animation == AnimType.DEATH:
		if shader_animation != AnimType.DEATH:
			play_animation(AnimType.DEATH, false)
	elif has_state(State.HURT):
		if shader_animation != AnimType.TAKE_HIT:
			play_animation(AnimType.TAKE_HIT, false)
	elif has_state(State.ATTACKING):
		if shader_animation != AnimType.ATTACK:
			play_animation(AnimType.ATTACK, false)
	elif has_state(State.IN_COMBAT):
		# Combat ready stance (not actively attacking) - use idle animation
		if shader_animation != AnimType.IDLE:
			play_animation(AnimType.IDLE, true)
	elif has_state(State.MOVING):
		if shader_animation != AnimType.WALK:
			play_animation(AnimType.WALK, true)
	elif has_state(State.IDLE):
		if shader_animation != AnimType.IDLE:
			play_animation(AnimType.IDLE, true)

func _update_sprite_flip():
	# Flip sprite based on movement direction
	if has_state(State.MOVING) and sprite:
		# Use the movement vector from parent class
		var movement_vec = move_target_pos - move_start_pos
		if movement_vec.length_squared() > 0.01:
			# Flip sprite if moving left (negative x direction)
			if movement_vec.x < 0:
				sprite.scale.x = -abs(sprite.scale.x)  # Face left
			else:
				sprite.scale.x = abs(sprite.scale.x)   # Face right

## Play an animation
func play_animation(anim_type: int, loop: bool = true) -> void:
	if shader_animation == anim_type and shader_animation_playing:
		return  # Already playing this animation

	shader_animation = anim_type
	shader_frame = 0.0
	shader_animation_playing = true
	shader_animation_loop = loop

	# Update shader immediately
	if shader_material:
		shader_material.set_shader_parameter("animation_row", anim_type)
		shader_material.set_shader_parameter("frame_index", 0)
		shader_material.set_shader_parameter("frames_per_row", ANIMATION_FRAME_COUNTS.get(anim_type, 1))

## Check if current animation has finished (non-looping animations only)
func is_animation_finished() -> bool:
	return not shader_animation_playing

## Play attack animation
func attack() -> void:
	play_animation(AnimType.ATTACK, false)

## Play hit animation
func take_hit() -> void:
	play_animation(AnimType.TAKE_HIT, false)

## Play death animation
func die() -> void:
	play_animation(AnimType.DEATH, false)
