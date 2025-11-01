// Loot drop table system
// Handles reward generation when entities are killed

use rand::Rng;

/// Represents a single reward item
#[derive(Debug, Clone)]
pub struct Reward {
    pub reward_type: RewardType,
    pub amount: i32,
}

/// Types of rewards that can be dropped
#[derive(Debug, Clone, PartialEq)]
pub enum RewardType {
    Draw,      // Card draw
    Gold,      // Currency
    Food,      // Resource
    Faith,     // Resource
    Labor,     // Resource
    Experience, // XP
}

impl RewardType {
    pub fn to_string(&self) -> String {
        match self {
            RewardType::Draw => "draw".to_string(),
            RewardType::Gold => "gold".to_string(),
            RewardType::Food => "food".to_string(),
            RewardType::Faith => "faith".to_string(),
            RewardType::Labor => "labor".to_string(),
            RewardType::Experience => "experience".to_string(),
        }
    }
}

/// A potential drop with its probability
#[derive(Debug, Clone)]
pub struct DropEntry {
    pub reward_type: RewardType,
    pub min_amount: i32,
    pub max_amount: i32,
    pub probability: f32, // 0.0 to 1.0 (1.0 = 100% chance)
}

/// Drop table for a specific entity type
#[derive(Debug, Clone)]
pub struct DropTable {
    pub entity_type: String,
    pub drops: Vec<DropEntry>,
}

impl DropTable {
    /// Roll for loot drops based on this table
    pub fn roll_drops(&self) -> Vec<Reward> {
        let mut rng = rand::thread_rng();
        let mut rewards = Vec::new();

        for entry in &self.drops {
            // Roll for probability
            let roll: f32 = rng.gen();
            if roll <= entry.probability {
                // Determine amount
                let amount = if entry.min_amount == entry.max_amount {
                    entry.min_amount
                } else {
                    rng.gen_range(entry.min_amount..=entry.max_amount)
                };

                rewards.push(Reward {
                    reward_type: entry.reward_type.clone(),
                    amount,
                });
            }
        }

        rewards
    }
}

/// Global drop table registry
pub struct DropTableRegistry {
    tables: std::collections::HashMap<String, DropTable>,
}

impl DropTableRegistry {
    pub fn new() -> Self {
        let mut registry = Self {
            tables: std::collections::HashMap::new(),
        };

        // Initialize default drop tables
        registry.register_default_tables();
        registry
    }

    /// Register all default drop tables for entity types
    fn register_default_tables(&mut self) {
        // Viking Ship - drops gold, food, and card draw
        self.register_table(DropTable {
            entity_type: "viking".to_string(),
            drops: vec![
                DropEntry {
                    reward_type: RewardType::Draw,
                    min_amount: 1,
                    max_amount: 1,
                    probability: 1.0, // Always drop 1 draw
                },
                DropEntry {
                    reward_type: RewardType::Gold,
                    min_amount: 50,
                    max_amount: 250,
                    probability: 0.8, // 80% chance
                },
                DropEntry {
                    reward_type: RewardType::Food,
                    min_amount: 50,
                    max_amount: 250,
                    probability: 0.6, // 60% chance
                },
            ],
        });

        // Raptor (Jezza) - drops food and draws
        self.register_table(DropTable {
            entity_type: "jezza".to_string(),
            drops: vec![
                DropEntry {
                    reward_type: RewardType::Draw,
                    min_amount: 1,
                    max_amount: 1,
                    probability: 1.0, // Always drop 1 draw
                },
                DropEntry {
                    reward_type: RewardType::Food,
                    min_amount: 75,
                    max_amount: 300,
                    probability: 0.9, // 90% chance (raptors are good for food)
                },
            ],
        });

        // King - drops faith and gold
        self.register_table(DropTable {
            entity_type: "king".to_string(),
            drops: vec![
                DropEntry {
                    reward_type: RewardType::Draw,
                    min_amount: 1,
                    max_amount: 2,
                    probability: 1.0, // Always drop 1-2 draws
                },
                DropEntry {
                    reward_type: RewardType::Faith,
                    min_amount: 100,
                    max_amount: 300,
                    probability: 0.9, // 90% chance
                },
                DropEntry {
                    reward_type: RewardType::Gold,
                    min_amount: 100,
                    max_amount: 400,
                    probability: 0.7, // 70% chance
                },
            ],
        });

        // Fantasy Warrior - drops labor and draws
        self.register_table(DropTable {
            entity_type: "fantasy_warrior".to_string(),
            drops: vec![
                DropEntry {
                    reward_type: RewardType::Draw,
                    min_amount: 1,
                    max_amount: 1,
                    probability: 1.0, // Always drop 1 draw
                },
                DropEntry {
                    reward_type: RewardType::Labor,
                    min_amount: 50,
                    max_amount: 200,
                    probability: 0.7, // 70% chance
                },
            ],
        });

        // Generic NPC fallback
        self.register_table(DropTable {
            entity_type: "default".to_string(),
            drops: vec![
                DropEntry {
                    reward_type: RewardType::Draw,
                    min_amount: 1,
                    max_amount: 1,
                    probability: 1.0, // Always drop 1 draw
                },
                DropEntry {
                    reward_type: RewardType::Gold,
                    min_amount: 25,
                    max_amount: 100,
                    probability: 0.5, // 50% chance
                },
            ],
        });
    }

    /// Register a custom drop table
    pub fn register_table(&mut self, table: DropTable) {
        self.tables.insert(table.entity_type.clone(), table);
    }

    /// Get drop table for entity type
    pub fn get_table(&self, entity_type: &str) -> Option<&DropTable> {
        // Try exact match first
        if let Some(table) = self.tables.get(entity_type) {
            return Some(table);
        }

        // Try partial match (e.g., "viking_ship" matches "viking")
        for (key, table) in &self.tables {
            if entity_type.to_lowercase().contains(&key.to_lowercase()) {
                return Some(table);
            }
        }

        // Fallback to default
        self.tables.get("default")
    }

    /// Generate loot for a killed entity
    pub fn generate_loot(&self, entity_type: &str) -> Vec<Reward> {
        if let Some(table) = self.get_table(entity_type) {
            table.roll_drops()
        } else {
            // No table found, use default
            if let Some(default_table) = self.tables.get("default") {
                default_table.roll_drops()
            } else {
                Vec::new()
            }
        }
    }
}

// Global instance
use once_cell::sync::Lazy;
use std::sync::Mutex;

static DROP_TABLES: Lazy<Mutex<DropTableRegistry>> = Lazy::new(|| {
    Mutex::new(DropTableRegistry::new())
});

/// Generate loot for a killed entity
pub fn generate_loot(entity_type: &str) -> Vec<Reward> {
    DROP_TABLES.lock().unwrap().generate_loot(entity_type)
}
