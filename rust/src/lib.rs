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

// Web browser integration (wry-based webview for native platforms)
#[cfg(any(target_os = "macos", target_os = "windows"))]
pub mod web;

// Native-only: Tokio runtime for async operations (macOS, Windows, Linux)
#[cfg(not(target_family = "wasm"))]
mod async_runtime;

// macOS-only: Native window management (transparency, always-on-top, focus tracking, browser)
#[cfg(target_os = "macos")]
mod macos;

// Windows-only: Native window management (browser integration)
#[cfg(target_os = "windows")]
mod windows;

struct Godo;

#[gdextension]
unsafe impl ExtensionLibrary for Godo {
    fn on_level_init(level: InitLevel) {
        if level == InitLevel::Scene {
            // Re-enabled: AsyncRuntime for future async operations (native only)
            #[cfg(not(target_family = "wasm"))]
            {
                godot::classes::Engine::singleton().register_singleton(
                    async_runtime::AsyncRuntime::SINGLETON,
                    &async_runtime::AsyncRuntime::new_alloc()
                );
                godot_print!("[Runtime] AsyncRuntime singleton registered");
            }

            // Note: macOS window setup moved to MacOSWindowBridge._ready()
            // The window doesn't exist yet at InitLevel::Scene, so we defer initialization
            // to when the Godot scene tree is fully loaded

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