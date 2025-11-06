# WebSocket Integration for AFK

## ⚠️ DEPRECATED - Code Kept for Reference Only

**Status**: All WebSocket/IRC functionality has been moved to GDScript (`cat/core/irc_websocket_client.gd`).

**Why**:
- Emscripten WebSocket symbols not available in Godot SIDE_MODULE builds
- Thread pool exhaustion issues in WASM (Rust spawns too many threads)
- GDScript WebSocketPeer works perfectly on ALL platforms (native + WASM)
- Simpler architecture, fewer dependencies, no FFI overhead

**This module is commented out but preserved for:**
- Future reference if WebSocket needs move back to Rust
- Learning/documentation purposes
- Potential native-only optimizations later

---

## Original Documentation (Historical)

This module **provided** unified WebSocket and HTTP/HTTPS support for both **native** (macOS, Linux, Windows) and **WASM** (browser) builds.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         Godot (GDScript)                     │
│                     ↓ FFI Calls ↓                            │
│                 UnifiedEventBridge                           │
└─────────────────────────────────────────────────────────────┘
                         ↓                ↑
                    GameRequest      GameEvent
                         ↓                ↑
┌─────────────────────────────────────────────────────────────┐
│                       GameActor                              │
│                   (Actor Thread - 60Hz)                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Request Handler → Network Worker Handle              │  │
│  │   - NetworkConnect    → worker.connect()             │  │
│  │   - NetworkSend       → worker.send_message()        │  │
│  │   - NetworkDisconnect → worker.disconnect()          │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Response Collector ← worker.try_recv()               │  │
│  │   - NetworkConnected                                  │  │
│  │   - NetworkMessageReceived                            │  │
│  │   - NetworkError                                      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                         ↓                ↑
                 NetworkWorkerRequest  NetworkWorkerResponse
                         ↓                ↑
┌─────────────────────────────────────────────────────────────┐
│                   Network Worker Thread                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │             WebSocketClient                          │  │
│  │   - Native:  tokio-tungstenite + tokio runtime       │  │
│  │   - WASM:    gloo-net WebSocket                      │  │
│  └──────────────────────────────────────────────────────┘  │
│  Features:                                                   │
│  • Auto-reconnection with configurable retry logic          │
│  • Non-blocking message receive/send                        │
│  • Binary and text message support                          │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. **Unified Client Abstraction** ([client.rs](./client.rs))

Provides platform-agnostic traits and implementations:

- **`WebSocketClient` trait**: Unified WebSocket interface
  - `connect()` - Establish WebSocket connection
  - `send()` - Send binary/text messages
  - `try_recv()` - Non-blocking message receive
  - `close()` - Gracefully close connection
  - `state()` - Get connection state

- **Native Implementation**: `NativeWebSocketClient`
  - Uses `tokio-tungstenite` for WebSocket
  - Uses `tokio` runtime for async operations
  - Spawns sender/receiver tasks on tokio runtime

- **WASM Implementation**: `WasmWebSocketClient`
  - Uses `gloo-net` WebSocket API
  - Spawns tasks with `wasm-bindgen-futures::spawn_local`
  - Browser-native WebSocket support

- **`HttpClient` trait**: REST API support
  - `get()` - HTTP GET request
  - `post_json()` - HTTP POST with JSON body
  - `put_json()` - HTTP PUT with JSON body
  - `delete()` - HTTP DELETE request

### 2. **Network Worker** ([network_worker.rs](./network_worker.rs))

Dedicated thread for handling WebSocket communication:

- **Configuration** (`NetworkWorkerConfig`):
  ```rust
  NetworkWorkerConfig {
      reconnect_interval_ms: 5000,      // Retry every 5 seconds
      max_reconnect_attempts: 0,        // 0 = infinite retries
      auto_reconnect: true,             // Enable auto-reconnect
      tick_rate_ms: 16,                 // ~60 Hz tick rate
  }
  ```

