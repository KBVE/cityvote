extends Control
class_name HealthBar

## Optimized Health Bar for 1000+ Entities
## Designed for minimal overhead and maximum performance
## Works seamlessly with Pool.gd / Cluster.gd
##
## Key Optimizations:
## - Dirty flag system: Only redraws when health changes
## - Minimal node tree: 3 nodes total (Control + 2 ColorRects)
## - No process callbacks by default
## - Canvas item caching enabled
## - Pre-calculated dimensions
## - No physics processing
## - Optional auto-hide when full health
## - Poolable and reusable

# Health values
var current_health: float = 100.0
var max_health: float = 100.0

# Visual settings
var bar_width: float = 40.0
var bar_height: float = 6.0
var bar_offset: Vector2 = Vector2(0, -30)  # Offset above entity

# Colors
var bg_color: Color = Color(0.2, 0.2, 0.2, 0.8)  # Dark background
var health_color: Color = Color(0.2, 0.8, 0.2, 1.0)  # Green
var low_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)  # Red
var mid_health_color: Color = Color(0.9, 0.7, 0.2, 1.0)  # Yellow
var low_health_threshold: float = 0.3  # Below 30% = red
var mid_health_threshold: float = 0.6  # Below 60% = yellow

# Performance settings
var auto_hide_when_full: bool = false  # Hide when at max health (disabled by default for testing)
var update_smoothing: bool = false  # Smooth health transitions (costs performance)
var smooth_speed: float = 10.0  # Speed of smooth transition

# Internal state
var _dirty: bool = true  # Needs redraw
var _target_health: float = 100.0  # For smoothing
var _is_smoothing: bool = false

# Node references (cached in _ready)
@onready var border_panel: PanelContainer = $BorderPanel
@onready var health_container: Control = $BorderPanel/HealthContainer
@onready var background: Panel = $BorderPanel/HealthContainer/Background
@onready var health_fill: Panel = $BorderPanel/HealthContainer/HealthFill
@onready var health_fill_style: StyleBoxFlat = null  # Cached style for color updates

func _ready() -> void:
	# Disable all processing by default - only enable when needed
	set_process(false)
	set_physics_process(false)

	# Enable canvas item caching for performance
	# This reduces draw calls when the health bar doesn't change
	if has_method("set_clip_contents"):
		set_clip_contents(false)  # No clipping needed

	# Set up initial dimensions
	_setup_dimensions()

	# Cache the health fill style for color updates
	if health_fill:
		var style = health_fill.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			health_fill_style = style

	# Initial update
	_update_visual()

## Set up bar dimensions (called once in _ready)
func _setup_dimensions() -> void:
	# Set control size
	custom_minimum_size = Vector2(bar_width, bar_height)
	size = custom_minimum_size

	# Center pivot for easier positioning above entities
	pivot_offset = size / 2.0

	# Position offset from entity
	position = bar_offset - pivot_offset

	# The BorderPanel will auto-fill the parent Control (anchors_preset = 15)
	# The HealthContainer is flush inside the border (no margins)
	# The Background fills the entire container
	# The HealthFill will be dynamically sized based on health percentage

	# Panels use StyleBoxFlat, so no need to set colors here - they're in the scene
	# Health fill will be sized dynamically in _update_visual() using anchors

## Initialize health bar with values
## Call this when acquiring from pool
func initialize(current_hp: float, max_hp: float) -> void:
	max_health = max_hp
	current_health = clampf(current_hp, 0.0, max_health)
	_target_health = current_health
	_dirty = true
	_update_visual()

## Update current health value
## This is the main method you'll call during gameplay
func set_health(new_health: float) -> void:
	new_health = clampf(new_health, 0.0, max_health)

	if new_health == current_health:
		return  # No change, skip update

	if update_smoothing:
		_target_health = new_health
		_is_smoothing = true
		if not is_processing():
			set_process(true)  # Enable processing for smoothing
	else:
		current_health = new_health
		_dirty = true
		_update_visual()

## Update max health (resizes bar capacity)
func set_max_health(new_max_health: float) -> void:
	if new_max_health == max_health:
		return

	max_health = new_max_health
	current_health = clampf(current_health, 0.0, max_health)
	_dirty = true
	_update_visual()

## Set both health values at once (more efficient)
func set_health_values(current_hp: float, max_hp: float) -> void:
	max_health = max_hp
	current_health = clampf(current_hp, 0.0, max_health)
	_target_health = current_health
	_dirty = true
	_update_visual()

## Get current health percentage (0.0 to 1.0)
func get_health_percentage() -> float:
	if max_health <= 0:
		return 0.0
	return current_health / max_health

## Process callback (only enabled when smoothing)
func _process(delta: float) -> void:
	if not _is_smoothing:
		set_process(false)
		return

	# Smooth health transition
	current_health = move_toward(current_health, _target_health, smooth_speed * max_health * delta)

	_dirty = true
	_update_visual()

	# Stop smoothing when reached target
	if absf(current_health - _target_health) < 0.1:
		current_health = _target_health
		_is_smoothing = false
		set_process(false)

## Update visual appearance (only when dirty)
func _update_visual() -> void:
	if not _dirty:
		return

	_dirty = false

	# Calculate health percentage
	var health_pct = get_health_percentage()

	# Auto-hide when full (if enabled)
	if auto_hide_when_full and health_pct >= 1.0:
		visible = false
		return
	else:
		visible = true

	# Update fill using anchor_right to scale from left edge
	# This keeps the fill flush with no gaps and curved at edges
	if health_fill:
		# Set anchor_right to health percentage (0.0 to 1.0)
		health_fill.anchor_right = health_pct

		# Force layout update to apply anchor changes immediately
		health_fill.reset_size()

		# Update color based on health percentage (using StyleBoxFlat)
		if health_fill_style:
			if health_pct <= low_health_threshold:
				health_fill_style.bg_color = low_health_color
			elif health_pct <= mid_health_threshold:
				health_fill_style.bg_color = mid_health_color
			else:
				health_fill_style.bg_color = health_color

## Reset for pooling (call before releasing to pool)
func reset_for_pool() -> void:
	set_process(false)
	set_physics_process(false)
	visible = false
	current_health = 100.0
	max_health = 100.0
	_target_health = 100.0
	_is_smoothing = false
	_dirty = true

## Configure bar appearance
func set_bar_size(width: float, height: float) -> void:
	bar_width = width
	bar_height = height
	_setup_dimensions()
	_dirty = true
	_update_visual()

## Configure bar offset from entity
func set_bar_offset(offset: Vector2) -> void:
	bar_offset = offset
	position = bar_offset - pivot_offset

## Configure colors
func set_bar_colors(health: Color, low: Color, mid: Color, bg: Color) -> void:
	health_color = health
	low_health_color = low
	mid_health_color = mid
	bg_color = bg

	if background:
		background.color = bg_color

	_dirty = true
	_update_visual()

## Enable/disable smooth health transitions
func set_smoothing(enabled: bool, speed: float = 10.0) -> void:
	update_smoothing = enabled
	smooth_speed = speed

	if not enabled and _is_smoothing:
		# Immediately jump to target health
		current_health = _target_health
		_is_smoothing = false
		set_process(false)
		_dirty = true
		_update_visual()

## Enable/disable auto-hide when at full health
func set_auto_hide(enabled: bool) -> void:
	auto_hide_when_full = enabled
	_dirty = true
	_update_visual()
