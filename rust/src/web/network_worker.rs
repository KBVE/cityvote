// Network worker thread for WebSocket communication
// Integrates with the actor system to handle multiplayer networking

use godot::prelude::*;
use super::client::{ConnectionState, WebMessage, WebSocketClient};
use crossbeam_channel::{unbounded, Receiver, Sender};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

#[cfg(not(target_family = "wasm"))]
use super::client::NativeWebSocketClient;

#[cfg(target_family = "wasm")]
use super::client::WasmWebSocketClient;

/// Network worker messages sent TO the worker
#[derive(Debug, Clone)]
pub enum NetworkWorkerRequest {
    /// Connect to a WebSocket server
    Connect { url: String },

    /// Send a message through the WebSocket
    SendMessage { data: Vec<u8> },

    /// Send a text message
    SendText { text: String },

    /// Disconnect from the WebSocket
    Disconnect,

    /// Shutdown the worker thread
    Shutdown,
}

/// Network worker messages sent FROM the worker
#[derive(Debug, Clone)]
pub enum NetworkWorkerResponse {
    /// Successfully connected to server
    Connected,

    /// Connection failed
    ConnectionFailed { error: String },

    /// Disconnected from server
    Disconnected,

    /// Received a binary message
    MessageReceived { data: Vec<u8> },

    /// Received a text message
    TextReceived { text: String },

    /// Connection state changed
    StateChanged { state: ConnectionState },

    /// Error occurred
    Error { message: String },
}

/// Network worker configuration
#[derive(Debug, Clone)]
pub struct NetworkWorkerConfig {
    /// Reconnection attempt interval in milliseconds
    pub reconnect_interval_ms: u64,

    /// Maximum reconnection attempts (0 = infinite)
    pub max_reconnect_attempts: u32,

    /// Enable automatic reconnection
    pub auto_reconnect: bool,

    /// Tick rate for worker loop in milliseconds
    pub tick_rate_ms: u64,
}

impl Default for NetworkWorkerConfig {
    fn default() -> Self {
        Self {
            reconnect_interval_ms: 5000,  // 5 seconds
            max_reconnect_attempts: 0,    // Infinite
            auto_reconnect: true,
            tick_rate_ms: 16,              // ~60 Hz
        }
    }
}

/// Handle to communicate with the network worker thread
/// NOTE: Do NOT derive Clone! Cloning the Receiver causes messages to be distributed
/// round-robin among clones instead of all going to one consumer.
/// Use Arc<NetworkWorkerHandle> if you need to share it.
pub struct NetworkWorkerHandle {
    pub request_tx: Sender<NetworkWorkerRequest>,
    pub response_rx: Receiver<NetworkWorkerResponse>,
}

impl NetworkWorkerHandle {
    /// Send a connection request
    pub fn connect(&self, url: String) {
        godot_print!("[IRC] NetworkWorkerHandle::connect() - sending Connect request for: {}", url);
        match self.request_tx.send(NetworkWorkerRequest::Connect { url: url.clone() }) {
            Ok(_) => godot_print!("[IRC] NetworkWorkerHandle::connect() - request sent successfully"),
            Err(e) => godot_error!("[IRC] NetworkWorkerHandle::connect() - ERROR sending request: {:?}", e),
        }
    }

    /// Send a binary message
    pub fn send_message(&self, data: Vec<u8>) {
        let _ = self.request_tx.send(NetworkWorkerRequest::SendMessage { data });
    }

    /// Send a text message
    pub fn send_text(&self, text: String) {
        let _ = self.request_tx.send(NetworkWorkerRequest::SendText { text });
    }

    /// Disconnect from the server
    pub fn disconnect(&self) {
        let _ = self.request_tx.send(NetworkWorkerRequest::Disconnect);
    }

    /// Shutdown the worker
    pub fn shutdown(&self) {
        let _ = self.request_tx.send(NetworkWorkerRequest::Shutdown);
    }

    /// Try to receive a response (non-blocking)
    pub fn try_recv(&self) -> Option<NetworkWorkerResponse> {
        self.response_rx.try_recv().ok()
    }
}

