use godot::prelude::*;
use std::collections::HashMap;

/// Stat types (must match GDScript enum)
/// Uses i64 for Godot compatibility
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(i64)]
pub enum StatType {
    // Core combat stats
    HP = 0,           // Current health points
    MaxHP = 1,        // Maximum health points
    Attack = 2,       // Attack power
    Defense = 3,      // Defense/armor
    Speed = 4,        // Movement/action speed

    // Resource stats
    Energy = 5,       // Current energy points
    MaxEnergy = 6,    // Maximum energy points

    // Secondary stats
    Range = 7,        // Attack/vision range
    Morale = 8,       // Unit morale (affects combat)
    Experience = 9,   // XP for leveling
    Level = 10,       // Current level

    // Resource production (for structures)
    ProductionRate = 11,   // Production efficiency
    StorageCapacity = 12, // Resource storage

    // Special stats
    Luck = 13,        // Critical hit chance modifier
    Evasion = 14,     // Dodge chance
}

impl StatType {
    pub fn from_i64(value: i64) -> Option<Self> {
        match value {
            0 => Some(StatType::HP),
            1 => Some(StatType::MaxHP),
            2 => Some(StatType::Attack),
            3 => Some(StatType::Defense),
            4 => Some(StatType::Speed),
            5 => Some(StatType::Energy),
            6 => Some(StatType::MaxEnergy),
            7 => Some(StatType::Range),
            8 => Some(StatType::Morale),
            9 => Some(StatType::Experience),
            10 => Some(StatType::Level),
            11 => Some(StatType::ProductionRate),
            12 => Some(StatType::StorageCapacity),
            13 => Some(StatType::Luck),
            14 => Some(StatType::Evasion),
            _ => None,
        }
    }
}

/// Entity stats container
#[derive(Debug, Clone)]
pub struct EntityStats {
    pub stats: HashMap<StatType, f32>,
}

impl EntityStats {
    pub fn new() -> Self {
        Self {
            stats: HashMap::new(),
        }
    }

    /// Create stats with default values for a water entity (ship)
    pub fn new_water_entity() -> Self {
        let mut stats = Self::new();
        stats.set(StatType::HP, 100.0);
        stats.set(StatType::MaxHP, 100.0);
        stats.set(StatType::Energy, 100.0);
        stats.set(StatType::MaxEnergy, 100.0);
        stats.set(StatType::Attack, 10.0);
        stats.set(StatType::Defense, 5.0);
        stats.set(StatType::Speed, 1.0);
        stats.set(StatType::Range, 3.0);
        stats.set(StatType::Morale, 100.0);
        stats.set(StatType::Level, 1.0);
        stats
    }

    /// Create stats with default values for a land entity (NPC)
    pub fn new_land_entity() -> Self {
        let mut stats = Self::new();
        stats.set(StatType::HP, 50.0);
        stats.set(StatType::MaxHP, 50.0);
        stats.set(StatType::Energy, 100.0);
        stats.set(StatType::MaxEnergy, 100.0);
        stats.set(StatType::Attack, 5.0);
        stats.set(StatType::Defense, 2.0);
        stats.set(StatType::Speed, 1.5);
        stats.set(StatType::Range, 1.0);
        stats.set(StatType::Morale, 100.0);
        stats.set(StatType::Level, 1.0);
        stats
    }

    pub fn get(&self, stat_type: StatType) -> f32 {
        self.stats.get(&stat_type).copied().unwrap_or(0.0)
    }

    pub fn set(&mut self, stat_type: StatType, value: f32) {
        self.stats.insert(stat_type, value);
    }

    pub fn add(&mut self, stat_type: StatType, amount: f32) {
        let current = self.get(stat_type);
        self.set(stat_type, current + amount);
    }

    /// Add to stat with clamping
    pub fn add_clamped(&mut self, stat_type: StatType, amount: f32, min: f32, max: f32) {
        let current = self.get(stat_type);
        let new_value = (current + amount).clamp(min, max);
        self.set(stat_type, new_value);
    }

