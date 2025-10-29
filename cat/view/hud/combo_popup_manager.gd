extends Node
class_name ComboPopupManager

## ComboPopupManager (Autoload Singleton)
## Manages display of card combo popups
## Usage: ComboPopup.show_combo(combo_data)

const COMBO_POPUP_SCENE = preload("res://view/hud/combo_popup.tscn")

var current_popup: ComboPopupPanel = null
var popup_container: Control = null
var ui_layer: CanvasLayer = null

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
	# Dismiss current popup if showing
	if current_popup and is_instance_valid(current_popup):
		current_popup.dismiss()
		await current_popup.dismissed
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

	# Show combo
	current_popup.show_combo(combo_data)
	current_popup.dismissed.connect(_on_popup_dismissed)

## Called when CardComboBridge detects a combo (from signal)
func _on_combo_detected_bridge(request_id: int, result: Dictionary) -> void:
	# The result already has all the data we need including resources
	if result.has("hand_name"):
		show_combo(result)

func _on_popup_dismissed() -> void:
	if current_popup:
		current_popup.queue_free()
		current_popup = null

## Apply combo resources to player's resource ledger
func apply_combo_resources(combo_data: Dictionary) -> void:
	if not combo_data.has("resource_bonuses"):
		return

	var resource_bonuses: Array = combo_data.get("resource_bonuses", [])
	for bonus in resource_bonuses:
		if bonus is Dictionary:
			var resource_type: int = bonus.get("resource_type", 0)
			var amount: float = bonus.get("amount", 0.0)

			# Add to resource ledger
			if ResourceLedger:
				match resource_type:
					0:  # Gold
						ResourceLedger.add(ResourceLedger.R.GOLD, amount)
					1:  # Food
						ResourceLedger.add(ResourceLedger.R.FOOD, amount)
					2:  # Labor
						ResourceLedger.add(ResourceLedger.R.LABOR, amount)
					3:  # Faith
						ResourceLedger.add(ResourceLedger.R.FAITH, amount)

	print("ComboPopupManager: Applied combo resources to player")
