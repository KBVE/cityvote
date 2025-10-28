extends Node
class_name ToastManager

# Toast notification manager (Autoload Singleton)
# Handles queue and display of toast messages
# Toasts appear in top right corner, below the topbar
# Usage: Toast.show_toast("Your message here", 3.0)

const TOAST_ITEM_SCENE = preload("res://view/hud/toast/toast_item.tscn")
const MAX_VISIBLE_TOASTS: int = 5

var toast_queue: Array[Dictionary] = []  # {message: String, duration: float}
var active_toasts: Array[ToastItem] = []
var toast_container: VBoxContainer = null
var ui_layer: CanvasLayer = null

func _ready() -> void:
	# Create UI layer for toasts
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 103  # Above other UI elements
	add_child(ui_layer)

	# Create container for toast items
	var control = Control.new()
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(control)

	toast_container = VBoxContainer.new()
	toast_container.position = Vector2(1010, 80)  # Top right, below topbar
	toast_container.custom_minimum_size = Vector2(260, 0)
	toast_container.add_theme_constant_override("separation", 10)
	toast_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.add_child(toast_container)

# Public API to show a toast message
func show_toast(message: String, duration: float = 3.0) -> void:
	# If at max capacity, queue it
	if active_toasts.size() >= MAX_VISIBLE_TOASTS:
		toast_queue.append({"message": message, "duration": duration})
		return

	# Create and display toast
	_create_toast(message, duration)

func _create_toast(message: String, duration: float) -> void:
	var toast = TOAST_ITEM_SCENE.instantiate() as ToastItem
	toast_container.add_child(toast)
	toast.setup(message, duration)
	toast.dismissed.connect(_on_toast_dismissed)
	active_toasts.append(toast)

func _on_toast_dismissed(toast: ToastItem) -> void:
	# Remove from active list
	var idx = active_toasts.find(toast)
	if idx >= 0:
		active_toasts.remove_at(idx)

	# Remove from scene
	toast.queue_free()

	# Process queue if there are pending toasts
	if toast_queue.size() > 0:
		var next_toast = toast_queue.pop_front()
		_create_toast(next_toast["message"], next_toast["duration"])
