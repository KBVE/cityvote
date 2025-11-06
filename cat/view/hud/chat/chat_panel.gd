extends PanelContainer
class_name ChatPanel

# IRC Chat Panel - displays messages and allows sending
# Follows the same pattern as TopbarUIUX

# UI References
@onready var message_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/MessageContainer
@onready var scroll_container: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var input_field: LineEdit = $MarginContainer/VBoxContainer/InputContainer/MessageInput
@onready var send_button: Button = $MarginContainer/VBoxContainer/InputContainer/SendButton
@onready var connect_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/ConnectButton
@onready var minimize_button: Button = $MarginContainer/VBoxContainer/HeaderContainer/MinimizeButton
@onready var channel_label: Label = $MarginContainer/VBoxContainer/HeaderContainer/ChannelLabel
@onready var compact_controls: HBoxContainer = $MarginContainer/VBoxContainer/CompactControls
@onready var expand_button: Button = $MarginContainer/VBoxContainer/CompactControls/ExpandButton
@onready var quick_input: LineEdit = $MarginContainer/VBoxContainer/CompactControls/QuickInput

# State
var is_connected: bool = false
var current_channel: String = "#general"  # IRC channel from GDScript IRC client
var player_name: String = "Player"  # Will be set from game state
var max_visible_messages: int = 100  # Keep message list from growing too large
var is_expanded: bool = false  # Track if chat is in maximized state

# Reference to IRC WebSocket client singleton
@onready var irc_client = get_node("/root/IrcWebSocketClient")

# Message type colors (matching Rust MessageType enum)
# Brighter colors for better readability in compact mode
const MESSAGE_COLORS = {
	0: Color(1.0, 1.0, 1.0),      # Channel - Bright White
	1: Color(0.9, 0.7, 1.0),      # Private - Bright Purple
	2: Color(0.8, 0.85, 0.9),     # System - Bright Gray/Blue
	3: Color(1.0, 0.5, 0.5),      # Error - Bright Red
}

func _ready() -> void:
	# Apply fonts
	_apply_fonts()

	# Connect button signals
	if send_button:
		send_button.pressed.connect(_on_send_pressed)

	if connect_button:
		connect_button.pressed.connect(_on_connect_pressed)

	if minimize_button:
		minimize_button.pressed.connect(_on_minimize_pressed)

	if expand_button:
		expand_button.pressed.connect(_on_expand_pressed)

	if quick_input:
		quick_input.text_submitted.connect(_on_quick_input_submitted)

	if input_field:
		input_field.text_submitted.connect(_on_text_submitted)

	# Connect to IrcWebSocketClient signals
	if irc_client:
		print("[ChatPanel] Connecting to IRC client signals...")
		irc_client.irc_connected.connect(_on_irc_connected)
		irc_client.irc_disconnected.connect(_on_irc_disconnected)
		irc_client.irc_message_received.connect(_on_irc_message_received)
		irc_client.irc_joined_channel.connect(_on_irc_joined_channel)
		print("[ChatPanel] Signals connected successfully")

		# Check if already connected (in case we missed the signal)
		if irc_client.is_irc_connected():
			print("[ChatPanel] IRC already connected, updating UI immediately")
			_on_irc_connected()
	else:
		push_error("[ChatPanel] Could not find IrcWebSocketClient singleton!")

	# Get player name from Cache
	if Cache and Cache.has_value("player_name"):
		player_name = Cache.get_value("player_name", "Player")
		print("[ChatPanel] Loaded player name from Cache: ", player_name)

	# Connect to language changes
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

	# Initialize UI state
	_update_connection_state()
	_update_channel_label()
	_update_button_text()

	# IRC client auto-connects on _ready() - no need for initialization message

	# Start in compact mode
	position = Vector2(10, 550)
	size = Vector2(400, 160)
	_set_compact_mode(true)

	# Double-check connection status after a brief delay (for race conditions)
	# Use a timer to allow websocket connection to complete
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 0.5  # Check after 500ms
	timer.one_shot = true
	timer.timeout.connect(_check_delayed_connection)
	timer.start()

