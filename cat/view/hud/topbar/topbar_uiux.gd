extends Control
class_name TopbarUIUX

# Topbar UI - spans full width at top of screen
# Container for smaller UI components (resources, notifications, etc.)

@onready var placeholder1: Label = $MarginContainer/HBoxContainer/LeftSection/Placeholder1
@onready var placeholder2: Label = $MarginContainer/HBoxContainer/LeftSection/Placeholder2
@onready var city_vote_button: Button = $MarginContainer/HBoxContainer/CenterSection/CityVoteButton
@onready var placeholder4: Label = $MarginContainer/HBoxContainer/RightSection/Placeholder4
@onready var placeholder5: Label = $MarginContainer/HBoxContainer/RightSection/Placeholder5

# Reference to camera (set by main scene)
var camera: Camera2D = null

func _ready() -> void:
	# Apply styling and setup
	_apply_fonts()

	# Connect CityVote button
	if city_vote_button:
		city_vote_button.pressed.connect(_on_city_vote_pressed)

func _apply_fonts() -> void:
	# Apply Alagard font from Cache to all labels
	var font = Cache.get_font("alagard")
	if font == null:
		push_warning("TopbarUIUX: Could not load Alagard font from Cache")
		return

	# Apply to all placeholder labels
	placeholder1.add_theme_font_override("font", font)
	placeholder2.add_theme_font_override("font", font)
	city_vote_button.add_theme_font_override("font", font)
	placeholder4.add_theme_font_override("font", font)
	placeholder5.add_theme_font_override("font", font)

func _on_city_vote_pressed() -> void:
	# Zoom out camera when CityVote is clicked
	if camera:
		var target_zoom = Vector2(0.5, 0.5)  # Zoom out to 0.5x
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(camera, "zoom", target_zoom, 0.5)
