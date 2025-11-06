// Unified web client abstraction for HTTP/HTTPS and WebSocket communication
// Supports both native (reqwest + tokio-tungstenite) and WASM (gloo-net) targets

use godot::prelude::*;
use serde::{Deserialize, Serialize};
use std::fmt;

#[cfg(not(target_family = "wasm"))]
use crate::async_runtime::AsyncRuntime;

/// Unified result type for web operations
pub type WebResult<T> = Result<T, WebError>;

/// Unified error type for web operations
#[derive(Debug, Clone)]
pub enum WebError {
    ConnectionFailed(String),
    SendFailed(String),
    ReceiveFailed(String),
    SerializationError(String),
    InvalidUrl(String),
    Disconnected,
    Timeout,
    Other(String),
}

impl fmt::Display for WebError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WebError::ConnectionFailed(msg) => write!(f, "Connection failed: {}", msg),
            WebError::SendFailed(msg) => write!(f, "Send failed: {}", msg),
            WebError::ReceiveFailed(msg) => write!(f, "Receive failed: {}", msg),
            WebError::SerializationError(msg) => write!(f, "Serialization error: {}", msg),
            WebError::InvalidUrl(msg) => write!(f, "Invalid URL: {}", msg),
            WebError::Disconnected => write!(f, "Disconnected"),
            WebError::Timeout => write!(f, "Timeout"),
            WebError::Other(msg) => write!(f, "Error: {}", msg),
        }
    }
}

impl std::error::Error for WebError {}

/// WebSocket connection state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
    Failed,
}

/// Message types for WebSocket communication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum WebMessage {
    Text(String),
    Binary(Vec<u8>),
    Ping,
    Pong,
    Close,
}

/// Unified WebSocket client trait
/// Implemented separately for native and WASM targets
pub trait WebSocketClient: Send + Sync {
    /// Connect to a WebSocket server
    fn connect(&mut self, url: &str) -> WebResult<()>;

    /// Send a message through the WebSocket
    fn send(&mut self, message: WebMessage) -> WebResult<()>;

    /// Try to receive a message (non-blocking)
    fn try_recv(&mut self) -> WebResult<Option<WebMessage>>;

    /// Close the WebSocket connection
    fn close(&mut self) -> WebResult<()>;

    /// Get current connection state
    fn state(&self) -> ConnectionState;

    /// Check if connected
    fn is_connected(&self) -> bool {
        self.state() == ConnectionState::Connected
    }
}

/// HTTP client trait for REST API calls
pub trait HttpClient: Send + Sync {
    /// Perform a GET request
    fn get(&self, url: &str) -> WebResult<Vec<u8>>;

    /// Perform a POST request with JSON body
    fn post_json<T: Serialize>(&self, url: &str, body: &T) -> WebResult<Vec<u8>>;

    /// Perform a PUT request with JSON body
    fn put_json<T: Serialize>(&self, url: &str, body: &T) -> WebResult<Vec<u8>>;

    /// Perform a DELETE request
    fn delete(&self, url: &str) -> WebResult<Vec<u8>>;
}

// Re-export platform-specific implementations
#[cfg(not(target_family = "wasm"))]
pub use native::*;

#[cfg(target_family = "wasm")]
pub use wasm::*;

// ============================================================================
// NATIVE IMPLEMENTATION (reqwest + tokio-tungstenite)
// ============================================================================
#[cfg(not(target_family = "wasm"))]
mod native {
    use super::*;
    use crossbeam_channel::{unbounded, Receiver, Sender};
    use futures_util::{SinkExt, StreamExt};
    use std::sync::{Arc, Mutex};
    use tokio_tungstenite::tungstenite::Message as WsMessage;

    /// Native WebSocket client using tokio-tungstenite
    pub struct NativeWebSocketClient {
        state: Arc<Mutex<ConnectionState>>,
        send_tx: Option<Sender<WebMessage>>,
        recv_rx: Option<Receiver<WebMessage>>,
    }

