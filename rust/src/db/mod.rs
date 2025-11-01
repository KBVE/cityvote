/// Database abstraction layer for terrain cache
///
/// This module provides a unified interface for SQLite operations across different platforms:
/// - Native (macOS, Linux, Windows): Uses rusqlite with high-level API
/// - WASM: Uses sqlite-wasm-rs with low-level FFI

#[cfg(not(target_family = "wasm"))]
mod native;
#[cfg(target_family = "wasm")]
mod wasm;

#[cfg(not(target_family = "wasm"))]
pub use native::TerrainDb;
#[cfg(target_family = "wasm")]
pub use wasm::TerrainDb;

/// Database error type
#[derive(Debug)]
pub enum DbError {
    OpenFailed(String),
    ExecuteFailed(String),
    QueryFailed(String),
}

impl std::fmt::Display for DbError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            DbError::OpenFailed(msg) => write!(f, "Failed to open database: {}", msg),
            DbError::ExecuteFailed(msg) => write!(f, "Failed to execute SQL: {}", msg),
            DbError::QueryFailed(msg) => write!(f, "Failed to query database: {}", msg),
        }
    }
}

impl std::error::Error for DbError {}