    /// Take damage (reduces HP, clamped to 0)
    pub fn take_damage(&mut self, damage: f32) -> f32 {
        let defense = self.get(StatType::Defense);
        let actual_damage = (damage - defense * 0.5).max(1.0); // Minimum 1 damage

        let current_hp = self.get(StatType::HP);
        let new_hp = (current_hp - actual_damage).max(0.0);
        self.set(StatType::HP, new_hp);

        actual_damage
    }

    /// Heal HP (clamped to MaxHP)
    pub fn heal(&mut self, amount: f32) -> f32 {
        let max_hp = self.get(StatType::MaxHP);
        let current_hp = self.get(StatType::HP);
        let actual_heal = (amount).min(max_hp - current_hp);
        self.set(StatType::HP, current_hp + actual_heal);
        actual_heal
    }

    /// Check if entity is alive
    pub fn is_alive(&self) -> bool {
        self.get(StatType::HP) > 0.0
    }

    /// Get all stats as vector
    pub fn get_all(&self) -> Vec<(StatType, f32)> {
        self.stats.iter().map(|(k, v)| (*k, *v)).collect()
    }
}

/// Terrain type for pathfinding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TerrainType {
    Land = 0b01,   // Walks on land tiles
    Water = 0b10,  // Walks on water tiles
}

impl TerrainType {
    pub fn from_u8(value: u8) -> Self {
        match value {
            0b10 => TerrainType::Water,
            _ => TerrainType::Land, // Default to land
        }
    }

    pub fn to_u8(&self) -> u8 {
        *self as u8
    }
}

/// Entity state (unified for all NPCs/Ships)
/// Entity state as bitwise flags (matches GDScript State enum)
/// Allows multiple states to be active simultaneously (e.g., MOVING | IN_COMBAT)
/// Uses i64 for Godot compatibility
pub mod entity_state_flags {
    pub const IDLE: i64 = 0b0001;           // 1 - Entity is idle
    pub const MOVING: i64 = 0b0010;         // 2 - Entity is moving
    pub const PATHFINDING: i64 = 0b0100;    // 4 - Pathfinding in progress
    pub const BLOCKED: i64 = 0b1000;        // 8 - Entity is blocked
    pub const INTERACTING: i64 = 0b10000;   // 16 - Entity is interacting
    pub const DEAD: i64 = 0b100000;         // 32 - Entity is dead
    pub const IN_COMBAT: i64 = 0b1000000;   // 64 - Entity is in combat
}

/// Legacy enum for backward compatibility (deprecated - use EntityStateFlags instead)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[deprecated(note = "Use EntityStateFlags bitwise flags instead")]
pub enum EntityState {
    Idle,
    Moving,
    Docked,         // Ships only (deprecated - use IDLE)
    Interacting,    // Land NPCs only
    Combat,
    Dead,
}

#[allow(deprecated)]
impl EntityState {
    pub fn to_string(&self) -> String {
        match self {
            EntityState::Idle => "idle".to_string(),
            EntityState::Moving => "moving".to_string(),
            EntityState::Docked => "docked".to_string(),
            EntityState::Interacting => "interacting".to_string(),
            EntityState::Combat => "combat".to_string(),
            EntityState::Dead => "dead".to_string(),
        }
    }

    pub fn from_string(s: &str) -> Self {
        match s {
            "idle" => EntityState::Idle,
            "moving" => EntityState::Moving,
            "docked" => EntityState::Docked,
            "interacting" => EntityState::Interacting,
            "combat" => EntityState::Combat,
            "dead" => EntityState::Dead,
            _ => EntityState::Idle,
        }
    }

    /// Convert legacy enum to bitwise flags
    pub fn to_flags(&self) -> i64 {
        match self {
            EntityState::Idle | EntityState::Docked => entity_state_flags::IDLE,
            EntityState::Moving => entity_state_flags::MOVING,
            EntityState::Interacting => entity_state_flags::INTERACTING,
            EntityState::Combat => entity_state_flags::IN_COMBAT,
            EntityState::Dead => entity_state_flags::DEAD,
        }
    }
}

