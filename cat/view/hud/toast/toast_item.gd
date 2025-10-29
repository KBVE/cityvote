extends PanelContainer
class_name ToastItem

# Individual toast notification item
# Auto-dismisses after duration, or can be manually dismissed

signal dismissed(toast: ToastItem)

@onready var message_label: Label = $MarginContainer/HBoxContainer/MessageLabel
@onready var dismiss_button: Button = $MarginContainer/HBoxContainer/DismissButton

var auto_dismiss_time: float = 3.0  # Default 3 seconds
var _timer: float = 0.0
var _is_active: bool = false

func _ready() -> void:
	dismiss_button.pressed.connect(_on_dismiss_pressed)

	# Apply Alagard font
	var font = Cache.get_font_for_current_language()
	if font:
		message_label.add_theme_font_override("font", font)
		dismiss_button.add_theme_font_override("font", font)
	else:
		push_warning("ToastItem: Could not load Alagard font from Cache")

	# Start hidden, will fade in
	modulate = Color(1, 1, 1, 0)

func setup(message: String, duration: float = 3.0) -> void:
	message_label.text = message
	auto_dismiss_time = duration
	_is_active = true
	_timer = 0.0

	# Fade in animation
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.3)

func _process(delta: float) -> void:
	if not _is_active:
		return

	_timer += delta
	if _timer >= auto_dismiss_time:
		dismiss()

func dismiss() -> void:
	if not _is_active:
		return

	_is_active = false

	# Fade out animation
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_callback(func(): dismissed.emit(self))

func _on_dismiss_pressed() -> void:
	dismiss()
