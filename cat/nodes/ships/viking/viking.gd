extends Ship

# Viking ship - extends the Ship base class

func _ready():
	# Set pool name for proper cleanup
	pool_name = "viking"

	# Configure attack speed (slower = more visible projectiles)
	attack_interval = 2.5  # Attack every 2.5 seconds
	# Use Sprite2D region mode with wave shader
	# Load the atlas image
	var atlas_image = preload("res://nodes/ships/viking/viking_atlas.png")
	sprite.texture = atlas_image

	# Enable region mode and set initial region (direction 0)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 64, 64)  # Start with first cell

	# Create shader material for wave motion
	var wave_shader = preload("res://nodes/ships/viking/viking_wave.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = wave_shader

	# Set wave parameters
	shader_material.set_shader_parameter("wave_speed", 0.6)
	shader_material.set_shader_parameter("wave_amplitude", 1.5)
	shader_material.set_shader_parameter("sway_amplitude", 1.0)
	shader_material.set_shader_parameter("wave_frequency", 1.2)

	sprite.material = shader_material

	# Scale down the sprite to fit better on hex tile (64x64 sprite -> ~38x38 visual size)
	sprite.scale = Vector2(0.6, 0.6)

	# Still load sprites array for compatibility (though not used for rendering)
	ship_sprites = [
		preload("res://nodes/ships/viking/ship1.png"),   # 0 - North
		preload("res://nodes/ships/viking/ship2.png"),   # 1 - NNW
		preload("res://nodes/ships/viking/ship3.png"),   # 2 - NW
		preload("res://nodes/ships/viking/ship4.png"),   # 3 - WNW
		preload("res://nodes/ships/viking/ship5.png"),   # 4 - West
		preload("res://nodes/ships/viking/ship6.png"),   # 5 - WSW
		preload("res://nodes/ships/viking/ship7.png"),   # 6 - SW
		preload("res://nodes/ships/viking/ship8.png"),   # 7 - SSW
		preload("res://nodes/ships/viking/ship9.png"),   # 8 - South
		preload("res://nodes/ships/viking/ship10.png"),  # 9 - SSE
		preload("res://nodes/ships/viking/ship11.png"),  # 10 - SE
		preload("res://nodes/ships/viking/ship12.png"),  # 11 - ESE
		preload("res://nodes/ships/viking/ship13.png"),  # 12 - East
		preload("res://nodes/ships/viking/ship14.png"),  # 13 - ENE
		preload("res://nodes/ships/viking/ship15.png"),  # 14 - NE
		preload("res://nodes/ships/viking/ship16.png")   # 15 - NNE
	]

	super._ready()

func _process(delta):
	# Call parent's _process to handle movement and rotation
	super._process(delta)

	# Example: rotate to face mouse (for testing)
	# Uncomment to test rotation:
	# var mouse_pos = get_global_mouse_position()
	# var direction_vec = mouse_pos - global_position
	# set_direction(vector_to_direction(direction_vec))
