extends CanvasLayer
class_name HintPanel

## Docked auto-hide panel for contextual hints
## Positions differently based on scene:
## - Title scene: Above the language selector
## - Main scene: Under the CityVote logo in topbar
## Expands on hover or when showing hints
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

	# Position based on which scene we're in
	_position_panel()

func _position_panel() -> void:
	# Wait for scene tree to be fully loaded (multiple frames)
	for i in range(10):
		await get_tree().process_frame

	# Check if we're in the title scene by looking for LanguageSelector
	var language_selector = get_tree().root.get_node_or_null("Title/LanguageSelector")
	if language_selector:
		# We're in title scene - position below language selector
		print("HintPanel: Detected title scene, positioning below language selector")
		_position_above_language_selector(language_selector)
		return

	# Otherwise, position under topbar in main scene
	print("HintPanel: Detected main scene, positioning under topbar")
	_position_under_city_vote()

func _position_above_language_selector(language_selector: Node) -> void:
	# Wait for layout to finalize
	await get_tree().process_frame

	# Get the panel from language selector
	var selector_panel = language_selector.get_node_or_null("Panel")
	if not selector_panel:
		push_warning("HintPanel: Could not find language selector panel")
		return

	# Position below the language selector panel (flush with its bottom border)
	var panel_global_pos = selector_panel.global_position
	var panel_size = selector_panel.size

	# Center horizontally below panel
	panel_container.position = Vector2(
		panel_global_pos.x + panel_size.x / 2 - panel_container.size.x / 2,
		panel_global_pos.y + panel_size.y + 2  # 2px below panel bottom border
	)

	# Match panel width for visual coherence (but slightly narrower)
	panel_container.custom_minimum_size.x = min(panel_size.x * 0.8, 400)

	print("HintPanel: Positioned below language selector at ", panel_container.position)

func _position_under_city_vote() -> void:
	# Use Cache to get Main scene reference (faster than tree search)
	var main_scene = Cache.get_main_scene()
	if not main_scene:
		# Cache not set yet, silently return (we're probably in title scene)
		return

	# Get the topbar from Cache (no expensive node path lookup!)
	var topbar = Cache.get_ui_reference("topbar")
	if not topbar:
		# Topbar not available yet, silently return
		return

	# Wait multiple frames for layout to finalize (topbar needs time to position)
	for i in range(5):
		await get_tree().process_frame

	# Get topbar position and size
	var topbar_global_pos = topbar.global_position
	var topbar_size = topbar.size

	print("HintPanel DEBUG: topbar global_pos = ", topbar_global_pos, ", size = ", topbar_size)

	# Center horizontally with topbar, position vertically flush with topbar's bottom border
	panel_container.position = Vector2(
		topbar_global_pos.x + topbar_size.x / 2 - panel_container.size.x / 2,  # Center horizontally
		topbar_global_pos.y + topbar_size.y + 2  # 2px below topbar bottom border
	)

	print("HintPanel: Positioned under topbar at ", panel_container.position, " (topbar bottom: ", topbar_global_pos.y + topbar_size.y, ")")

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

## Public function to reposition the panel (called by main scene on ready)
func reposition_for_main_scene() -> void:
	print("HintPanel: Repositioning for main scene")
	_position_under_city_vote()
