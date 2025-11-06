use godot::prelude::*;

macro_rules! debug_log {
    ($($arg:tt)*) => {
        if cfg!(feature = "debug_logs") {
            godot_print!($($arg)*);
        }
    };
}

//mod animation;
//mod inventory_data_warehouse;

pub mod config;  // Centralized configuration constants
mod db;  // Platform-specific SQLite abstraction
mod npc;
mod ui;
mod utility;
mod storage;
mod card;
mod economy;
// Stats moved to npc::entity module
mod combat;
mod world_gen;
mod structures;
mod loot;
mod events;  // Unified event system (actor-coordinator pattern)
pub mod web;  // Web/network module for HTTP/WebSocket (native + WASM)
mod async_runtime;  // Tokio runtime singleton for async operations

struct Godo;

#[gdextension]
unsafe impl ExtensionLibrary for Godo {
    fn on_level_init(level: InitLevel) {
        if level == InitLevel::Scene {
            // Install rustls crypto provider (ring) before any TLS connections
            #[cfg(not(target_family = "wasm"))]
            {
                let _ = rustls::crypto::ring::default_provider().install_default();
            }

            // Set up panic hook for better diagnostics
            std::panic::set_hook(Box::new(|panic_info| {
                let payload = panic_info.payload();
                let message = if let Some(s) = payload.downcast_ref::<&str>() {
                    s.to_string()
                } else if let Some(s) = payload.downcast_ref::<String>() {
                    s.clone()
                } else {
                    "Unknown panic payload".to_string()
                };

                let location = if let Some(loc) = panic_info.location() {
                    format!("{}:{}:{}", loc.file(), loc.line(), loc.column())
                } else {
                    "Unknown location".to_string()
                };

                godot::prelude::godot_error!(
                    "RUST PANIC: {} at {}",
                    message,
                    location
                );
            }));

            // Register AsyncRuntime singleton for tokio operations (native only)
            #[cfg(not(target_family = "wasm"))]
            {
                godot::classes::Engine::singleton().register_singleton(
                    async_runtime::AsyncRuntime::SINGLETON,
                    &async_runtime::AsyncRuntime::new_alloc()
                );
            }

            debug_log!("Godo v0.1.1 - Bevy GDExtension loaded successfully!");

            // DISABLED: Old entity worker (replaced by UnifiedEventBridge Actor)
            // npc::start_entity_worker();
        }
    }

    fn on_level_deinit(level: InitLevel) {
        if level == InitLevel::Scene {
            // Cleanup AsyncRuntime singleton (native only)
            #[cfg(not(target_family = "wasm"))]
            {
                let mut engine = godot::classes::Engine::singleton();
                if let Some(async_singleton) = engine.get_singleton(async_runtime::AsyncRuntime::SINGLETON) {
                    engine.unregister_singleton(async_runtime::AsyncRuntime::SINGLETON);
                    async_singleton.free();
                    godot_print!("[IRC] AsyncRuntime singleton cleaned up");
                }
            }
        }
    }
}