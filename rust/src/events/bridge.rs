// Unified Event Bridge - Single Godot FFI entry point
// TRUE ACTOR PATTERN: Actor runs on dedicated thread, communicates via channels

use godot::prelude::*;
use godot::classes::INode;
use crossbeam_channel::{Sender, Receiver, unbounded};
use std::sync::{Mutex};
use once_cell::sync::Lazy;

use super::actor::spawn_actor_thread;
use super::types::{GameEvent, GameRequest};
use crate::npc::terrain_cache::TerrainType;

// Global channels (proper Actor pattern with crossbeam_channel)
struct Channels {
    request_tx: Sender<GameRequest>,
    event_rx: Receiver<GameEvent>,
}

static CHANNELS: Lazy<Channels> = Lazy::new(|| {
    // Create channels
    let (request_tx, request_rx) = unbounded::<GameRequest>();
    let (event_tx, event_rx) = unbounded::<GameEvent>();

    // Spawn Actor thread with its channels
    spawn_actor_thread(request_rx, event_tx);

    Channels { request_tx, event_rx }
});

#[derive(GodotClass)]
#[class(base=Node)]
pub struct UnifiedEventBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for UnifiedEventBridge {
    fn init(base: Base<Node>) -> Self {
        // Initialize channels (Lazy will spawn Actor thread on first access)
        let _ = &*CHANNELS;

        Self { base }
    }

    fn ready(&mut self) {
        // Enable process() to be called every frame
        self.base_mut().set_process(true);
    }

    fn process(&mut self, _delta: f64) {
        // Main thread ONLY reads events from the Actor thread via channel
        // Actor thread runs independently at 60 ticks/sec
        // NO SHARED STATE - ZERO LOCK CONTENTION

        // Drain all available events (non-blocking)
        while let Ok(event) = CHANNELS.event_rx.try_recv() {
            self.emit_event(event);
        }
    }
}

#[godot_api]
impl UnifiedEventBridge {
    // ========================================================================
    // SIGNALS (Unified - All game events)
    // ========================================================================

    /// Emitted when an entity successfully spawns
    #[signal]
    fn entity_spawned(ulid: PackedByteArray, position_q: i32, position_r: i32, terrain_type: i32, entity_type: GString);

    /// Emitted when a spawn request fails
    #[signal]
    fn spawn_failed(entity_type: GString, error: GString);

    /// Emitted when a pathfinding request succeeds
    #[signal]
    fn path_found(ulid: PackedByteArray, path: Array<Vector2i>, cost: f32);

    /// Emitted when a pathfinding request fails
    #[signal]
    fn path_failed(ulid: PackedByteArray);

    /// Emitted when a random destination is found
    #[signal]
    fn random_dest_found(ulid: PackedByteArray, destination_q: i32, destination_r: i32, found: bool);

    /// Emitted when combat starts
    #[signal]
    fn combat_started(attacker: PackedByteArray, defender: PackedByteArray);

    /// Emitted when damage is dealt
    #[signal]
    fn damage_dealt(attacker: PackedByteArray, defender: PackedByteArray, damage: i32);

    /// Emitted when an entity dies
    #[signal]
    fn entity_died(ulid: PackedByteArray);

    /// Emitted when combat ends
    #[signal]
    fn combat_ended(attacker: PackedByteArray, defender: PackedByteArray);

    /// Emitted when a resource changes
    #[signal]
    fn resource_changed(resource_type: i32, current: f32, cap: f32, rate: f32);

    /// Emitted when a stat changes
    #[signal]
    fn stat_changed(ulid: PackedByteArray, stat_type: i64, new_value: f32);

    /// Emitted when entity takes damage
    #[signal]
    fn entity_damaged(ulid: PackedByteArray, damage: f32, new_hp: f32);

    /// Emitted when entity is healed
    #[signal]
    fn entity_healed(ulid: PackedByteArray, heal_amount: f32, new_hp: f32);

