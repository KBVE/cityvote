extends PanelContainer
class_name StructureInfoPanel

## Structure Info Panel (Floating Window)
## Displays detailed information for a selected structure (city, village, castle, etc.)
## Closeable with ESC key or X button

# Currently displayed structure
var current_structure = null  # Reference to the Structure Rust object

# UI references
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderBar/CloseButton
@onready var structure_name_label: Label = $MarginContainer/VBoxContainer/HeaderBar/StructureNameLabel
@onready var type_label: Label = $MarginContainer/VBoxContainer/InfoContainer/TypeLabel
@onready var description_label: Label = $MarginContainer/VBoxContainer/InfoContainer/DescriptionLabel
@onready var stats_container: VBoxContainer = $MarginContainer/VBoxContainer/StatsContainer
@onready var actions_container: VBoxContainer = $MarginContainer/VBoxContainer/ActionsContainer

# Cached stat label references for reuse (memory optimization)
var stat_labels: Dictionary = {}  # stat_name -> {name_label, value_label}

# Action buttons
var trade_button: Button = null
var rest_button: Button = null
var recruit_button: Button = null
var attack_button: Button = null

func _ready() -> void:
	# Start hidden
	visible = false

	# Apply Alagard font to header elements
	var font = Cache.get_font_for_current_language()
	if font:
		if structure_name_label:
			structure_name_label.add_theme_font_override("font", font)
		if close_button:
			close_button.add_theme_font_override("font", font)
		if type_label:
			type_label.add_theme_font_override("font", font)
		if description_label:
			description_label.add_theme_font_override("font", font)

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Connect to language change signal
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

	# Create action buttons
	_create_action_buttons()

func _input(event: InputEvent) -> void:
	# Close on ESC key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and visible:
			close_panel()
			get_viewport().set_input_as_handled()

## Show structure information
func show_structure(structure) -> void:
	if structure == null:
		push_error("StructureInfoPanel: Cannot show null structure")
		return

	current_structure = structure

	# Update header with structure name
	if structure_name_label:
		structure_name_label.text = structure.get_name()

	# Update structure type
	if type_label:
		var type_name = structure.get_type_name()
		type_label.text = I18n.translate("structure.type") + ": " + type_name

	# Update description
	if description_label:
		description_label.text = structure.get_description()

	# Display stats
	_display_structure_stats(structure)

	# Update action buttons based on structure state
	_update_action_buttons(structure)

	# Show panel
	visible = true

## Display structure stats
func _display_structure_stats(structure) -> void:
	# Clear existing stats
	stat_labels.clear()
	for child in stats_container.get_children():
		child.queue_free()

	# Get structure properties
	var position = structure.get_position()
	var population = structure.get_population()
	var wealth = structure.get_wealth()
	var reputation = structure.get_reputation()
	var is_active = structure.is_structure_active()

	# Display position
	_update_stat_text(
		I18n.translate("structure.position"),
		"(%.0f, %.0f)" % [position.x, position.y],
		Color(0.7, 0.7, 0.8)
	)

	# Display status
	var status_text = I18n.translate("structure.active") if is_active else I18n.translate("structure.inactive")
	var status_color = Color(0.3, 0.9, 0.3) if is_active else Color(0.9, 0.3, 0.3)
	_update_stat_text(
		I18n.translate("structure.status"),
		status_text,
		status_color
	)

	# Display population (if inhabited)
	if structure.has_type(StructureType.INHABITED) or population > 0:
		_update_stat_value(
			I18n.translate("structure.population"),
			population,
			Color(0.9, 0.7, 0.4)
		)

	# Display wealth
	_update_stat_bar(
		I18n.translate("structure.wealth"),
		wealth,
		100.0,
		Color(1.0, 0.8, 0.2)
	)

	# Display reputation
	var rep_color = Color(0.3, 0.9, 0.3) if reputation >= 0 else Color(0.9, 0.3, 0.3)
	_update_stat_bar(
		I18n.translate("structure.reputation"),
		reputation,
		100.0,
		rep_color,
		-100.0
	)

	# Display trade modifier
	if structure.has_type(StructureType.TRADING_POST):
		var trade_mod = structure.get_trade_modifier()
		var mod_text = "%+.0f%%" % (trade_mod * 100.0)
		var mod_color = Color(0.3, 0.9, 0.3) if trade_mod < 0 else Color(0.9, 0.9, 0.3)
		_update_stat_text(
			I18n.translate("structure.trade_modifier"),
			mod_text,
			mod_color
		)

## Update a stat with text value
func _update_stat_text(stat_name: String, text_value: String, value_color: Color = Color(1, 1, 1, 1)) -> void:
	if not stats_container:
		return

	var font = Cache.get_font_for_current_language()

	# Create stat row
	var stat_row = HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 10)

	# Stat name label
	var name_label = Label.new()
	name_label.text = stat_name + ":"
	name_label.custom_minimum_size = Vector2(140, 0)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	if font:
		name_label.add_theme_font_override("font", font)
		name_label.add_theme_font_size_override("font_size", 14)
	stat_row.add_child(name_label)

	# Stat value label
	var value_label = Label.new()
	value_label.text = text_value
	value_label.add_theme_color_override("font_color", value_color)
	if font:
		value_label.add_theme_font_override("font", font)
		value_label.add_theme_font_size_override("font_size", 14)
	stat_row.add_child(value_label)

	stats_container.add_child(stat_row)

## Update a stat with numeric value
func _update_stat_value(stat_name: String, value: int, value_color: Color = Color(1, 1, 1, 1)) -> void:
	_update_stat_text(stat_name, str(value), value_color)

