extends Node
## IRC WebSocket client for WASM builds
## In WASM, GDScript handles WebSocket connections directly since Emscripten WebSocket symbols
## are not available in SIDE_MODULEs. Native builds use the Rust implementation instead.

# IRC WebSocket server URL
@export var websocket_url = "wss://chat.kbve.com/webirc"
@export var irc_channel = "#general"

# WebSocketPeer instance
var socket: WebSocketPeer
var connected: bool = false
var authenticated: bool = false
var handshake_sent: bool = false
var nickname: String = ""

# Signals for IRC events
signal irc_connected()
signal irc_disconnected()
signal irc_message_received(channel: String, sender: String, message: String)
signal irc_joined_channel(channel: String)

func _ready():
	# Create WebSocketPeer
	socket = WebSocketPeer.new()

	# Use GDScript WebSocket for ALL platforms (native + WASM)
	# This avoids Rust thread spawning and Emscripten symbol issues
	print("[IRC/WebSocket] Using GDScript WebSocket (all platforms)")

	# Get player name from Cache (set by title screen)
	if Cache and Cache.has_value("player_name"):
		var player_name = Cache.get_value("player_name", "Player")
		nickname = "CityVote_" + player_name
		print("[IRC/WebSocket] Loaded player name from Cache: ", player_name)
	else:
		# Generate random anonymous player name: PlayerAnon + 9 random alphanumeric chars
		var random_suffix = _generate_random_alphanumeric(9)
		nickname = "CityVote_PlayerAnon" + random_suffix
		print("[IRC/WebSocket] No player name in Cache, using anonymous: PlayerAnon%s" % random_suffix)

	call_deferred("_connect_to_irc")

func _connect_to_irc():
	"""Connect to IRC WebSocket server"""
	var err = socket.connect_to_url(websocket_url)
	if err == OK:
		print("[IRC/WebSocket] Connecting to %s..." % websocket_url)
		connected = true
		set_process(true)
	else:
		push_error("[IRC/WebSocket] Unable to connect: error=%d" % err)
		set_process(false)

func _send_irc_command(command: String):
	"""Send raw IRC command"""
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var message = command + "\r\n"
		socket.send_text(message)
		print("[IRC/WebSocket] > %s" % command.strip_edges())

func _handle_irc_message(line: String):
	"""Parse and handle IRC protocol messages"""
	line = line.strip_edges()
	if line.is_empty():
		return

	print("[IRC/WebSocket] < %s" % line)

	# Handle PING (must respond with PONG to stay connected)
	if line.begins_with("PING "):
		var server = line.substr(5)
		_send_irc_command("PONG " + server)
		return

	# Parse IRC message format: [:prefix] command [params...]
	var parts = line.split(" ", false)
	if parts.is_empty():
		return

	var command_index = 0
	var prefix = ""

	# Check for prefix (starts with :)
	if parts[0].begins_with(":"):
		prefix = parts[0].substr(1)
		command_index = 1

	if command_index >= parts.size():
		return

	var command = parts[command_index]
	print("[IRC/WebSocket] Processing command: '%s'" % command)

	# Handle different IRC commands
	match command:
		"001":  # RPL_WELCOME - successfully connected
			print("[IRC/WebSocket] ✓ Connected to IRC server (001 received)")
			authenticated = true
			print("[IRC/WebSocket] Emitting irc_connected signal...")
			irc_connected.emit()
			print("[IRC/WebSocket] Signal emitted, joining channel...")
			# Join channel after authentication
			_send_irc_command("JOIN " + irc_channel)

		"433":  # ERR_NICKNAMEINUSE - nickname already in use
			print("[IRC/WebSocket] Nickname '%s' already in use, trying alternative..." % nickname)
			# Add random suffix to make nickname unique
			nickname = nickname + str(randi() % 1000)
			_send_irc_command("NICK " + nickname)
			_send_irc_command("USER " + nickname + " 0 * :CityVote Player")
			handshake_sent = true

		"JOIN":  # User joined channel
			if command_index + 1 < parts.size():
				var channel = parts[command_index + 1]
				if channel.begins_with(":"):
					channel = channel.substr(1)
				print("[IRC/WebSocket] ✓ Joined channel: %s" % channel)
				irc_joined_channel.emit(channel)

		"PRIVMSG":  # Channel message
			if command_index + 2 < parts.size():
				var channel = parts[command_index + 1]
				# Extract sender from prefix (nick!user@host)
				var sender = prefix.split("!")[0] if "!" in prefix else prefix
				# Message starts after channel, begins with :
				var message_start = command_index + 2
				var message = " ".join(parts.slice(message_start))
				if message.begins_with(":"):
					message = message.substr(1)
				irc_message_received.emit(channel, sender, message)

func _process(_delta):
	if not connected:
		return

	# Poll for WebSocket events
	socket.poll()

	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		# Send IRC handshake once when connection opens
		if not authenticated and not handshake_sent:
			_send_irc_command("NICK " + nickname)
			_send_irc_command("USER " + nickname + " 0 * :CityVote Player")
			handshake_sent = true

		# Process incoming messages
		while socket.get_available_packet_count():
			var packet = socket.get_packet()
			if socket.was_string_packet():
				var message = packet.get_string_from_utf8()
				# IRC can send multiple lines in one packet
				var lines = message.split("\n")
				for line in lines:
					_handle_irc_message(line)

	elif state == WebSocketPeer.STATE_CLOSING:
		pass  # Keep polling for clean close

	elif state == WebSocketPeer.STATE_CLOSED:
		var code = socket.get_close_code()
		print("[IRC/WebSocket] Connection closed: code=%d, clean=%s" % [code, code != -1])
		connected = false
		authenticated = false
		handshake_sent = false
		irc_disconnected.emit()
		set_process(false)

# Public API for sending messages
func send_message(channel: String, message: String) -> void:
	"""Send a message to IRC channel"""
	if authenticated and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_irc_command("PRIVMSG " + channel + " :" + message)
	else:
		push_warning("[IRC/WebSocket] Cannot send message - not connected")

func is_irc_connected() -> bool:
	"""Check if connected and authenticated"""
	return authenticated and socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func disconnect_irc() -> void:
	"""Disconnect from IRC server"""
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_send_irc_command("QUIT :Leaving")
		socket.close()
		connected = false
		authenticated = false
		handshake_sent = false
		# Emit disconnected signal immediately
		irc_disconnected.emit()
		set_process(false)

func _generate_random_alphanumeric(length: int) -> String:
	"""Generate a random alphanumeric string of specified length"""
	const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	var result = ""
	for i in range(length):
		result += chars[randi() % chars.length()]
	return result
