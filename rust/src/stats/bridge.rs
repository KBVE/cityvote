use godot::prelude::*;
use godot::classes::{Node, INode};
use super::entity_stats;

/// Godot-Rust bridge for EntityStats system
/// Manages entity stats and emits signals when stats change
#[derive(GodotClass)]
#[class(base=Node)]
pub struct StatsManagerBridge {
    #[base]
    base: Base<Node>,
}

#[godot_api]
impl INode for StatsManagerBridge {
    fn init(base: Base<Node>) -> Self {
        // Initialize stats system
        entity_stats::initialize();
        godot_print!("StatsManagerBridge: Initialized entity stats system");

        Self { base }
    }

    fn ready(&mut self) {
        godot_print!("StatsManagerBridge: Ready");
    }
}

#[godot_api]
impl StatsManagerBridge {
    /// Signal emitted when a stat changes
    /// Args: ulid (PackedByteArray), stat_type (int), new_value (float)
    #[signal]
    fn stat_changed(ulid: PackedByteArray, stat_type: i32, new_value: f32);

    /// Signal emitted when entity takes damage
    /// Args: ulid (PackedByteArray), damage (float), new_hp (float)
    #[signal]
    fn entity_damaged(ulid: PackedByteArray, damage: f32, new_hp: f32);

    /// Signal emitted when entity is healed
    /// Args: ulid (PackedByteArray), heal_amount (float), new_hp (float)
    #[signal]
    fn entity_healed(ulid: PackedByteArray, heal_amount: f32, new_hp: f32);

    /// Signal emitted when entity dies
    /// Args: ulid (PackedByteArray)
    #[signal]
    fn entity_died(ulid: PackedByteArray);

    /// Register entity with default stats based on type
    /// entity_type: "ship", "npc", or "building"
    #[func]
    fn register_entity(&mut self, ulid: PackedByteArray, entity_type: GString) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let type_str = entity_type.to_string();

        entity_stats::register_entity(ulid_bytes, &type_str);
    }

    /// Unregister entity
    #[func]
    fn unregister_entity(&mut self, ulid: PackedByteArray) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        entity_stats::unregister_entity(&ulid_bytes)
    }

    /// Get stat value for an entity
    #[func]
    fn get_stat(&self, ulid: PackedByteArray, stat_type: i32) -> f32 {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(st) = entity_stats::StatType::from_i32(stat_type) {
            entity_stats::get_stat(&ulid_bytes, st).unwrap_or(0.0)
        } else {
            0.0
        }
    }

    /// Set stat value for an entity (emits signal if successful)
    #[func]
    fn set_stat(&mut self, ulid: PackedByteArray, stat_type: i32, value: f32) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(st) = entity_stats::StatType::from_i32(stat_type) {
            let success = entity_stats::set_stat(&ulid_bytes, st, value);

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
    fn add_stat(&mut self, ulid: PackedByteArray, stat_type: i32, amount: f32) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(st) = entity_stats::StatType::from_i32(stat_type) {
            let success = entity_stats::add_stat(&ulid_bytes, st, amount);

            if success {
                let new_value = entity_stats::get_stat(&ulid_bytes, st).unwrap_or(0.0);
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

        if let Some(stats) = entity_stats::get_all_stats(&ulid_bytes) {
            for (stat_type, value) in stats {
                dict.set(stat_type as i32, value);
            }
        }

        dict
    }

    /// Entity takes damage (returns actual damage dealt)
    #[func]
    fn take_damage(&mut self, ulid: PackedByteArray, damage: f32) -> f32 {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(actual_damage) = entity_stats::take_damage(&ulid_bytes, damage) {
            let new_hp = entity_stats::get_stat(&ulid_bytes, entity_stats::StatType::HP)
                .unwrap_or(0.0);

            // Emit damage signal
            self.base_mut().emit_signal(
                "entity_damaged",
                &[ulid.to_variant(), actual_damage.to_variant(), new_hp.to_variant()],
            );

            // Emit HP stat changed signal
            self.base_mut().emit_signal(
                "stat_changed",
                &[(ulid.to_variant()), (entity_stats::StatType::HP as i32).to_variant(), new_hp.to_variant()],
            );

            // Check if entity died
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

        if let Some(actual_heal) = entity_stats::heal(&ulid_bytes, amount) {
            let new_hp = entity_stats::get_stat(&ulid_bytes, entity_stats::StatType::HP)
                .unwrap_or(0.0);

            // Emit heal signal
            self.base_mut().emit_signal(
                "entity_healed",
                &[ulid.to_variant(), actual_heal.to_variant(), new_hp.to_variant()],
            );

            // Emit HP stat changed signal
            self.base_mut().emit_signal(
                "stat_changed",
                &[ulid.to_variant(), (entity_stats::StatType::HP as i32).to_variant(), new_hp.to_variant()],
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
        entity_stats::is_alive(&ulid_bytes)
    }

    /// Get count of registered entities
    #[func]
    fn count(&self) -> i32 {
        entity_stats::count() as i32
    }

    /// Print statistics (debugging)
    #[func]
    fn print_stats(&self) {
        let summary = entity_stats::get_stats_summary();
        godot_print!("{}", summary);
    }
}
