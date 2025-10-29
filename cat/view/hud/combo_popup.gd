extends PanelContainer
class_name ComboPopupPanel

## Combo popup panel - displays poker hand name and resource bonuses
## Appears when a combo is detected, auto-dismisses after duration
## Used by ComboPopupManager (autoload singleton)

signal dismissed()

# Node references
@onready var combo_name_label: Label = $MarginContainer/VBoxContainer/ComboNameLabel
@onready var resources_container: VBoxContainer = $MarginContainer/VBoxContainer/ResourcesContainer

# Animation settings
var display_duration: float = 4.0  # Show for 4 seconds
var _timer: float = 0.0
var _is_active: bool = false

func _ready() -> void:
	# Apply Alagard font
	var font = Cache.get_font_for_current_language()
	if font:
		combo_name_label.add_theme_font_override("font", font)

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

			# Color based on resource type
			match resource_type:
				0:  # Gold
					resource_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
				1:  # Food
					resource_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
				2:  # Labor
					resource_label.add_theme_color_override("font_color", Color(0.3, 0.3, 0.9))
				3:  # Faith
					resource_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))

			resources_container.add_child(resource_label)

	# Reset timer and activate
	_timer = 0.0
	_is_active = true
	visible = true

	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.3)

func _process(delta: float) -> void:
	if not _is_active:
		return

	_timer += delta
	if _timer >= display_duration:
		dismiss()

## Dismiss the popup
func dismiss() -> void:
	if not _is_active:
		return

	_is_active = false

	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.3)
	tween.tween_callback(func():
		visible = false
		dismissed.emit()
	)
