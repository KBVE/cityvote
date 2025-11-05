extends PanelContainer
class_name InventoryPanel

## Inventory Panel - Shows player's inventory items
## Toggleable via Inventory button in topbar

# UI elements
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/TitleBar/CloseButton
@onready var items_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ItemsContainer

# Inventory data (placeholder for now - will be populated from game state)
var inventory_items: Array[Dictionary] = []

func _ready() -> void:
	# Start hidden
	visible = false

	# Apply fonts
	_apply_fonts()

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Connect to language changes
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

	# Populate initial inventory (placeholder)
	_populate_inventory()

func _input(event: InputEvent) -> void:
	# Close panel when ESC is pressed (only if visible)
	if visible and event.is_action_pressed("ui_cancel"):
		hide_panel()
		get_viewport().set_input_as_handled()

func _apply_fonts() -> void:
	var font = Cache.get_font_for_current_language()
	if font == null:
		push_warning("InventoryPanel: Could not load font from Cache")
		return

	if title_label:
		title_label.add_theme_font_override("font", font)
	if close_button:
		close_button.add_theme_font_override("font", font)

func _on_language_changed(_new_language: int) -> void:
	_apply_fonts()
	_update_labels()

func _update_labels() -> void:
	if title_label:
		title_label.text = I18n.translate("ui.inventory.title")

## Toggle panel visibility
func toggle_visibility() -> void:
	visible = not visible
	if visible:
		_populate_inventory()

## Show panel
func show_panel() -> void:
	visible = true
	_populate_inventory()

## Hide panel
func hide_panel() -> void:
	visible = false

func _on_close_pressed() -> void:
	hide_panel()

## Populate inventory with items
func _populate_inventory() -> void:
	# Clear existing items
	if items_container:
		for child in items_container.get_children():
			child.queue_free()

	# Placeholder: Add some dummy items for testing
	# TODO: Replace with actual inventory system
	if inventory_items.is_empty():
		var placeholder_label = Label.new()
		placeholder_label.text = "Inventory system coming soon..."
		placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		items_container.add_child(placeholder_label)
	else:
		for item in inventory_items:
			var item_label = Label.new()
			item_label.text = "%s x%d" % [item.get("name", "Unknown"), item.get("count", 0)]
			items_container.add_child(item_label)
