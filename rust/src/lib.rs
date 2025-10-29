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

mod npc;
mod ui;
mod utility;
mod storage;
mod card;
mod economy;
mod stats;

struct Godo;

#[gdextension]
unsafe impl ExtensionLibrary for Godo {
    fn on_level_init(level: InitLevel) {
        if level == InitLevel::Scene {
            debug_log!("Godo v0.1.1 - Bevy GDExtension loaded successfully!");
        }
    }
}