    impl NativeWebSocketClient {
        pub fn new() -> WebResult<Self> {
            godot_print!("[IRC] Using AsyncRuntime singleton for WebSocket");

            Ok(Self {
                state: Arc::new(Mutex::new(ConnectionState::Disconnected)),
                send_tx: None,
                recv_rx: None,
            })
        }
    }

    impl WebSocketClient for NativeWebSocketClient {
        fn connect(&mut self, url: &str) -> WebResult<()> {
            // External API uses crossbeam (keeps existing public API)
            let (send_tx, send_rx) = unbounded::<WebMessage>();
            let (recv_tx, recv_rx) = unbounded::<WebMessage>();

            let state = Arc::clone(&self.state);
            let url = url.to_string();

            // Update state to connecting
            *state.lock().unwrap() = ConnectionState::Connecting;

            // Spawn dedicated thread with block_on instead of relying on tokio spawn
            // This ensures the async code actually runs instead of getting stuck
            std::thread::spawn(move || {
                let runtime = AsyncRuntime::runtime();
                runtime.block_on(async move {
                godot_print!("[IRC] Inside async task, attempting connect_async to: {}", url);

                use tokio_tungstenite::tungstenite::client::IntoClientRequest;
                use tokio_tungstenite::tungstenite::http::header::{SEC_WEBSOCKET_PROTOCOL, ORIGIN};

                let mut request = match url.as_str().into_client_request() {
                    Ok(req) => req,
                    Err(e) => {
                        godot_error!("[IRC] Failed to create WebSocket request: {}", e);
                        *state.lock().unwrap() = ConnectionState::Failed;
                        return;
                    }
                };

                // CRITICAL: Add Sec-WebSocket-Protocol header for IRCv3 (typed constant)
                request.headers_mut().insert(
                    SEC_WEBSOCKET_PROTOCOL,
                    "text.ircv3.net".parse().expect("Failed to parse IRCv3 protocol")
                );

                // Optional: Add Origin header if server enforces it
                if let Ok(origin) = "https://chat.kbve.com".parse() {
                    request.headers_mut().insert(ORIGIN, origin);
                }

                godot_print!("[IRC] Created WebSocket request with Sec-WebSocket-Protocol: text.ircv3.net");

                // Test 1: Try DNS resolution first
                godot_print!("[IRC] Step 1: Resolving DNS for chat.kbve.com...");
                match tokio::net::lookup_host("chat.kbve.com:443").await {
                    Ok(mut addrs) => {
                        if let Some(addr) = addrs.next() {
                            godot_print!("[IRC] DNS resolution successful: {}", addr);
                        } else {
                            godot_error!("[IRC] DNS resolution returned no addresses");
                            *state.lock().unwrap() = ConnectionState::Failed;
                            return;
                        }
                    }
                    Err(e) => {
                        godot_error!("[IRC] DNS resolution failed: {}", e);
                        *state.lock().unwrap() = ConnectionState::Failed;
                        return;
                    }
                }

                godot_print!("[IRC] Step 2: Calling connect_async directly...");

                // Try direct connection without timeout first to diagnose
                match tokio_tungstenite::connect_async(request).await {
                            Ok((ws_stream, response)) => {
                                // Handshake diagnostics
                                godot_print!("[IRC] ✓ WebSocket handshake succeeded!");
                                godot_print!("[IRC] Status: {:?}", response.status());

                                if let Some(protocol) = response.headers().get(SEC_WEBSOCKET_PROTOCOL) {
                                    godot_print!("[IRC] Server selected protocol: {}", protocol.to_str().unwrap_or("<invalid>"));
                                } else {
                                    godot_print!("[IRC] WARNING: Server returned no Sec-WebSocket-Protocol header");
                                }

                                if let Some(upgrade) = response.headers().get("Upgrade") {
                                    godot_print!("[IRC] Upgrade: {}", upgrade.to_str().unwrap_or("<invalid>"));
                                }

                                *state.lock().unwrap() = ConnectionState::Connected;

                                let (mut write, mut read) = ws_stream.split();

                                // CRITICAL FIX: Use async tokio mpsc instead of blocking crossbeam
                                // Create async channel for WebSocket writer task
                                use tokio::sync::mpsc;
                                let (tx_async, mut rx_async) = mpsc::unbounded_channel::<WebMessage>();

                                // Bridge crossbeam → tokio mpsc (run on separate thread to avoid blocking)
                                std::thread::spawn(move || {
                                    while let Ok(msg) = send_rx.recv() {
                                        if tx_async.send(msg).is_err() {
                                            break;
                                        }
                                    }
                                });

                                // Spawn ASYNC sender task (now non-blocking!)
                                let state_send = Arc::clone(&state);
                                tokio::spawn(async move {
                                    while let Some(msg) = rx_async.recv().await {
                                        let ws_msg = match msg {
                                            WebMessage::Text(text) => WsMessage::Text(text.into()),
                                            WebMessage::Binary(data) => WsMessage::Binary(data.into()),
                                            WebMessage::Ping => WsMessage::Ping(vec![].into()),
                                            WebMessage::Pong => WsMessage::Pong(vec![].into()),
                                            WebMessage::Close => {
                                                let _ = write.close().await;
                                                break;
                                            }
                                        };

                                if write.send(ws_msg).await.is_err() {
                                    *state_send.lock().unwrap() = ConnectionState::Failed;
                                    break;
                                }
                            }
                        });

                        // Spawn receiver task
                        let state_recv = Arc::clone(&state);
                        tokio::spawn(async move {
                            while let Some(result) = read.next().await {
                                match result {
                                    Ok(ws_msg) => {
                                        let msg = match ws_msg {
                                            WsMessage::Text(text) => WebMessage::Text(text.to_string()),
                                            WsMessage::Binary(data) => WebMessage::Binary(data.to_vec()),
                                            WsMessage::Ping(_) => WebMessage::Ping,
                                            WsMessage::Pong(_) => WebMessage::Pong,
                                            WsMessage::Close(_) => {
                                                *state_recv.lock().unwrap() = ConnectionState::Disconnected;
                                                WebMessage::Close
                                            }
                                            _ => continue,
                                        };

                                        if recv_tx.send(msg).is_err() {
                                            break;
                                        }
                                    }
                                    Err(_) => {
                                        *state_recv.lock().unwrap() = ConnectionState::Failed;
                                        break;
                                    }
                                }
                            }
                        });
                            }
                            Err(e) => {
                                godot_error!("[IRC] WebSocket connection error: {}", e);
                                *state.lock().unwrap() = ConnectionState::Failed;
                            }
                        }
                }) // Close async block
            }); // Close thread spawn

            self.send_tx = Some(send_tx);
            self.recv_rx = Some(recv_rx);

            Ok(())
        }