- **Request Types**:
  - `Connect { url }` - Connect to WebSocket server
  - `SendMessage { data }` - Send binary data
  - `SendText { text }` - Send text data
  - `Disconnect` - Close connection
  - `Shutdown` - Stop worker thread

- **Response Types**:
  - `Connected` - Successfully connected
  - `ConnectionFailed { error }` - Connection failed
  - `Disconnected` - Connection closed
  - `MessageReceived { data }` - Binary message received
  - `TextReceived { text }` - Text message received
  - `Error { message }` - Error occurred
  - `StateChanged { state }` - Connection state changed

### 3. **Protocol & Serialization** ([protocol.rs](./protocol.rs))

Game-specific network protocol using `bincode` for efficient binary serialization:

- **`GameMessage` enum**: All network messages
  - Client → Server:
    - `Connect` - Initial handshake
    - `MoveEntity` - Player movement
    - `AttackEntity` - Combat action
    - `SpawnEntity` - Entity spawn request
    - `PlaceCard` - Card placement
    - `Chat` - Chat message

  - Server → Client:
    - `Connected` - Connection accepted
    - `EntityUpdate` - Entity state sync
    - `CombatEvent` - Combat notification
    - `ResourceUpdate` - Resource state sync
    - `ComboDetected` - Combo event
    - `ChatMessage` - Chat from other player

- **`NetworkProtocol`**: Serialization utilities
  - `serialize()` - Binary serialization (bincode)
  - `deserialize()` - Binary deserialization
  - `serialize_json()` - JSON serialization (debugging)
  - `deserialize_json()` - JSON deserialization

### 4. **Actor Integration** ([events/actor.rs](../events/actor.rs))

The `GameActor` coordinates network operations:

- **Initialization**: Network worker starts on-demand when first `NetworkConnect` request arrives
- **Request Handling**:
  ```rust
  GameRequest::NetworkConnect { url } => {
      // Initialize worker if needed
      if self.network_worker.is_none() {
          let config = NetworkWorkerConfig::default();
          self.network_worker = Some(start_network_worker(config));
      }
      // Connect to server
      if let Some(ref worker) = self.network_worker {
          worker.connect(url);
      }
  }
  ```

- **Event Collection**: Every tick, actor polls network worker for responses
  ```rust
  fn collect_network_results(&mut self) {
      if let Some(ref worker) = self.network_worker {
          while let Some(response) = worker.try_recv() {
              // Convert to GameEvent and emit to Godot
          }
      }
  }
  ```

### 5. **Godot Integration** ([events/bridge.rs](../events/bridge.rs))

New Godot signals for network events:

- `network_connected(session_id: String)` - Connected to server
- `network_connection_failed(error: String)` - Connection failed
- `network_disconnected()` - Disconnected from server
- `network_message_received(data: PackedByteArray)` - Message received
- `network_error(message: String)` - Error occurred

## Usage from GDScript

### 1. Connect to a WebSocket Server

```gdscript
extends Node

@onready var event_bridge = $UnifiedEventBridge

func _ready():
    # Connect signals
    event_bridge.network_connected.connect(_on_network_connected)
    event_bridge.network_connection_failed.connect(_on_connection_failed)
    event_bridge.network_message_received.connect(_on_message_received)
    event_bridge.network_error.connect(_on_network_error)

    # Connect to server
    event_bridge.network_connect("wss://example.com/game")

func _on_network_connected(session_id: String):
    print("Connected! Session: ", session_id)

func _on_connection_failed(error: String):
    print("Connection failed: ", error)

func _on_message_received(data: PackedByteArray):
    print("Received ", data.size(), " bytes")
    # Deserialize and handle message

func _on_network_error(message: String):
    print("Network error: ", message)
```

### 2. Send Messages

```gdscript
func send_player_move(entity_ulid: PackedByteArray, target_pos: Vector2i):
    # Serialize message using NetworkProtocol
    var message = {
        "type": "MoveEntity",
        "ulid": entity_ulid,
        "target_position": [target_pos.x, target_pos.y]
    }

    # Convert to bytes (in real implementation, use bincode serialization)
    var data = var_to_bytes(message)

    # Send through network
    event_bridge.network_send(data)
```

