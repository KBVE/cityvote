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

    // === Card Events ===
    ComboDetected {
        hand_rank: i32,          // PokerHand rank (0-9)
        hand_name: String,       // "One Pair", "Full House", etc.
        card_positions: Vec<(i32, i32)>,  // Positions of cards in the combo
        resource_bonuses: Vec<(i32, f32)>, // (resource_type, amount) pairs
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
    /// Process turn-based resource consumption (called by GameTimer on turn end)
    /// Consumes 1 food per active entity (entities with registered stats)
    ProcessTurnConsumption,
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
        player_ulid: Vec<u8>,  // Team affiliation (empty = AI team)
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

    // === Card Requests ===
    PlaceCard {
        x: i32,
        y: i32,
        ulid: Vec<u8>,
        suit: u8,
        value: u8,
        card_id: i32,
        is_custom: bool,
    },
    RemoveCardAt {
        x: i32,
        y: i32,
    },
    RemoveCardByUlid {
        ulid: Vec<u8>,
    },
    /// Request combo detection at a specific position
    /// Actor will check cards in radius and emit combo event if found
    DetectCombo {
        center_x: i32,
        center_y: i32,
        radius: i32,
    },
}

// ============================================================================
// WORKER COMMUNICATION TYPES
// ============================================================================

/// Entity snapshot for combat worker (immutable snapshot of entity state)
#[derive(Debug, Clone)]
pub struct CombatEntitySnapshot {
    pub ulid: Vec<u8>,
    pub player_ulid: Vec<u8>,  // Team affiliation (empty = AI team)
    pub position: (i32, i32),
    pub terrain_type: TerrainType,
    pub hp: i32,
    pub max_hp: i32,
    pub attack: i32,
    pub defense: i32,
    pub range: i32,
}

/// Work request sent from Actor to Combat Worker
#[derive(Debug, Clone)]
pub struct CombatWorkRequest {
    pub entities_snapshot: Vec<CombatEntitySnapshot>,
}

/// Work result sent from Combat Worker back to Actor
#[derive(Debug, Clone)]
pub enum CombatWorkResult {
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
}
