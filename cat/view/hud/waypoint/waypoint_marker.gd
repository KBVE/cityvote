extends Node2D
class_name WaypointMarker

## Visual marker for a single waypoint in a ship's path
## Shows a dot at the waypoint location with optional animation

@onready var sprite: Sprite2D = $Sprite2D

var waypoint_index: int = 0  # Position in the path (0 = start)
var is_reached: bool = false
var pending_color: Color = Color(0.2, 0.8, 1.0, 0.8)  # Default cyan
var entity_ulid: PackedByteArray = PackedByteArray()  # ULID of the entity this waypoint belongs to
var entity_name: String = ""  # Name of the entity for display

func _ready() -> void:
	# Apply pending color
	if sprite:
		sprite.modulate = pending_color

	# Setup click detection
	_setup_click_area()

	# Simple pulse animation
	_start_pulse_animation()

func _setup_click_area() -> void:
	# Create Area2D for click detection
	var area = Area2D.new()
	area.name = "ClickArea"
	area.input_pickable = true  # Enable input detection
	area.monitorable = false  # Don't need monitoring
	area.monitoring = false  # Don't monitor other areas
	add_child(area)

	# Create collision shape (circle around the waypoint)
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 16.0  # Generous click area
	collision.shape = shape
	area.add_child(collision)

	# Connect input event
	area.input_event.connect(_on_area_input_event)

func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Handle right-click on waypoint to open entity stats
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not entity_ulid.is_empty():
				# Open stats panel using ULID
				var stats_panel = get_node_or_null("/root/Main/EntityStatsPanel")
				if stats_panel and stats_panel.has_method("show_entity_stats_by_ulid"):
					stats_panel.show_entity_stats_by_ulid(entity_ulid, entity_name)
					get_viewport().set_input_as_handled()

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
