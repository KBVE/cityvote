extends CanvasLayer
class_name GlobalPointerUI

## Global UI system for drawing attention to specific areas
## Singleton pattern - add once to the scene tree and reuse
##
## USAGE:
## ```gdscript
## # Show pointer at a world position
## GlobalPointer.point_to_world_position(world_pos, "Click here!")
##
## # Show pointer at a screen position
## GlobalPointer.point_to_screen_position(screen_pos, "Important!")
##
## # Show pointer at a node
## GlobalPointer.point_to_node(some_node, "Check this out!")
##
## # Hide pointer
## GlobalPointer.hide_pointer()
## ```

## Emitted when the pointer is clicked
signal pointer_clicked()

## Pointer visual elements
@onready var pointer_container: Control = $PointerContainer
@onready var arrow: Polygon2D = $PointerContainer/Arrow
@onready var pulse_circle: ColorRect = $PointerContainer/PulseCircle
@onready var label: Label = $PointerContainer/Label

## Animation state
var is_visible: bool = false
var target_node: Node = null  # If following a node
var target_world_pos: Vector2 = Vector2.ZERO
var target_screen_pos: Vector2 = Vector2.ZERO
var follow_mode: FollowMode = FollowMode.NONE

enum FollowMode {
	NONE,           # Static position
	SCREEN,         # Screen space position
	WORLD,          # World space position (follows camera)
	NODE            # Follow a node's global position
}

## Visual settings
var arrow_color: Color = Color(1.0, 0.8, 0.2, 1.0)  # Golden/yellow
var pulse_speed: float = 2.0
var pulse_scale_min: float = 0.8
var pulse_scale_max: float = 1.2
var bob_amount: float = 10.0  # Up/down bobbing in pixels
var bob_speed: float = 3.0

## Animation time
var time: float = 0.0

func _ready() -> void:
	# Start hidden
	pointer_container.visible = false
	is_visible = false

	# Set initial arrow color
	if arrow:
		arrow.color = arrow_color

	print("GlobalPointerUI: Ready")

func _process(delta: float) -> void:
	if not is_visible:
		return

	time += delta

	# Update position based on follow mode
	match follow_mode:
		FollowMode.NODE:
			if target_node and is_instance_valid(target_node):
				if target_node is Node2D:
					target_world_pos = target_node.global_position
					_update_pointer_position_from_world(target_world_pos)
				elif target_node is Control:
					target_screen_pos = target_node.global_position
					_update_pointer_position_from_screen(target_screen_pos)
			else:
				# Node is invalid, hide pointer
				hide_pointer()
		FollowMode.WORLD:
			_update_pointer_position_from_world(target_world_pos)
		FollowMode.SCREEN:
			_update_pointer_position_from_screen(target_screen_pos)

	# Animate pulse circle
	if pulse_circle:
		var pulse_scale = lerp(pulse_scale_min, pulse_scale_max, (sin(time * pulse_speed) + 1.0) / 2.0)
		pulse_circle.scale = Vector2(pulse_scale, pulse_scale)
		pulse_circle.modulate.a = lerp(0.3, 0.7, (sin(time * pulse_speed) + 1.0) / 2.0)

	# Animate arrow bobbing
	if arrow:
		var bob_offset = sin(time * bob_speed) * bob_amount
		arrow.position.y = bob_offset

## Show pointer at a world position (follows camera movement)
func point_to_world_position(world_pos: Vector2, text: String = "") -> void:
	target_world_pos = world_pos
	follow_mode = FollowMode.WORLD
	_show_pointer(text)
	_update_pointer_position_from_world(world_pos)

## Show pointer at a screen position (UI space, doesn't follow camera)
func point_to_screen_position(screen_pos: Vector2, text: String = "") -> void:
	target_screen_pos = screen_pos
	follow_mode = FollowMode.SCREEN
	_show_pointer(text)
	_update_pointer_position_from_screen(screen_pos)

## Show pointer at a node (follows the node as it moves)
func point_to_node(node: Node, text: String = "") -> void:
	target_node = node
	follow_mode = FollowMode.NODE
	_show_pointer(text)

## Hide the pointer
func hide_pointer() -> void:
	is_visible = false
	pointer_container.visible = false
	target_node = null
	follow_mode = FollowMode.NONE
	print("GlobalPointerUI: Hidden")

## Internal: Show pointer with optional text
func _show_pointer(text: String) -> void:
	is_visible = true
	pointer_container.visible = true
	time = 0.0

	# Set label text
	if label:
		label.text = text
		label.visible = text != ""

	print("GlobalPointerUI: Showing pointer with text: ", text)

## Internal: Update pointer position from world coordinates
func _update_pointer_position_from_world(world_pos: Vector2) -> void:
	# Convert world position to screen position
	var camera = get_viewport().get_camera_2d()
	if camera:
		var screen_pos = camera.get_screen_center_position() + (world_pos - camera.global_position)
		pointer_container.position = screen_pos
	else:
		# No camera, treat as screen position
		pointer_container.position = world_pos

## Internal: Update pointer position from screen coordinates
func _update_pointer_position_from_screen(screen_pos: Vector2) -> void:
	pointer_container.position = screen_pos

## Change pointer color (useful for different attention levels)
func set_pointer_color(color: Color) -> void:
	arrow_color = color
	if arrow:
		arrow.color = color

## Set pointer text (can update while visible)
func set_pointer_text(text: String) -> void:
	if label:
		label.text = text
		label.visible = text != ""