/// Start the network worker thread
/// Returns a handle to communicate with the worker
/// Note: WASM uses pthread emulation via Emscripten atomics
pub fn start_network_worker(config: NetworkWorkerConfig) -> NetworkWorkerHandle {
    let (request_tx, request_rx) = unbounded::<NetworkWorkerRequest>();
    let (response_tx, response_rx) = unbounded::<NetworkWorkerResponse>();

    // Spawn the worker thread (works on both native and WASM with pthread)
    thread::spawn(move || {
        run_network_worker(config, request_rx, response_tx);
    });

    NetworkWorkerHandle {
        request_tx,
        response_rx,
    }
}

/// Main network worker loop
#[cfg(not(target_family = "wasm"))]
fn run_network_worker(
    config: NetworkWorkerConfig,
    request_rx: Receiver<NetworkWorkerRequest>,
    response_tx: Sender<NetworkWorkerResponse>,
) {
    godot_print!("[IRC] Network worker thread started, tick_rate: {}ms", config.tick_rate_ms);
    let mut client: Option<NativeWebSocketClient> = None;
    let mut reconnect_attempts = 0u32;
    let mut last_url: Option<String> = None;
    let mut should_reconnect = false;

    let tick_duration = Duration::from_millis(config.tick_rate_ms);

    godot_print!("[IRC] Network worker entering main loop");
    loop {
        // Process incoming requests
        while let Ok(request) = request_rx.try_recv() {
            match request {
                NetworkWorkerRequest::Connect { url } => {
                    godot_print!("[IRC] Network worker received Connect request for: {}", url);
                    match NativeWebSocketClient::new() {
                        Ok(mut ws_client) => {
                            godot_print!("[IRC] WebSocket client created, attempting connection...");
                            if let Err(e) = ws_client.connect(&url) {
                                godot_error!("[IRC] WebSocket connection failed: {}", e);
                                let _ = response_tx.send(NetworkWorkerResponse::ConnectionFailed {
                                    error: e.to_string(),
                                });
                            } else {
                                godot_print!("[IRC] WebSocket connect() call succeeded, waiting for connection...");
                                client = Some(ws_client);
                                last_url = Some(url.clone());
                                reconnect_attempts = 0;
                                should_reconnect = config.auto_reconnect;

                                // Wait for connection to establish (async operation)
                                // The tokio async task will update the state
                                // Poll for up to 5 seconds with 50ms intervals
                                godot_print!("[IRC] Starting connection state polling...");
                                let mut attempts = 0;
                                let max_attempts = 100; // 100 * 50ms = 5 seconds
                                let mut connected = false;
                                let mut failed = false;

                                while attempts < max_attempts {
                                    thread::sleep(Duration::from_millis(50));
                                    attempts += 1;

                                    if let Some(ref ws) = client {
                                        let current_state = ws.state();

                                        // Log every 10 attempts (every 500ms)
                                        if attempts % 10 == 0 {
                                            godot_print!("[IRC] Poll attempt {}/{}, state: {:?}", attempts, max_attempts, current_state);
                                        }

                                        match current_state {
                                            ConnectionState::Connected => {
                                                godot_print!("[IRC] WebSocket CONNECTED after {}ms!", attempts * 50);
                                                godot_print!("[IRC] NetworkWorker: Sending Connected response...");
                                                match response_tx.send(NetworkWorkerResponse::Connected) {
                                                    Ok(_) => godot_print!("[IRC] NetworkWorker: Connected response sent successfully"),
                                                    Err(e) => godot_error!("[IRC] NetworkWorker: FAILED to send Connected response: {:?}", e),
                                                }
                                                connected = true;
                                                break;
                                            }
                                            ConnectionState::Failed => {
                                                godot_error!("[IRC] WebSocket FAILED after {}ms", attempts * 50);
                                                let _ = response_tx.send(NetworkWorkerResponse::ConnectionFailed {
                                                    error: "Connection failed - check logs for details".to_string(),
                                                });
                                                failed = true;
                                                break;
                                            }
                                            _ => {
                                                // Still connecting, keep polling
                                            }
                                        }
                                    }
                                }

                                if !connected && !failed {
                                    godot_error!("[IRC] WebSocket connection TIMEOUT after {}ms", max_attempts * 50);
                                    let _ = response_tx.send(NetworkWorkerResponse::ConnectionFailed {
                                        error: format!("Connection timeout after {}ms", max_attempts * 50),
                                    });
                                }
                            }
                        }
                        Err(e) => {
                            godot_error!("[IRC] Failed to create WebSocket client: {}", e);
                            let _ = response_tx.send(NetworkWorkerResponse::ConnectionFailed {
                                error: e.to_string(),
                            });
                        }
                    }
                }

                NetworkWorkerRequest::SendMessage { data } => {
                    if let Some(ref mut ws_client) = client {
                        if let Err(e) = ws_client.send(WebMessage::Binary(data)) {
                            let _ = response_tx.send(NetworkWorkerResponse::Error {
                                message: format!("Send failed: {}", e),
                            });
                        }
                    }
                }

                NetworkWorkerRequest::SendText { text } => {
                    if let Some(ref mut ws_client) = client {
                        if let Err(e) = ws_client.send(WebMessage::Text(text)) {
                            let _ = response_tx.send(NetworkWorkerResponse::Error {
                                message: format!("Send failed: {}", e),
                            });
                        }
                    }
                }

                NetworkWorkerRequest::Disconnect => {
                    if let Some(ref mut ws_client) = client {
                        let _ = ws_client.close();
                        client = None;
                        should_reconnect = false;
                        let _ = response_tx.send(NetworkWorkerResponse::Disconnected);
                    }
                }

                NetworkWorkerRequest::Shutdown => {
                    if let Some(ref mut ws_client) = client {
                        let _ = ws_client.close();
                    }
                    return; // Exit worker thread
                }
            }
        }

        // Process incoming messages from WebSocket
        let mut should_clear_client = false;

        if let Some(ref mut ws_client) = client {
            // Check connection state
            let state = ws_client.state();

            if state == ConnectionState::Failed || state == ConnectionState::Disconnected {
                should_clear_client = true;
            } else if state == ConnectionState::Connected {
                // Try to receive messages
                while let Ok(Some(msg)) = ws_client.try_recv() {
                    match msg {
                        WebMessage::Binary(data) => {
                            let _ = response_tx.send(NetworkWorkerResponse::MessageReceived { data });
                        }
                        WebMessage::Text(text) => {
                            let _ = response_tx.send(NetworkWorkerResponse::TextReceived { text });
                        }
                        WebMessage::Close => {
                            let _ = response_tx.send(NetworkWorkerResponse::Disconnected);
                            should_clear_client = true;
                            break;
                        }
                        _ => {} // Ignore ping/pong
                    }
                }
            }
        }

        // Handle disconnection and reconnection outside the borrow
        if should_clear_client {
            client = None;

            // Attempt reconnection if enabled
            if should_reconnect {
                if config.max_reconnect_attempts == 0
                    || reconnect_attempts < config.max_reconnect_attempts
                {
                    reconnect_attempts += 1;
                    thread::sleep(Duration::from_millis(config.reconnect_interval_ms));

                    if let Some(ref url) = last_url {
                        if let Ok(mut new_client) = NativeWebSocketClient::new() {
                            if new_client.connect(url).is_ok() {
                                client = Some(new_client);
                                reconnect_attempts = 0;
                            }
                        }
                    }
                }
            }
        }

        // Sleep to avoid busy-waiting
        thread::sleep(tick_duration);
    }
}