        fn send(&mut self, message: WebMessage) -> WebResult<()> {
            if let Some(tx) = &self.send_tx {
                tx.send(message)
                    .map_err(|e| WebError::SendFailed(e.to_string()))?;
                Ok(())
            } else {
                Err(WebError::Disconnected)
            }
        }

        fn try_recv(&mut self) -> WebResult<Option<WebMessage>> {
            if let Some(rx) = &self.recv_rx {
                match rx.try_recv() {
                    Ok(msg) => Ok(Some(msg)),
                    Err(crossbeam_channel::TryRecvError::Empty) => Ok(None),
                    Err(e) => Err(WebError::ReceiveFailed(e.to_string())),
                }
            } else {
                Err(WebError::Disconnected)
            }
        }

        fn close(&mut self) -> WebResult<()> {
            if let Some(tx) = &self.send_tx {
                tx.send(WebMessage::Close)
                    .map_err(|e| WebError::SendFailed(e.to_string()))?;
            }
            *self.state.lock().unwrap() = ConnectionState::Disconnected;
            self.send_tx = None;
            self.recv_rx = None;
            Ok(())
        }

        fn state(&self) -> ConnectionState {
            *self.state.lock().unwrap()
        }
    }

    /// Native HTTP client using reqwest
    pub struct NativeHttpClient {
        client: reqwest::blocking::Client,
    }

