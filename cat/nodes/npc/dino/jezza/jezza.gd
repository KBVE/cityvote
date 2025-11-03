extends NPC
class_name Jezza

# Jezza the Raptor - ground-based NPC with shader-driven animations
# Controls the UV shader to display different animation frames from a texture atlas

# Animation types (matches rows in texture atlas)
enum AnimType {
	IDLE = 0,
	WALK = 1,
	RUN = 2,
	BITE = 3,
	POUNCE = 4,
	POUNCE_READY = 5,
	POUNCE_END = 6,
	POUNCE_LATCHED = 7,
	POUNCED_ATTACK = 8,
	ROAR = 9,
	SCANNING = 10,
	ON_HIT = 11,
	DEAD = 12,
	JUMP = 13,
	FALLING = 14,
}

# Animation frame counts (matches actual atlas - 128x64 frames)
# NOTE: Idle uses walk (row 0), so it has same frame count
const ANIMATION_FRAME_COUNTS = {
	AnimType.IDLE: 6,           # Using walk as idle (row 0)
	AnimType.WALK: 6,           # raptor-walk: 768px = 6 frames (row 1)
	AnimType.RUN: 6,            # raptor-run: 768px = 6 frames (row 2)
	AnimType.BITE: 10,          # raptor-bite: 1280px = 10 frames (row 3)
	AnimType.POUNCE: 1,         # raptor-pounce: 128px = 1 frame (row 4)
	AnimType.POUNCE_READY: 2,   # raptor-ready-pounce: 256px = 2 frames (row 5)
	AnimType.POUNCE_END: 1,     # raptor-pounce-end: 128px = 1 frame (row 6)
	AnimType.POUNCE_LATCHED: 1, # raptor-pounce-latched: 128px = 1 frame (row 7)
	AnimType.POUNCED_ATTACK: 8, # raptor-pounced-attack: 1024px = 8 frames (row 8)
	AnimType.ROAR: 6,           # raptor-roar: 768px = 6 frames (row 9)
	AnimType.SCANNING: 18,      # raptor-scanning: 2304px = 18 frames (row 10)
	AnimType.ON_HIT: 1,         # raptor-on-hit: 128px = 1 frame (row 11)
	AnimType.DEAD: 6,           # raptor-dead: 768px = 6 frames (row 12)
	AnimType.JUMP: 1,           # raptor-jump: 128px = 1 frame (row 13)
	AnimType.FALLING: 1,        # raptor-falling: 128px = 1 frame (row 14)
}

# Animation speeds (frames per second)
const ANIMATION_SPEEDS = {
	AnimType.IDLE: 2.0,  # Slow idle breathing animation
	AnimType.WALK: 8.0,
	AnimType.RUN: 12.0,
	AnimType.BITE: 10.0,
	AnimType.POUNCE: 15.0,
	AnimType.POUNCE_READY: 6.0,
	AnimType.POUNCE_END: 8.0,
	AnimType.POUNCE_LATCHED: 4.0,
	AnimType.POUNCED_ATTACK: 12.0,
	AnimType.ROAR: 8.0,
	AnimType.SCANNING: 6.0,
	AnimType.ON_HIT: 10.0,
	AnimType.DEAD: 1.0,
	AnimType.JUMP: 10.0,
	AnimType.FALLING: 6.0,
}

# Current animation state
var current_animation: int = AnimType.IDLE
var current_frame: float = 0.0  # Float for smooth interpolation
var animation_playing: bool = true
var animation_loop: bool = true

# Shader material reference
var shader_material: ShaderMaterial = null

func _ready():
	# Configure terrain type for land pathfinding
	terrain_type = TerrainType.LAND

	super._ready()  # Call parent NPC _ready

	# Setup shader material
	_setup_shader()

	# Start with scanning animation (our idle/looking around animation)
	play_animation(AnimType.SCANNING, true)

## Override parent's _update_sprite since we use animation-based sprites, not direction-based
func _update_sprite():
	# Jezza uses animation frames, not directional sprites
	# The shader handles frame display via frame_index and animation_row
	pass