// ============================================================
// Legacy type aliases for backward compatibility
// These map to the unified EntityState and EntityData
// ============================================================

/// Ship state (legacy - maps to EntityState)
pub type ShipState = EntityState;

/// NPC state (legacy - maps to EntityState)
pub type NpcState = EntityState;

/// Ship data (legacy - maps to EntityData with TerrainType::Water)
pub type ShipData = EntityData;

/// NPC data (legacy - maps to EntityData with TerrainType::Land)
pub type NpcData = EntityData;

/// Unified entity data structure (replaces ShipData and NpcData)
#[derive(Debug, Clone)]
pub struct EntityData {
    pub ulid: Vec<u8>,                     // 16-byte ULID
    pub position: (i32, i32),              // Current position (q, r) hex coords
    pub destination: Option<(i32, i32)>,   // Target destination if moving
    pub state: i64,                        // Bitwise state flags (matches GDScript State enum)
    pub terrain_type: TerrainType,         // Determines pathfinding behavior
    pub stats: EntityStats,                // Entity stats (HP, Attack, Defense, etc.)
    pub speed: f32,                        // Deprecated: use stats.get(StatType::Speed)
    pub owner_id: Option<i64>,             // Godot instance ID of owner (player, AI)
    pub entity_type: String,               // Type identifier (e.g., "viking", "king", "jezza")
    pub cargo: Vec<u8>,                    // Cargo data (water entities only)
}

impl EntityData {
    /// Create a new entity
    pub fn new(ulid: Vec<u8>, position: (i32, i32), terrain_type: TerrainType, entity_type: String) -> Self {
        // Initialize stats based on terrain type
        let stats = match terrain_type {
            TerrainType::Water => EntityStats::new_water_entity(),
            TerrainType::Land => EntityStats::new_land_entity(),
        };

        Self {
            ulid,
            position,
            destination: None,
            state: entity_state_flags::IDLE,
            terrain_type,
            stats,
            speed: if terrain_type == TerrainType::Water { 1.2 } else { 1.0 },
            owner_id: None,
            entity_type,
            cargo: Vec::new(),
        }
    }

    /// Create from legacy ShipData
    pub fn from_ship(ulid: Vec<u8>, position: (i32, i32)) -> Self {
        Self::new(ulid, position, TerrainType::Water, "viking".to_string())
    }

    /// Get stat value
    pub fn get_stat(&self, stat_type: StatType) -> f32 {
        self.stats.get(stat_type)
    }

    /// Set stat value
    pub fn set_stat(&mut self, stat_type: StatType, value: f32) {
        self.stats.set(stat_type, value);
    }

    /// Take damage
    pub fn take_damage(&mut self, damage: f32) -> f32 {
        let actual_damage = self.stats.take_damage(damage);
        // Update state if dead
        if !self.stats.is_alive() {
            self.state = entity_state_flags::DEAD;
        }
        actual_damage
    }

    /// Heal entity
    pub fn heal(&mut self, amount: f32) -> f32 {
        self.stats.heal(amount)
    }

    /// Check if entity is alive
    pub fn is_alive(&self) -> bool {
        self.stats.is_alive()
    }

    /// Create from legacy NpcData
    pub fn from_npc(ulid: Vec<u8>, position: (i32, i32), npc_type: String) -> Self {
        Self::new(ulid, position, TerrainType::Land, npc_type)
    }

    /// Check if this is a water entity (ship/viking)
    pub fn is_water_entity(&self) -> bool {
        self.terrain_type == TerrainType::Water
    }

    /// Check if this is a land entity
    pub fn is_land_entity(&self) -> bool {
        self.terrain_type == TerrainType::Land
    }

    /// Set destination and start moving
    pub fn set_destination(&mut self, dest: (i32, i32)) {
        self.destination = Some(dest);
        // Remove IDLE, add MOVING
        self.state = (self.state & !entity_state_flags::IDLE) | entity_state_flags::MOVING;
    }

