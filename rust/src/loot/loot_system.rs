// Loot system - tracks combat and generates rewards

use std::sync::Arc;
use std::collections::HashMap;
use parking_lot::RwLock;
use crossbeam_queue::SegQueue;

use super::drop_table::{generate_loot, Reward, RewardType};
use crate::ui::toast;
use crate::economy::resource_ledger::{self, ResourceType};
use crate::storage::ulid_storage;

/// Loot event to send to GDScript (for Draw/XP only)
#[derive(Debug, Clone)]
pub struct LootEvent {
    pub player_ulid: Vec<u8>,
    pub entity_type: String,
    pub rewards: Vec<Reward>,
}

/// Tracks combat participants and generates loot on death
pub struct LootSystem {
    /// Maps defender_ulid -> attacker_ulid (who is attacking whom)
    combat_tracker: Arc<RwLock<HashMap<Vec<u8>, Vec<u8>>>>,

    /// Queue of loot events to send to GDScript (for Draw/XP only)
    loot_events: Arc<SegQueue<LootEvent>>,
}

impl LootSystem {
    pub fn new() -> Self {
        Self {
            combat_tracker: Arc::new(RwLock::new(HashMap::new())),
            loot_events: Arc::new(SegQueue::new()),
        }
    }

    /// Track combat start (defender -> attacker)
    pub fn on_combat_started(&self, attacker_ulid: Vec<u8>, defender_ulid: Vec<u8>) {
        self.combat_tracker.write().insert(defender_ulid, attacker_ulid);
    }

    /// Handle entity death - generate loot and send rewards
    /// Looks up entity type from ULID storage
    pub fn on_entity_died(&self, dead_entity_ulid: &[u8]) {
        // Find who killed this entity
        let killer_ulid = {
            let tracker = self.combat_tracker.read();
            tracker.get(dead_entity_ulid).cloned()
        };

        // Clean up tracker
        self.combat_tracker.write().remove(dead_entity_ulid);

        // If no killer, no loot
        let _killer_ulid = match killer_ulid {
            Some(ulid) => ulid,
            None => {
                // Entity died without combat (probably cleanup)
                return;
            }
        };

        // Note: We don't need killer_ulid or player_ulid anymore because:
        // - Resources are applied globally (not per-player yet)
        // - When we add multiplayer, we'll need to track player ownership elsewhere

        // Look up entity type from ULID storage
        let entity_type = ulid_storage::get_entity_class(dead_entity_ulid);

        // Generate loot
        let rewards = generate_loot(&entity_type);

        // Skip if no rewards
        if rewards.is_empty() {
            return;
        }

        // Format toast message with i18n placeholders
        // GDScript will replace {resource.gold}, {card.draw}, etc. with translated text
        let mut reward_texts = Vec::new();
        for reward in &rewards {
            let text = match reward.reward_type {
                RewardType::Draw => format!("+{} {{{{card.draw}}}}", reward.amount),
                RewardType::Gold => format!("+{} {{{{resource.gold}}}}", reward.amount),
                RewardType::Food => format!("+{} {{{{resource.food}}}}", reward.amount),
                RewardType::Faith => format!("+{} {{{{resource.faith}}}}", reward.amount),
                RewardType::Labor => format!("+{} {{{{resource.labor}}}}", reward.amount),
                RewardType::Experience => format!("+{} {{{{stat.experience}}}}", reward.amount),
            };
            reward_texts.push(text);
        }

        // Send toast notification with i18n placeholders
        // Format: "{game.loot}: +150 {resource.gold}, +200 {resource.food}"
        let toast_message = format!("{{{{game.loot}}}}: {}", reward_texts.join(", "));
        toast::send_message(toast_message);

        // Apply resources directly from Rust
        for reward in &rewards {
            match reward.reward_type {
                RewardType::Gold => {
                    resource_ledger::add(ResourceType::Gold, reward.amount as f32);
                },
                RewardType::Food => {
                    resource_ledger::add(ResourceType::Food, reward.amount as f32);
                },
                RewardType::Labor => {
                    resource_ledger::add(ResourceType::Labor, reward.amount as f32);
                },
                RewardType::Faith => {
                    resource_ledger::add(ResourceType::Faith, reward.amount as f32);
                },
                RewardType::Draw | RewardType::Experience => {
                    // Queue these for GDScript - card draw and XP systems don't exist yet in Rust
                    self.loot_events.push(LootEvent {
                        player_ulid: vec![], // Not used yet (no multiplayer)
                        entity_type: entity_type.clone(),
                        rewards: vec![reward.clone()],
                    });
                }
            }
        }
    }

    /// Pop next loot event (called from GDScript)
    pub fn pop_loot_event(&self) -> Option<LootEvent> {
        self.loot_events.pop()
    }
}

// Global instance
use once_cell::sync::Lazy;

static LOOT_SYSTEM: Lazy<LootSystem> = Lazy::new(|| LootSystem::new());

/// Get global loot system instance
pub fn get_loot_system() -> &'static LootSystem {
    &LOOT_SYSTEM
}

/// Track combat start
pub fn on_combat_started(attacker_ulid: Vec<u8>, defender_ulid: Vec<u8>) {
    get_loot_system().on_combat_started(attacker_ulid, defender_ulid);
}

/// Handle entity death
pub fn on_entity_died(dead_entity_ulid: &[u8]) {
    get_loot_system().on_entity_died(dead_entity_ulid);
}

/// Pop next loot event
pub fn pop_loot_event() -> Option<LootEvent> {
    get_loot_system().pop_loot_event()
}