    impl NativeHttpClient {
        pub fn new() -> WebResult<Self> {
            let client = reqwest::blocking::Client::builder()
                .timeout(std::time::Duration::from_secs(30))
                .build()
                .map_err(|e| WebError::Other(format!("Failed to create HTTP client: {}", e)))?;

            Ok(Self { client })
        }
    }

    impl HttpClient for NativeHttpClient {
        fn get(&self, url: &str) -> WebResult<Vec<u8>> {
            self.client
                .get(url)
                .send()
                .map_err(|e| WebError::Other(e.to_string()))?
                .bytes()
                .map(|b| b.to_vec())
                .map_err(|e| WebError::Other(e.to_string()))
        }

        fn post_json<T: Serialize>(&self, url: &str, body: &T) -> WebResult<Vec<u8>> {
            self.client
                .post(url)
                .json(body)
                .send()
                .map_err(|e| WebError::Other(e.to_string()))?
                .bytes()
                .map(|b| b.to_vec())
                .map_err(|e| WebError::Other(e.to_string()))
        }

        fn put_json<T: Serialize>(&self, url: &str, body: &T) -> WebResult<Vec<u8>> {
            self.client
                .put(url)
                .json(body)
                .send()
                .map_err(|e| WebError::Other(e.to_string()))?
                .bytes()
                .map(|b| b.to_vec())
                .map_err(|e| WebError::Other(e.to_string()))
        }

        fn delete(&self, url: &str) -> WebResult<Vec<u8>> {
            self.client
                .delete(url)
                .send()
                .map_err(|e| WebError::Other(e.to_string()))?
                .bytes()
                .map(|b| b.to_vec())
                .map_err(|e| WebError::Other(e.to_string()))
        }
    }

    impl Default for NativeHttpClient {
        fn default() -> Self {
            Self::new().expect("Failed to create HTTP client")
        }
    }

    impl Default for NativeWebSocketClient {
        fn default() -> Self {
            Self::new().expect("Failed to create WebSocket client")
        }
    }
}

// ============================================================================
// WASM IMPLEMENTATION (Emscripten native WebSocket)
// ============================================================================
#[cfg(target_family = "wasm")]
mod wasm {
    use super::*;
    use crate::web::emscripten_websocket::*;
    use crossbeam_channel::{unbounded, Receiver, Sender};
    use std::ffi::{CStr, CString};
    use std::os::raw::{c_char, c_int, c_uint, c_void};
    use std::sync::{Arc, Mutex};

    /// WASM WebSocket client using Emscripten native WebSocket API
    pub struct WasmWebSocketClient {
        socket: EMSCRIPTEN_WEBSOCKET_T,
        state: Arc<Mutex<ConnectionState>>,
        recv_rx: Receiver<WebMessage>,
        // Keep channels alive (they're used by callbacks)
        _recv_tx: Arc<Mutex<Sender<WebMessage>>>,
    }

    impl WasmWebSocketClient {
        pub fn new() -> WebResult<Self> {
            // Check if WebSocket is supported
            unsafe {
                if emscripten_websocket_is_supported() == EM_FALSE {
                    return Err(WebError::Other(
                        "WebSocket not supported in this environment".to_string(),
                    ));
                }
            }

            // Create channels for receiving messages
            let (recv_tx, recv_rx) = unbounded::<WebMessage>();

            Ok(Self {
                socket: -1, // Invalid socket initially
                state: Arc::new(Mutex::new(ConnectionState::Disconnected)),
                recv_rx,
                _recv_tx: Arc::new(Mutex::new(recv_tx)),
            })
        }
    }

    // Structure to pass state and channels to callbacks
    struct CallbackContext {
        state: Arc<Mutex<ConnectionState>>,
        recv_tx: Arc<Mutex<Sender<WebMessage>>>,
    }

    // Callback handlers for Emscripten WebSocket events
    unsafe extern "C" fn on_open(
        _event_type: c_int,
        _event: *const EmscriptenWebSocketOpenEvent,
        user_data: *mut c_void,
    ) -> EM_BOOL {
        let ctx = &*(user_data as *const CallbackContext);
        // Use try_lock to avoid deadlock
        if let Ok(mut state) = ctx.state.try_lock() {
            *state = ConnectionState::Connected;
        }
        eprintln!("[WASM] WebSocket connection opened");
        EM_TRUE
    }