    /// Update position (called when reaching destination)
    pub fn update_position(&mut self, new_pos: (i32, i32)) {
        self.position = new_pos;

        // Check if reached destination
        if let Some(dest) = self.destination {
            if dest == new_pos {
                self.destination = None;
                // Remove MOVING, add IDLE
                self.state = (self.state & !entity_state_flags::MOVING) | entity_state_flags::IDLE;
            }
        }
    }

    /// Get current position
    pub fn get_position(&self) -> (i32, i32) {
        self.position
    }

    /// Check if entity is moving
    pub fn is_moving(&self) -> bool {
        (self.state & entity_state_flags::MOVING) != 0
    }

    /// Check if entity is idle
    pub fn is_idle(&self) -> bool {
        (self.state & entity_state_flags::IDLE) != 0 &&
        (self.state & (entity_state_flags::MOVING | entity_state_flags::PATHFINDING | entity_state_flags::BLOCKED)) == 0
    }

    /// Set state to idle
    pub fn set_idle(&mut self) {
        // Clear all states except DEAD and IN_COMBAT, then set IDLE
        self.state = (self.state & (entity_state_flags::DEAD | entity_state_flags::IN_COMBAT)) | entity_state_flags::IDLE;
        self.destination = None;
    }

    /// Set state to moving
    pub fn set_moving(&mut self) {
        // Remove IDLE, add MOVING
        self.state = (self.state & !entity_state_flags::IDLE) | entity_state_flags::MOVING;
    }

    /// Check if entity is dead
    pub fn is_dead(&self) -> bool {
        (self.state & entity_state_flags::DEAD) != 0 || !self.stats.is_alive()
    }

    /// Use energy (returns true if successful)
    pub fn use_energy(&mut self, amount: f32) -> bool {
        let current_energy = self.stats.get(StatType::Energy);
        if current_energy >= amount {
            self.stats.set(StatType::Energy, current_energy - amount);
            true
        } else {
            false
        }
    }

    /// Restore energy
    pub fn restore_energy(&mut self, amount: f32) {
        let current_energy = self.stats.get(StatType::Energy);
        let max_energy = self.stats.get(StatType::MaxEnergy);
        self.stats.set(StatType::Energy, (current_energy + amount).min(max_energy));
    }

    /// Regenerate energy over time
    pub fn regenerate_energy(&mut self, amount: f32) {
        self.restore_energy(amount);
    }
}

// ============================================================
// Godot-exposed entity manager bridge
// ============================================================

use dashmap::DashMap;
use once_cell::sync::Lazy;
use std::sync::Arc;

/// Global entity stats storage (ULID -> EntityStats)
/// Part of the unified entity system
pub static ENTITY_STATS: Lazy<Arc<DashMap<Vec<u8>, EntityStats>>> =
    Lazy::new(|| Arc::new(DashMap::new()));

/// Global entity data storage (ULID -> EntityData)
/// This is the single source of truth for entity state
pub static ENTITY_DATA: Lazy<Arc<DashMap<Vec<u8>, EntityData>>> =
    Lazy::new(|| Arc::new(DashMap::new()));

/// Godot-Rust bridge for Entity management
/// Manages entity stats and emits signals when stats change
#[derive(GodotClass)]
#[class(base=Node)]
pub struct EntityManagerBridge {
    #[base]
    base: Base<Node>,
}

#[godot_api]
impl INode for EntityManagerBridge {
    fn init(base: Base<Node>) -> Self {
        // Force initialization of lazy static
        let _ = &*ENTITY_STATS;
        Self { base }
    }

    fn ready(&mut self) {
        // Entity stats system ready
    }
}

#[godot_api]
impl EntityManagerBridge {
    /// Signal emitted when a stat changes
    #[signal]
    fn stat_changed(ulid: PackedByteArray, stat_type: i64, new_value: f32);

    /// Signal emitted when entity takes damage
    #[signal]
    fn entity_damaged(ulid: PackedByteArray, damage: f32, new_hp: f32);

    /// Signal emitted when entity is healed
    #[signal]
    fn entity_healed(ulid: PackedByteArray, heal_amount: f32, new_hp: f32);

