extends Control
class_name BrowserControl

# Browser Control - outermost container for browser system
# Contains BrowserPanel -> BrowserContainer -> Browser (wry) hierarchy
# Can be toggled on/off via topbar button

@onready var close_button: Button = $BrowserPanel/MarginContainer/VBoxContainer/HeaderBar/CloseButton
@onready var browser_container: Control = $BrowserPanel/MarginContainer/VBoxContainer/BrowserContainer

var browser: Object = null  # GodotBrowser instance (Rust)
var is_visible_panel: bool = false

func _ready() -> void:
	# Start hidden
	visible = false
	is_visible_panel = false

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Create browser instance (only on macOS/Windows)
	if ClassDB.class_exists("GodotBrowser"):
		# Create browser and add it directly to the container
		browser = ClassDB.instantiate("GodotBrowser")
		if browser:
			browser_container.add_child(browser)

			# Anchor browser to fill the container
			browser.set_anchors_preset(Control.PRESET_FULL_RECT)
			browser.set_anchor(SIDE_LEFT, 0.0)
			browser.set_anchor(SIDE_TOP, 0.0)
			browser.set_anchor(SIDE_RIGHT, 1.0)
			browser.set_anchor(SIDE_BOTTOM, 1.0)
			browser.set_offset(SIDE_LEFT, 0.0)
			browser.set_offset(SIDE_TOP, 0.0)
			browser.set_offset(SIDE_RIGHT, 0.0)
			browser.set_offset(SIDE_BOTTOM, 0.0)

			# Set browser properties
			browser.url = "https://kbve.com/"
			browser.transparent = false
			browser.devtools = true

			# Hide browser initially (off-screen with 0 size)
			if browser.has_method("set_browser_visible"):
				# Wait for layout to be calculated before positioning
				await get_tree().process_frame
				await get_tree().process_frame
				browser.set_browser_visible(false)

			# Connect to resize notifications
			get_viewport().size_changed.connect(_on_viewport_size_changed)

			print("[BrowserControl] GodotBrowser initialized successfully (hidden)")
			print("[BrowserControl] BrowserContainer global pos: ", browser_container.get_global_position())
			print("[BrowserControl] BrowserContainer size: ", browser_container.get_size())
		else:
			push_error("[BrowserControl] Failed to instantiate GodotBrowser")
	else:
		print("[BrowserControl] GodotBrowser not available (macOS/Windows only)")
		# Show a message instead
		var label = Label.new()
		label.text = "Browser not available on this platform\n(macOS/Windows only)"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		browser_container.add_child(label)

func toggle_visibility() -> void:
	is_visible_panel = not is_visible_panel
	visible = is_visible_panel

	if browser and browser.has_method("set_browser_visible"):
		if is_visible_panel:
			# Show and resize browser to fit container
			await get_tree().process_frame
			await get_tree().process_frame  # Wait one more frame for layout

			# Debug: Print browser position and size
			print("[BrowserControl] Browser global pos: ", browser.get_global_position())
			print("[BrowserControl] Browser size: ", browser.get_size())
			print("[BrowserControl] BrowserContainer global pos: ", browser_container.get_global_position())
			print("[BrowserControl] BrowserContainer size: ", browser_container.get_size())

			# Force a resize before showing
			if browser.has_method("resize"):
				browser.resize()

			browser.set_browser_visible(true)
		else:
			# Hide browser (move off-screen with 0 size)
			browser.set_browser_visible(false)

func _on_close_pressed() -> void:
	toggle_visibility()

func _on_viewport_size_changed() -> void:
	# Resize browser when viewport changes
	if is_visible_panel and browser and browser.has_method("resize"):
		browser.resize()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		# Handle window resize
		if is_visible_panel and browser and browser.has_method("resize"):
			browser.resize()
