use dashmap::DashMap;
use once_cell::sync::Lazy;
use std::sync::Arc;

/// Stat types (must match GDScript enum)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(i32)]
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
    pub fn from_i32(value: i32) -> Option<Self> {
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
    pub stats: std::collections::HashMap<StatType, f32>,
}

impl EntityStats {
    pub fn new() -> Self {
        Self {
            stats: std::collections::HashMap::new(),
        }
    }

    /// Create stats with default values for a ship
    pub fn new_ship() -> Self {
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

    /// Create stats with default values for an NPC
    pub fn new_npc() -> Self {
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

    /// Create stats with default values for a building
    pub fn new_building() -> Self {
        let mut stats = Self::new();
        stats.set(StatType::HP, 200.0);
        stats.set(StatType::MaxHP, 200.0);
        stats.set(StatType::Defense, 10.0);
        stats.set(StatType::ProductionRate, 1.0);
        stats.set(StatType::StorageCapacity, 100.0);
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

    /// Add to stat with clamping (e.g., HP can't exceed MaxHP)
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

    /// Get all stats as vector of (StatType, value)
    pub fn get_all(&self) -> Vec<(StatType, f32)> {
        self.stats.iter().map(|(k, v)| (*k, *v)).collect()
    }
}

/// Global entity stats storage (ULID -> EntityStats)
static ENTITY_STATS: Lazy<Arc<DashMap<Vec<u8>, EntityStats>>> =
    Lazy::new(|| Arc::new(DashMap::new()));

/// Initialize the stats system
pub fn initialize() {
    // Force initialization of lazy static
    let _ = &*ENTITY_STATS;
}

/// Register entity with default stats based on type
pub fn register_entity(ulid: Vec<u8>, entity_type: &str) {
    let stats = match entity_type {
        "ship" => EntityStats::new_ship(),
        "npc" => EntityStats::new_npc(),
        "building" => EntityStats::new_building(),
        _ => EntityStats::new(),
    };

    ENTITY_STATS.insert(ulid, stats);
}

/// Register entity with custom stats
pub fn register_entity_with_stats(ulid: Vec<u8>, stats: EntityStats) {
    ENTITY_STATS.insert(ulid, stats);
}

/// Unregister entity
pub fn unregister_entity(ulid: &[u8]) -> bool {
    ENTITY_STATS.remove(ulid).is_some()
}

/// Get stat value for an entity
pub fn get_stat(ulid: &[u8], stat_type: StatType) -> Option<f32> {
    ENTITY_STATS.get(ulid).map(|stats| stats.get(stat_type))
}

/// Set stat value for an entity
pub fn set_stat(ulid: &[u8], stat_type: StatType, value: f32) -> bool {
    if let Some(mut stats) = ENTITY_STATS.get_mut(ulid) {
        stats.set(stat_type, value);
        true
    } else {
        false
    }
}

/// Add to stat value for an entity
pub fn add_stat(ulid: &[u8], stat_type: StatType, amount: f32) -> bool {
    if let Some(mut stats) = ENTITY_STATS.get_mut(ulid) {
        stats.add(stat_type, amount);
        true
    } else {
        false
    }
}

/// Get all stats for an entity
pub fn get_all_stats(ulid: &[u8]) -> Option<Vec<(StatType, f32)>> {
    ENTITY_STATS.get(ulid).map(|stats| stats.get_all())
}

/// Take damage (returns actual damage dealt, or None if entity not found)
pub fn take_damage(ulid: &[u8], damage: f32) -> Option<f32> {
    ENTITY_STATS.get_mut(ulid).map(|mut stats| stats.take_damage(damage))
}

/// Heal entity (returns actual amount healed, or None if entity not found)
pub fn heal(ulid: &[u8], amount: f32) -> Option<f32> {
    ENTITY_STATS.get_mut(ulid).map(|mut stats| stats.heal(amount))
}

/// Check if entity is alive
pub fn is_alive(ulid: &[u8]) -> bool {
    ENTITY_STATS.get(ulid).map(|stats| stats.is_alive()).unwrap_or(false)
}

/// Get all entities with their stats (for debugging)
pub fn get_all_entities() -> Vec<(Vec<u8>, Vec<(StatType, f32)>)> {
    ENTITY_STATS
        .iter()
        .map(|entry| (entry.key().clone(), entry.value().get_all()))
        .collect()
}

/// Get count of registered entities
pub fn count() -> usize {
    ENTITY_STATS.len()
}

/// Clear all entities (for testing/reset)
pub fn clear_all() {
    ENTITY_STATS.clear();
}

/// Get statistics for debugging
pub fn get_stats_summary() -> String {
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

    summary
}