    /// Signal emitted when entity dies
    #[signal]
    fn entity_died(ulid: PackedByteArray);

    /// Signal emitted when entity state changes
    #[signal]
    fn entity_state_changed(ulid: PackedByteArray, new_state: i64);

    /// Signal emitted when entity position changes
    #[signal]
    fn entity_position_changed(ulid: PackedByteArray, q: i32, r: i32);

    /// Signal emitted when entity destination changes
    #[signal]
    fn entity_destination_changed(ulid: PackedByteArray, q: i32, r: i32, has_destination: bool);

    /// Register entity with default stats based on type
    #[func]
    fn register_entity(&mut self, ulid: PackedByteArray, entity_type: GString, q: i32, r: i32) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let type_str = entity_type.to_string();

        // Determine terrain type
        let terrain_type = match type_str.as_str() {
            "ship" | "water" | "viking" => TerrainType::Water,
            "npc" | "land" | "king" | "jezza" => TerrainType::Land,
            _ => TerrainType::Land,
        };

        // Create stats
        let stats = match terrain_type {
            TerrainType::Water => EntityStats::new_water_entity(),
            TerrainType::Land => EntityStats::new_land_entity(),
        };

        // Create entity data
        let entity_data = EntityData::new(
            ulid_bytes.clone(),
            (q, r),
            terrain_type,
            type_str.clone(),
        );

