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
@onready var preview_container: CenterContainer = $MarginContainer/VBoxContainer/PreviewAndFlavorContainer/EntityPreviewContainer
@onready var flavor_text_label: Label = $MarginContainer/VBoxContainer/PreviewAndFlavorContainer/FlavorTextLabel
@onready var stats_container: VBoxContainer = $MarginContainer/VBoxContainer/StatsContainer

# Cached stat label references for reuse (memory optimization)
var stat_labels: Dictionary = {}  # stat_name -> {name_label, value_label}

# Typewriter effect
var typewriter_tween: Tween = null
var current_full_text: String = ""
var typewriter_speed: float = 0.05  # seconds per character

# Flavor text is now managed by I18n system
# Keys: entity.viking.flavor, entity.jezza.flavor

func _ready() -> void:
	# Start hidden
	visible = false

	# Apply Alagard font to header elements
	var font = Cache.get_font_for_current_language()
	if font:
		if entity_name_label:
			entity_name_label.add_theme_font_override("font", font)
		if close_button:
			close_button.add_theme_font_override("font", font)

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Connect to language change signal
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

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

	# Display ULID (full hex string)
	if ulid.size() > 0:
		var ulid_hex = UlidManager.to_hex(ulid)
		_update_stat_text("ULID", ulid_hex, Color(0.7, 0.7, 0.8))

	# Display Player ID (if entity has player_ulid property)
	if current_entity_node != null:
		var player_id_hex = ""
		if "player_ulid" in current_entity_node:
			var player_ulid_bytes = current_entity_node.player_ulid
			if player_ulid_bytes.size() > 0:
				player_id_hex = UlidManager.to_hex(player_ulid_bytes)
			else:
				player_id_hex = "AI-Controlled"
		else:
			player_id_hex = "N/A"
		_update_stat_text("Player ID", player_id_hex, Color(0.6, 0.8, 0.9))

	# Update stat displays (creates labels on first call, reuses thereafter)
	_update_stat(I18n.translate("stat.health") + " (HP)", all_stats.get(StatsManager.STAT.HP, 0), all_stats.get(StatsManager.STAT.MAX_HP, 0), Color(0.9, 0.3, 0.3))  # Red
	_update_stat(I18n.translate("ui.stats.energy") + " (EP)", all_stats.get(StatsManager.STAT.ENERGY, 0), all_stats.get(StatsManager.STAT.MAX_ENERGY, 0), Color(0.2, 0.6, 0.9))  # Blue
	_update_stat(I18n.translate("stat.attack") + " (ATK)", all_stats.get(StatsManager.STAT.ATTACK, 0), -1, Color(1.0, 0.6, 0.2))  # Orange
	_update_stat(I18n.translate("stat.defense") + " (DEF)", all_stats.get(StatsManager.STAT.DEFENSE, 0), -1, Color(0.4, 0.7, 1.0))  # Blue
	_update_stat(I18n.translate("stat.speed") + " (SPD)", all_stats.get(StatsManager.STAT.SPEED, 0), -1, Color(0.5, 1.0, 0.5))  # Green
	_update_stat(I18n.translate("stat.range") + " (RNG)", all_stats.get(StatsManager.STAT.RANGE, 0), -1, Color(0.9, 0.9, 0.5))  # Yellow
	_update_stat(I18n.translate("stat.morale") + " (MOR)", all_stats.get(StatsManager.STAT.MORALE, 0), -1, Color(0.8, 0.5, 1.0))  # Purple
	_update_stat(I18n.translate("stat.level") + " (LVL)", all_stats.get(StatsManager.STAT.LEVEL, 0), -1, Color(1.0, 0.8, 0.3))  # Gold

	# Check for experience
	var exp = all_stats.get(StatsManager.STAT.EXPERIENCE, -1)
	if exp >= 0:
		_update_stat(I18n.translate("stat.experience") + " (EXP)", exp, -1, Color(0.6, 0.9, 1.0))  # Cyan

	# Check for building stats
	var prod_rate = all_stats.get(StatsManager.STAT.PRODUCTION_RATE, -1)
	if prod_rate >= 0:
		_update_stat(I18n.translate("stat.production_rate") + " (PROD)", prod_rate, -1, Color(0.9, 0.7, 0.4))  # Tan

	var storage = all_stats.get(StatsManager.STAT.STORAGE_CAPACITY, -1)
	if storage >= 0:
		_update_stat(I18n.translate("stat.storage_capacity") + " (STOR)", storage, -1, Color(0.7, 0.6, 0.5))  # Brown

## Close the panel
func close_panel() -> void:
	_clear_entity_preview()
	_stop_typewriter()
	visible = false
	current_entity_ulid = PackedByteArray()
	current_entity_node = null

## Start typewriter effect for flavor text
func _start_typewriter(pool_key: String) -> void:
	# Stop any existing typewriter
	_stop_typewriter()

	# Get flavor text for this entity type from I18n
	var flavor_key = "entity.%s.flavor" % pool_key
	var flavor_text = I18n.translate(flavor_key) if I18n.has_key(flavor_key) else "A mysterious entity shrouded in legend..."
	current_full_text = flavor_text

	if not flavor_text_label:
		return

	# Apply Alagard font
	var font = Cache.get_font_for_current_language()
	if font:
		flavor_text_label.add_theme_font_override("font", font)

	# Start with empty text
	flavor_text_label.text = ""

	# Calculate total duration based on text length
	var total_duration = flavor_text.length() * typewriter_speed

	# Create typewriter tween
	typewriter_tween = create_tween()

	# Animate from 0 to full text length
	for i in range(flavor_text.length() + 1):
		typewriter_tween.tween_callback(
			func(): flavor_text_label.text = current_full_text.substr(0, i)
		)
		if i < flavor_text.length():
			typewriter_tween.tween_interval(typewriter_speed)

