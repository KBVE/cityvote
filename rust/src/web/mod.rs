// Web module for HTTP/HTTPS and WebSocket communication
// Supports both native and WASM builds

pub mod client;
pub mod network_worker;
pub mod protocol;
pub mod irc;
pub mod irc_client;
pub mod chat_history;
pub mod irc_bridge;

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
