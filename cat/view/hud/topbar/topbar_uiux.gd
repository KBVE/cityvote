extends Control
class_name TopbarUIUX

# Topbar UI - spans full width at top of screen
# Container for smaller UI components (resources, notifications, etc.)

# Resource value labels
@onready var gold_value: Label = $MarginContainer/HBoxContainer/LeftSection/GoldContainer/GoldValue
@onready var food_value: Label = $MarginContainer/HBoxContainer/LeftSection/FoodContainer/FoodValue
@onready var labor_value: Label = $MarginContainer/HBoxContainer/LeftSection/LaborContainer/LaborValue
@onready var faith_value: Label = $MarginContainer/HBoxContainer/LeftSection/FaithContainer/FaithValue

# Resource name labels (for font application)
@onready var gold_name: Label = $MarginContainer/HBoxContainer/LeftSection/GoldContainer/GoldName
@onready var food_name: Label = $MarginContainer/HBoxContainer/LeftSection/FoodContainer/FoodName
@onready var labor_name: Label = $MarginContainer/HBoxContainer/LeftSection/LaborContainer/LaborName
@onready var faith_name: Label = $MarginContainer/HBoxContainer/LeftSection/FaithContainer/FaithName

# Center labels and button
@onready var turn_label: Label = $MarginContainer/HBoxContainer/CenterSection/TurnLabel
@onready var city_vote_button: Button = $MarginContainer/HBoxContainer/CenterSection/CityVoteButton
@onready var timer_label: Label = $MarginContainer/HBoxContainer/CenterSection/TimerLabel

# Right section labels
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

	# Connect to global timer
	if GameTimer:
		GameTimer.timer_tick.connect(_on_timer_tick)
		GameTimer.timer_reset.connect(_on_timer_reset)
		GameTimer.turn_changed.connect(_on_turn_changed)
		# Initialize with current time and turn
		_update_timer_display(GameTimer.get_time_left())
		_update_turn_display(GameTimer.get_current_turn())

	# Connect to resource ledger
	if ResourceLedger:
		ResourceLedger.resource_changed.connect(_on_resource_changed)
		# Initialize resource displays with current values
		_update_resource_display(ResourceLedger.R.GOLD, ResourceLedger.get_current(ResourceLedger.R.GOLD), ResourceLedger.get_cap(ResourceLedger.R.GOLD), ResourceLedger.get_rate(ResourceLedger.R.GOLD))
		_update_resource_display(ResourceLedger.R.FOOD, ResourceLedger.get_current(ResourceLedger.R.FOOD), ResourceLedger.get_cap(ResourceLedger.R.FOOD), ResourceLedger.get_rate(ResourceLedger.R.FOOD))
		_update_resource_display(ResourceLedger.R.LABOR, ResourceLedger.get_current(ResourceLedger.R.LABOR), ResourceLedger.get_cap(ResourceLedger.R.LABOR), ResourceLedger.get_rate(ResourceLedger.R.LABOR))
		_update_resource_display(ResourceLedger.R.FAITH, ResourceLedger.get_current(ResourceLedger.R.FAITH), ResourceLedger.get_cap(ResourceLedger.R.FAITH), ResourceLedger.get_rate(ResourceLedger.R.FAITH))

func _apply_fonts() -> void:
	# Apply Alagard font from Cache to all labels
	var font = Cache.get_font("alagard")
	if font == null:
		push_warning("TopbarUIUX: Could not load Alagard font from Cache")
		return

	# Apply to resource name labels
	gold_name.add_theme_font_override("font", font)
	food_name.add_theme_font_override("font", font)
	labor_name.add_theme_font_override("font", font)
	faith_name.add_theme_font_override("font", font)

	# Apply to resource value labels
	gold_value.add_theme_font_override("font", font)
	food_value.add_theme_font_override("font", font)
	labor_value.add_theme_font_override("font", font)
	faith_value.add_theme_font_override("font", font)

	# Apply to center section
	turn_label.add_theme_font_override("font", font)
	city_vote_button.add_theme_font_override("font", font)
	timer_label.add_theme_font_override("font", font)

	# Apply to right section
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

func _on_timer_tick(time_left: int) -> void:
	_update_timer_display(time_left)

func _on_timer_reset() -> void:
	# Visual feedback when timer resets (optional: add flash effect, etc.)
	pass

func _on_turn_changed(turn: int) -> void:
	_update_turn_display(turn)

func _update_timer_display(time_left: int) -> void:
	if timer_label:
		timer_label.text = "Timer: %ds" % time_left

func _update_turn_display(turn: int) -> void:
	if turn_label:
		turn_label.text = "Turn: %d" % turn

func _on_resource_changed(kind: int, current: float, cap: float, rate: float) -> void:
	_update_resource_display(kind, current, cap, rate)

func _update_resource_display(kind: int, current: float, cap: float, rate: float) -> void:
	var current_int = int(current)

	match kind:
		ResourceLedger.R.GOLD:
			if gold_value:
				gold_value.text = "%d" % current_int
		ResourceLedger.R.FOOD:
			if food_value:
				food_value.text = "%d" % current_int
		ResourceLedger.R.LABOR:
			if labor_value:
				labor_value.text = "%d" % current_int
		ResourceLedger.R.FAITH:
			if faith_value:
				faith_value.text = "%d" % current_int
