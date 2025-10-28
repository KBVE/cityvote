# Rust Thread → Godot Toast Test - Perfect

This demonstrates using Rust threads with `crossbeam_queue::SegQueue` to send messages to Godot.

## Architecture

```
┌─────────────────┐         ┌──────────────┐         ┌─────────────┐
│  Rust Thread    │ push()  │  SegQueue    │  pop()  │   Godot     │
│  (Worker)       ├────────→│  (MPSC)      ├────────→│  (Main)     │
└─────────────────┘         └──────────────┘         └─────────────┘
                                                             │
                                                             ▼
                                                      Toast.show_toast()
```

## Components

### 1. **toast_test.rs** (Rust)
- `ToastBridge` - Godot node that bridges Rust threads to GDScript
- Uses `SegQueue<String>` for thread-safe message passing
- Polls the queue every frame in `process()`
- Emits `toast_message_received` signal to GDScript

### 2. **rust_toast_bridge.gd** (GDScript Autoload)
- Instantiates the Rust `ToastBridge` node
- Connects to the `toast_message_received` signal
- Calls `Toast.show_toast()` when messages arrive

## Usage

### From GDScript Console:
```gdscript
# Spawn a single test thread (2 second delay)
RustToastBridge.test_rust_thread()

# Spawn multiple messages
RustToastBridge.test_multi_messages(5, 1000)  # 5 messages, 1 second apart

# Check queue size
print(RustToastBridge.get_queue_size())

# Clear queue
RustToastBridge.clear_queue()
```

### From Rust (Advanced):
```rust
// Get reference to the message queue
let queue = Arc::clone(&MESSAGE_QUEUE);

// Spawn a thread
std::thread::spawn(move || {
    // Do some work...
    queue.push("Result ready!".to_string());
});
```

## Building

1. **Compile Rust extension:**
   ```bash
   cd rust
   cargo build --release
   ```

2. **Copy to Godot:**
   ```bash
   # The .gdextension file should already be configured
   # Make sure libgodo.so/dll/dylib is in the right place
   ```

3. **Run Godot:**
   - The bridge will auto-initialize
   - You should see a test toast after 1 second

## How It Works

1. **Rust side:**
   - `spawn_test_thread()` creates a new OS thread
   - Thread sleeps for 2 seconds (simulating work)
   - Thread pushes message to `SegQueue`
   - Thread terminates

2. **Godot side:**
   - `ToastBridge.process()` runs every frame
   - Checks if queue has messages (`pop()`)
   - If message found, emits signal to GDScript
   - GDScript calls `Toast.show_toast()`

3. **Result:**
   - Toast appears in top-right corner
   - Message says "Toast from Rust thread! 🦀"

## Thread Safety

✅ **Safe:**
- `SegQueue` is lock-free and thread-safe
- Multiple threads can `push()` simultaneously
- Main thread `pop()`s in `process()`

❌ **Avoid:**
- Don't call Godot APIs from worker threads
- Don't touch WebGL/rendering from workers
- Keep threads for computation only

## Future Ideas

- Pathfinding in Rust threads
- Card shuffling/deck management
- Game state calculations
- AI decision trees
- Procedural generation

## Notes

- This uses **pthreads** on native platforms
- For **WASM**, requires `-sUSE_PTHREADS=1` flag
- Worker threads can't access DOM/WebGL
- Communication is async (not immediate)
