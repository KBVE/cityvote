// GDScript bridge for loot system

use godot::prelude::*;
use super::drop_table::{generate_loot, RewardType};
use super::loot_system;

#[derive(GodotClass)]
#[class(base=Node)]
pub struct LootBridge {
    #[base]
    base: Base<Node>,
}

#[godot_api]
impl INode for LootBridge {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl LootBridge {
    /// Notify loot system of combat start
    #[func]
    pub fn on_combat_started(&self, attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray) {
        loot_system::on_combat_started(
            attacker_ulid.to_vec(),
            defender_ulid.to_vec()
        );
    }

    /// Notify loot system of entity death
    #[func]
    pub fn on_entity_died(&self, entity_ulid: PackedByteArray) {
        loot_system::on_entity_died(&entity_ulid.to_vec());
    }

    /// Pop next loot event (returns Dictionary or null)
    #[func]
    pub fn pop_loot_event(&self) -> Variant {
        if let Some(event) = loot_system::pop_loot_event() {
            let mut dict = Dictionary::new();
            dict.set("player_ulid", PackedByteArray::from(event.player_ulid.as_slice()));
            dict.set("entity_type", event.entity_type);

            // Convert rewards to array
            let mut rewards_array = VariantArray::new();
            for reward in event.rewards {
                let mut reward_dict = Dictionary::new();
                reward_dict.set("type", reward.reward_type.to_string());
                reward_dict.set("amount", reward.amount);
                rewards_array.push(&reward_dict.to_variant());
            }
            dict.set("rewards", rewards_array);

            dict.to_variant()
        } else {
            Variant::nil()
        }
    }

    /// Generate loot for testing (not used in production)
    #[func]
    pub fn generate_loot(&self, entity_type: GString) -> VariantArray {
        let entity_type_str = entity_type.to_string();
        let rewards = generate_loot(&entity_type_str);

        let mut result = VariantArray::new();
        for reward in rewards {
            let mut dict = Dictionary::new();
            dict.set("type", reward.reward_type.to_string());
            dict.set("amount", reward.amount);
            result.push(&dict.to_variant());
        }

        result
    }

    /// Get drop table info for debugging
    #[func]
    pub fn debug_drop_table(&self, entity_type: GString) -> GString {
        let entity_type_str = entity_type.to_string();

        // Generate a few sample rolls
        let mut samples = Vec::new();
        for _ in 0..5 {
            let rewards = generate_loot(&entity_type_str);
            samples.push(format!("{:?}", rewards));
        }

        GString::from(format!("Sample drops for '{}':\n{}", entity_type_str, samples.join("\n")))
    }
}
