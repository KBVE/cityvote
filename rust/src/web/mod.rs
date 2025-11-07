// ============================================================================
// DEPRECATED: Web module for HTTP/HTTPS and WebSocket communication
// ============================================================================
//
// STATUS: All WebSocket/IRC functionality moved to GDScript (irc_websocket_client.gd)
//
// REASON FOR DEPRECATION:
// - Emscripten WebSocket symbols not available in Godot SIDE_MODULE builds
// - Thread pool exhaustion in WASM (Rust spawns too many threads)
// - GDScript WebSocketPeer works on ALL platforms (native + WASM)
// - Simpler architecture, no FFI overhead
//
// This code is commented out but preserved for future reference.
// See README.md in this directory for full explanation.
// ============================================================================

pub mod web_browser;

/* COMMENTED OUT - Kept for reference

pub mod client;
pub mod network_worker;
pub mod protocol;
pub mod irc;
pub mod irc_client;
pub mod chat_history;
pub mod irc_bridge;

#[cfg(target_family = "wasm")]
pub mod emscripten_websocket;

pub use client::{
    ConnectionState, HttpClient, WebError, WebMessage, WebResult, WebSocketClient,
};
pub use network_worker::{
    start_network_worker, NetworkWorkerConfig, NetworkWorkerHandle, NetworkWorkerRequest,
    NetworkWorkerResponse,
};
pub use protocol::{GameMessage, NetworkProtocol};
pub use irc::{IrcCommands, IrcConfig, IrcConnectionState, IrcEvent, IrcMessage};
pub use irc_client::IrcClient;
pub use chat_history::{ChannelHistory, ChatMessage, MessageType};
pub use irc_bridge::IrcChatBridge;

#[cfg(not(target_family = "wasm"))]
pub use client::{NativeHttpClient, NativeWebSocketClient};

#[cfg(target_family = "wasm")]
pub use client::{WasmHttpClient, WasmWebSocketClient};

*/
