extends PanelContainer
class_name EntityStatsPanel

## Entity Stats Panel (Floating Window)
## Displays detailed stats for a selected entity (ship, NPC, building)
## Fully agnostic - works with ULID only, no entity type dependencies
## Closeable with ESC key or X button

# Currently displayed entity
var current_entity_ulid: PackedByteArray = PackedByteArray()
var current_entity_node: Node = null  # Optional reference for future use

# Preview management
var preview_instance: Node2D = null
var preview_pool_key: String = ""

# UI references
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderBar/CloseButton
@onready var entity_name_label: Label = $MarginContainer/VBoxContainer/HeaderBar/EntityNameLabel
@onready var preview_container: CenterContainer = $MarginContainer/VBoxContainer/EntityPreviewContainer
@onready var stats_container: VBoxContainer = $MarginContainer/VBoxContainer/StatsContainer

# Cached stat label references for reuse (memory optimization)
var stat_labels: Dictionary = {}  # stat_name -> {name_label, value_label}

func _ready() -> void:
	# Start hidden
	visible = false

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Connect to StatsManager signals for live updates
	if StatsManager:
		StatsManager.stat_changed.connect(_on_stat_changed)
		StatsManager.entity_died.connect(_on_entity_died)

func _input(event: InputEvent) -> void:
	# Close on ESC key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and visible:
			close_panel()
			get_viewport().set_input_as_handled()

## Show stats for an entity (with entity reference) - kept for backward compatibility
func show_entity_stats(entity: Node, ulid: PackedByteArray, entity_name: String = "Entity") -> void:
	current_entity_ulid = ulid
	current_entity_node = entity

	# Update header
	if entity_name_label:
		entity_name_label.text = entity_name

	# Show entity preview
	_show_entity_preview(entity)

	# Display stats
	_display_stats_from_ulid(ulid)

	# Show panel
	visible = true

## Show stats for an entity by ULID (primary method - fully agnostic)
func show_entity_stats_by_ulid(ulid: PackedByteArray, entity_name: String = "Entity") -> void:
	current_entity_ulid = ulid

	# Update header
	if entity_name_label:
		entity_name_label.text = entity_name

	# No preview without entity reference
	_clear_entity_preview()

	# Display stats
	_display_stats_from_ulid(ulid)

	# Show panel
	visible = true

## Internal helper to display stats from ULID
func _display_stats_from_ulid(ulid: PackedByteArray) -> void:
	# Get all stats from StatsManager
	var all_stats = StatsManager.get_all_stats(ulid)

	# Update stat displays (creates labels on first call, reuses thereafter)
	_update_stat("Health (HP)", all_stats.get(StatsManager.STAT.HP, 0), all_stats.get(StatsManager.STAT.MAX_HP, 0), Color(0.9, 0.3, 0.3))  # Red
	_update_stat("Attack", all_stats.get(StatsManager.STAT.ATTACK, 0), -1, Color(1.0, 0.6, 0.2))  # Orange
	_update_stat("Defense", all_stats.get(StatsManager.STAT.DEFENSE, 0), -1, Color(0.4, 0.7, 1.0))  # Blue
	_update_stat("Speed", all_stats.get(StatsManager.STAT.SPEED, 0), -1, Color(0.5, 1.0, 0.5))  # Green
	_update_stat("Range", all_stats.get(StatsManager.STAT.RANGE, 0), -1, Color(0.9, 0.9, 0.5))  # Yellow
	_update_stat("Morale", all_stats.get(StatsManager.STAT.MORALE, 0), -1, Color(0.8, 0.5, 1.0))  # Purple
	_update_stat("Level", all_stats.get(StatsManager.STAT.LEVEL, 0), -1, Color(1.0, 0.8, 0.3))  # Gold

	# Check for experience
	var exp = all_stats.get(StatsManager.STAT.EXPERIENCE, -1)
	if exp >= 0:
		_update_stat("Experience", exp, -1, Color(0.6, 0.9, 1.0))  # Cyan

	# Check for building stats
	var prod_rate = all_stats.get(StatsManager.STAT.PRODUCTION_RATE, -1)
	if prod_rate >= 0:
		_update_stat("Production Rate", prod_rate, -1, Color(0.9, 0.7, 0.4))  # Tan

	var storage = all_stats.get(StatsManager.STAT.STORAGE_CAPACITY, -1)
	if storage >= 0:
		_update_stat("Storage Capacity", storage, -1, Color(0.7, 0.6, 0.5))  # Brown

## Close the panel
func close_panel() -> void:
	_clear_entity_preview()
	visible = false
	current_entity_ulid = PackedByteArray()
	current_entity_node = null

