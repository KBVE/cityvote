extends NPC
class_name MartialHero

## Martial Hero - Animated sprite-based ground NPC
## Uses sprite atlas with 8 different animations (Idle, Run, Jump, Fall, Attack1, Attack2, Take Hit, Death)

# Animation state
enum AnimationType {
	IDLE = 0,
	RUN = 1,
	JUMP = 2,
	FALL = 3,
	ATTACK1 = 4,
	ATTACK2 = 5,
	TAKE_HIT = 6,
	DEATH = 7
}

# Animation metadata (from martialhero_atlas.json)
const ANIM_FRAMES = {
	AnimationType.IDLE: 8,
	AnimationType.RUN: 8,
	AnimationType.JUMP: 4,
	AnimationType.FALL: 4,
	AnimationType.ATTACK1: 6,
	AnimationType.ATTACK2: 6,
	AnimationType.TAKE_HIT: 4,
	AnimationType.DEATH: 6
}

# Animation timing (frames per second)
const ANIM_FPS = {
	AnimationType.IDLE: 8.0,
	AnimationType.RUN: 12.0,
	AnimationType.JUMP: 10.0,
	AnimationType.FALL: 8.0,
	AnimationType.ATTACK1: 12.0,
	AnimationType.ATTACK2: 12.0,
	AnimationType.TAKE_HIT: 10.0,
	AnimationType.DEATH: 8.0
}

# Current animation state
var current_animation: AnimationType = AnimationType.IDLE
var current_frame: int = 0
var animation_time: float = 0.0
var animation_loop: bool = true  # Whether current animation should loop

# Sprite shader reference
var sprite_material: ShaderMaterial = null

# Pool configuration
var pool_key: String = "martialhero"

func _ready():
	super._ready()

	# Set terrain type to LAND
	terrain_type = TerrainType.LAND

	# Set pool name
	pool_name = "martialhero"

	# Setup sprite material with shader
	if sprite:
		_setup_sprite_shader()

	# Start with idle animation
	play_animation(AnimationType.IDLE, true)

	# Connect to path_complete signal to play idle animation
	path_complete.connect(_on_path_complete)

func _setup_sprite_shader():
	"""Setup the sprite atlas shader on the Sprite2D node"""
	# Load the shader
	var shader = load("res://nodes/npc/martialhero/martialhero.gdshader")
	if not shader:
		push_error("MartialHero: Failed to load shader")
		return

	# Create shader material
	sprite_material = ShaderMaterial.new()
	sprite_material.shader = shader

	# Load the atlas texture
	var atlas_texture = load("res://nodes/npc/martialhero/martialhero_atlas.png")
	if not atlas_texture:
		push_error("MartialHero: Failed to load atlas texture")
		return

	# Set shader parameters
	# Atlas: 1600x1600 (8 columns × 8 rows @ 200x200 each)
	sprite_material.set_shader_parameter("atlas_texture", atlas_texture)
	sprite_material.set_shader_parameter("frame_size", Vector2(200, 200))
	sprite_material.set_shader_parameter("atlas_size", Vector2(1600, 1600))
	sprite_material.set_shader_parameter("frames_per_row", 8)  # Max frames in any row
	sprite_material.set_shader_parameter("animation_row", 0)
	sprite_material.set_shader_parameter("frame_index", 0)

	# Create a simple 200x200 white placeholder texture for the sprite
	# The shader will handle drawing the correct atlas frame
	var placeholder = Image.create(200, 200, false, Image.FORMAT_RGBA8)
	placeholder.fill(Color.WHITE)
	var placeholder_texture = ImageTexture.create_from_image(placeholder)

	sprite.texture = placeholder_texture
	sprite.material = sprite_material
	sprite.centered = true
	sprite.scale = Vector2(0.4, 0.4)  # Scale sprite only, not health bar (200x200 → 80x80)

func _process(delta):
	super._process(delta)

	# Update animation
	_update_animation(delta)

	# Auto-play run animation when moving, idle when not
	if is_moving and current_animation == AnimationType.IDLE:
		play_animation(AnimationType.RUN, true)
	elif not is_moving and current_animation == AnimationType.RUN:
		play_animation(AnimationType.IDLE, true)

	# Handle sprite flipping based on movement direction
	_update_sprite_flip()

func _update_animation(delta: float):
	"""Update the current animation frame"""
	if current_animation == AnimationType.DEATH and current_frame >= ANIM_FRAMES[AnimationType.DEATH] - 1:
		# Death animation finished, stay on last frame
		return

	# Get frame count and FPS for current animation
	var frame_count = ANIM_FRAMES.get(current_animation, 8)
	var fps = ANIM_FPS.get(current_animation, 8.0)
	var frame_duration = 1.0 / fps

	# Update animation timer
	animation_time += delta

	# Check if we need to advance to next frame
	if animation_time >= frame_duration:
		animation_time -= frame_duration
		current_frame += 1

		# Handle looping or animation end
		if current_frame >= frame_count:
			if animation_loop:
				current_frame = 0
			else:
				current_frame = frame_count - 1  # Stay on last frame

		# Update shader
		_update_shader_frame()

func _update_shader_frame():
	"""Update shader parameters with current animation state"""
	if sprite_material:
		sprite_material.set_shader_parameter("animation_row", current_animation)
		sprite_material.set_shader_parameter("frame_index", current_frame)

func _update_sprite_flip():
	"""Flip sprite horizontally based on movement direction"""
	if not sprite:
		return

	# If moving, determine flip based on target position
	if is_moving and move_target_pos != position:
		var direction_vec = move_target_pos - position

		# Flip sprite when moving left (negative x direction)
		if direction_vec.x < 0:
			sprite.flip_h = true
		elif direction_vec.x > 0:
			sprite.flip_h = false
		# If moving purely vertically, keep current flip state

func play_animation(anim: AnimationType, loop: bool = true):
	"""Play a specific animation"""
	if current_animation == anim:
		return  # Already playing this animation

	current_animation = anim
	current_frame = 0
	animation_time = 0.0
	animation_loop = loop
	_update_shader_frame()

func play_attack():
	"""Play attack animation (randomly chooses Attack1 or Attack2)"""
	var attack_anim = AnimationType.ATTACK1 if randi() % 2 == 0 else AnimationType.ATTACK2
	play_animation(attack_anim, false)

	# Return to idle after attack completes
	var attack_duration = ANIM_FRAMES[attack_anim] / ANIM_FPS[attack_anim]
	get_tree().create_timer(attack_duration).timeout.connect(func():
		if current_animation == attack_anim:
			play_animation(AnimationType.IDLE, true)
	)

func take_damage():
	"""Play take hit animation"""
	play_animation(AnimationType.TAKE_HIT, false)

	# Return to previous animation after hit
	var hit_duration = ANIM_FRAMES[AnimationType.TAKE_HIT] / ANIM_FPS[AnimationType.TAKE_HIT]
	get_tree().create_timer(hit_duration).timeout.connect(func():
		if current_animation == AnimationType.TAKE_HIT:
			play_animation(AnimationType.IDLE if not is_moving else AnimationType.RUN, true)
	)

func die():
	"""Play death animation"""
	play_animation(AnimationType.DEATH, false)
	current_state = State.DEAD
	is_moving = false

# Signal handlers for animation transitions
func _on_path_complete():
	"""Play idle animation when path completes"""
	play_animation(AnimationType.IDLE, true)

# Override NPC methods to integrate animations
func follow_path(path: Array[Vector2i], tile_map):
	"""Override to trigger run animation"""
	super.follow_path(path, tile_map)

	if path.size() > 0:
		play_animation(AnimationType.RUN, true)