/// Main network worker loop for WASM
/// Uses pthread emulation via Emscripten atomics
#[cfg(target_family = "wasm")]
fn run_network_worker(
    config: NetworkWorkerConfig,
    request_rx: Receiver<NetworkWorkerRequest>,
    response_tx: Sender<NetworkWorkerResponse>,
) {
    godot_print!("[IRC] WASM Network worker thread started with pthread, tick_rate: {}ms", config.tick_rate_ms);
    let mut client: Option<WasmWebSocketClient> = None;
    let mut reconnect_attempts = 0u32;
    let mut last_url: Option<String> = None;
    let mut should_reconnect = false;

    let tick_duration = Duration::from_millis(config.tick_rate_ms);

    loop {
            // Process incoming requests
            while let Ok(request) = request_rx.try_recv() {
                match request {
                    NetworkWorkerRequest::Connect { url } => {
                        match WasmWebSocketClient::new() {
                            Ok(mut ws_client) => {
                                if let Err(e) = ws_client.connect(&url) {
                                    let _ = response_tx.send(NetworkWorkerResponse::ConnectionFailed {
                                        error: e.to_string(),
                                    });
                                } else {
                                    client = Some(ws_client);
                                    last_url = Some(url.clone());
                                    reconnect_attempts = 0;
                                    should_reconnect = config.auto_reconnect;
                                }
                            }
                            Err(e) => {
                                let _ = response_tx.send(NetworkWorkerResponse::ConnectionFailed {
                                    error: e.to_string(),
                                });
                            }
                        }
                    }

                    NetworkWorkerRequest::SendMessage { data } => {
                        if let Some(ref mut ws_client) = client {
                            if let Err(e) = ws_client.send(WebMessage::Binary(data)) {
                                let _ = response_tx.send(NetworkWorkerResponse::Error {
                                    message: format!("Send failed: {}", e),
                                });
                            }
                        }
                    }

                    NetworkWorkerRequest::SendText { text } => {
                        if let Some(ref mut ws_client) = client {
                            if let Err(e) = ws_client.send(WebMessage::Text(text)) {
                                let _ = response_tx.send(NetworkWorkerResponse::Error {
                                    message: format!("Send failed: {}", e),
                                });
                            }
                        }
                    }

                    NetworkWorkerRequest::Disconnect => {
                        if let Some(ref mut ws_client) = client {
                            let _ = ws_client.close();
                            client = None;
                            should_reconnect = false;
                            let _ = response_tx.send(NetworkWorkerResponse::Disconnected);
                        }
                    }

                    NetworkWorkerRequest::Shutdown => {
                        if let Some(ref mut ws_client) = client {
                            let _ = ws_client.close();
                        }
                        return; // Exit worker
                    }
                }
            }

            // Process incoming messages from WebSocket
            let mut should_disconnect = false;
            if let Some(ref mut ws_client) = client {
                let state = ws_client.state();

                if state == ConnectionState::Failed || state == ConnectionState::Disconnected {
                    should_disconnect = true;
                } else if state == ConnectionState::Connected {
                    // Try to receive messages
                    while let Ok(Some(msg)) = ws_client.try_recv() {
                        match msg {
                            WebMessage::Binary(data) => {
                                let _ = response_tx.send(NetworkWorkerResponse::MessageReceived { data });
                            }
                            WebMessage::Text(text) => {
                                let _ = response_tx.send(NetworkWorkerResponse::TextReceived { text });
                            }
                            WebMessage::Close => {
                                let _ = response_tx.send(NetworkWorkerResponse::Disconnected);
                                should_disconnect = true;
                                break;
                            }
                            _ => {} // Ignore ping/pong
                        }
                    }
                }
            }

            // Handle disconnection outside the borrow
            if should_disconnect {
                client = None;

                // Attempt reconnection if enabled
                if should_reconnect {
                    if config.max_reconnect_attempts == 0
                        || reconnect_attempts < config.max_reconnect_attempts
                    {
                        reconnect_attempts += 1;

                        // Sleep before reconnection attempt
                        thread::sleep(Duration::from_millis(config.reconnect_interval_ms));

                        if let Some(ref url) = last_url {
                            if let Ok(mut new_client) = WasmWebSocketClient::new() {
                                if new_client.connect(url).is_ok() {
                                    client = Some(new_client);
                                    reconnect_attempts = 0;
                                }
                            }
                        }
                    }
                }
            }

            // Sleep to avoid busy-waiting (pthread in WASM supports thread::sleep)
            thread::sleep(tick_duration);
        }
}