    // ========================================================================
    // REQUEST METHODS (Unified API - All game requests)
    // ========================================================================

    /// Spawn an entity
    #[func]
    fn spawn_entity(&mut self, entity_type: GString, terrain_type: i32, preferred_q: i32, preferred_r: i32, search_radius: i32) {
        let _ = CHANNELS.request_tx.send(GameRequest::SpawnEntity {
            entity_type: entity_type.to_string(),
            terrain_type: if terrain_type == 0 { TerrainType::Water } else { TerrainType::Land },
            preferred_location: (preferred_q, preferred_r),
            search_radius,
        });
    }

    /// Request pathfinding
    #[func]
    fn request_path(&mut self, ulid: PackedByteArray, terrain_type: i32, start_q: i32, start_r: i32, goal_q: i32, goal_r: i32, avoid_entities: bool) {
        let _ = CHANNELS.request_tx.send(GameRequest::RequestPath {
            ulid: ulid.to_vec(),
            terrain_type: if terrain_type == 0 { TerrainType::Water } else { TerrainType::Land },
            start: (start_q, start_r),
            goal: (goal_q, goal_r),
            avoid_entities,
        });
    }

    /// Request random destination
    #[func]
    fn request_random_destination(&mut self, ulid: PackedByteArray, terrain_type: i32, start_q: i32, start_r: i32, min_distance: i32, max_distance: i32) {
        let _ = CHANNELS.request_tx.send(GameRequest::RequestRandomDest {
            ulid: ulid.to_vec(),
            terrain_type: if terrain_type == 0 { TerrainType::Water } else { TerrainType::Land },
            start: (start_q, start_r),
            min_distance,
            max_distance,
        });
    }

    /// Update entity position
    #[func]
    fn update_entity_position(&mut self, ulid: PackedByteArray, q: i32, r: i32) {
        let _ = CHANNELS.request_tx.send(GameRequest::UpdateEntityPosition {
            ulid: ulid.to_vec(),
            position: (q, r),
        });
    }

    /// Update entity state
    #[func]
    fn set_entity_state(&mut self, ulid: PackedByteArray, state: i64) {
        let _ = CHANNELS.request_tx.send(GameRequest::UpdateEntityState {
            ulid: ulid.to_vec(),
            state,
        });
    }

    /// Remove entity
    #[func]
    fn remove_entity(&mut self, ulid: PackedByteArray) {
        let _ = CHANNELS.request_tx.send(GameRequest::RemoveEntity {
            ulid: ulid.to_vec(),
        });
    }

    /// Register a resource producer
    #[func]
    fn register_producer(&mut self, ulid: PackedByteArray, resource_type: i32, rate_per_sec: f32, active: bool) {
        let _ = CHANNELS.request_tx.send(GameRequest::RegisterProducer {
            ulid: ulid.to_vec(),
            resource_type,
            rate_per_sec,
            active,
        });
    }

    /// Register a resource consumer
    #[func]
    fn register_consumer(&mut self, ulid: PackedByteArray, resource_type: i32, rate_per_sec: f32, active: bool) {
        let _ = CHANNELS.request_tx.send(GameRequest::RegisterConsumer {
            ulid: ulid.to_vec(),
            resource_type,
            rate_per_sec,
            active,
        });
    }

    /// Remove a producer
    #[func]
    fn remove_producer(&mut self, ulid: PackedByteArray) {
        let _ = CHANNELS.request_tx.send(GameRequest::RemoveProducer {
            ulid: ulid.to_vec(),
        });
    }

    /// Remove a consumer
    #[func]
    fn remove_consumer(&mut self, ulid: PackedByteArray) {
        let _ = CHANNELS.request_tx.send(GameRequest::RemoveConsumer {
            ulid: ulid.to_vec(),
        });
    }

    // ========================================================================
    // STATS METHODS
    // ========================================================================

