pub mod terrain_cache;
pub mod entity;  // Unified entity system (includes EntityManagerBridge)
pub mod unified_pathfinding;  // Unified pathfinding implementation
pub mod spawn_manager;  // Entity spawning (Rust-authoritative)

// Re-export unified entity types
pub use entity::{
    EntityData,
    EntityState,
    EntityStats,
    StatType,
    entity_state_flags,
    EntityManagerBridge,  // Now part of entity module
    ENTITY_STATS,         // Global entity stats storage
    ENTITY_DATA,          // Global entity data storage (source of truth)
};

// Export unified pathfinding bridge
pub use unified_pathfinding::{
    UnifiedPathfindingBridge,
    PathfindingRequest,
    PathfindingResult,
};

// Export spawn manager bridge
pub use spawn_manager::EntitySpawnBridge;

// Re-export legacy entity types for backwards compatibility (type aliases)
pub use entity::{ShipData, ShipState, NpcData, NpcState};
