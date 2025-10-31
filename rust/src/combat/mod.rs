// Combat system module
// Handles real-time combat resolution in separate worker thread

pub mod combat_system;
pub mod combat_state;
pub mod target_finder;
pub mod range_calculator;
pub mod bridge;

pub use combat_system::CombatSystem;
pub use combat_state::{CombatInstance, CombatEvent};
pub use bridge::CombatBridge;
