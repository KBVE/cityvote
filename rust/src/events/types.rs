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
    /// Spawn a projectile for ranged/bow/magic combat
    SpawnProjectile {
        attacker_ulid: Vec<u8>,
        attacker_position: (i32, i32),
        target_ulid: Vec<u8>,
        target_position: (i32, i32),
        projectile_type: u8,
        damage: i32,
    },

    // === Economy Events ===
    ResourceChanged {
        resource_type: i64,
        current: f64,
        cap: f64,
        rate: f64,
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

    // === Network Events ===
    /// Successfully connected to multiplayer server
    NetworkConnected {
        session_id: String,
    },
    /// Connection to server failed
    NetworkConnectionFailed {
        error: String,
    },
    /// Disconnected from server
    NetworkDisconnected,
    /// Received a message from the server
    NetworkMessageReceived {
        data: Vec<u8>,
    },
    /// Network error occurred
    NetworkError {
        message: String,
    },

    // === IRC Chat Events ===
    /// Connected to IRC server
    IrcConnected {
        nickname: String,
        server: String,
    },
    /// Disconnected from IRC
    IrcDisconnected {
        reason: Option<String>,
    },
    /// Joined IRC channel
    IrcJoinedChannel {
        channel: String,
        nickname: String,
    },
    /// Left IRC channel
    IrcLeftChannel {
        channel: String,
        nickname: String,
        message: Option<String>,
    },
    /// Received channel message
    IrcChannelMessage {
        channel: String,
        sender: String,
        message: String,
    },
    /// Received private message
    IrcPrivateMessage {
        sender: String,
        message: String,
    },
    /// User joined channel
    IrcUserJoined {
        channel: String,
        nickname: String,
    },
    /// User left channel
    IrcUserLeft {
        channel: String,
        nickname: String,
        message: Option<String>,
    },
    /// User quit IRC
    IrcUserQuit {
        nickname: String,
        message: Option<String>,
    },
    /// IRC error
    IrcError {
        message: String,
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
        cost: Vec<(i64, f64)>, // (resource_type, amount)
    },
    AddResources {
        resource_type: i64,
        amount: f64,
    },
    /// Process turn-based resource consumption (called by GameTimer on turn end)
    /// Consumes 1 food per active entity (entities with registered stats)
    ProcessTurnConsumption,
    RegisterProducer {
        ulid: Vec<u8>,
        resource_type: i64,
        rate_per_sec: f64,
        active: bool,
    },
    RegisterConsumer {
        ulid: Vec<u8>,
        resource_type: i64,
        rate_per_sec: f64,
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
        combat_type: u8,       // CombatType bitwise flags
        projectile_type: u8,   // ProjectileType enum value
        combat_range: i32,     // Attack range in hexes
        aggro_range: i32,      // Detection/aggro range in hexes
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

    // === Combat Requests ===
    /// Called by GDScript when a projectile hits its target
    /// This is when damage is actually applied for ranged/bow/magic combat
    ProjectileHit {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
        damage: i32,
        projectile_type: u8,
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

    // === Network Requests ===
    /// Connect to a multiplayer server
    NetworkConnect {
        url: String,
    },
    /// Send a network message to the server
    NetworkSend {
        message: Vec<u8>,
    },
    /// Disconnect from the multiplayer server
    NetworkDisconnect,

    // === IRC Chat Requests ===
    /// Connect to IRC server (Ergo WebIRC)
    IrcConnect {
        player_name: String,
    },
    /// Send a message to IRC channel
    IrcSendMessage {
        message: String,
    },
    /// Join an IRC channel
    IrcJoinChannel {
        channel: String,
    },
    /// Leave an IRC channel
    IrcLeaveChannel {
        channel: String,
        message: Option<String>,
    },
    /// Disconnect from IRC
    IrcDisconnect {
        message: Option<String>,
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
    pub mana: i32,             // Current mana (for magic attacks)
    pub max_mana: i32,         // Maximum mana
    pub attack: i32,
    pub defense: i32,
    pub range: i32,
    pub combat_type: u8,       // CombatType bitwise flags
    pub projectile_type: u8,   // ProjectileType enum value
    pub combat_range: i32,     // Attack range in hexes
    pub aggro_range: i32,      // Detection/aggro range in hexes
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
    /// Attack animation should play (sets ATTACKING state)
    AttackExecuted {
        attacker_ulid: Vec<u8>,
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
    /// Spawn a projectile for ranged/bow/magic combat
    SpawnProjectile {
        attacker_ulid: Vec<u8>,
        attacker_position: (i32, i32),
        target_ulid: Vec<u8>,
        target_position: (i32, i32),
        projectile_type: u8,  // ProjectileType enum value
        damage: i32,          // Pre-calculated damage
    },
    /// Mana consumed from attacker (for magic attacks)
    ManaConsumed {
        entity_ulid: Vec<u8>,
        mana_cost: i32,
        new_mana: i32,
    },
    /// Ranged unit should kite away from enemy (move to ideal distance)
    KiteAway {
        entity_ulid: Vec<u8>,
        enemy_position: (i32, i32),
        ideal_distance: i32,
    },
}
