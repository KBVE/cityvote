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
// DEPRECATED: Web module disabled - IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
// pub mod web;  // Web/network module for HTTP/WebSocket (native + WASM)
mod async_runtime;  // Tokio runtime singleton for async operations

struct Godo;

#[gdextension]
unsafe impl ExtensionLibrary for Godo {
    fn on_level_init(level: InitLevel) {
        if level == InitLevel::Scene {
            // DEPRECATED: rustls no longer needed (WebSocket moved to GDScript)
            // #[cfg(not(target_family = "wasm"))]
            // {
            //     let _ = rustls::crypto::ring::default_provider().install_default();
            // }

            // DEPRECATED: AsyncRuntime no longer needed (no tokio WebSocket)
            // #[cfg(not(target_family = "wasm"))]
            // {
            //     godot::classes::Engine::singleton().register_singleton(
            //         async_runtime::AsyncRuntime::SINGLETON,
            //         &async_runtime::AsyncRuntime::new_alloc()
            //     );
            // }

            debug_log!("Godo v0.1.1 - GDExtension loaded successfully!");

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