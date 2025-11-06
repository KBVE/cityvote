extends PanelContainer
class_name ChatToggleButton

# Compact chat toggle - just shows expand button and quick input
# The actual messages are always in ChatPanel (single source of truth)
# This just controls showing ChatPanel in mini vs full mode

@onready var expand_button: Button = $MarginContainer/VBoxContainer/InputRow/ExpandButton
@onready var quick_input: LineEdit = $MarginContainer/VBoxContainer/InputRow/QuickInput

var is_expanded: bool = false

func _ready() -> void:
	# Apply font
	_apply_font()

	# Connect expand button
	if expand_button:
		expand_button.pressed.connect(_on_expand_pressed)

	# Connect quick input to send messages
	if quick_input:
		quick_input.text_submitted.connect(_on_quick_message_submitted)

	# Connect to IRC client to receive messages and check connection
	var irc_client = get_node_or_null("/root/IrcWebSocketClient")
	if irc_client:
		irc_client.irc_message_received.connect(_on_message_received)
		irc_client.irc_connected.connect(_on_irc_connected)
		irc_client.irc_disconnected.connect(_on_irc_disconnected)

		# Check if already connected
		if irc_client.is_irc_connected():
			_on_irc_connected()

	# Connect to language change
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

	# Update button text with translations
	_update_button_text()

	# Initialize ChatPanel to compact mode - position it ABOVE the toggle button
	var chat_panel = get_node_or_null("/root/Main/ChatPanel")
	if chat_panel:
		# Position ChatPanel above the toggle button so they don't overlap
		chat_panel.position = Vector2(10, 380)  # Above toggle button at y=550
		chat_panel.size = Vector2(400, 130)     # Smaller height for compact mode
		chat_panel.visible = true

func _apply_font() -> void:
	var font = Cache.get_font_for_current_language()
	if font:
		if expand_button:
			expand_button.add_theme_font_override("font", font)
		if quick_input:
			quick_input.add_theme_font_override("font", font)

func _on_language_changed(_new_language: int) -> void:
	_apply_font()
	_update_button_text()
	# Update placeholder text based on current connection state
	var irc_client = get_node_or_null("/root/IrcWebSocketClient")
	if irc_client:
		if irc_client.is_irc_connected():
			_on_irc_connected()
		else:
			_on_irc_disconnected()

func _update_button_text() -> void:
	if expand_button:
		if is_expanded:
			expand_button.text = I18n.translate("chat.minimize")
		else:
			expand_button.text = I18n.translate("chat.expand")

func _on_irc_connected() -> void:
	# Enable quick input when connected
	if quick_input:
		quick_input.editable = true
		quick_input.placeholder_text = I18n.translate("chat.quick_placeholder")

func _on_irc_disconnected() -> void:
	# Disable quick input when disconnected
	if quick_input:
		quick_input.editable = false
		quick_input.placeholder_text = I18n.translate("chat.not_connected_placeholder")

func _on_message_received(channel: String, sender: String, message: String) -> void:
	# Messages are handled by ChatPanel - no action needed here
	pass

func _on_quick_message_submitted(text: String) -> void:
	if text.is_empty():
		return

	# Send message via IRC client
	var irc_client = get_node_or_null("/root/IrcWebSocketClient")
	if irc_client and irc_client.is_irc_connected():
		irc_client.send_message("#general", text)

		# Echo our own message to the chat panel (same as ChatPanel does)
		var chat_panel = get_node_or_null("/root/Main/ChatPanel")
		if chat_panel:
			# Get player name
			var player_name = "Player"
			if Cache and Cache.has_value("player_name"):
				player_name = Cache.get_value("player_name", "Player")

			var nickname = "CityVote_%s" % player_name
			chat_panel._add_message(nickname, text, 0)  # MessageType::Channel

		quick_input.clear()
	else:
		print("[ChatToggleButton] Cannot send message - not connected")

func _on_expand_pressed() -> void:
	# Toggle between compact and full chat modes
	# ChatPanel is always visible, we just resize it
	var chat_panel = get_node_or_null("/root/Main/ChatPanel")
	if not chat_panel:
		push_warning("[ChatToggleButton] ChatPanel not found at /root/Main/ChatPanel")
		return

	if not is_expanded:
		# Expanding: Animate from compact to full chat
		is_expanded = true

		# Switch to full mode (show header and input)
		chat_panel._set_compact_mode(false)

		# Compact position and size (bottom-left, shows ~5 messages)
		var start_pos = Vector2(10, 550)
		var start_size = Vector2(400, 160)

		# Full chat position and size
		var end_pos = Vector2(10, 300)
		var end_size = Vector2(500, 400)

		# Ensure chat panel is visible and at start position
		chat_panel.visible = true
		chat_panel.position = start_pos
		chat_panel.size = start_size

		# Tween to full size
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(chat_panel, "position", end_pos, 0.3)
		tween.tween_property(chat_panel, "size", end_size, 0.3)

		# Update button text and hide toggle controls
		expand_button.text = I18n.translate("chat.minimize")
		await tween.finished
		visible = false
	else:
		# Minimizing: Animate from full chat back to compact
		is_expanded = false

		# Show toggle controls
		visible = true
		expand_button.text = I18n.translate("chat.expand")

		# Full chat position and size
		var start_pos = Vector2(10, 300)
		var start_size = Vector2(500, 400)

		# Compact position and size - position above toggle button
		var end_pos = Vector2(10, 380)
		var end_size = Vector2(400, 130)

		# Tween to compact size
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(chat_panel, "position", end_pos, 0.3)
		tween.tween_property(chat_panel, "size", end_size, 0.3)

		# ChatPanel stays visible in compact mode
		await tween.finished

		# Switch back to compact mode (hide header and input, only show messages)
		chat_panel._set_compact_mode(true)
