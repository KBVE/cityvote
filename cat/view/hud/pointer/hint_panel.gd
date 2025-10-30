extends CanvasLayer
class_name HintPanel

## Docked auto-hide panel for contextual hints
## Sits under the CityVote logo in topbar and expands on hover or when showing hints
##
## USAGE:
## ```gdscript
## # Show hint in the panel
## GlobalHint.show_hint("Double click or tap to place")
##
## # Hide hint (auto-hides after delay)
## GlobalHint.hide_hint()
##
## # Show hint with custom duration
## GlobalHint.show_hint_timed("Tip: Use combos for bonuses!", 5.0)
## ```

## Signals
signal hint_panel_opened()
signal hint_panel_closed()

## UI elements
@onready var panel_container: PanelContainer = $PanelContainer
@onready var hint_label: Label = $PanelContainer/MarginContainer/HintLabel

## Animation state
var is_expanded: bool = false
var is_mouse_over: bool = false
var target_height: float = 0.0
var collapsed_height: float = 4.0  # Thin peek bar
var expanded_height: float = 60.0  # Full panel height

## Auto-hide settings
var auto_hide_delay: float = 3.0  # Seconds before auto-hiding
var auto_hide_timer: float = 0.0
var has_active_hint: bool = false

## Animation settings
var expand_speed: float = 12.0

func _ready() -> void:
	# Start collapsed
	panel_container.custom_minimum_size.y = collapsed_height
	is_expanded = false
	has_active_hint = false

	# Connect mouse enter/exit on the panel container
	panel_container.mouse_entered.connect(_on_mouse_entered)
	panel_container.mouse_exited.connect(_on_mouse_exited)

	# Position under CityVote button in topbar
	_position_under_city_vote()

	print("HintPanel: Ready - Docked under CityVote logo")

func _position_under_city_vote() -> void:
	# Wait one frame for UI to initialize
	await get_tree().process_frame

	# Find the Main scene and topbar
	var main_scene = get_tree().root.get_node_or_null("Main")
	if not main_scene:
		push_warning("HintPanel: Could not find Main scene")
		return

	# Get the topbar directly from Main scene
	var topbar = main_scene.get_node_or_null("TopbarUIUX")
	if not topbar:
		push_warning("HintPanel: Could not find TopbarUIUX in Main scene")
		return

	# Get the CityVote button
	var city_vote_button = topbar.get_node_or_null("MarginContainer/HBoxContainer/CenterSection/CityVoteButton")
	if not city_vote_button:
		push_warning("HintPanel: Could not find CityVote button")
		return

	# Position directly under the CityVote button
	var button_global_pos = city_vote_button.global_position
	var button_size = city_vote_button.size

	# Center horizontally under button, position at bottom edge
	panel_container.position = Vector2(
		button_global_pos.x + button_size.x / 2 - panel_container.size.x / 2,
		button_global_pos.y + button_size.y
	)

	# Match button width for visual coherence
	panel_container.custom_minimum_size.x = button_size.x

	print("HintPanel: Positioned under CityVote button at ", panel_container.position)

func _process(delta: float) -> void:
	# Determine if panel should be expanded
	var should_expand = is_mouse_over or has_active_hint

	if should_expand and not is_expanded:
		_expand()
	elif not should_expand and is_expanded:
		_collapse()

	# Animate height smoothly
	var current_height = panel_container.custom_minimum_size.y
	panel_container.custom_minimum_size.y = lerp(current_height, target_height, expand_speed * delta)

	# Auto-hide timer (only when expanded with active hint)
	if has_active_hint and is_expanded and not is_mouse_over:
		auto_hide_timer += delta
		if auto_hide_timer >= auto_hide_delay:
			hide_hint()

func _on_mouse_entered() -> void:
	is_mouse_over = true

func _on_mouse_exited() -> void:
	is_mouse_over = false

func _expand() -> void:
	if is_expanded:
		return

	is_expanded = true
	target_height = expanded_height
	hint_label.visible = true
	hint_panel_opened.emit()

func _collapse() -> void:
	if not is_expanded:
		return

	is_expanded = false
	target_height = collapsed_height
	# Hide label when collapsed
	await get_tree().create_timer(0.2).timeout  # Wait for animation
	if not is_expanded:  # Check again in case it re-expanded
		hint_label.visible = false
	hint_panel_closed.emit()

## Show hint in the panel
func show_hint(text: String) -> void:
	has_active_hint = true
	auto_hide_timer = 0.0

	# Set translated text
	if hint_label:
		hint_label.text = text

	print("HintPanel: Showing hint - ", text)

## Show hint with custom auto-hide duration
func show_hint_timed(text: String, duration: float) -> void:
	auto_hide_delay = duration
	show_hint(text)

## Hide the hint
func hide_hint() -> void:
	has_active_hint = false
	auto_hide_timer = 0.0
	# Panel will collapse automatically in _process

## Update hint text while visible
func update_hint_text(text: String) -> void:
	if hint_label:
		hint_label.text = text
	# Reset auto-hide timer when text updates
	auto_hide_timer = 0.0

## Force expand (for testing or manual control)
func force_expand() -> void:
	has_active_hint = true

## Force collapse
func force_collapse() -> void:
	has_active_hint = false
	is_mouse_over = false
