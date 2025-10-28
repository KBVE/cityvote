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
	toast_bridge.connect("toast_message_received", _on_toast_message_received)

	print("RustToastBridge: Connected to Rust ToastBridge!")

	# Test: spawn a thread after 1 second
	await get_tree().create_timer(1.0).timeout
	test_rust_thread()

func _process(_delta: float) -> void:
	# Debug: Check queue size periodically
	if toast_bridge and Engine.get_frames_drawn() % 60 == 0:  # Every second
		var queue_size = toast_bridge.get_queue_size()
		if queue_size > 0:
			print("RustToastBridge: Queue has ", queue_size, " messages waiting!")

func _on_toast_message_received(message: String) -> void:
	print("RustToastBridge: Received message from Rust: ", message)

	# Check if Toast is available
	if not has_node("/root/Toast"):
		push_error("RustToastBridge: Toast autoload not found!")
		return

	# Display as toast
	var toast_node = get_node("/root/Toast")
	toast_node.show_toast(message, 3.0)
	print("RustToastBridge: Toast displayed!")

# Test functions you can call from GDScript
func test_rust_thread() -> void:
	if toast_bridge:
		print("RustToastBridge: Spawning test Rust thread...")
		toast_bridge.spawn_test_thread()
		print("RustToastBridge: spawn_test_thread() called successfully")

func test_multi_messages(count: int = 5, delay_ms: int = 1000) -> void:
	if toast_bridge:
		print("RustToastBridge: Spawning multi-message Rust thread...")
		toast_bridge.spawn_multi_message_thread(count, delay_ms)

func get_queue_size() -> int:
	if toast_bridge:
		return toast_bridge.get_queue_size()
	return 0

func clear_queue() -> void:
	if toast_bridge:
		toast_bridge.clear_queue()