    unsafe extern "C" fn on_error(
        _event_type: c_int,
        _event: *const EmscriptenWebSocketErrorEvent,
        user_data: *mut c_void,
    ) -> EM_BOOL {
        let ctx = &*(user_data as *const CallbackContext);
        // Use try_lock to avoid deadlock
        if let Ok(mut state) = ctx.state.try_lock() {
            *state = ConnectionState::Failed;
        }
        eprintln!("[WASM] WebSocket error occurred");
        EM_TRUE
    }

    unsafe extern "C" fn on_close(
        _event_type: c_int,
        event: *const EmscriptenWebSocketCloseEvent,
        user_data: *mut c_void,
    ) -> EM_BOOL {
        let ctx = &*(user_data as *const CallbackContext);
        // Use try_lock to avoid deadlock
        if let Ok(mut state) = ctx.state.try_lock() {
            *state = ConnectionState::Disconnected;
        }

        let code = (*event).code;
        let reason_bytes = &(*event).reason;
        let reason = CStr::from_ptr(reason_bytes.as_ptr())
            .to_string_lossy()
            .into_owned();

        eprintln!("[WASM] WebSocket closed: code={}, reason={}", code, reason);
        EM_TRUE
    }

    unsafe extern "C" fn on_message(
        _event_type: c_int,
        event: *const EmscriptenWebSocketMessageEvent,
        user_data: *mut c_void,
    ) -> EM_BOOL {
        let ctx = &*(user_data as *const CallbackContext);
        // Use try_lock to avoid deadlock
        if let Ok(recv_tx) = ctx.recv_tx.try_lock() {
            let is_text = (*event).is_text == EM_TRUE;
            let data_ptr = (*event).data;
            let num_bytes = (*event).num_bytes as usize;

            if is_text {
                // Text message
                let slice = std::slice::from_raw_parts(data_ptr, num_bytes);
                if let Ok(text) = std::str::from_utf8(slice) {
                    let _ = recv_tx.send(WebMessage::Text(text.to_string()));
                }
            } else {
                // Binary message
                let slice = std::slice::from_raw_parts(data_ptr, num_bytes);
                let _ = recv_tx.send(WebMessage::Binary(slice.to_vec()));
            }
        }

        EM_TRUE
    }

    impl WebSocketClient for WasmWebSocketClient {
        fn connect(&mut self, url: &str) -> WebResult<()> {
            // Update state to connecting
            *self.state.lock().unwrap() = ConnectionState::Connecting;

            // Prepare URL and protocol
            let url_c = CString::new(url)
                .map_err(|e| WebError::InvalidUrl(e.to_string()))?;

            // IRC WebSocket subprotocol
            let protocol = CString::new("text.ircv3.net")
                .map_err(|e| WebError::Other(e.to_string()))?;
            let protocols = vec![protocol.as_ptr()];

            // Create WebSocket attributes
            let attrs = EmscriptenWebSocketCreateAttributes {
                url: url_c.as_ptr(),
                protocols: protocols.as_ptr(),
                num_protocols: protocols.len() as c_int,
                create_on_main_thread: EM_TRUE,
            };

            // Create callback context (Box to keep it alive)
            let ctx = Box::new(CallbackContext {
                state: Arc::clone(&self.state),
                recv_tx: Arc::clone(&self._recv_tx),
            });
            let ctx_ptr = Box::into_raw(ctx) as *mut c_void;

            // Create WebSocket
            unsafe {
                self.socket = emscripten_websocket_new(&attrs);

                if self.socket <= 0 {
                    // Free context on failure
                    let _ = Box::from_raw(ctx_ptr as *mut CallbackContext);
                    return Err(WebError::ConnectionFailed(
                        "Failed to create WebSocket".to_string(),
                    ));
                }

                // Set up event callbacks
                emscripten_websocket_set_onopen_callback(self.socket, ctx_ptr, on_open);
                emscripten_websocket_set_onerror_callback(self.socket, ctx_ptr, on_error);
                emscripten_websocket_set_onclose_callback(self.socket, ctx_ptr, on_close);
                emscripten_websocket_set_onmessage_callback(self.socket, ctx_ptr, on_message);
            }

            eprintln!("[WASM] WebSocket connection initiated to: {}", url);
            Ok(())
        }

