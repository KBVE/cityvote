// Unified event system module
// Actor-coordinator pattern with lock-free communication

pub mod actor;
pub mod types;
pub mod bridge;
pub mod workers;

pub use actor::GameActor;
pub use types::{GameEvent, GameRequest};
pub use bridge::UnifiedEventBridge;
