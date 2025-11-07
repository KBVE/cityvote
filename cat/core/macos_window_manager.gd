extends Node
## MacOS Window Manager - Autoload for managing macOS window features
## Handles focus-based transparency and window management
## Only active on macOS builds

var macos_bridge = null
var is_macos: bool = false
var focus_tracking_enabled: bool = false
var last_focus_state: bool = true

# Transparency settings
var focused_alpha: float = 1.0      # Fully opaque when focused
var unfocused_alpha: float = 0.2    # 20% opaque when unfocused

func _ready() -> void:
	# Autoloads initialize very early - we need to wait for the window to be created
	# This happens after the scene tree is ready and main scene starts loading
	call_deferred("_initialize_macos_features")

func _initialize_macos_features() -> void:
	# Check if the bridge class exists
	if not ClassDB.class_exists("MacOSWindowBridge"):
		print("[MacOSWindowManager] MacOSWindowBridge class not found (not macOS build)")
		return

	# Create the bridge instance
	macos_bridge = ClassDB.instantiate("MacOSWindowBridge")
	if not macos_bridge:
		print("[MacOSWindowManager] Failed to instantiate MacOSWindowBridge")
		return

	add_child(macos_bridge)
	is_macos = macos_bridge.is_macos()

	if not is_macos:
		print("[MacOSWindowManager] Not running on macOS - features disabled")
		return

	# Wait for the main window to exist, then initialize (retry for up to 3 seconds)
	print("[MacOSWindowManager] Running on macOS - waiting for window...")

	# Wait a bit longer initially to give macOS time to create the NSWindow
	for _i in range(10):  # Wait ~166ms (10 frames at 60fps)
		await get_tree().process_frame

	# Now try to initialize with retries
	for attempt in range(180):  # 180 frames at 60fps = 3 seconds
		# Try to initialize
		if macos_bridge.initialize():
			print("[MacOSWindowManager] Window features initialized successfully (attempt ", attempt + 1, ")")
			focus_tracking_enabled = true
			return  # Success!

		# Wait before next attempt
		await get_tree().process_frame

	# If we get here, we timed out
	print("[MacOSWindowManager] Warning: Failed to initialize window features (window may not be ready)")

func _process(_delta: float) -> void:
	if not is_macos or not focus_tracking_enabled or not macos_bridge:
		return

	# Check if focus state changed and update transparency and border accordingly
	var current_focus = macos_bridge.is_window_focused()
	if current_focus != last_focus_state:
		last_focus_state = current_focus
		macos_bridge.update_focus_transparency()

		# Toggle border based on focus state
		# Focused: Show border (borderless = false)
		# Unfocused: Hide border (borderless = true)
		macos_bridge.set_borderless(not current_focus)

		if current_focus:
			print("[MacOSWindowManager] Window focused - opacity: ", focused_alpha, " border: visible")
		else:
			print("[MacOSWindowManager] Window unfocused - opacity: ", unfocused_alpha, " border: hidden")

## Set custom transparency values for focused/unfocused states
func configure_focus_transparency(focused: float, unfocused: float) -> bool:
	if not is_macos or not macos_bridge:
		return false

	focused_alpha = clamp(focused, 0.0, 1.0)
	unfocused_alpha = clamp(unfocused, 0.0, 1.0)

	var success = macos_bridge.enable_focus_based_transparency(focused_alpha, unfocused_alpha)
	if success:
		focus_tracking_enabled = true
		print("[MacOSWindowManager] Focus-based transparency configured: focused=", focused_alpha, " unfocused=", unfocused_alpha)

	return success

## Enable focus-based transparency with default values (1.0 focused, 0.8 unfocused)
func enable_focus_transparency() -> bool:
	return configure_focus_transparency(1.0, 0.8)

## Disable focus-based transparency and restore full opacity
func disable_focus_transparency() -> bool:
	if not is_macos or not macos_bridge:
		return false

	focus_tracking_enabled = false
	var success = macos_bridge.disable_focus_based_transparency()
	if success:
		print("[MacOSWindowManager] Focus-based transparency disabled")

	return success

## Set window transparency manually (0.0 = fully transparent, 1.0 = fully opaque)
func set_transparency(alpha: float) -> bool:
	if not is_macos or not macos_bridge:
		return false

	return macos_bridge.set_transparency(clamp(alpha, 0.0, 1.0))

## Enable or disable always-on-top mode
func set_always_on_top(enabled: bool) -> bool:
	if not is_macos or not macos_bridge:
		return false

	return macos_bridge.set_always_on_top(enabled)

## Check if window is currently focused
func is_focused() -> bool:
	if not is_macos or not macos_bridge:
		return true  # Assume focused on non-macOS

	return macos_bridge.is_window_focused()
