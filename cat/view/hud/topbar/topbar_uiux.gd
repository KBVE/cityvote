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

# Center section buttons
@onready var city_vote_button: Button = $MarginContainer/HBoxContainer/CenterSection/CityVoteButton
@onready var inventory_button: Button = $MarginContainer/HBoxContainer/CenterSection/InventoryButton

# Right section labels (timer and turn moved here)
@onready var timer_label: Label = $MarginContainer/HBoxContainer/RightSection/TimerLabel
@onready var turn_label: Label = $MarginContainer/HBoxContainer/RightSection/TurnLabel

# Reference to camera (set by main scene)
var camera: Camera2D = null

# Camera zoom states (4 levels that cycle through)
var zoom_states: Array[Vector2] = [
	Vector2(1.0, 1.0),   # Default zoom
	Vector2(0.75, 0.75), # Slight zoom out
	Vector2(0.5, 0.5),   # Medium zoom out
	Vector2(0.35, 0.35)  # Far zoom out
]
var current_zoom_index: int = 0

# Current displayed values (for lerping animation)
var displayed_gold: float = 0.0
var displayed_food: float = 0.0
var displayed_labor: float = 0.0
var displayed_faith: float = 0.0

# Target values (from ResourceLedger)
var target_gold: float = 0.0
var target_food: float = 0.0
var target_labor: float = 0.0
var target_faith: float = 0.0

# Animation speed (numbers per second)
var lerp_speed: float = 50.0

func _ready() -> void:
	# Apply styling and setup
	_apply_fonts()
	_update_resource_labels()

	# Connect to language change signal
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

	# Connect CityVote button
	if city_vote_button:
		city_vote_button.pressed.connect(_on_city_vote_pressed)

	# Connect Inventory button
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_pressed)

	# Connect to global timer
	if GameTimer:
		GameTimer.timer_tick.connect(_on_timer_tick)
		GameTimer.timer_reset.connect(_on_timer_reset)
		GameTimer.turn_changed.connect(_on_turn_changed)
		# Initialize with current time and turn
		_update_timer_display(GameTimer.get_time_left())
		_update_turn_display(GameTimer.get_current_turn())

	# Connect to UnifiedEventBridge for resource changes
	if UnifiedEventBridge:
		UnifiedEventBridge.resource_changed.connect(_on_resource_changed)
		# Initialize to 1000 to match Actor's initial values (no animation needed)
		displayed_gold = 1000.0
		displayed_food = 1000.0
		displayed_labor = 1000.0
		displayed_faith = 1000.0

		target_gold = 1000.0
		target_food = 1000.0
		target_labor = 1000.0
		target_faith = 1000.0

func _process(delta: float) -> void:
	# Animate resource numbers smoothly
	var changed = false

	# Gold
	if displayed_gold != target_gold:
		displayed_gold = move_toward(displayed_gold, target_gold, lerp_speed * delta)
		if gold_value:
			gold_value.text = "%d" % int(displayed_gold)
		changed = true

	# Food
	if displayed_food != target_food:
		displayed_food = move_toward(displayed_food, target_food, lerp_speed * delta)
		if food_value:
			food_value.text = "%d" % int(displayed_food)
		changed = true

	# Labor
	if displayed_labor != target_labor:
		displayed_labor = move_toward(displayed_labor, target_labor, lerp_speed * delta)
		if labor_value:
			labor_value.text = "%d" % int(displayed_labor)
		changed = true

	# Faith
	if displayed_faith != target_faith:
		displayed_faith = move_toward(displayed_faith, target_faith, lerp_speed * delta)
		if faith_value:
			faith_value.text = "%d" % int(displayed_faith)
		changed = true

func _apply_fonts() -> void:
	# Apply Alagard font from Cache to all labels
	var font = Cache.get_font_for_current_language()
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

	# Apply to center section buttons
	city_vote_button.add_theme_font_override("font", font)
	inventory_button.add_theme_font_override("font", font)

	# Apply to right section (timer and turn)
	timer_label.add_theme_font_override("font", font)
	turn_label.add_theme_font_override("font", font)

func _update_resource_labels() -> void:
	# Update resource name labels with translations
	if gold_name:
		gold_name.text = I18n.translate("resource.gold")
	if food_name:
		food_name.text = I18n.translate("resource.food")
	if labor_name:
		labor_name.text = I18n.translate("resource.labor")
	if faith_name:
		faith_name.text = I18n.translate("resource.faith")

func _on_language_changed(_new_language: int) -> void:
	# Refresh fonts and labels when language changes
	_apply_fonts()
	_update_resource_labels()

func _on_city_vote_pressed() -> void:
	# Cycle through camera zoom states
	if camera:
		# Move to next zoom state
		current_zoom_index = (current_zoom_index + 1) % zoom_states.size()
		var target_zoom = zoom_states[current_zoom_index]

		# Animate to new zoom level
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(camera, "zoom", target_zoom, 0.5)

		print("TopbarUIUX: Cycling to zoom state %d: %v" % [current_zoom_index, target_zoom])

func _on_inventory_pressed() -> void:
	# Toggle inventory panel visibility
	var inventory_panel = get_node_or_null("/root/Main/InventoryPanel")
	if inventory_panel:
		inventory_panel.toggle_visibility()
	else:
		push_warning("TopbarUIUX: InventoryPanel not found!")

func _on_timer_tick(time_left: int) -> void:
	_update_timer_display(time_left)

func _on_timer_reset() -> void:
	# Visual feedback when timer resets (optional: add flash effect, etc.)
	pass

func _on_turn_changed(turn: int) -> void:
	_update_turn_display(turn)

func _update_timer_display(time_left: int) -> void:
	if timer_label:
		var timer_format = I18n.translate("ui.hud.timer")
		timer_label.text = timer_format % time_left

func _update_turn_display(turn: int) -> void:
	if turn_label:
		var turn_format = I18n.translate("ui.hud.turn")
		turn_label.text = turn_format % turn

func _on_resource_changed(kind: int, current: float, cap: float, rate: float) -> void:
	_update_resource_display(kind, current, cap, rate)

func _update_resource_display(kind: int, current: float, cap: float, rate: float) -> void:
	# ResourceType enum: GOLD=0, FOOD=1, LABOR=2, FAITH=3 (matches Rust)
	# Update target values - the _process loop will animate the numbers
	match kind:
		0:  # GOLD
			target_gold = current
		1:  # FOOD
			target_food = current
		2:  # LABOR
			target_labor = current
		3:  # FAITH
			target_faith = current
