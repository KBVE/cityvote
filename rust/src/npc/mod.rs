pub mod ship;
pub mod ground;
pub mod terrain_cache;

// Re-export entity types for convenience
pub use ship::{ShipData, ShipState};
pub use ground::{NpcData, NpcState};