## Stop typewriter effect
func _stop_typewriter() -> void:
	if typewriter_tween and typewriter_tween.is_valid():
		typewriter_tween.kill()
		typewriter_tween = null
	current_full_text = ""

## Update a single stat with text value (creates labels on first call, reuses thereafter)
## Used for ULID, Player ID, and other non-numeric stats
func _update_stat_text(stat_name: String, text_value: String, value_color: Color = Color(1, 1, 1, 1)) -> void:
	if not stats_container:
		return

	# Check if we already have labels for this stat
	if not stat_labels.has(stat_name):
		# Get cached font
		var font = Cache.get_font_for_current_language() if Cache.has_font("alagard") else null

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

		# Stat value label (colored, smaller font for long text)
		var value_label = Label.new()
		if font:
			value_label.add_theme_font_override("font", font)
			value_label.add_theme_font_size_override("font_size", 12)  # Smaller for ULID hex strings
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
	value_label.text = text_value

## Update a single stat (creates labels on first call, reuses thereafter)
func _update_stat(stat_name: String, value: float, max_value: float = -1, value_color: Color = Color(1, 1, 1, 1)) -> void:
	if not stats_container:
		return

	# Check if we already have labels for this stat
	if not stat_labels.has(stat_name):
		# Get cached font
		var font = Cache.get_font_for_current_language() if Cache.has_font("alagard") else null

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

## Handle language changes
func _on_language_changed(_new_language: int) -> void:
	# Update fonts
	var font = Cache.get_font_for_current_language()
	if font:
		if entity_name_label:
			entity_name_label.add_theme_font_override("font", font)
		if close_button:
			close_button.add_theme_font_override("font", font)

	# Refresh stats display if panel is visible
	if visible and current_entity_ulid:
		_display_stats_from_ulid(current_entity_ulid)

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
	if entity is Jezza:
		pool_key = "jezza"
	elif entity is NPC:
		# Check for water entities (vikings/ships)
		if "terrain_type" in entity and entity.terrain_type == NPC.TerrainType.WATER:
			pool_key = "viking"
		else:
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
			sprite.position = Vector2.ZERO  # Reset sprite position
			sprite.z_index = 0  # Ensure not hidden behind

			# Debug: Check texture type and material
			var tex = sprite.texture
			print("EntityStatsPanel: Sprite visible=%s, texture type=%s, material=%s" % [sprite.visible, tex.get_class() if tex else "null", sprite.material != null])

			# If using AtlasTexture, we need to ensure the full atlas is used for the shader
			if tex and tex is AtlasTexture:
				var atlas_tex = tex as AtlasTexture
				print("EntityStatsPanel: AtlasTexture region=%s, atlas=%s" % [atlas_tex.region, atlas_tex.atlas != null])

				# For shader-based ships, replace AtlasTexture with the full atlas
				if sprite.material and sprite.material is ShaderMaterial and atlas_tex.atlas:
					sprite.texture = atlas_tex.atlas
					print("EntityStatsPanel: Replaced AtlasTexture with full atlas for shader")

			# For ships with shader materials, set direction and disable wave animation
			if sprite.material and sprite.material is ShaderMaterial:
				# Set direction to 8 (south-facing) for consistent preview
				sprite.material.set_shader_parameter("direction", 8)
				# Disable wave animation by setting amplitudes to 0
				sprite.material.set_shader_parameter("wave_amplitude", 0.0)
				sprite.material.set_shader_parameter("sway_amplitude", 0.0)
				print("EntityStatsPanel: Set shader parameters for ship preview (direction=8)")

			# Auto-scale sprite to fit container
			_auto_scale_preview(preview_instance, sprite)

		# Start typewriter effect for this entity type
		_start_typewriter(pool_key)
	else:
		push_error("EntityStatsPanel: Failed to acquire preview from pool '%s'" % pool_key)

## Auto-scale preview to fit within container
func _auto_scale_preview(instance: Node2D, sprite: Sprite2D) -> void:
	if not preview_container or not sprite.texture:
		return

	# Get container size
	var container_size = preview_container.custom_minimum_size
	if container_size == Vector2.ZERO:
		container_size = Vector2(80, 80)  # Default size

	# Get base texture size
	var texture_size = sprite.texture.get_size()

	# For atlas-based shaders, use 1/4 of the texture size (4x4 grid)
	if sprite.material and sprite.material is ShaderMaterial:
		texture_size = texture_size / 4.0

	# Account for sprite's existing scale
	var sprite_size = texture_size * sprite.scale

	# Calculate scale factor to fit within container with some padding
	var padding = 20.0  # pixels of padding
	var available_size = container_size - Vector2(padding, padding)

	var scale_x = available_size.x / sprite_size.x
	var scale_y = available_size.y / sprite_size.y

	# Use the smaller scale to fit both dimensions
	var final_scale = min(scale_x, scale_y)

	# Apply scale to instance (this multiplies with sprite's scale)
	instance.scale = Vector2(final_scale, final_scale)

	print("EntityStatsPanel: Auto-scaled preview to %s (texture=%s, sprite.scale=%s, final_sprite_size=%s)" % [final_scale, texture_size, sprite.scale, sprite_size])

## Clear entity preview and return to pool
func _clear_entity_preview() -> void:
	if preview_instance and preview_container and not preview_pool_key.is_empty():
		preview_container.remove_child(preview_instance)
		Cluster.release(preview_pool_key, preview_instance)
		preview_instance = null
		preview_pool_key = ""
	elif preview_instance:
		push_error("EntityStatsPanel: Preview instance exists but missing container or pool_key")