        fn send(&mut self, message: WebMessage) -> WebResult<()> {
            if self.socket <= 0 {
                return Err(WebError::Disconnected);
            }

            unsafe {
                match message {
                    WebMessage::Text(text) => {
                        let text_c = CString::new(text)
                            .map_err(|e| WebError::SendFailed(e.to_string()))?;
                        let result =
                            emscripten_websocket_send_utf8_text(self.socket, text_c.as_ptr());
                        if result != EMSCRIPTEN_RESULT_SUCCESS {
                            return Err(WebError::SendFailed(format!("Send failed: {}", result)));
                        }
                    }
                    WebMessage::Binary(data) => {
                        let result = emscripten_websocket_send_binary(
                            self.socket,
                            data.as_ptr() as *const c_void,
                            data.len() as c_uint,
                        );
                        if result != EMSCRIPTEN_RESULT_SUCCESS {
                            return Err(WebError::SendFailed(format!("Send failed: {}", result)));
                        }
                    }
                    _ => {} // Ping/Pong/Close handled elsewhere
                }
            }

            Ok(())
        }

        fn try_recv(&mut self) -> WebResult<Option<WebMessage>> {
            match self.recv_rx.try_recv() {
                Ok(msg) => Ok(Some(msg)),
                Err(crossbeam_channel::TryRecvError::Empty) => Ok(None),
                Err(e) => Err(WebError::ReceiveFailed(e.to_string())),
            }
        }

        fn close(&mut self) -> WebResult<()> {
            if self.socket > 0 {
                unsafe {
                    let reason = CString::new("Client closing connection").unwrap();
                    emscripten_websocket_close(self.socket, 1000, reason.as_ptr());
                    emscripten_websocket_delete(self.socket);
                }
                self.socket = -1;
            }
            // Use try_lock to avoid deadlock
            if let Ok(mut state) = self.state.try_lock() {
                *state = ConnectionState::Disconnected;
            }
            Ok(())
        }

        fn state(&self) -> ConnectionState {
            // Use try_lock to avoid deadlock - return last known state if locked
            self.state.try_lock()
                .map(|s| *s)
                .unwrap_or(ConnectionState::Disconnected)
        }
    }

    /// WASM HTTP client using gloo-net
    pub struct WasmHttpClient;

    impl WasmHttpClient {
        pub fn new() -> WebResult<Self> {
            Ok(Self)
        }
    }

    impl HttpClient for WasmHttpClient {
        fn get(&self, _url: &str) -> WebResult<Vec<u8>> {
            // Note: gloo-net's HTTP client is async-only
            // For now, return an error - this needs async context
            Err(WebError::Other("HTTP client requires async context in WASM".to_string()))
        }

        fn post_json<T: Serialize>(&self, _url: &str, _body: &T) -> WebResult<Vec<u8>> {
            Err(WebError::Other("HTTP client requires async context in WASM".to_string()))
        }

        fn put_json<T: Serialize>(&self, _url: &str, _body: &T) -> WebResult<Vec<u8>> {
            Err(WebError::Other("HTTP client requires async context in WASM".to_string()))
        }

        fn delete(&self, _url: &str) -> WebResult<Vec<u8>> {
            Err(WebError::Other("HTTP client requires async context in WASM".to_string()))
        }
    }

    impl Default for WasmHttpClient {
        fn default() -> Self {
            Self::new().expect("Failed to create HTTP client")
        }
    }

    impl Default for WasmWebSocketClient {
        fn default() -> Self {
            Self::new().expect("Failed to create WebSocket client")
        }
    }
}
