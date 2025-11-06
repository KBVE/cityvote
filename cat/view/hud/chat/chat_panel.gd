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
@onready var channel_label: Label = $MarginContainer/VBoxContainer/HeaderContainer/ChannelLabel

# State
var is_connected: bool = false
var current_channel: String = "#general"  # Changed from #cityvote to #general
var player_name: String = "Player"  # Will be set from game state
var max_visible_messages: int = 100  # Keep message list from growing too large

# Reference to UnifiedEventBridge singleton
@onready var event_bridge = get_node("/root/UnifiedEventBridge")

# Message type colors (matching Rust MessageType enum)
const MESSAGE_COLORS = {
	0: Color(1.0, 1.0, 1.0),      # Channel - White
	1: Color(0.8, 0.6, 1.0),      # Private - Purple
	2: Color(0.6, 0.6, 0.6),      # System - Gray
	3: Color(1.0, 0.3, 0.3),      # Error - Red
}

func _ready() -> void:
	# Apply fonts
	_apply_fonts()

	# Connect button signals
	if send_button:
		send_button.pressed.connect(_on_send_pressed)

	if connect_button:
		connect_button.pressed.connect(_on_connect_pressed)

	if input_field:
		input_field.text_submitted.connect(_on_text_submitted)

	# Connect to UnifiedEventBridge IRC signals
	event_bridge.irc_connected.connect(_on_irc_connected)
	event_bridge.irc_disconnected.connect(_on_irc_disconnected)
	event_bridge.irc_channel_message.connect(_on_channel_message)
	event_bridge.irc_private_message.connect(_on_private_message)
	event_bridge.irc_notice.connect(_on_notice)
	event_bridge.irc_error.connect(_on_error)
	event_bridge.irc_user_joined.connect(_on_user_joined)
	event_bridge.irc_user_parted.connect(_on_user_parted)
	event_bridge.irc_user_quit.connect(_on_user_quit)

	# Initialize UI state
	_update_connection_state()
	_update_channel_label()

	# Load any existing chat history from Rust
	_load_chat_history()

func _apply_fonts() -> void:
	var font = Cache.get_font_for_current_language()
	if font == null:
		push_warning("ChatPanel: Could not load font from Cache")
		return

	if channel_label:
		channel_label.add_theme_font_override("font", font)
	if input_field:
		input_field.add_theme_font_override("font", font)
	if send_button:
		send_button.add_theme_font_override("font", font)
	if connect_button:
		connect_button.add_theme_font_override("font", font)

func _on_connect_pressed() -> void:
	if not is_connected:
		# Connect to IRC
		event_bridge.irc_connect(player_name)
		_add_system_message("Connecting to IRC...")
	else:
		# Disconnect from IRC
		event_bridge.irc_disconnect("Leaving")
		_add_system_message("Disconnecting from IRC...")

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
		_add_error_message("Not connected to IRC!")
		return

	# Send message via UnifiedEventBridge
	event_bridge.irc_send_message(message)
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

	# Apply font
	var font = Cache.get_font_for_current_language()
	if font:
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 14)

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
			connect_button.text = "Disconnect"
			connect_button.modulate = Color(1.0, 0.4, 0.4)  # Red tint
		else:
			connect_button.text = "Connect"
			connect_button.modulate = Color(0.4, 1.0, 0.4)  # Green tint

	# Enable/disable input based on connection
	if input_field:
		input_field.editable = is_connected
	if send_button:
		send_button.disabled = not is_connected

func _update_channel_label() -> void:
	if channel_label:
		if is_connected:
			channel_label.text = "Channel: %s" % current_channel
		else:
			channel_label.text = "Not Connected"

func _load_chat_history() -> void:
	# Load last N messages from Rust DashMap via UnifiedEventBridge
	var messages = event_bridge.get_last_messages(current_channel, 50)
	for msg_dict in messages:
		var sender = msg_dict.get("sender", "")
		var message = msg_dict.get("message", "")
		var msg_type = msg_dict.get("msg_type", 0)
		_add_message(sender, message, msg_type)

# ========================================================================
# IRC EVENT HANDLERS (from UnifiedEventBridge signals)
# ========================================================================

func _on_irc_connected(nickname: String, server: String) -> void:
	is_connected = true
	_update_connection_state()
	_update_channel_label()
	_add_system_message("Connected to %s as %s" % [server, nickname])

func _on_irc_disconnected(reason: String) -> void:
	is_connected = false
	_update_connection_state()
	_update_channel_label()
	var msg = "Disconnected from IRC"
	if not reason.is_empty():
		msg += ": %s" % reason
	# If we weren't connected yet, this is likely a connection failure
	if not is_connected:
		_add_error_message("Connection failed: %s" % reason if not reason.is_empty() else "Unknown error")
	else:
		_add_system_message(msg)

func _on_channel_message(channel: String, sender: String, message: String) -> void:
	if channel == current_channel:
		_add_message(sender, message, 0)  # MessageType::Channel

func _on_private_message(sender: String, message: String) -> void:
	_add_message(sender, message, 1)  # MessageType::Private

func _on_notice(sender: String, message: String) -> void:
	var display_sender = sender if not sender.is_empty() else "Server"
	_add_message(display_sender, message, 2)  # MessageType::System

func _on_error(message: String) -> void:
	_add_error_message(message)

func _on_user_joined(channel: String, nickname: String) -> void:
	if channel == current_channel:
		_add_system_message("%s joined %s" % [nickname, channel])

func _on_user_parted(channel: String, nickname: String, message: String) -> void:
	if channel == current_channel:
		var msg = "%s left %s" % [nickname, channel]
		if not message.is_empty():
			msg += " (%s)" % message
		_add_system_message(msg)

func _on_user_quit(nickname: String, message: String) -> void:
	var msg = "%s quit" % nickname
	if not message.is_empty():
		msg += " (%s)" % message
	_add_system_message(msg)

# ========================================================================
# PUBLIC METHODS
# ========================================================================

func set_player_name(name: String) -> void:
	player_name = name

func toggle_visibility() -> void:
	visible = not visible