## Update a stat with progress bar
func _update_stat_bar(stat_name: String, value: float, max_value: float, value_color: Color = Color(1, 1, 1, 1), min_value: float = 0.0) -> void:
	if not stats_container:
		return

	var font = Cache.get_font_for_current_language()

	# Create stat row
	var stat_row = VBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 4)

	# Name and value row
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)

	# Stat name label
	var name_label = Label.new()
	name_label.text = stat_name + ":"
	name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	if font:
		name_label.add_theme_font_override("font", font)
		name_label.add_theme_font_size_override("font_size", 14)
	header_row.add_child(name_label)

	# Stat value label
	var value_label = Label.new()
	value_label.text = "%.0f / %.0f" % [value, max_value]
	value_label.add_theme_color_override("font_color", value_color)
	if font:
		value_label.add_theme_font_override("font", font)
		value_label.add_theme_font_size_override("font_size", 14)
	header_row.add_child(value_label)

	stat_row.add_child(header_row)

	# Progress bar
	var progress_bar = ProgressBar.new()
	progress_bar.min_value = min_value
	progress_bar.max_value = max_value
	progress_bar.value = value
	progress_bar.custom_minimum_size = Vector2(200, 8)
	progress_bar.show_percentage = false

	# Style the progress bar
	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = value_color
	stylebox.border_width_left = 1
	stylebox.border_width_right = 1
	stylebox.border_width_top = 1
	stylebox.border_width_bottom = 1
	stylebox.border_color = value_color.darkened(0.3)
	progress_bar.add_theme_stylebox_override("fill", stylebox)

	stat_row.add_child(progress_bar)
	stats_container.add_child(stat_row)

## Create action buttons
func _create_action_buttons() -> void:
	if not actions_container:
		return

	var font = Cache.get_font_for_current_language()

	# Trade button
	trade_button = Button.new()
	trade_button.text = I18n.translate("structure.action.trade")
	trade_button.pressed.connect(_on_trade_pressed)
	if font:
		trade_button.add_theme_font_override("font", font)
	actions_container.add_child(trade_button)

	# Rest button
	rest_button = Button.new()
	rest_button.text = I18n.translate("structure.action.rest")
	rest_button.pressed.connect(_on_rest_pressed)
	if font:
		rest_button.add_theme_font_override("font", font)
	actions_container.add_child(rest_button)

	# Recruit button
	recruit_button = Button.new()
	recruit_button.text = I18n.translate("structure.action.recruit")
	recruit_button.pressed.connect(_on_recruit_pressed)
	if font:
		recruit_button.add_theme_font_override("font", font)
	actions_container.add_child(recruit_button)

	# Attack button
	attack_button = Button.new()
	attack_button.text = I18n.translate("structure.action.attack")
	attack_button.pressed.connect(_on_attack_pressed)
	if font:
		attack_button.add_theme_font_override("font", font)
	actions_container.add_child(attack_button)

## Update action button visibility based on structure state
func _update_action_buttons(structure) -> void:
	if not current_structure:
		return

	var can_interact = structure.can_interact()

	# Trade button - only if trading post and can interact
	if trade_button:
		trade_button.visible = structure.has_type(StructureType.TRADING_POST) and can_interact

	# Rest button - only if inhabited and can interact
	if rest_button:
		rest_button.visible = structure.has_type(StructureType.INHABITED) and can_interact

	# Recruit button - only if city/village and can interact
	if recruit_button:
		var can_recruit = (structure.has_type(StructureType.CITY) or structure.has_type(StructureType.VILLAGE)) and can_interact
		recruit_button.visible = can_recruit

	# Attack button - always visible if hostile, or if player wants to attack
	if attack_button:
		attack_button.visible = true
		if structure.has_type(StructureType.HOSTILE):
			attack_button.text = I18n.translate("structure.action.defend")
		else:
			attack_button.text = I18n.translate("structure.action.attack")

## Close the panel
func close_panel() -> void:
	visible = false
	current_structure = null

## Handle close button press
func _on_close_pressed() -> void:
	close_panel()

## Handle language changes
func _on_language_changed(_new_language: int) -> void:
	# Update fonts
	var font = Cache.get_font_for_current_language()
	if font:
		if structure_name_label:
			structure_name_label.add_theme_font_override("font", font)
		if close_button:
			close_button.add_theme_font_override("font", font)
		if type_label:
			type_label.add_theme_font_override("font", font)
		if description_label:
			description_label.add_theme_font_override("font", font)

	# Update button texts
	if trade_button:
		trade_button.text = I18n.translate("structure.action.trade")
	if rest_button:
		rest_button.text = I18n.translate("structure.action.rest")
	if recruit_button:
		recruit_button.text = I18n.translate("structure.action.recruit")
	if attack_button:
		if current_structure and current_structure.has_type(StructureType.HOSTILE):
			attack_button.text = I18n.translate("structure.action.defend")
		else:
			attack_button.text = I18n.translate("structure.action.attack")

	# Refresh display if panel is visible
	if visible and current_structure:
		show_structure(current_structure)

## Action handlers - to be implemented
func _on_trade_pressed() -> void:
	print("StructureInfoPanel: Trade action - to be implemented")
	# TODO: Open trade window

func _on_rest_pressed() -> void:
	print("StructureInfoPanel: Rest action - to be implemented")
	# TODO: Rest at structure (restore health/energy)

func _on_recruit_pressed() -> void:
	print("StructureInfoPanel: Recruit action - to be implemented")
	# TODO: Open recruitment window

func _on_attack_pressed() -> void:
	print("StructureInfoPanel: Attack action - to be implemented")
	# TODO: Initiate combat or defense
