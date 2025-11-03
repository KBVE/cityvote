extends NPC
class_name King

# King - ground-based NPC with shader-driven animations
# 160x111 pixel character animated via shader atlas system
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

# Animation frame counts (from artist specs)
const ANIMATION_FRAME_COUNTS = {
	AnimType.IDLE: 8,       # Idle.png: 8 frames
	AnimType.RUN: 8,        # Run.png: 8 frames
	AnimType.JUMP: 2,       # Jump.png: 2 frames
	AnimType.FALL: 2,       # Fall.png: 2 frames
	AnimType.ATTACK1: 4,    # Attack1.png: 4 frames
	AnimType.ATTACK2: 4,    # Attack2.png: 4 frames
	AnimType.ATTACK3: 4,    # Attack3.png: 4 frames
	AnimType.TAKE_HIT: 4,   # Take Hit.png: 4 frames
	AnimType.DEATH: 6,      # Death.png: 6 frames
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
	# Configure terrain type for land pathfinding
	terrain_type = TerrainType.LAND
	print("King._ready(): Setting terrain_type to LAND (%d), class=%s" % [terrain_type, get_class()])

	super._ready()  # Call parent NPC _ready

	# Setup shader material
	_setup_shader()

	# Start with idle animation
	play_animation(AnimType.IDLE, true)

	print("King._ready(): COMPLETE - terrain_type = %d" % terrain_type)

## Override parent's _update_sprite since we use animation-based sprites, not direction-based
func _update_sprite():
	# King uses animation frames, not directional sprites
	# The shader handles frame display via frame_index and animation_row
	pass

func _setup_shader():
	# Load the shader
	var shader = load("res://nodes/npc/king/king.gdshader")
	if not shader:
		push_error("King: Failed to load shader")
		return

	# Create shader material
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader

	# Load the atlas texture
	var atlas_texture = load("res://nodes/npc/king/king_atlas.png")
	if not atlas_texture:
		push_error("King: Failed to load atlas texture")
		return

	# Set shader parameters
	# Atlas: 1280x999, Frame: 160x111 (1280/8 = 160 per frame)
	shader_material.set_shader_parameter("atlas_texture", atlas_texture)
	shader_material.set_shader_parameter("frame_size", Vector2(160, 111))
	shader_material.set_shader_parameter("atlas_size", Vector2(1280, 999))
	shader_material.set_shader_parameter("frames_per_row", 8)  # Max frames in Idle/Run rows
	shader_material.set_shader_parameter("animation_row", 0)
	shader_material.set_shader_parameter("frame_index", 0)

	# Apply to sprite
	if has_node("Sprite2D"):
		var sprite = $Sprite2D

		# Create a simple 160x111 white texture for the sprite
		var img = Image.create(160, 111, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		var tex = ImageTexture.create_from_image(img)

		sprite.texture = tex
		sprite.material = shader_material
		sprite.centered = true

		# Scale down the sprite to fit better on the tile map
		# King is 160x111 pixels, scale to approximately 0.35 to match Fantasy Warrior size
		sprite.scale = Vector2(0.35, 0.35)

func _process(delta):
	super._process(delta)

	# Update sprite flipping based on movement direction
	_update_sprite_flip()

	# Handle animation state based on movement
	if is_moving and current_animation == AnimType.IDLE:
		play_animation(AnimType.RUN, true)
	elif not is_moving and current_animation == AnimType.RUN:
		play_animation(AnimType.IDLE, true)

	# Update animation frame
	if animation_playing:
		_update_animation(delta)

func _update_animation(delta: float):
	if not shader_material:
		return

	var frame_count = ANIMATION_FRAME_COUNTS.get(current_animation, 1)
	var speed = ANIMATION_SPEEDS.get(current_animation, 10.0)

	# Advance frame
	current_frame += speed * delta

	# Handle looping or stop
	if current_frame >= frame_count:
		if animation_loop:
			current_frame = fmod(current_frame, frame_count)
		else:
			current_frame = frame_count - 1
			animation_playing = false

	# Update shader parameters
	var frame_int = int(current_frame)
	shader_material.set_shader_parameter("animation_row", current_animation)
	shader_material.set_shader_parameter("frame_index", frame_int)

## Play an animation
func play_animation(anim_type: int, loop: bool = true):
	if anim_type == current_animation and animation_playing:
		return  # Already playing this animation

	current_animation = anim_type
	current_frame = 0.0
	animation_playing = true
	animation_loop = loop

## Get current animation type
func get_current_animation() -> int:
	return current_animation

## Check if animation is finished
func is_animation_finished() -> bool:
	return not animation_playing

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
