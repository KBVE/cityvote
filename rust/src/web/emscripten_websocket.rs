// Emscripten WebSocket FFI bindings for wasm32-unknown-emscripten target
// Uses Emscripten's native WebSocket API instead of wasm-bindgen
// Documentation: https://emscripten.org/docs/api_reference/websocket.h.html

#![cfg(target_family = "wasm")]

use std::os::raw::{c_char, c_int, c_uchar, c_uint, c_ushort, c_void};

// Emscripten WebSocket types
pub type EMSCRIPTEN_WEBSOCKET_T = c_int;
pub type EM_BOOL = c_int;

pub const EM_TRUE: EM_BOOL = 1;
pub const EM_FALSE: EM_BOOL = 0;

// WebSocket ready states (matches browser WebSocket API)
pub const EMSCRIPTEN_WEBSOCKET_READYSTATE_CONNECTING: c_ushort = 0;
pub const EMSCRIPTEN_WEBSOCKET_READYSTATE_OPEN: c_ushort = 1;
pub const EMSCRIPTEN_WEBSOCKET_READYSTATE_CLOSING: c_ushort = 2;
pub const EMSCRIPTEN_WEBSOCKET_READYSTATE_CLOSED: c_ushort = 3;

// Result codes
pub const EMSCRIPTEN_RESULT_SUCCESS: c_int = 0;
pub const EMSCRIPTEN_RESULT_DEFERRED: c_int = 1;
pub const EMSCRIPTEN_RESULT_NOT_SUPPORTED: c_int = -1;
pub const EMSCRIPTEN_RESULT_FAILED_NOT_DEFERRED: c_int = -2;
pub const EMSCRIPTEN_RESULT_INVALID_TARGET: c_int = -3;
pub const EMSCRIPTEN_RESULT_UNKNOWN_TARGET: c_int = -4;
pub const EMSCRIPTEN_RESULT_INVALID_PARAM: c_int = -5;
pub const EMSCRIPTEN_RESULT_FAILED: c_int = -6;
pub const EMSCRIPTEN_RESULT_NO_DATA: c_int = -7;

// Event types
pub const EMSCRIPTEN_EVENT_OPEN: c_int = 0;
pub const EMSCRIPTEN_EVENT_ERROR: c_int = 1;
pub const EMSCRIPTEN_EVENT_CLOSE: c_int = 2;
pub const EMSCRIPTEN_EVENT_MESSAGE: c_int = 3;

#[repr(C)]
pub struct EmscriptenWebSocketCreateAttributes {
    pub url: *const c_char,
    pub protocols: *const *const c_char,  // Array of protocol strings
    pub num_protocols: c_int,
    pub create_on_main_thread: EM_BOOL,   // Use EM_BOOL (c_int), not Rust bool
}

#[repr(C)]
pub struct EmscriptenWebSocketOpenEvent {
    pub socket: EMSCRIPTEN_WEBSOCKET_T,
}

#[repr(C)]
pub struct EmscriptenWebSocketErrorEvent {
    pub socket: EMSCRIPTEN_WEBSOCKET_T,
}

#[repr(C)]
pub struct EmscriptenWebSocketCloseEvent {
    pub socket: EMSCRIPTEN_WEBSOCKET_T,
    pub was_clean: EM_BOOL,
    pub code: c_ushort,
    pub reason: [c_char; 512],
}

#[repr(C)]
pub struct EmscriptenWebSocketMessageEvent {
    pub socket: EMSCRIPTEN_WEBSOCKET_T,
    pub data: *const c_uchar,
    pub num_bytes: c_uint,
    pub is_text: EM_BOOL,
}

// Callback type aliases
pub type EmWebSocketOpenCallback = unsafe extern "C" fn(
    event_type: c_int,
    event: *const EmscriptenWebSocketOpenEvent,
    user_data: *mut c_void,
) -> EM_BOOL;

pub type EmWebSocketErrorCallback = unsafe extern "C" fn(
    event_type: c_int,
    event: *const EmscriptenWebSocketErrorEvent,
    user_data: *mut c_void,
) -> EM_BOOL;

pub type EmWebSocketCloseCallback = unsafe extern "C" fn(
    event_type: c_int,
    event: *const EmscriptenWebSocketCloseEvent,
    user_data: *mut c_void,
) -> EM_BOOL;

pub type EmWebSocketMessageCallback = unsafe extern "C" fn(
    event_type: c_int,
    event: *const EmscriptenWebSocketMessageEvent,
    user_data: *mut c_void,
) -> EM_BOOL;

extern "C" {
    // Create and manage WebSocket
    pub fn emscripten_websocket_new(
        attrs: *const EmscriptenWebSocketCreateAttributes,
    ) -> EMSCRIPTEN_WEBSOCKET_T;

    pub fn emscripten_websocket_close(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        code: c_ushort,
        reason: *const c_char,
    ) -> c_int;

    pub fn emscripten_websocket_delete(socket: EMSCRIPTEN_WEBSOCKET_T) -> c_int;

    // Send data
    pub fn emscripten_websocket_send_utf8_text(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        text: *const c_char,
    ) -> c_int;

    pub fn emscripten_websocket_send_binary(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        data: *const c_void,
        num_bytes: c_uint,
    ) -> c_int;

    // Get state
    pub fn emscripten_websocket_get_ready_state(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        ready_state: *mut c_ushort,
    ) -> c_int;

    // Set callbacks
    pub fn emscripten_websocket_set_onopen_callback(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        user_data: *mut c_void,
        callback: EmWebSocketOpenCallback,
    ) -> c_int;

    pub fn emscripten_websocket_set_onerror_callback(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        user_data: *mut c_void,
        callback: EmWebSocketErrorCallback,
    ) -> c_int;

    pub fn emscripten_websocket_set_onclose_callback(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        user_data: *mut c_void,
        callback: EmWebSocketCloseCallback,
    ) -> c_int;

    pub fn emscripten_websocket_set_onmessage_callback(
        socket: EMSCRIPTEN_WEBSOCKET_T,
        user_data: *mut c_void,
        callback: EmWebSocketMessageCallback,
    ) -> c_int;

    // Check if WebSocket is supported
    pub fn emscripten_websocket_is_supported() -> EM_BOOL;
}