func _setup_shader():
	# Load texture atlas
	var atlas_texture = load("res://nodes/npc/dino/jezza/jezza_atlas.png")
	if not atlas_texture:
		push_error("Jezza: Failed to load texture atlas!")
		return

	# Load shader
	var shader = load("res://nodes/npc/dino/jezza/jezza.gdshader")
	if not shader:
		push_error("Jezza: Failed to load shader!")
		return

	# Create shader material
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader

	# Set atlas parameters (128x64 frames, 18 frames per row)
	shader_material.set_shader_parameter("atlas_texture", atlas_texture)
	shader_material.set_shader_parameter("frame_size", Vector2(128, 64))
	shader_material.set_shader_parameter("atlas_size", Vector2(2304, 960))
	shader_material.set_shader_parameter("frames_per_row", 18)
	shader_material.set_shader_parameter("frame_index", 0)
	shader_material.set_shader_parameter("animation_row", 0)

	# Apply to sprite
	if sprite:
		# Create a simple 128x64 white texture for the sprite
		# The shader will handle drawing the correct atlas frame
		var placeholder = Image.create(128, 64, false, Image.FORMAT_RGBA8)
		placeholder.fill(Color.WHITE)
		var placeholder_texture = ImageTexture.create_from_image(placeholder)

		sprite.texture = placeholder_texture
		sprite.material = shader_material
		sprite.centered = true

## Play an animation
func play_animation(animation: int, loop: bool = true):
	if animation == current_animation and animation_playing:
		return  # Already playing this animation

	current_animation = animation
	current_frame = 0.0
	animation_playing = true
	animation_loop = loop

	# Update shader parameter
	if shader_material:
		shader_material.set_shader_parameter("animation_row", animation)

## Stop current animation
func stop_animation():
	animation_playing = false

## Resume animation
func resume_animation():
	animation_playing = true

## Get current animation
func get_current_animation() -> int:
	return current_animation

## Check if animation is playing
func is_animation_playing() -> bool:
	return animation_playing

func _process(delta):
	super._process(delta)  # Call parent NPC _process for movement

	# Update sprite flipping based on movement direction
	_update_sprite_flip()

	# Update animation frame
	if animation_playing:
		_update_animation(delta)

	# Auto-play animations based on state
	_auto_select_animation()

func _update_animation(delta: float):
	# Get animation properties
	var frame_count = ANIMATION_FRAME_COUNTS.get(current_animation, 1)
	var fps = ANIMATION_SPEEDS.get(current_animation, 8.0)

	# Advance frame
	current_frame += fps * delta

	# Handle looping
	if current_frame >= frame_count:
		if animation_loop:
			current_frame = fmod(current_frame, frame_count)
		else:
			current_frame = frame_count - 1
			animation_playing = false

	# Update shader
	if shader_material:
		var frame_idx = int(current_frame)
		# Clamp frame to valid range
		frame_idx = clamp(frame_idx, 0, frame_count - 1)

		shader_material.set_shader_parameter("frame_index", frame_idx)
		shader_material.set_shader_parameter("animation_row", current_animation)

func _auto_select_animation():
	# Automatically select animation based on NPC state
	if has_state(State.DEAD) or current_animation == AnimType.DEAD:
		if current_animation != AnimType.DEAD:
			play_animation(AnimType.DEAD, false)
	elif has_state(State.INTERACTING):
		# Could be roaring, biting, etc.
		pass  # Manual control
	elif is_moving:
		# Use run when moving
		if current_animation != AnimType.RUN and current_animation != AnimType.WALK:
			play_animation(AnimType.RUN, true)
	elif has_state(State.IDLE):
		# Scanning animation when idle (looking around)
		if current_animation != AnimType.SCANNING:
			play_animation(AnimType.SCANNING, true)

## Trigger specific animations (for combat, interactions, etc.)
func roar():
	play_animation(AnimType.ROAR, false)

func bite():
	play_animation(AnimType.BITE, false)

func pounce():
	play_animation(AnimType.POUNCE, false)

func scan():
	play_animation(AnimType.SCANNING, true)

func take_hit():
	play_animation(AnimType.ON_HIT, false)
	# After hit animation, return to previous state
	await get_tree().create_timer(0.3).timeout
	_auto_select_animation()

func die():
	add_state(State.DEAD)
	play_animation(AnimType.DEAD, false)

func _update_sprite_flip():
	# Flip sprite based on movement direction
	if is_moving:
		# Use the movement vector from parent class
		var movement_vec = move_target_pos - move_start_pos
		if movement_vec.length_squared() > 0.01:
			# Flip sprite if moving left (negative x direction)
			if movement_vec.x < 0:
				sprite.scale.x = -abs(sprite.scale.x)  # Face left
			else:
				sprite.scale.x = abs(sprite.scale.x)   # Face right