func _input(event: InputEvent) -> void:
	# Handle ESC key to minimize chat when expanded
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Only handle if chat is visible (expanded mode)
		if visible and not _is_compact():
			_on_minimize_pressed()
			get_viewport().set_input_as_handled()

func _is_compact() -> bool:
	# Check if we're in compact mode
	var header = get_node_or_null("MarginContainer/VBoxContainer/HeaderContainer")
	return header and not header.visible

func _set_compact_mode(compact: bool) -> void:
	# In compact mode: hide header and full input, show compact controls, hide scrollbar
	# In full mode: show header and full input, hide compact controls, show scrollbar
	var header = get_node_or_null("MarginContainer/VBoxContainer/HeaderContainer")
	var input_container = get_node_or_null("MarginContainer/VBoxContainer/InputContainer")

	if header:
		header.visible = not compact
	if input_container:
		input_container.visible = not compact
	if compact_controls:
		compact_controls.visible = compact

	# Control scrollbar visibility: hidden in compact mode, auto in expanded mode
	if scroll_container:
		if compact:
			scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		else:
			scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

func _on_expand_pressed() -> void:
	# Expand chat to full size
	is_expanded = true
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", Vector2(10, 300), 0.3)
	tween.tween_property(self, "size", Vector2(500, 400), 0.3)
	await tween.finished
	_set_compact_mode(false)

func _on_minimize_pressed() -> void:
	# Minimize chat to compact size
	is_expanded = false
	_set_compact_mode(true)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", Vector2(10, 550), 0.3)
	tween.tween_property(self, "size", Vector2(400, 160), 0.3)

func _on_quick_input_submitted(text: String) -> void:
	if text.is_empty():
		return
	if not is_connected:
		return
	if irc_client:
		irc_client.send_message(current_channel, text)
		var nickname = "CityVote_%s" % player_name
		_add_message(nickname, text, 0)
	quick_input.clear()

func _apply_fonts() -> void:
	var font = Cache.get_font_for_current_language()
	if font == null:
		push_warning("ChatPanel: Could not load font from Cache")
		return

	if minimize_button:
		minimize_button.add_theme_font_override("font", font)

	if channel_label:
		channel_label.add_theme_font_override("font", font)
	if input_field:
		input_field.add_theme_font_override("font", font)
	if send_button:
		send_button.add_theme_font_override("font", font)
	if connect_button:
		connect_button.add_theme_font_override("font", font)
	if expand_button:
		expand_button.add_theme_font_override("font", font)
	if quick_input:
		quick_input.add_theme_font_override("font", font)

func _on_language_changed(_new_language: int) -> void:
	_apply_fonts()
	_update_connection_state()
	_update_channel_label()
	_update_button_text()

func _update_button_text() -> void:
	if minimize_button:
		minimize_button.text = I18n.translate("chat.minimize")
	if send_button:
		send_button.text = I18n.translate("chat.send")

func _on_connect_pressed() -> void:
	if not is_connected:
		# IRC client auto-connects on startup - if disconnected, try reconnecting
		if irc_client:
			irc_client._connect_to_irc()
	else:
		# Disconnect from IRC
		if irc_client:
			irc_client.disconnect_irc()
		_add_system_message(I18n.translate("chat.disconnecting"))

func _on_send_pressed() -> void:
	_send_message()

func _on_text_submitted(_text: String) -> void:
	_send_message()

func _send_message() -> void:
	if not input_field:
		return

	var message = input_field.text.strip_edges()
	if message.is_empty():
		return

	if not is_connected:
		_add_error_message(I18n.translate("chat.not_connected_error"))
		return

	# Send message via IrcWebSocketClient
	if irc_client:
		irc_client.send_message(current_channel, message)
		# Echo our own message locally
		var nickname = "CityVote_%s" % player_name
		_add_message(nickname, message, 0)  # MessageType::Channel

	# Clear input field
	input_field.text = ""

