extends Control
class_name TopbarUIUX

# Topbar UI - spans full width at top of screen
# Container for smaller UI components (resources, notifications, etc.)

@onready var placeholder1: Label = $MarginContainer/HBoxContainer/LeftSection/Placeholder1
@onready var placeholder2: Label = $MarginContainer/HBoxContainer/LeftSection/Placeholder2
@onready var placeholder3: Label = $MarginContainer/HBoxContainer/CenterSection/Placeholder3
@onready var placeholder4: Label = $MarginContainer/HBoxContainer/RightSection/Placeholder4
@onready var placeholder5: Label = $MarginContainer/HBoxContainer/RightSection/Placeholder5

func _ready() -> void:
	# Apply styling and setup
	_apply_fonts()

func _apply_fonts() -> void:
	# Apply Alagard font from Cache to all labels
	var font = Cache.get_font("alagard")
	if font == null:
		push_warning("TopbarUIUX: Could not load Alagard font from Cache")
		return

	# Apply to all placeholder labels
	placeholder1.add_theme_font_override("font", font)
	placeholder2.add_theme_font_override("font", font)
	placeholder3.add_theme_font_override("font", font)
	placeholder4.add_theme_font_override("font", font)
	placeholder5.add_theme_font_override("font", font)
