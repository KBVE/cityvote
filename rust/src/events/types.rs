// Event and request type definitions for the unified event system

use crate::npc::terrain_cache::TerrainType;

/// All game events emitted from Actor to Godot
#[derive(Debug, Clone)]
pub enum GameEvent {
    // === Spawn Events ===
    EntitySpawned {
        ulid: Vec<u8>,
        position: (i32, i32),
        terrain_type: i32,
        entity_type: String,
    },
    SpawnFailed {
        entity_type: String,
        error: String,
    },

    // === Pathfinding Events ===
    PathFound {
        ulid: Vec<u8>,
        path: Vec<(i32, i32)>,
        cost: f32,
    },
    PathFailed {
        ulid: Vec<u8>,
    },
    RandomDestFound {
        ulid: Vec<u8>,
        destination: (i32, i32),
        found: bool,
    },

    // === Combat Events ===
    CombatStarted {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
    },
    DamageDealt {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
        damage: i32,
    },
    EntityDied {
        ulid: Vec<u8>,
    },
    CombatEnded {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
    },

    // === Economy Events ===
    ResourceChanged {
        resource_type: i32,
        current: f32,
        cap: f32,
        rate: f32,
    },

    // === Stats Events ===
    StatChanged {
        ulid: Vec<u8>,
        stat_type: i64,
        new_value: f32,
    },
    EntityDamaged {
        ulid: Vec<u8>,
        damage: f32,
        new_hp: f32,
    },
    EntityHealed {
        ulid: Vec<u8>,
        heal_amount: f32,
        new_hp: f32,
    },
}

/// All requests from Godot to Actor
#[derive(Debug, Clone)]
pub enum GameRequest {
    // === Spawn Requests ===
    SpawnEntity {
        entity_type: String,
        terrain_type: TerrainType,
        preferred_location: (i32, i32),
        search_radius: i32,
    },

    // === Pathfinding Requests ===
    RequestPath {
        ulid: Vec<u8>,
        terrain_type: TerrainType,
        start: (i32, i32),
        goal: (i32, i32),
        avoid_entities: bool,
    },
    RequestRandomDest {
        ulid: Vec<u8>,
        terrain_type: TerrainType,
        start: (i32, i32),
        min_distance: i32,
        max_distance: i32,
    },

    // === Entity Update Requests ===
    UpdateEntityPosition {
        ulid: Vec<u8>,
        position: (i32, i32),
    },
    UpdateEntityState {
        ulid: Vec<u8>,
        state: i64,
    },
    RemoveEntity {
        ulid: Vec<u8>,
    },

    // === Resource Requests ===
    SpendResources {
        cost: Vec<(i32, f32)>, // (resource_type, amount)
    },
    AddResources {
        resource_type: i32,
        amount: f32,
    },
    RegisterProducer {
        ulid: Vec<u8>,
        resource_type: i32,
        rate_per_sec: f32,
        active: bool,
    },
    RegisterConsumer {
        ulid: Vec<u8>,
        resource_type: i32,
        rate_per_sec: f32,
        active: bool,
    },
    RemoveProducer {
        ulid: Vec<u8>,
    },
    RemoveConsumer {
        ulid: Vec<u8>,
    },

    // === Stats Requests ===
    RegisterEntityStats {
        ulid: Vec<u8>,
        entity_type: String,
        terrain_type: i32,
        position: (i32, i32),
    },
    GetStat {
        ulid: Vec<u8>,
        stat_type: i64,
    },
    SetStat {
        ulid: Vec<u8>,
        stat_type: i64,
        value: f32,
    },
    TakeDamage {
        ulid: Vec<u8>,
        damage: f32,
    },
    Heal {
        ulid: Vec<u8>,
        amount: f32,
    },
}