func _add_message(sender: String, message: String, msg_type: int) -> void:
	if not message_container:
		return

	# Create message label
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 400  # Ensure proper wrapping

	# Format message
	var formatted_text = ""
	if msg_type == 2:  # System message
		formatted_text = "* %s" % message
	elif msg_type == 3:  # Error message
		formatted_text = "! %s" % message
	else:
		formatted_text = "<%s> %s" % [sender, message]

	label.text = formatted_text

	# Apply color based on message type
	if msg_type in MESSAGE_COLORS:
		label.add_theme_color_override("font_color", MESSAGE_COLORS[msg_type])

	# Apply font with larger size for better readability in compact mode
	var font = Cache.get_font_for_current_language()
	if font:
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 16)  # Increased from 14 to 16

	# Add subtle text outline for better readability
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))

	# Add to container
	message_container.add_child(label)

	# Limit message count to prevent memory issues
	while message_container.get_child_count() > max_visible_messages:
		var oldest = message_container.get_child(0)
		message_container.remove_child(oldest)
		oldest.queue_free()

	# Auto-scroll to bottom
	await get_tree().process_frame
	if scroll_container:
		scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _add_system_message(message: String) -> void:
	_add_message("*", message, 2)

func _add_error_message(message: String) -> void:
	_add_message("!", message, 3)

func _update_connection_state() -> void:
	if connect_button:
		if is_connected:
			connect_button.text = I18n.translate("chat.disconnect")
			connect_button.modulate = Color(1.0, 0.4, 0.4)  # Red tint
		else:
			connect_button.text = I18n.translate("chat.connect")
			connect_button.modulate = Color(0.4, 1.0, 0.4)  # Green tint

	# Enable/disable input based on connection
	if input_field:
		input_field.editable = is_connected
		if is_connected:
			input_field.placeholder_text = I18n.translate("chat.placeholder")
		else:
			input_field.placeholder_text = I18n.translate("chat.not_connected_placeholder")
	if quick_input:
		quick_input.editable = is_connected
		if is_connected:
			quick_input.placeholder_text = I18n.translate("chat.quick_placeholder")
		else:
			quick_input.placeholder_text = I18n.translate("chat.not_connected_placeholder")
	if send_button:
		send_button.disabled = not is_connected

func _update_channel_label() -> void:
	if channel_label:
		if is_connected:
			channel_label.text = I18n.translate("chat.channel", [current_channel])
		else:
			channel_label.text = I18n.translate("chat.not_connected")

# ========================================================================
# IRC EVENT HANDLERS (from IrcWebSocketClient signals)
# ========================================================================

func _on_irc_connected() -> void:
	print("[ChatPanel] _on_irc_connected() called!")
	is_connected = true
	_update_connection_state()
	_update_channel_label()
	var nickname = "CityVote_%s" % player_name
	_add_system_message(I18n.translate("chat.connected_as", [nickname]))
	print("[ChatPanel] UI updated - is_connected=%s" % is_connected)

func _on_irc_disconnected() -> void:
	is_connected = false
	_update_connection_state()
	_update_channel_label()
	_add_system_message(I18n.translate("chat.disconnected"))

func _on_irc_message_received(channel: String, sender: String, message: String) -> void:
	if channel == current_channel:
		_add_message(sender, message, 0)  # MessageType::Channel

func _on_irc_joined_channel(channel: String) -> void:
	_add_system_message(I18n.translate("chat.joined_channel", [channel]))
	current_channel = channel
	_update_channel_label()

# ========================================================================
# PUBLIC METHODS
# ========================================================================

func set_player_name(name: String) -> void:
	player_name = name

func toggle_visibility() -> void:
	visible = not visible

func _check_delayed_connection() -> void:
	# Check connection status after _ready() completes
	if irc_client and irc_client.is_irc_connected():
		print("[ChatPanel] Delayed check: IRC is connected, updating UI")
		_on_irc_connected()
