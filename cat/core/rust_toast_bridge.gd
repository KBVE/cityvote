extends Node

# Bridge between Rust threads and Godot Toast system
# Listens for messages from Rust and displays them as toasts

var toast_bridge: Node = null

func _ready() -> void:
	# Create the Rust ToastBridge node
	toast_bridge = ClassDB.instantiate("ToastBridge")

	if toast_bridge == null:
		push_error("RustToastBridge: Failed to instantiate ToastBridge from Rust!")
		push_error("Make sure the Rust extension is compiled and loaded.")
		return

	add_child(toast_bridge)

	# Connect to the Rust signal
	if not toast_bridge.connect("toast_message_received", _on_toast_message_received) == OK:
		push_error("RustToastBridge: Failed to connect to toast_message_received signal!")

	# Test: spawn a thread after 1 second
	await get_tree().create_timer(1.0).timeout
	test_rust_thread()

func _on_toast_message_received(message: String) -> void:
	# Check if Toast is available
	if not has_node("/root/Toast"):
		push_error("RustToastBridge: Toast autoload not found!")
		return

	# Try to translate the message using I18n
	# If the message is a translation key, use it; otherwise display as-is
	var translated_message = message
	if I18n.has_key(message):
		translated_message = I18n.translate(message)

	# Display as toast
	var toast_node = get_node("/root/Toast")
	if toast_node:
		toast_node.show_toast(translated_message, 3.0)
	else:
		push_error("RustToastBridge: Failed to get Toast node!")

# Test functions you can call from GDScript
func test_rust_thread() -> void:
	if toast_bridge:
		toast_bridge.spawn_test_thread()
	else:
		push_error("RustToastBridge: Cannot spawn test thread - bridge not initialized!")

func test_multi_messages(count: int = 5, delay_ms: int = 1000) -> void:
	if toast_bridge:
		toast_bridge.spawn_multi_message_thread(count, delay_ms)
	else:
		push_error("RustToastBridge: Cannot spawn multi-message thread - bridge not initialized!")

func get_queue_size() -> int:
	if toast_bridge:
		return toast_bridge.get_queue_size()
	return 0

func clear_queue() -> void:
	if toast_bridge:
		toast_bridge.clear_queue()
