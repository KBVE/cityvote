extends NPC
class_name FantasyWarrior

# Fantasy Warrior - ground-based NPC with shader-driven animations
# 27x45 pixel character animated via shader atlas system
# Controls the UV shader to display different animation frames

# Animation types (matches rows in texture atlas)
enum AnimType {
	IDLE = 0,
	RUN = 1,
	JUMP = 2,
	FALL = 3,
	ATTACK1 = 4,
	ATTACK2 = 5,
	ATTACK3 = 6,
	TAKE_HIT = 7,
	DEATH = 8,
}

# Animation frame counts (matches actual atlas - 162x162 frames)
const ANIMATION_FRAME_COUNTS = {
	AnimType.IDLE: 10,       # Idle.png: 10 frames
	AnimType.RUN: 8,         # Run.png: 8 frames
	AnimType.JUMP: 3,        # Jump.png: 3 frames
	AnimType.FALL: 3,        # Fall.png: 3 frames
	AnimType.ATTACK1: 7,     # Attack1.png: 7 frames
	AnimType.ATTACK2: 7,     # Attack2.png: 7 frames
	AnimType.ATTACK3: 8,     # Attack3.png: 8 frames
	AnimType.TAKE_HIT: 3,    # Take hit.png: 3 frames
	AnimType.DEATH: 7,       # Death.png: 7 frames
}

# Animation speeds (frames per second)
const ANIMATION_SPEEDS = {
	AnimType.IDLE: 6.0,      # Slow idle animation
	AnimType.RUN: 10.0,
	AnimType.JUMP: 8.0,
	AnimType.FALL: 6.0,
	AnimType.ATTACK1: 12.0,
	AnimType.ATTACK2: 12.0,
	AnimType.ATTACK3: 12.0,
	AnimType.TAKE_HIT: 10.0,
	AnimType.DEATH: 5.0,     # Slow death animation
}

# Current animation state
var current_animation: int = AnimType.IDLE
var current_frame: float = 0.0  # Float for smooth interpolation
var animation_playing: bool = true
var animation_loop: bool = true

# Shader material reference
var shader_material: ShaderMaterial = null

func _ready():
	super._ready()  # Call parent NPC _ready

	# Setup shader material
	_setup_shader()

	# Start with idle animation
	play_animation(AnimType.IDLE, true)

## Override parent's _update_sprite since we use animation-based sprites, not direction-based
func _update_sprite():
	# Fantasy Warrior uses animation frames, not directional sprites
	# The shader handles frame display via frame_index and animation_row
	pass

func _setup_shader():
	# Load the shader
	var shader = load("res://nodes/npc/fantasy-warrior/fantasy_warrior.gdshader")
	if not shader:
		push_error("FantasyWarrior: Failed to load shader")
		return

	# Create shader material
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader

	# Load the atlas texture
	var atlas_texture = load("res://nodes/npc/fantasy-warrior/fantasy_warrior_atlas.png")
	if not atlas_texture:
		push_error("FantasyWarrior: Failed to load atlas texture")
		return

	# Set shader parameters
	shader_material.set_shader_parameter("atlas_texture", atlas_texture)
	shader_material.set_shader_parameter("frame_size", Vector2(162, 162))
	shader_material.set_shader_parameter("atlas_size", Vector2(1620, 1458))
	shader_material.set_shader_parameter("frames_per_row", 10)  # Max frames in any row
	shader_material.set_shader_parameter("animation_row", 0)
	shader_material.set_shader_parameter("frame_index", 0)

	# Apply to sprite
	if has_node("Sprite2D"):
		var sprite = $Sprite2D

		# Create a simple 162x162 white texture for the sprite
		# The shader will handle drawing the correct atlas frame
		var placeholder = Image.create(162, 162, false, Image.FORMAT_RGBA8)
		placeholder.fill(Color.WHITE)
		var placeholder_texture = ImageTexture.create_from_image(placeholder)

		sprite.texture = placeholder_texture
		sprite.material = shader_material
		sprite.centered = true

		# Scale down the sprite to fit better on the tile map
		# Fantasy Warrior is 27x45 pixels, but our frame is 162x162
		# Scale to approximately 35% to match tile size better
		sprite.scale = Vector2(0.35, 0.35)
	else:
		push_error("FantasyWarrior: No Sprite2D node found")

func _process(delta: float):
	super._process(delta)

	# Update sprite flipping based on movement direction
	_update_sprite_flip()

	# Handle animation state based on movement
	if is_moving and current_animation == AnimType.IDLE:
		play_animation(AnimType.RUN, true)
	elif not is_moving and current_animation == AnimType.RUN:
		play_animation(AnimType.IDLE, true)

	if not animation_playing or not shader_material:
		return

	# Get current animation settings
	var frame_count = ANIMATION_FRAME_COUNTS.get(current_animation, 1)
	var anim_speed = ANIMATION_SPEEDS.get(current_animation, 6.0)

	# Advance frame
	current_frame += anim_speed * delta

	# Handle looping
	if current_frame >= frame_count:
		if animation_loop:
			current_frame = fmod(current_frame, float(frame_count))
		else:
			current_frame = frame_count - 1
			animation_playing = false

	# Update shader parameters
	shader_material.set_shader_parameter("frame_index", int(current_frame))
	shader_material.set_shader_parameter("animation_row", current_animation)
	shader_material.set_shader_parameter("frames_per_row", frame_count)

func _update_sprite_flip():
	# Flip sprite based on movement direction
	if is_moving and sprite:
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
	if current_animation == anim_type and animation_playing:
		return  # Already playing this animation

	current_animation = anim_type
	current_frame = 0.0
	animation_playing = true
	animation_loop = loop

	# Update shader immediately
	if shader_material:
		shader_material.set_shader_parameter("animation_row", anim_type)
		shader_material.set_shader_parameter("frame_index", 0)
		shader_material.set_shader_parameter("frames_per_row", ANIMATION_FRAME_COUNTS.get(anim_type, 1))

## Check if current animation has finished (non-looping animations only)
func is_animation_finished() -> bool:
	return not animation_playing

## Play attack animation
func attack(attack_num: int = 1) -> void:
	var attack_anim = AnimType.ATTACK1
	match attack_num:
		1: attack_anim = AnimType.ATTACK1
		2: attack_anim = AnimType.ATTACK2
		3: attack_anim = AnimType.ATTACK3

	play_animation(attack_anim, false)

## Play hit animation
func take_hit() -> void:
	play_animation(AnimType.TAKE_HIT, false)

## Play death animation
func die() -> void:
	play_animation(AnimType.DEATH, false)
