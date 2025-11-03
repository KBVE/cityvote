extends CanvasLayer
class_name HintUI

## Reusable hint/tip UI system for contextual help messages
## Shows helpful hints at cursor position or specific screen locations
##
## USAGE:
## ```gdscript
## # Show hint at cursor
## GlobalHint.show_hint_at_cursor("Double click to place")
##
## # Show hint at screen position
## GlobalHint.show_hint_at_position(Vector2(640, 360), "Press E to interact")
##
## # Hide hint
## GlobalHint.hide_hint()
## ```

## UI elements
@onready var hint_container: PanelContainer = $HintContainer
@onready var hint_label: Label = $HintContainer/MarginContainer/Label

## State
var is_visible: bool = false
var follow_cursor: bool = false
var fixed_position: Vector2 = Vector2.ZERO
var cursor_offset: Vector2 = Vector2(20, -40)  # Offset from cursor (right and up)

## Visual settings
var fade_speed: float = 10.0
var target_alpha: float = 0.0

func _ready() -> void:
	# Start hidden
	hint_container.visible = false
	hint_container.modulate.a = 0.0
	is_visible = false

func _process(delta: float) -> void:
	if not is_visible:
		return

	# Update position if following cursor
	if follow_cursor:
		var mouse_pos = get_viewport().get_mouse_position()
		hint_container.position = mouse_pos + cursor_offset

	# Fade in/out animation
	hint_container.modulate.a = lerp(hint_container.modulate.a, target_alpha, fade_speed * delta)

## Show hint at cursor position (follows mouse)
func show_hint_at_cursor(text: String) -> void:
	_show_hint(text, true, Vector2.ZERO)

## Show hint at cursor with custom offset
func show_hint_at_cursor_with_offset(text: String, offset: Vector2) -> void:
	cursor_offset = offset
	_show_hint(text, true, Vector2.ZERO)

## Show hint at fixed screen position
func show_hint_at_position(pos: Vector2, text: String) -> void:
	_show_hint(text, false, pos)

## Hide the hint
func hide_hint() -> void:
	is_visible = false
	target_alpha = 0.0
	# Wait for fade out, then hide completely
	await get_tree().create_timer(0.2).timeout
	if not is_visible:  # Check again in case it was shown during fade
		hint_container.visible = false

## Internal: Show hint with configuration
func _show_hint(text: String, follow_mouse: bool, pos: Vector2) -> void:
	is_visible = true
	follow_cursor = follow_mouse
	fixed_position = pos

	# Set text (with i18n support)
	if hint_label:
		hint_label.text = text

	# Position immediately
	if follow_cursor:
		var mouse_pos = get_viewport().get_mouse_position()
		hint_container.position = mouse_pos + cursor_offset
	else:
		hint_container.position = fixed_position

	# Make visible and start fade in
	hint_container.visible = true
	target_alpha = 1.0

## Set custom cursor offset
func set_cursor_offset(offset: Vector2) -> void:
	cursor_offset = offset

## Update hint text while visible
func update_hint_text(text: String) -> void:
	if hint_label:
		hint_label.text = text
