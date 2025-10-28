extends Node2D
class_name WaypointMarker

## Visual marker for a single waypoint in a ship's path
## Shows a dot at the waypoint location with optional animation

@onready var sprite: Sprite2D = $Sprite2D

var waypoint_index: int = 0  # Position in the path (0 = start)
var is_reached: bool = false
var pending_color: Color = Color(0.2, 0.8, 1.0, 0.8)  # Default cyan

func _ready() -> void:
	# Apply pending color
	if sprite:
		sprite.modulate = pending_color

	# Simple pulse animation
	_start_pulse_animation()

func _start_pulse_animation() -> void:
	if not sprite:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(sprite, "scale", Vector2(1.3, 1.3), 0.5).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.5).set_ease(Tween.EASE_IN_OUT)

func mark_reached() -> void:
	if not sprite:
		return

	is_reached = true

	# Fade out animation
	var tween = create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)

func set_color(color: Color) -> void:
	pending_color = color
	if sprite:
		sprite.modulate = color
