extends PanelContainer
class_name ComboPopupPanel

## Combo popup panel - displays poker hand name and resource bonuses
## Appears when a combo is detected, auto-dismisses after duration
## Used by ComboPopupManager (autoload singleton)

signal dismissed()
signal combo_accepted(combo_data: Dictionary)
signal combo_declined(combo_data: Dictionary)

# Node references
@onready var combo_name_label: Label = $MarginContainer/VBoxContainer/ComboNameLabel
@onready var resources_container: VBoxContainer = $MarginContainer/VBoxContainer/ResourcesContainer
@onready var button_container: HBoxContainer = $MarginContainer/VBoxContainer/ButtonContainer
@onready var accept_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/AcceptButton
@onready var decline_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/DeclineButton

# Combo data reference
var current_combo_data: Dictionary = {}

# Animation settings (no longer auto-dismisses - requires player action)
var _is_active: bool = false

func _ready() -> void:
	# Apply Alagard font
	var font = Cache.get_font_for_current_language()
	if font:
		combo_name_label.add_theme_font_override("font", font)
		if accept_button:
			accept_button.add_theme_font_override("font", font)
		if decline_button:
			decline_button.add_theme_font_override("font", font)

	# Connect button signals
	if accept_button:
		accept_button.pressed.connect(_on_accept_pressed)
	if decline_button:
		decline_button.pressed.connect(_on_decline_pressed)

	# Start hidden
	modulate = Color(1, 1, 1, 0)
	visible = false

## Setup and display combo popup
## combo_data: Dictionary with keys: hand_name (String), bonus_multiplier (float), resource_bonuses (Array)
## resource_bonuses: Array of Dictionaries with keys: resource_name (String), amount (float)
func show_combo(combo_data: Dictionary) -> void:
	if not combo_data.has("hand_name"):
		push_error("ComboPopup: Invalid combo data - missing hand_name")
		return

	# Set combo name with multiplier (localized)
	var hand_name_raw: String = combo_data.get("hand_name", "Unknown")
	var hand_name_localized: String = I18n.get_combo_name(hand_name_raw)
	var multiplier: float = combo_data.get("bonus_multiplier", 1.0)
	combo_name_label.text = "%s (x%.1f)" % [hand_name_localized, multiplier]

	# Clear previous resource labels
	for child in resources_container.get_children():
		child.queue_free()

	# Add resource bonus labels
	var resource_bonuses: Array = combo_data.get("resource_bonuses", [])
	for bonus in resource_bonuses:
		if bonus is Dictionary:
			var resource_type: int = bonus.get("resource_type", 0)
			var amount: float = bonus.get("amount", 0.0)

			# Get localized resource name
			var resource_key = ""
			match resource_type:
				0:  # Gold
					resource_key = "resource.gold"
				1:  # Food
					resource_key = "resource.food"
				2:  # Labor
					resource_key = "resource.labor"
				3:  # Faith
					resource_key = "resource.faith"

			var resource_name_localized = I18n.translate(resource_key)

			var resource_label = Label.new()
			resource_label.text = "+%d %s" % [int(amount), resource_name_localized]
			resource_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

			# Apply font
			var font = Cache.get_font_for_current_language()
			if font:
				resource_label.add_theme_font_override("font", font)

			# Color based on resource type (using Resources.get_color())
			var color = Resources.get_color(resource_type)
			resource_label.add_theme_color_override("font_color", color)

			resources_container.add_child(resource_label)

	# Store combo data for later use
	current_combo_data = combo_data

	# Activate and show
	_is_active = true
	visible = true

	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.3)

## Called when player presses Accept button
func _on_accept_pressed() -> void:
	combo_accepted.emit(current_combo_data)
	dismiss()

## Called when player presses Decline button
func _on_decline_pressed() -> void:
	combo_declined.emit(current_combo_data)
	dismiss()

## Dismiss the popup
func dismiss() -> void:
	if not _is_active:
		return

	_is_active = false

	# Fade out animation (only if in scene tree)
	if is_inside_tree():
		var tween = create_tween()
		if tween:
			tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.3)
			tween.tween_callback(func():
				visible = false
				dismissed.emit()
			)
		else:
			visible = false
			dismissed.emit()
	else:
		visible = false
		dismissed.emit()