    /// Register entity stats (called when entity spawns)
    #[func]
    fn register_entity_stats(&mut self, ulid: PackedByteArray, entity_type: GString, terrain_type: i32, q: i32, r: i32) {
        let _ = CHANNELS.request_tx.send(GameRequest::RegisterEntityStats {
            ulid: ulid.to_vec(),
            entity_type: entity_type.to_string(),
            terrain_type,
            position: (q, r),
        });
    }

    /// Set stat value
    #[func]
    fn set_stat(&mut self, ulid: PackedByteArray, stat_type: i64, value: f32) {
        let _ = CHANNELS.request_tx.send(GameRequest::SetStat {
            ulid: ulid.to_vec(),
            stat_type,
            value,
        });
    }

    /// Entity takes damage
    #[func]
    fn take_damage(&mut self, ulid: PackedByteArray, damage: f32) {
        let _ = CHANNELS.request_tx.send(GameRequest::TakeDamage {
            ulid: ulid.to_vec(),
            damage,
        });
    }

    /// Heal entity
    #[func]
    fn heal(&mut self, ulid: PackedByteArray, amount: f32) {
        let _ = CHANNELS.request_tx.send(GameRequest::Heal {
            ulid: ulid.to_vec(),
            amount,
        });
    }

    /// Get a single stat value for an entity (synchronous query)
    #[func]
    fn get_stat(&self, ulid: PackedByteArray, stat_type: i64) -> f32 {
        use crate::npc::entity::{StatType, ENTITY_STATS};

        if let Some(stat_type_enum) = StatType::from_i64(stat_type) {
            if let Some(stats) = ENTITY_STATS.get(&ulid.to_vec()) {
                return stats.get(stat_type_enum);
            }
        }
        0.0
    }

    /// Get all stats for an entity as a Dictionary (synchronous query)
    #[func]
    fn get_all_stats(&self, ulid: PackedByteArray) -> Dictionary {
        use crate::npc::entity::{StatType, ENTITY_STATS};

        let mut dict = Dictionary::new();

        let ulid_vec = ulid.to_vec();

        // DEBUG: Only log when stats NOT found to diagnose ULID mismatch (full ULID in hex)
        if ENTITY_STATS.get(&ulid_vec).is_none() {
            godot_print!("❌ Stats query MISS for ULID: {:02x?}", &ulid_vec);
            if let Some(first_entry) = ENTITY_STATS.iter().next() {
                let first_ulid = first_entry.key();
                godot_print!("   Cache has {} entries, first entry ULID: {:02x?}",
                    ENTITY_STATS.len(), first_ulid);
            }
        }

        if let Some(stats) = ENTITY_STATS.get(&ulid_vec) {
            // Return all stat types as dictionary keys
            dict.insert(StatType::HP as i64, stats.get(StatType::HP));
            dict.insert(StatType::MaxHP as i64, stats.get(StatType::MaxHP));
            dict.insert(StatType::Attack as i64, stats.get(StatType::Attack));
            dict.insert(StatType::Defense as i64, stats.get(StatType::Defense));
            dict.insert(StatType::Speed as i64, stats.get(StatType::Speed));
            dict.insert(StatType::Energy as i64, stats.get(StatType::Energy));
            dict.insert(StatType::MaxEnergy as i64, stats.get(StatType::MaxEnergy));
            dict.insert(StatType::Range as i64, stats.get(StatType::Range));
            dict.insert(StatType::Morale as i64, stats.get(StatType::Morale));
            dict.insert(StatType::Experience as i64, stats.get(StatType::Experience));
            dict.insert(StatType::Level as i64, stats.get(StatType::Level));
        }

        dict
    }

    // ========================================================================
    // EVENT EMISSION (Internal - converts Rust events to Godot signals)
    // ========================================================================