        // Insert into both storages
        ENTITY_STATS.insert(ulid_bytes.clone(), stats);
        ENTITY_DATA.insert(ulid_bytes, entity_data);
    }

    /// Unregister entity
    #[func]
    fn unregister_entity(&mut self, ulid: PackedByteArray) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let removed_stats = ENTITY_STATS.remove(&ulid_bytes).is_some();
        let removed_data = ENTITY_DATA.remove(&ulid_bytes).is_some();
        removed_stats || removed_data
    }

    /// Get stat value for an entity
    #[func]
    fn get_stat(&self, ulid: PackedByteArray, stat_type: i64) -> f32 {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(st) = StatType::from_i64(stat_type) {
            ENTITY_STATS.get(&ulid_bytes).map(|stats| stats.get(st)).unwrap_or(0.0)
        } else {
            0.0
        }
    }

    /// Set stat value for an entity (emits signal if successful)
    #[func]
    fn set_stat(&mut self, ulid: PackedByteArray, stat_type: i64, value: f32) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(st) = StatType::from_i64(stat_type) {
            let success = ENTITY_STATS.get_mut(&ulid_bytes).map(|mut stats| {
                stats.set(st, value);
            }).is_some();

            if success {
                self.base_mut().emit_signal(
                    "stat_changed",
                    &[ulid.to_variant(), stat_type.to_variant(), value.to_variant()],
                );
            }

            success
        } else {
            false
        }
    }

    /// Add to stat value for an entity (emits signal if successful)
    #[func]
    fn add_stat(&mut self, ulid: PackedByteArray, stat_type: i64, amount: f32) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(st) = StatType::from_i64(stat_type) {
            let mut new_value = 0.0;
            let success = ENTITY_STATS.get_mut(&ulid_bytes).map(|mut stats| {
                stats.add(st, amount);
                new_value = stats.get(st);
            }).is_some();

            if success {
                self.base_mut().emit_signal(
                    "stat_changed",
                    &[ulid.to_variant(), stat_type.to_variant(), new_value.to_variant()],
                );
            }

            success
        } else {
            false
        }
    }

    /// Get all stats for an entity as Dictionary
    #[func]
    fn get_all_stats(&self, ulid: PackedByteArray) -> Dictionary {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let mut dict = Dictionary::new();

        if let Some(stats) = ENTITY_STATS.get(&ulid_bytes) {
            for (stat_type, value) in stats.get_all() {
                dict.set(stat_type as i64, value);
            }
        }

        dict
    }

    /// Entity takes damage (returns actual damage dealt)
    #[func]
    fn take_damage(&mut self, ulid: PackedByteArray, damage: f32) -> f32 {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut stats_ref) = ENTITY_STATS.get_mut(&ulid_bytes) {
            let actual_damage = stats_ref.take_damage(damage);
            let new_hp = stats_ref.get(StatType::HP);

            self.base_mut().emit_signal(
                "entity_damaged",
                &[ulid.to_variant(), actual_damage.to_variant(), new_hp.to_variant()],
            );

            self.base_mut().emit_signal(
                "stat_changed",
                &[(ulid.to_variant()), (StatType::HP as i64).to_variant(), new_hp.to_variant()],
            );

            if new_hp <= 0.0 {
                self.base_mut().emit_signal("entity_died", &[ulid.to_variant()]);
            }

            actual_damage
        } else {
            0.0
        }
    }

    /// Heal entity (returns actual amount healed)
    #[func]
    fn heal(&mut self, ulid: PackedByteArray, amount: f32) -> f32 {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut stats_ref) = ENTITY_STATS.get_mut(&ulid_bytes) {
            let actual_heal = stats_ref.heal(amount);
            let new_hp = stats_ref.get(StatType::HP);

            self.base_mut().emit_signal(
                "entity_healed",
                &[ulid.to_variant(), actual_heal.to_variant(), new_hp.to_variant()],
            );

            self.base_mut().emit_signal(
                "stat_changed",
                &[ulid.to_variant(), (StatType::HP as i64).to_variant(), new_hp.to_variant()],
            );

            actual_heal
        } else {
            0.0
        }
    }

    /// Check if entity is alive
    #[func]
    fn is_alive(&self, ulid: PackedByteArray) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        ENTITY_STATS.get(&ulid_bytes).map(|stats| stats.is_alive()).unwrap_or(false)
    }

    // ============================================================
    // Entity State Management (Rust as Source of Truth)
    // ============================================================

    /// Get entity state flags
    #[func]
    fn get_entity_state(&self, ulid: PackedByteArray) -> i64 {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        ENTITY_DATA.get(&ulid_bytes)
            .map(|entity| entity.state)
            .unwrap_or(entity_state_flags::IDLE)
    }

    /// Get entity position
    #[func]
    fn get_entity_position(&self, ulid: PackedByteArray) -> Dictionary {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let mut dict = Dictionary::new();

        if let Some(entity) = ENTITY_DATA.get(&ulid_bytes) {
            dict.set("q", entity.position.0);
            dict.set("r", entity.position.1);
        }

        dict
    }

    /// Get entity destination (returns empty dict if no destination)
    #[func]
    fn get_entity_destination(&self, ulid: PackedByteArray) -> Dictionary {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let mut dict = Dictionary::new();

        if let Some(entity) = ENTITY_DATA.get(&ulid_bytes) {
            if let Some(dest) = entity.destination {
                dict.set("q", dest.0);
                dict.set("r", dest.1);
                dict.set("has_destination", true);
            } else {
                dict.set("has_destination", false);
            }
        } else {
            dict.set("has_destination", false);
        }

        dict
    }

    /// Get complete entity data as Dictionary
    #[func]
    fn get_entity_data(&self, ulid: PackedByteArray) -> Dictionary {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let mut dict = Dictionary::new();

        if let Some(entity) = ENTITY_DATA.get(&ulid_bytes) {
            dict.set("position_q", entity.position.0);
            dict.set("position_r", entity.position.1);
            dict.set("state", entity.state);
            dict.set("terrain_type", entity.terrain_type as i32);
            dict.set("entity_type", entity.entity_type.clone());
            dict.set("speed", entity.speed);

            if let Some(dest) = entity.destination {
                dict.set("destination_q", dest.0);
                dict.set("destination_r", dest.1);
                dict.set("has_destination", true);
            } else {
                dict.set("has_destination", false);
            }

            if let Some(owner) = entity.owner_id {
                dict.set("owner_id", owner);
            }
        }

        dict
    }

    /// Notify that entity started moving (GDScript -> Rust)
    #[func]
    fn notify_movement_started(&mut self, ulid: PackedByteArray, start_q: i32, start_r: i32, target_q: i32, target_r: i32) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid_bytes) {
            entity.position = (start_q, start_r);
            entity.destination = Some((target_q, target_r));
            entity.state = (entity.state & !entity_state_flags::IDLE) | entity_state_flags::MOVING;

            let new_state = entity.state;
            drop(entity);

            // Emit signals
            self.base_mut().emit_signal("entity_state_changed", &[ulid.to_variant(), new_state.to_variant()]);
            self.base_mut().emit_signal("entity_destination_changed", &[ulid.to_variant(), target_q.to_variant(), target_r.to_variant(), true.to_variant()]);
        }
    }

    /// Notify that entity completed movement (GDScript -> Rust)
    #[func]
    fn notify_movement_completed(&mut self, ulid: PackedByteArray, final_q: i32, final_r: i32) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid_bytes) {
            entity.position = (final_q, final_r);
            entity.destination = None;
            entity.state = (entity.state & !entity_state_flags::MOVING) | entity_state_flags::IDLE;

            let new_state = entity.state;
            drop(entity);

            // Emit signals
            self.base_mut().emit_signal("entity_state_changed", &[ulid.to_variant(), new_state.to_variant()]);
            self.base_mut().emit_signal("entity_position_changed", &[ulid.to_variant(), final_q.to_variant(), final_r.to_variant()]);
            self.base_mut().emit_signal("entity_destination_changed", &[ulid.to_variant(), 0.to_variant(), 0.to_variant(), false.to_variant()]);
        }
    }

    /// Notify that pathfinding started (GDScript -> Rust)
    #[func]
    fn notify_pathfinding_started(&mut self, ulid: PackedByteArray, target_q: i32, target_r: i32) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid_bytes) {
            entity.destination = Some((target_q, target_r));
            entity.state = (entity.state & !entity_state_flags::IDLE) | entity_state_flags::PATHFINDING;

            let new_state = entity.state;
            drop(entity);

            self.base_mut().emit_signal("entity_state_changed", &[ulid.to_variant(), new_state.to_variant()]);
        }
    }

    /// Notify that pathfinding completed (GDScript -> Rust)
    #[func]
    fn notify_pathfinding_completed(&mut self, ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid_bytes) {
            entity.state = entity.state & !entity_state_flags::PATHFINDING;

            let new_state = entity.state;
            drop(entity);

            self.base_mut().emit_signal("entity_state_changed", &[ulid.to_variant(), new_state.to_variant()]);
        }
    }

    /// Update entity position (called frequently during movement)
    #[func]
    fn update_position(&mut self, ulid: PackedByteArray, q: i32, r: i32) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid_bytes) {
            entity.position = (q, r);
            drop(entity);

            self.base_mut().emit_signal("entity_position_changed", &[ulid.to_variant(), q.to_variant(), r.to_variant()]);
        }
    }

    /// Set entity state directly (use notification methods instead when possible)
    #[func]
    fn set_entity_state(&mut self, ulid: PackedByteArray, new_state: i64) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid_bytes) {
            entity.state = new_state;
            drop(entity);

            self.base_mut().emit_signal("entity_state_changed", &[ulid.to_variant(), new_state.to_variant()]);
        }
    }

    /// Get count of registered entities
    #[func]
    fn count(&self) -> i32 {
        ENTITY_STATS.len() as i32
    }

    /// Print statistics (debugging)
    #[func]
    fn print_stats(&self) {
        let mut summary = String::from("=== Entity Stats Summary ===\n");
        summary.push_str(&format!("Total entities: {}\n", ENTITY_STATS.len()));

        for entry in ENTITY_STATS.iter() {
            let ulid_hex = entry.key().iter()
                .map(|b| format!("{:02x}", b))
                .collect::<String>();

            summary.push_str(&format!("\nEntity {}:\n", &ulid_hex[..8]));

            let stats = entry.value();
            for (stat_type, value) in stats.get_all() {
                summary.push_str(&format!("  {:?}: {:.1}\n", stat_type, value));
            }
        }

        godot_print!("{}", summary);
    }
}
