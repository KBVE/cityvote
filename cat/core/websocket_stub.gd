extends Node
## WebSocket stub to force Emscripten to include WebSocket symbols in WASM builds
## This ensures the MAIN_MODULE (Godot) provides WebSocket functions to SIDE_MODULEs (Rust GDExtension)
## Without this, Rust code calling emscripten_websocket_* functions will fail with "undefined symbol" errors
##
## This stub can also serve as a fallback IRC client if the Rust implementation fails

# IRC WebSocket server URL
@export var websocket_url = "wss://chat.kbve.com/webirc"

# WebSocketPeer instance - just creating it includes symbols in WASM export
var socket: WebSocketPeer
var connected: bool = false

func _ready():
	# Create WebSocketPeer to pull in Emscripten WebSocket symbols
	socket = WebSocketPeer.new()

	# Optionally connect to test (disabled by default - Rust handles IRC)
	# Uncomment to test GDScript WebSocket as fallback
	# _connect_to_irc()

func _connect_to_irc():
	"""Connect to IRC WebSocket server (fallback/test function)"""
	# Note: Godot 4.x doesn't support WebSocket subprotocols in connect_to_url()
	# The IRC subprotocol ("text.ircv3.net") must be handled via TLS options or headers
	var err = socket.connect_to_url(websocket_url)
	if err == OK:
		print("[WebSocketStub] Connecting to %s..." % websocket_url)
		connected = true
		set_process(true)
	else:
		push_error("[WebSocketStub] Unable to connect to IRC: %d" % err)
		set_process(false)

func _process(_delta):
	if not connected:
		return

	# Poll for WebSocket events
	socket.poll()

	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		# Process incoming messages
		while socket.get_available_packet_count():
			var packet = socket.get_packet()
			if socket.was_string_packet():
				var message = packet.get_string_from_utf8()
				print("[WebSocketStub] < IRC: %s" % message)
				# TODO: Parse IRC messages and emit signals

	elif state == WebSocketPeer.STATE_CLOSING:
		pass  # Keep polling for clean close

	elif state == WebSocketPeer.STATE_CLOSED:
		var code = socket.get_close_code()
		print("[WebSocketStub] WebSocket closed: code=%d, clean=%s" % [code, code != -1])
		connected = false
		set_process(false)

func send_irc_message(message: String) -> void:
	"""Send IRC message (fallback function)"""
	if connected and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(message)
		print("[WebSocketStub] > IRC: %s" % message)
