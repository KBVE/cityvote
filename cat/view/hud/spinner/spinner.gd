extends ColorRect

# Universal spinner component
# Can be used anywhere in the game for loading indicators

@export var rotation_speed: float = 5.0  # Radians per second
@export var auto_start: bool = true
@export var spinner_size: Vector2 = Vector2(16, 16)
@export var spinner_color: Color = Color(0.9, 0.7, 0.3, 1.0)  # Golden color

var is_spinning: bool = false
var spinner_rotation: float = 0.0

func _ready() -> void:
	# Set size
	custom_minimum_size = spinner_size
	size = spinner_size

	# Set color
	color = spinner_color

	# Set pivot to center for rotation
	pivot_offset = spinner_size / 2.0

	# Auto-start if enabled
	if auto_start:
		start()

func _process(delta: float) -> void:
	if is_spinning:
		spinner_rotation += delta * rotation_speed
		rotation = spinner_rotation

## Start spinning
func start() -> void:
	is_spinning = true
	visible = true
	set_process(true)

## Stop spinning
func stop() -> void:
	is_spinning = false
	set_process(false)

## Hide and stop spinning
func hide_spinner() -> void:
	stop()
	visible = false

## Show and start spinning
func show_spinner() -> void:
	visible = true
	start()