## Update a single stat (creates labels on first call, reuses thereafter)
func _update_stat(stat_name: String, value: float, max_value: float = -1, value_color: Color = Color(1, 1, 1, 1)) -> void:
	if not stats_container:
		return

	# Check if we already have labels for this stat
	if not stat_labels.has(stat_name):
		# Get cached font
		var font = Cache.get_font("alagard") if Cache.has_font("alagard") else null

		# Create new labels and container
		var stat_row = HBoxContainer.new()
		stat_row.add_theme_constant_override("separation", 10)

		# Stat name label (dimmer gray)
		var name_label = Label.new()
		name_label.text = stat_name + ":"
		name_label.custom_minimum_size = Vector2(140, 0)
		name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		if font:
			name_label.add_theme_font_override("font", font)
			name_label.add_theme_font_size_override("font_size", 14)
		stat_row.add_child(name_label)

		# Stat value label (colored)
		var value_label = Label.new()
		if font:
			value_label.add_theme_font_override("font", font)
			value_label.add_theme_font_size_override("font_size", 16)
		stat_row.add_child(value_label)

		# Add to container and cache references
		stats_container.add_child(stat_row)
		stat_labels[stat_name] = {
			"row": stat_row,
			"name_label": name_label,
			"value_label": value_label
		}

	# Update value label text and color
	var labels = stat_labels[stat_name]
	var value_label = labels["value_label"]
	value_label.add_theme_color_override("font_color", value_color)

	if max_value > 0:
		value_label.text = "%d / %d" % [int(value), int(max_value)]
	else:
		value_label.text = str(int(value))

## Handle close button press
func _on_close_pressed() -> void:
	close_panel()

## Handle stat changes (live updates)
func _on_stat_changed(ulid: PackedByteArray, stat_type: int, new_value: float) -> void:
	# Only update if this is the currently displayed entity
	if ulid != current_entity_ulid:
		return

	# Re-fetch and redisplay all stats
	if visible:
		# Just refresh the stats display without recreating the whole panel
		_display_stats_from_ulid(ulid)

## Handle entity death
func _on_entity_died(ulid: PackedByteArray) -> void:
	# If the displayed entity died, close the panel
	if ulid == current_entity_ulid:
		close_panel()

## Show entity preview from pool
func _show_entity_preview(entity: Node) -> void:
	# Clear any existing preview
	_clear_entity_preview()

	# Determine pool key based on entity type
	var pool_key = ""
	if entity is Ship:
		pool_key = "viking"
	elif entity is Jezza:
		pool_key = "jezza"
	elif entity is NPC:
		# Generic NPC - try to infer pool key
		var script = entity.get_script()
		if script:
			var class_name_val = script.get_global_name()
			if not class_name_val.is_empty():
				pool_key = class_name_val.to_lower()

	if pool_key.is_empty():
		return

	# Acquire from pool
	preview_pool_key = pool_key
	preview_instance = Cluster.acquire(pool_key)

	if preview_instance and preview_container:
		preview_container.add_child(preview_instance)
		preview_instance.scale = Vector2(2.0, 2.0)  # Scale up for visibility
		preview_instance.visible = true  # Ensure visible
		preview_instance.position = Vector2.ZERO  # Center in container
		preview_instance.rotation = 0.0  # Reset rotation

		# Stop any movement/animations
		if "is_moving" in preview_instance:
			preview_instance.is_moving = false

		# If it has a sprite child, ensure it's visible and reset
		if preview_instance.has_node("Sprite2D"):
			var sprite = preview_instance.get_node("Sprite2D")
			sprite.visible = true
			sprite.modulate = Color(1, 1, 1, 1)  # Reset color/alpha
			sprite.rotation = 0.0  # Reset sprite rotation

		print("EntityStatsPanel: Acquired preview from pool '%s', scale=%s" % [pool_key, preview_instance.scale])
	else:
		print("EntityStatsPanel: Failed to acquire preview - pool_key='%s', instance=%s, container=%s" % [pool_key, preview_instance, preview_container])

## Clear entity preview and return to pool
func _clear_entity_preview() -> void:
	if preview_instance and preview_container and not preview_pool_key.is_empty():
		preview_container.remove_child(preview_instance)
		Cluster.release(preview_pool_key, preview_instance)
		print("EntityStatsPanel: Released preview back to pool '%s'" % preview_pool_key)
		preview_instance = null
		preview_pool_key = ""
	elif preview_instance:
		print("EntityStatsPanel: Preview instance exists but missing container or pool_key")
