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

struct Godo;

#[gdextension]
unsafe impl ExtensionLibrary for Godo {
    fn on_level_init(level: InitLevel) {
        if level == InitLevel::Scene {
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

            debug_log!("Godo v0.1.1 - Bevy GDExtension loaded successfully!");

            // Start entity worker thread (hybrid lock-free architecture)
            npc::start_entity_worker();
        }
    }
}