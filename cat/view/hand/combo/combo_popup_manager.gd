extends Node
class_name ComboPopupManager

## ComboPopupManager (Autoload Singleton)
## Manages display of card combo popups
## Usage: ComboPopup.show_combo(combo_data)

signal combo_accepted_by_player(combo_data: Dictionary)
signal combo_declined_by_player(combo_data: Dictionary)

const COMBO_POPUP_SCENE = preload("res://view/hand/combo/combo_popup.tscn")

var current_popup: ComboPopupPanel = null
var popup_container: Control = null
var ui_layer: CanvasLayer = null
var is_popup_active: bool = false

func _ready() -> void:
	# Create UI layer for combo popup
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 105  # Above toasts (103) and other UI
	add_child(ui_layer)

	# Create container for popup
	popup_container = Control.new()
	popup_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(popup_container)

	# Connect to CardComboBridge signal if available
	if CardComboBridge:
		CardComboBridge.combo_detected.connect(_on_combo_detected_bridge)

## Public API to show a combo popup
## combo_data: Dictionary with keys: hand_name, bonus_multiplier, resource_bonuses
func show_combo(combo_data: Dictionary) -> void:
	# Remove current popup immediately if showing (skip animation for instant replacement)
	if current_popup and is_instance_valid(current_popup):
		current_popup.queue_free()
		current_popup = null

	# Create new popup
	current_popup = COMBO_POPUP_SCENE.instantiate() as ComboPopupPanel
	popup_container.add_child(current_popup)

	# Center popup on screen
	var viewport_size = get_viewport().get_visible_rect().size
	current_popup.position = Vector2(
		(viewport_size.x - current_popup.size.x) / 2,
		viewport_size.y * 0.3  # 30% from top
	)

	# Mark popup as active (blocks player input)
	is_popup_active = true

	# Show combo
	current_popup.show_combo(combo_data)
	current_popup.dismissed.connect(_on_popup_dismissed)
	current_popup.combo_accepted.connect(_on_combo_accepted)
	current_popup.combo_declined.connect(_on_combo_declined)

## Called when CardComboBridge detects a combo (from signal)
func _on_combo_detected_bridge(request_id: int, result: Dictionary) -> void:
	print("ComboPopupManager._on_combo_detected_bridge called:")
	print("  request_id parameter: ", request_id)
	print("  result.has('request_id'): ", result.has("request_id"))
	if result.has("request_id"):
		print("  result['request_id']: ", result["request_id"])
	print("  result keys: ", result.keys())

	# The result already has all the data we need including resources
	# Ensure request_id is in the result (should already be there from CardComboBridge)
	if not result.has("request_id"):
		print("  WARNING: request_id missing from result, adding it now")
		result["request_id"] = request_id

	if result.has("hand_name"):
		print("  Calling show_combo with result")
		show_combo(result)
	else:
		print("  ERROR: result missing hand_name, not showing combo")

func _on_popup_dismissed() -> void:
	is_popup_active = false
	if current_popup and is_instance_valid(current_popup):
		current_popup.queue_free()
		current_popup = null

## Called when player accepts the combo
func _on_combo_accepted(combo_data: Dictionary) -> void:
	print("ComboPopupManager: Player accepted combo - %s" % combo_data.get("hand_name", "Unknown"))

	# Apply resources via Rust (SECURE: Rust-authoritative)
	var request_id = combo_data.get("request_id", 0)
	print("  -> Request ID: %d" % request_id)
	print("  -> CardComboBridge available: %s" % (CardComboBridge != null))

	if request_id > 0 and CardComboBridge:
		print("  -> Calling CardComboBridge.accept_combo(%d)..." % request_id)
		var success = CardComboBridge.accept_combo(request_id)
		print("  -> Result: %s" % ("SUCCESS" if success else "FAILED"))
		if not success:
			push_error("ComboPopupManager: Failed to apply combo rewards! Invalid request_id: %d" % request_id)
		else:
			print("  -> Rewards should be applied by Rust!")
	else:
		push_error("ComboPopupManager: Missing request_id in combo_data or CardComboBridge not available!")

	# Emit signal for play_hand.gd to clear cards
	combo_accepted_by_player.emit(combo_data)

## Called when player declines the combo
func _on_combo_declined(combo_data: Dictionary) -> void:
	print("ComboPopupManager: Player declined combo - %s" % combo_data.get("hand_name", "Unknown"))

	# Notify Rust to remove from pending combos
	var request_id = combo_data.get("request_id", 0)
	if request_id > 0 and CardComboBridge:
		CardComboBridge.decline_combo(request_id)

	# Emit signal for play_hand.gd to remove highlights
	combo_declined_by_player.emit(combo_data)

## DEPRECATED: Apply combo resources to player's resource ledger
## DO NOT USE: This function is insecure - rewards should be applied via Rust
## Use CardComboBridge.accept_combo(request_id) instead
func apply_combo_resources(combo_data: Dictionary) -> void:
	push_error("ComboPopupManager: apply_combo_resources() is DEPRECATED and INSECURE!")
	push_error("  Use CardComboBridge.accept_combo(request_id) instead")
	push_error("  Client-side reward application can be manipulated by malicious clients")
