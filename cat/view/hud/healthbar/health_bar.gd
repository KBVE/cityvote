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

# Energy values
var current_energy: float = 100.0
var max_energy: float = 100.0
var show_energy: bool = true  # Whether to display energy bar

# Visual settings
var bar_width: float = 40.0
var bar_height: float = 6.0
var bar_spacing: float = 2.0  # Space between health and energy bars
var bar_offset: Vector2 = Vector2(0, -30)  # Offset above entity

# Colors
var bg_color: Color = Color(0.2, 0.2, 0.2, 0.8)  # Dark background
var health_color: Color = Color(0.2, 0.8, 0.2, 1.0)  # Green
var low_health_color: Color = Color(0.9, 0.2, 0.2, 1.0)  # Red
var mid_health_color: Color = Color(0.9, 0.7, 0.2, 1.0)  # Yellow
var energy_color: Color = Color(0.2, 0.6, 0.9, 1.0)  # Blue
var low_energy_color: Color = Color(0.5, 0.3, 0.8, 1.0)  # Purple
var low_health_threshold: float = 0.3  # Below 30% = red
var mid_health_threshold: float = 0.6  # Below 60% = yellow
var low_energy_threshold: float = 0.3  # Below 30% = purple

# Performance settings
var auto_hide_when_full: bool = false  # Hide when at max health (disabled by default for testing)
var update_smoothing: bool = false  # Smooth health transitions (costs performance)
var smooth_speed: float = 10.0  # Speed of smooth transition

# Internal state
var _dirty: bool = true  # Needs redraw
var _target_health: float = 100.0  # For smoothing
var _is_smoothing: bool = false

# Combined atlas (cached globally across all health bars)
static var _combined_atlas: Texture2D = null

# Node references (cached in _ready)
@onready var border_panel: PanelContainer = $BorderPanel
@onready var health_container: Control = $BorderPanel/HealthContainer
@onready var background: Panel = $BorderPanel/HealthContainer/Background
@onready var health_fill: Panel = $BorderPanel/HealthContainer/HealthFill
@onready var health_fill_style: StyleBoxFlat = null  # Cached style for color updates
@onready var flag_icon: TextureRect = $FlagIcon

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

	# CRITICAL: Duplicate the health fill style to avoid sharing between instances
	# Without this, all pooled healthbars will share the same StyleBoxFlat resource
	# and changing one healthbar's color will affect ALL healthbars!
	if health_fill:
		var style = health_fill.get_theme_stylebox("panel")
		if style and style is StyleBoxFlat:
			# Duplicate the style so each healthbar has its own instance
			health_fill_style = style.duplicate() as StyleBoxFlat
			health_fill.add_theme_stylebox_override("panel", health_fill_style)

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
func initialize(current_hp: float, max_hp: float, current_ep: float = 100.0, max_ep: float = 100.0) -> void:
	max_health = max_hp
	current_health = clampf(current_hp, 0.0, max_health)
	max_energy = max_ep
	current_energy = clampf(current_ep, 0.0, max_energy)
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
	var old_health = current_health
	max_health = max_hp
	current_health = clampf(current_hp, 0.0, max_health)
	_target_health = current_health

	# Show floating number if health changed
	var health_diff = current_health - old_health
	if absf(health_diff) > 0.1:  # Ignore tiny changes
		_show_floating_number(health_diff)

	_dirty = true
	_update_visual()

## Update current energy value
func set_energy(new_energy: float) -> void:
	new_energy = clampf(new_energy, 0.0, max_energy)

	if new_energy == current_energy:
		return  # No change, skip update

	current_energy = new_energy
	_dirty = true
	_update_visual()

## Update max energy (resizes bar capacity)
func set_max_energy(new_max_energy: float) -> void:
	if new_max_energy == max_energy:
		return

	max_energy = new_max_energy
	current_energy = clampf(current_energy, 0.0, max_energy)
	_dirty = true
	_update_visual()

## Set both energy values at once (more efficient)
func set_energy_values(current_ep: float, max_ep: float) -> void:
	max_energy = max_ep
	current_energy = clampf(current_ep, 0.0, max_energy)
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
		# Disable grow mode to allow anchor changes to work properly
		health_fill.grow_horizontal = Control.GROW_DIRECTION_BEGIN

		# Set anchor_right to health percentage (0.0 to 1.0)
		health_fill.anchor_right = health_pct

		# Keep anchors locked to left edge
		health_fill.anchor_left = 0.0

		# Update offsets to match anchors (required for anchor changes to take effect)
		health_fill.offset_left = 0.0
		health_fill.offset_right = 0.0

		# Force layout update to apply anchor changes immediately
		health_fill.queue_redraw()

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
	# Reset flag
	if flag_icon:
		flag_icon.texture = null
		flag_icon.visible = false

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

## Show floating damage/healing number
func _show_floating_number(amount: float) -> void:
	# Create label
	var label = Label.new()

	# Format text with sign
	if amount > 0:
		label.text = "+%d" % int(amount)
		label.modulate = Color(0.2, 1.0, 0.2)  # Bright green for healing
	else:
		label.text = "%d" % int(amount)  # Already has minus sign
		label.modulate = Color(1.0, 0.2, 0.2)  # Bright red for damage

	# Style the label
	label.add_theme_font_size_override("font_size", 14)
	# Add outline for better visibility
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)

	# Add to health bar (will float above it)
	add_child(label)
	label.position = Vector2(-10, -15)  # Slightly above the bar

	# Animate: move up and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30, 1.2)
	tween.tween_property(label, "modulate:a", 0.0, 1.2)
	tween.finished.connect(func(): label.queue_free())

## Set the flag icon for this health bar
## flag_name: Name of the flag (e.g., "bavaria", "british", "china")
## If empty or null, hides the flag
func set_flag(flag_name: String) -> void:
	if not flag_icon:
		push_warning("HealthBar: flag_icon node not found!")
		return

	# Hide flag if no name provided
	if flag_name.is_empty():
		flag_icon.visible = false
		flag_icon.texture = null
		return

	# Load combined atlas on first use (cached globally)
	if _combined_atlas == null:
		_combined_atlas = load(I18n.COMBINED_ATLAS_PATH)
		if not _combined_atlas:
			push_error("HealthBar: Failed to load combined atlas from %s" % I18n.COMBINED_ATLAS_PATH)
			return

	# Get flag frame from I18n system
	var flag_frame = I18n.get_flag_frame(flag_name)

	# Create AtlasTexture
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = _combined_atlas
	atlas_texture.region = flag_frame

	# Apply texture to flag icon
	flag_icon.texture = atlas_texture
	flag_icon.visible = true
	flag_icon.modulate = Color.WHITE  # Ensure it's not transparent