    fn emit_event(&mut self, event: GameEvent) {
        match event {
            GameEvent::EntitySpawned { ulid, position, terrain_type, entity_type } => {
                self.base_mut().emit_signal(
                    "entity_spawned",
                    &[
                        PackedByteArray::from(&ulid[..]).to_variant(),
                        position.0.to_variant(),
                        position.1.to_variant(),
                        terrain_type.to_variant(),
                        GString::from(&entity_type).to_variant(),
                    ],
                );
            }

            GameEvent::SpawnFailed { entity_type, error } => {
                self.base_mut().emit_signal(
                    "spawn_failed",
                    &[
                        GString::from(&entity_type).to_variant(),
                        GString::from(&error).to_variant(),
                    ],
                );
            }

            GameEvent::PathFound { ulid, path, cost } => {
                // Convert path to Godot array
                let mut path_array = Array::new();
                for (q, r) in path {
                    path_array.push(Vector2i::new(q, r));
                }

                self.base_mut().emit_signal(
                    "path_found",
                    &[
                        PackedByteArray::from(&ulid[..]).to_variant(),
                        path_array.to_variant(),
                        cost.to_variant(),
                    ],
                );
            }

            GameEvent::PathFailed { ulid } => {
                self.base_mut().emit_signal(
                    "path_failed",
                    &[PackedByteArray::from(&ulid[..]).to_variant()],
                );
            }

            GameEvent::RandomDestFound { ulid, destination, found } => {
                self.base_mut().emit_signal(
                    "random_dest_found",
                    &[
                        PackedByteArray::from(&ulid[..]).to_variant(),
                        destination.0.to_variant(),
                        destination.1.to_variant(),
                        found.to_variant(),
                    ],
                );
            }

            GameEvent::CombatStarted { attacker_ulid, defender_ulid } => {
                self.base_mut().emit_signal(
                    "combat_started",
                    &[
                        PackedByteArray::from(&attacker_ulid[..]).to_variant(),
                        PackedByteArray::from(&defender_ulid[..]).to_variant(),
                    ],
                );
            }

            GameEvent::DamageDealt { attacker_ulid, defender_ulid, damage } => {
                self.base_mut().emit_signal(
                    "damage_dealt",
                    &[
                        PackedByteArray::from(&attacker_ulid[..]).to_variant(),
                        PackedByteArray::from(&defender_ulid[..]).to_variant(),
                        damage.to_variant(),
                    ],
                );
            }

            GameEvent::EntityDied { ulid } => {
                self.base_mut().emit_signal(
                    "entity_died",
                    &[PackedByteArray::from(&ulid[..]).to_variant()],
                );
            }

            GameEvent::CombatEnded { attacker_ulid, defender_ulid } => {
                self.base_mut().emit_signal(
                    "combat_ended",
                    &[
                        PackedByteArray::from(&attacker_ulid[..]).to_variant(),
                        PackedByteArray::from(&defender_ulid[..]).to_variant(),
                    ],
                );
            }

            GameEvent::ResourceChanged { resource_type, current, cap, rate } => {
                self.base_mut().emit_signal(
                    "resource_changed",
                    &[
                        resource_type.to_variant(),
                        current.to_variant(),
                        cap.to_variant(),
                        rate.to_variant(),
                    ],
                );
            }

            GameEvent::StatChanged { ulid, stat_type, new_value } => {
                self.base_mut().emit_signal(
                    "stat_changed",
                    &[
                        PackedByteArray::from(&ulid[..]).to_variant(),
                        stat_type.to_variant(),
                        new_value.to_variant(),
                    ],
                );
            }

            GameEvent::EntityDamaged { ulid, damage, new_hp } => {
                self.base_mut().emit_signal(
                    "entity_damaged",
                    &[
                        PackedByteArray::from(&ulid[..]).to_variant(),
                        damage.to_variant(),
                        new_hp.to_variant(),
                    ],
                );
            }

            GameEvent::EntityHealed { ulid, heal_amount, new_hp } => {
                self.base_mut().emit_signal(
                    "entity_healed",
                    &[
                        PackedByteArray::from(&ulid[..]).to_variant(),
                        heal_amount.to_variant(),
                        new_hp.to_variant(),
                    ],
                );
            }
        }
    }
}
