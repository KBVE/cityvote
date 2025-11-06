extends Control
## hCaptcha Test Interface
## Tests hCaptcha integration via JavaScript bridge
## This will only work in WASM builds (browser environment)

@onready var panel: PanelContainer = $Panel
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var token_label: Label = $Panel/VBoxContainer/TokenLabel
@onready var show_button: Button = $Panel/VBoxContainer/ButtonContainer/ShowButton
@onready var hide_button: Button = $Panel/VBoxContainer/ButtonContainer/HideButton
@onready var reset_button: Button = $Panel/VBoxContainer/ButtonContainer/ResetButton
@onready var get_response_button: Button = $Panel/VBoxContainer/ButtonContainer/GetResponseButton
@onready var close_button: Button = $Panel/VBoxContainer/CloseButtonContainer/CloseButton

signal captcha_closed(token: String)

var is_initialized: bool = false
var last_token: String = ""

func _ready() -> void:
	# Center the panel on screen using offsets
	_center_panel()

	# Apply fonts
	_apply_fonts()

	# Connect button signals
	show_button.pressed.connect(_on_show_pressed)
	hide_button.pressed.connect(_on_hide_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	get_response_button.pressed.connect(_on_get_response_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Initialize hCaptcha
	_initialize_hcaptcha()

	_update_status("Ready to test hCaptcha")

func _apply_fonts() -> void:
	var font = Cache.get_font_for_current_language() if Cache else null
	if font == null:
		return

	if status_label:
		status_label.add_theme_font_override("font", font)
	if token_label:
		token_label.add_theme_font_override("font", font)
	if show_button:
		show_button.add_theme_font_override("font", font)
	if hide_button:
		hide_button.add_theme_font_override("font", font)
	if reset_button:
		reset_button.add_theme_font_override("font", font)
	if get_response_button:
		get_response_button.add_theme_font_override("font", font)
	if close_button:
		close_button.add_theme_font_override("font", font)

func _initialize_hcaptcha() -> void:
	# Check if running in browser (WASM)
	if OS.has_feature("web"):
		_update_status("Initializing hCaptcha...")

		# Initialize hCaptcha with callback
		var js_code = """
		(function() {
			try {
				// Define callback function that will be called when captcha is completed
				window.hcaptchaTestCallback = function(token) {
					console.log('[hCaptcha Test] Token received:', token.substring(0, 20) + '...');
					// Store token in a global variable that GDScript can read
					window.lastHCaptchaToken = token;
				};

				// Initialize hCaptcha (uses default site key from custom_shell.html)
				var result = window.initHCaptcha(null, window.hcaptchaTestCallback);

				if (result) {
					console.log('[hCaptcha Test] Initialization successful');
					return 'SUCCESS';
				} else {
					console.error('[hCaptcha Test] Initialization failed');
					return 'FAILED';
				}
			} catch (e) {
				console.error('[hCaptcha Test] Error:', e);
				return 'ERROR: ' + e.message;
			}
		})();
		"""

		var result = JavaScriptBridge.eval(js_code)

		if result == "SUCCESS":
			is_initialized = true
			_update_status("hCaptcha initialized successfully")
		else:
			_update_status("Failed to initialize: " + str(result))
	else:
		_update_status("hCaptcha only works in browser (WASM builds)")
		show_button.disabled = true
		hide_button.disabled = true
		reset_button.disabled = true
		get_response_button.disabled = true

func _on_show_pressed() -> void:
	if not is_initialized:
		_update_status("Error: hCaptcha not initialized")
		return

	_update_status("Showing hCaptcha challenge...")
	var result = JavaScriptBridge.eval("window.showHCaptcha()")

	if result:
		_update_status("hCaptcha challenge displayed")
	else:
		_update_status("Failed to show hCaptcha")

func _on_hide_pressed() -> void:
	if not is_initialized:
		_update_status("Error: hCaptcha not initialized")
		return

	_update_status("Hiding hCaptcha challenge...")
	JavaScriptBridge.eval("window.hideHCaptcha()")
	_update_status("hCaptcha challenge hidden")

func _on_reset_pressed() -> void:
	if not is_initialized:
		_update_status("Error: hCaptcha not initialized")
		return

	_update_status("Resetting hCaptcha...")
	var result = JavaScriptBridge.eval("window.resetHCaptcha()")

	if result:
		_update_status("hCaptcha reset successfully")
		last_token = ""
		_update_token("")
	else:
		_update_status("Failed to reset hCaptcha")

func _on_get_response_pressed() -> void:
	if not is_initialized:
		_update_status("Error: hCaptcha not initialized")
		return

	_update_status("Getting hCaptcha response...")

	# Get token from the global variable set by callback
	var token = JavaScriptBridge.eval("window.lastHCaptchaToken || null")

	if token and token != "null":
		last_token = str(token)
		_update_status("Token received successfully!")
		_update_token(last_token)
		print("[hCaptcha Test] Full token: ", last_token)
	else:
		_update_status("No token available - complete the captcha first")
		_update_token("")

func _update_status(message: String) -> void:
	if status_label:
		status_label.text = "Status: " + message
	print("[hCaptcha Test] ", message)

func _update_token(token: String) -> void:
	if token_label:
		if token.is_empty():
			token_label.text = "Token: (none)"
		else:
			# Show first 40 characters of token
			var display_token = token.substr(0, 40) + "..." if token.length() > 40 else token
			token_label.text = "Token: " + display_token

# Public method to get the last received token
func get_token() -> String:
	return last_token

# Public method to check if captcha was completed
func is_captcha_completed() -> bool:
	return not last_token.is_empty()

func _on_close_pressed() -> void:
	# Hide hCaptcha before closing
	if is_initialized:
		JavaScriptBridge.eval("window.hideHCaptcha()")

	# Emit signal with token (may be empty if not completed)
	captcha_closed.emit(last_token)

	# Remove this interface
	queue_free()

func _center_panel() -> void:
	# Wait for the panel to be ready and sized
	await get_tree().process_frame

	if panel:
		# Get viewport size
		var viewport_size = get_viewport().get_visible_rect().size

		# Get panel size
		var panel_size = panel.size

		# Calculate centered position
		var centered_x = (viewport_size.x - panel_size.x) / 2.0
		var centered_y = (viewport_size.y - panel_size.y) / 2.0

		# Set position using offsets
		panel.position = Vector2(centered_x, centered_y)