### 3. Disconnect

```gdscript
func _exit_tree():
    event_bridge.network_disconnect()
```

## Building

### Native (macOS/Linux/Windows)

```bash
cd rust
cargo build --release
```

Dependencies:
- `reqwest` (v0.12.24) - HTTP client with blocking support
- `tokio` (v1) - Async runtime
- `tokio-tungstenite` (v0.24) - WebSocket client
- `futures-util` (v0.3) - Async utilities

### WASM (Browser)

```bash
cd rust
cargo build --target wasm32-unknown-emscripten --release
```

Dependencies:
- `gloo-net` (v0.6.0) - Browser WebSocket and HTTP APIs
- `wasm-bindgen-futures` (v0.4) - Async support in WASM

## Configuration

### Network Worker Settings

Customize reconnection behavior:

```rust
let config = NetworkWorkerConfig {
    reconnect_interval_ms: 3000,      // Retry every 3 seconds
    max_reconnect_attempts: 10,       // Max 10 retries
    auto_reconnect: true,             // Enable auto-reconnect
    tick_rate_ms: 16,                 // ~60 Hz
};

let worker = start_network_worker(config);
```

### Message Protocol

The protocol uses **bincode** for efficient binary serialization:

- **Advantages**:
  - Fast serialization/deserialization
  - Small message size (no JSON overhead)
  - Type-safe with Rust derives

- **JSON Fallback**: Available for debugging
  ```rust
  let json = NetworkProtocol::serialize_json(&message)?;
  let message = NetworkProtocol::deserialize_json(&json)?;
  ```

## Thread Architecture

```
Main Thread (Godot)
  └─ UnifiedEventBridge.process()  (called every frame)
       └─ Drains event channel (non-blocking)

Actor Thread (60 Hz)
  └─ GameActor.tick()
       ├─ Processes GameRequest::NetworkConnect/Send/Disconnect
       ├─ Sends NetworkWorkerRequest to worker
       └─ Collects NetworkWorkerResponse from worker

Network Worker Thread (~60 Hz)
  └─ run_network_worker()
       ├─ Processes NetworkWorkerRequest
       ├─ Native: tokio runtime with async WebSocket
       ├─ WASM: spawn_local with gloo-net WebSocket
       └─ Sends NetworkWorkerResponse back to actor
```

## Testing

### Unit Tests

```bash
cd rust
cargo test web::protocol
```

Tests included:
- Binary serialization/deserialization
- JSON serialization/deserialization
- Message type conversions

### Integration Testing

Create a simple echo server test:

```rust
#[test]
fn test_websocket_connection() {
    let config = NetworkWorkerConfig::default();
    let worker = start_network_worker(config);

    worker.connect("ws://localhost:8080".to_string());

    // Wait for connection
    thread::sleep(Duration::from_millis(500));

    // Check for Connected response
    if let Some(NetworkWorkerResponse::Connected) = worker.try_recv() {
        println!("Connected successfully!");
    }
}
```

## Performance Considerations

1. **Zero-Copy Channels**: Uses `crossbeam_channel::unbounded()` for lock-free communication
2. **Non-Blocking Operations**: All `try_recv()` calls are non-blocking
3. **Dedicated Threads**: Network worker runs on separate thread to avoid blocking game logic
4. **Binary Protocol**: Bincode serialization is significantly faster than JSON
5. **Auto-Reconnection**: Handles connection drops gracefully without blocking

## Future Enhancements

- [ ] SSL/TLS certificate validation configuration
- [ ] Custom heartbeat/ping-pong intervals
- [ ] Message compression (gzip/zstd)
- [ ] Connection pooling for multiple servers
- [ ] UDP transport option for low-latency scenarios
- [ ] WebRTC data channels for peer-to-peer
- [ ] Bandwidth monitoring and throttling

## License

MIT (same as parent project)
