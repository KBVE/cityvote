// Game Actor - Central coordinator that owns all shared state
// Processes requests, coordinates workers, emits events
// TRUE ACTOR PATTERN: Runs on dedicated thread, communicates only via channels

use std::sync::Arc;
use std::thread;
use dashmap::DashMap;
use crossbeam_channel::{Sender, Receiver};
use std::collections::{HashSet, HashMap};
use std::time::{Duration, Instant};
use godot::prelude::*;
use once_cell::sync::Lazy;

use crate::npc::entity::{EntityData, EntityStats};
use crate::economy::resource_ledger::ResourceType;
use crate::card::card_registry::CardRegistry;
// DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
// use crate::web::{NetworkWorkerHandle, NetworkWorkerConfig, start_network_worker, NetworkWorkerResponse, IrcClient, IrcConfig, IrcEvent, ChannelHistory, ChatMessage, MessageType};
use super::types::{GameEvent, GameRequest, CombatEntitySnapshot};
use super::workers::*;

// Global entity stats storage (thread-safe, shared between Actor and FFI)
// Actor owns write access, FFI reads via get_all_stats()
pub static ACTOR_ENTITY_STATS: Lazy<Arc<DashMap<Vec<u8>, EntityStats>>> = Lazy::new(|| {
    Arc::new(DashMap::new())
});

// DEPRECATED: IRC chat history now handled by GDScript (irc_websocket_client.gd)
// Global IRC chat history storage (thread-safe, shared between Actor and FFI)
// Actor owns write access, FFI reads for UI rendering
// pub static IRC_CHAT_HISTORY: Lazy<Arc<DashMap<String, ChannelHistory>>> = Lazy::new(|| {
//     Arc::new(DashMap::new())
// });

/// Central coordinator that owns all shared state
/// RUNS ON DEDICATED THREAD - No shared state, zero lock contention
pub struct GameActor {
    // === OWNED STATE (Direct ownership, no Arc needed) ===
    entities: DashMap<Vec<u8>, EntityData>,
    entity_stats: Arc<DashMap<Vec<u8>, EntityStats>>,  // Reference to global stats
    entity_player_ulids: DashMap<Vec<u8>, Vec<u8>>,     // ULID -> player_ulid (for team detection)
    pending_spawns: HashSet<(i32, i32)>,
    card_registry: CardRegistry,  // SINGLE SOURCE OF TRUTH for card placement

    // === COMMUNICATION (crossbeam_channel for proper Actor pattern) ===
    request_rx: Receiver<GameRequest>,  // Receive requests from Godot
    event_tx: Sender<GameEvent>,        // Send events to Godot

    // Resource state (simplified for now)
    resources: HashMap<i64, (f64, f64, f64)>, // (current, cap, rate)
    producers: Vec<(Vec<u8>, i64, f64, bool)>, // (ulid, resource_type, rate, active)
    consumers: Vec<(Vec<u8>, i64, f64, bool)>,

    // === WORKER CHANNELS ===
    spawn_tx: Sender<SpawnWorkRequest>,
    spawn_rx: Receiver<SpawnWorkResult>,

    path_tx: Sender<PathWorkRequest>,
    path_rx: Receiver<PathWorkResult>,

    combat_tx: Sender<CombatWorkRequest>,
    combat_rx: Receiver<CombatWorkResult>,

    economy_tx: Sender<EconomyWorkRequest>,
    economy_rx: Receiver<EconomyWorkResult>,

    // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
    // === GENERIC NETWORK WORKER (for general HTTP/WebSocket, NOT IRC) ===
    // network_worker: Option<NetworkWorkerHandle>,

    // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
    // === IRC CLIENT (owns its own dedicated network worker) ===
    // irc_client: Option<IrcClient>,

    // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
    // === IRC CHAT HISTORY ===
    // chat_history: Arc<DashMap<String, ChannelHistory>>,  // Reference to global chat history

    // === TIMING ===
    last_combat_tick: Instant,
    last_economy_tick: Instant,
}

impl GameActor {
    fn new(
        request_rx: Receiver<GameRequest>,
        event_tx: Sender<GameEvent>,
    ) -> Self {
        use crossbeam_channel::unbounded;

        // Create owned state (no Arc wrapping - this thread is the only owner)
        let entities = DashMap::new();
        let entity_stats = Arc::clone(&ACTOR_ENTITY_STATS);  // Use global stats storage
        let entity_player_ulids = DashMap::new();

        // Initialize resources with defaults
        let mut resources = HashMap::new();
        resources.insert(0, (1000.0, 10000.0, 0.0)); // Gold
        resources.insert(1, (1000.0, 10000.0, 0.0)); // Food
        resources.insert(2, (1000.0, 10000.0, 0.0)); // Labor
        resources.insert(3, (1000.0, 10000.0, 0.0)); // Faith

        // Create worker channels
        let (spawn_tx, spawn_rx_worker) = unbounded();
        let (spawn_tx_worker, spawn_rx) = unbounded();

        let (path_tx, path_rx_worker) = unbounded();
        let (path_tx_worker, path_rx) = unbounded();

        let (combat_tx, combat_rx_worker) = unbounded();
        let (combat_tx_worker, combat_rx) = unbounded();

        let (economy_tx, economy_rx_worker) = unbounded();
        let (economy_tx_worker, economy_rx) = unbounded();

        // Spawn worker threads
        spawn_spawn_worker(spawn_rx_worker, spawn_tx_worker);
        spawn_pathfinding_pool(path_rx_worker, path_tx_worker, 4);
        spawn_combat_worker(combat_rx_worker, combat_tx_worker);
        spawn_economy_worker(economy_rx_worker, economy_tx_worker);

        // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
        // Generic network worker (for HTTP/WebSocket, NOT IRC)
        // let network_worker = None;

        // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
        // IRC client will own its own dedicated network worker when created
        // let irc_client = None;

        // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
        // Get reference to global chat history
        // let chat_history = Arc::clone(&IRC_CHAT_HISTORY);

        let mut actor = Self {
            entities,
            entity_stats,
            entity_player_ulids,
            pending_spawns: HashSet::new(),
            card_registry: CardRegistry::new(),  // Actor owns the card registry

            request_rx,
            event_tx: event_tx.clone(),

            resources,
            producers: Vec::new(),
            consumers: Vec::new(),

            spawn_tx,
            spawn_rx,

            path_tx,
            path_rx,

            combat_tx,
            combat_rx,

            economy_tx,
            economy_rx,

            // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
            // network_worker,
            // irc_client,
            // chat_history,

            last_combat_tick: Instant::now(),
            last_economy_tick: Instant::now(),
        };

        // Emit initial resource states
        actor.emit_initial_resources();

        actor
    }

    /// Emit initial resource events (called once at startup)
    fn emit_initial_resources(&mut self) {
        for (resource_type, (current, cap, rate)) in &self.resources {
            let _ = self.event_tx.send(GameEvent::ResourceChanged {
                resource_type: *resource_type,
                current: *current,
                cap: *cap,
                rate: *rate,
            });
        }
    }

    /// Main tick function - called with fixed delta (0.016s)
    pub fn tick(&mut self, _delta: f64) {
        // 1. Process all incoming requests from Godot
        self.process_requests();

        // 2. Collect results from workers and update state
        self.collect_spawn_results();
        self.collect_pathfinding_results();
        self.collect_combat_results();
        self.collect_economy_results();
        // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
        // self.collect_network_results();
        // self.collect_irc_events();

        // 3. Periodic ticks
        if self.last_combat_tick.elapsed() >= Duration::from_millis(500) {
            self.tick_combat();
            self.last_combat_tick = Instant::now();
        }

        if self.last_economy_tick.elapsed() >= Duration::from_secs(1) {
            self.tick_economy();
            self.last_economy_tick = Instant::now();
        }
    }

    /// Process incoming requests from Godot (via channel)
    fn process_requests(&mut self) {
        // Drain all available requests (non-blocking)
        while let Ok(request) = self.request_rx.try_recv() {
            match request {
                GameRequest::SpawnEntity { entity_type, terrain_type, preferred_location, search_radius } => {
                    // Create work request with entity position snapshot
                    let work = SpawnWorkRequest {
                        entity_type,
                        terrain_type,
                        preferred_location,
                        search_radius,
                        occupied_positions: self.get_occupied_positions(),
                    };

                    // Reserve position
                    self.pending_spawns.insert(preferred_location);

                    // Send to worker
                    let _ = self.spawn_tx.send(work);
                }

                GameRequest::RequestPath { ulid, terrain_type, start, goal, avoid_entities } => {
                    let work = PathWorkRequest {
                        ulid,
                        terrain_type,
                        start,
                        goal,
                        avoid_entities,
                        entity_positions: if avoid_entities {
                            Some(self.get_entity_positions())
                        } else {
                            None
                        },
                    };

                    let _ = self.path_tx.send(work);
                }

                GameRequest::RequestRandomDest { ulid, terrain_type, start, min_distance, max_distance } => {
                    // Pick random destination in hex grid (not Cartesian!)
                    use rand::Rng;
                    let mut rng = rand::thread_rng();

                    // Try to find a valid destination (max 10 attempts)
                    let mut found_dest = None;
                    for attempt in 0..10 {
                        // Pick random hex distance (in hex tiles, not pixels!)
                        let distance = rng.gen_range(min_distance..=max_distance);

                        // Pick random direction in hex grid (6 cardinal directions + diagonals)
                        // Use axial hex coordinates: q (x-axis), r (y-axis)
                        let angle_index = rng.gen_range(0..6);
                        let hex_directions = [
                            (1, 0), (1, -1), (0, -1),  // E, NE, NW
                            (-1, 0), (-1, 1), (0, 1),  // W, SW, SE
                        ];
                        let (base_dq, base_dr) = hex_directions[angle_index];

                        // Scale by distance and add some randomness for diagonal movement
                        let rand_offset = rng.gen_range(-distance/3..=distance/3);
                        let dq = base_dq * distance + rand_offset;
                        let dr = base_dr * distance - rand_offset;  // Subtract to maintain hex constraint

                        let dest = (start.0 + dq, start.1 + dr);

                        // Check if destination is walkable and not occupied
                        use crate::npc::terrain_cache;
                        let dest_terrain = terrain_cache::get_terrain(dest.0, dest.1);

                        if dest_terrain == terrain_type {
                            // Check if not occupied by another entity
                            let is_occupied = self.entities.iter().any(|entry| {
                                entry.value().position == dest
                            });

                            if !is_occupied {
                                found_dest = Some(dest);
                                break;
                            }
                        }
                    }

                    if let Some(dest) = found_dest {
                        let _ = self.event_tx.send(GameEvent::RandomDestFound {
                            ulid,
                            destination: dest,
                            found: true,
                        });
                    } else {
                        let _ = self.event_tx.send(GameEvent::RandomDestFound {
                            ulid,
                            destination: start,
                            found: false,
                        });
                    }
                }

                GameRequest::UpdateEntityPosition { ulid, position } => {
                    // Direct update (fast, no worker needed)
                    if let Some(mut entity) = self.entities.get_mut(&ulid) {
                        entity.position = position;
                    }
                }

                GameRequest::UpdateEntityState { ulid, state } => {
                    // Direct update
                    if let Some(mut entity) = self.entities.get_mut(&ulid) {
                        entity.state = state;
                    }
                }

                GameRequest::RemoveEntity { ulid } => {
                    use crate::npc::entity::ENTITY_STATS;

                    self.entities.remove(&ulid);
                    self.entity_stats.remove(&ulid);
                    ENTITY_STATS.remove(&ulid);  // Clean up cache too
                }

                GameRequest::RegisterProducer { ulid, resource_type, rate_per_sec, active } => {
                    self.producers.push((ulid, resource_type, rate_per_sec, active));
                }

                GameRequest::RegisterConsumer { ulid, resource_type, rate_per_sec, active } => {
                    self.consumers.push((ulid, resource_type, rate_per_sec, active));
                }

                GameRequest::RemoveProducer { ulid } => {
                    self.producers.retain(|(u, _, _, _)| u != &ulid);
                }

                GameRequest::RemoveConsumer { ulid } => {
                    self.consumers.retain(|(u, _, _, _)| u != &ulid);
                }

                GameRequest::RegisterEntityStats { ulid, player_ulid, entity_type, terrain_type, position, combat_type, projectile_type, combat_range, aggro_range } => {
                    use crate::npc::entity::{EntityStats, TerrainType as EntityTerrainType, StatType, ENTITY_STATS, CombatType, ProjectileType};

                    // Store player_ulid for team detection
                    self.entity_player_ulids.insert(ulid.clone(), player_ulid);

                    // Determine terrain type from i32
                    let et = match terrain_type {
                        0 => EntityTerrainType::Water,
                        _ => EntityTerrainType::Land,
                    };

                    // Create default stats based on terrain type
                    let stats = match et {
                        EntityTerrainType::Water => EntityStats::new_water_entity(),
                        EntityTerrainType::Land => EntityStats::new_land_entity(),
                    };

                    // Get initial HP values before inserting
                    let initial_hp = stats.get(StatType::HP);
                    let max_hp = stats.get(StatType::MaxHP);

                    // Actor OWNS stats - store in Actor's DashMap
                    self.entity_stats.insert(ulid.clone(), stats.clone());

                    // Also sync to global ENTITY_STATS for GDScript queries (read-only cache)
                    ENTITY_STATS.insert(ulid.clone(), stats.clone());

                    // Emit initial stat events for ALL stats so GDScript knows all starting values
                    // This is CRITICAL for UI panels to display correctly
                    // Send in a specific order: MaxHP/MaxEnergy first, then current values, then other stats
                    let all_stat_types = [
                        StatType::MaxHP,
                        StatType::MaxEnergy,
                        StatType::HP,
                        StatType::Energy,
                        StatType::Attack,
                        StatType::Defense,
                        StatType::Speed,
                        StatType::Range,
                        StatType::Morale,
                        StatType::Level,
                        StatType::Experience,
                    ];

                    for stat_type in all_stat_types.iter() {
                        let value = stats.get(*stat_type);
                        let _ = self.event_tx.send(GameEvent::StatChanged {
                            ulid: ulid.clone(),
                            stat_type: *stat_type as i64,
                            new_value: value,
                        });
                    }

                    // Also create entity data if it doesn't exist
                    if !self.entities.contains_key(&ulid) {
                        // Parse combat type and projectile type
                        let ct = CombatType::from_u8(combat_type).unwrap_or(CombatType::Melee);
                        let pt = ProjectileType::from_u8(projectile_type).unwrap_or(ProjectileType::None);

                        // Create entity data with combat info
                        let mut entity_data = EntityData::new(ulid.clone(), position, et, entity_type);
                        entity_data.combat_type = ct;
                        entity_data.projectile_type = pt;
                        entity_data.combat_range = combat_range;
                        entity_data.aggro_range = aggro_range;

                        self.entities.insert(entity_data.ulid.clone(), entity_data);
                    }
                }

                GameRequest::SetStat { ulid, stat_type, value } => {
                    use crate::npc::entity::{StatType, ENTITY_STATS};

                    if let Some(st) = StatType::from_i64(stat_type) {
                        if let Some(mut stats) = self.entity_stats.get_mut(&ulid) {
                            stats.set(st, value);

                            // Sync to global cache
                            if let Some(mut cache) = ENTITY_STATS.get_mut(&ulid) {
                                cache.set(st, value);
                            }

                            // Emit stat changed event
                            let _ = self.event_tx.send(GameEvent::StatChanged {
                                ulid,
                                stat_type,
                                new_value: value,
                            });
                        }
                    }
                }

                GameRequest::TakeDamage { ulid, damage } => {
                    use crate::npc::entity::{StatType, ENTITY_STATS};

                    if let Some(mut stats) = self.entity_stats.get_mut(&ulid) {
                        let actual_damage = stats.take_damage(damage);
                        let mut new_hp = stats.get(StatType::HP);

                        // CRITICAL: If HP would be fractional and < 1.0, set to 0.0 (entity should die)
                        if new_hp > 0.0 && new_hp < 1.0 {
                            new_hp = 0.0;
                            stats.set(StatType::HP, new_hp);
                        }

                        // Sync to global cache
                        if let Some(mut cache) = ENTITY_STATS.get_mut(&ulid) {
                            cache.take_damage(damage);
                            // Also apply the < 1.0 fix to cache
                            let cache_hp = cache.get(StatType::HP);
                            if cache_hp > 0.0 && cache_hp < 1.0 {
                                cache.set(StatType::HP, 0.0);
                            }
                        }

                        // Emit damage event
                        let _ = self.event_tx.send(GameEvent::EntityDamaged {
                            ulid: ulid.clone(),
                            damage: actual_damage,
                            new_hp,
                        });

                        // Emit stat changed event
                        let _ = self.event_tx.send(GameEvent::StatChanged {
                            ulid: ulid.clone(),
                            stat_type: StatType::HP as i64,
                            new_value: new_hp,
                        });

                        // Check for death
                        if new_hp <= 0.0 {
                            let _ = self.event_tx.send(GameEvent::EntityDied {
                                ulid,
                            });
                        }
                    }
                }

                GameRequest::Heal { ulid, amount } => {
                    use crate::npc::entity::{StatType, ENTITY_STATS};

                    if let Some(mut stats) = self.entity_stats.get_mut(&ulid) {
                        let actual_heal = stats.heal(amount);
                        let new_hp = stats.get(StatType::HP);

                        // Sync to global cache
                        if let Some(mut cache) = ENTITY_STATS.get_mut(&ulid) {
                            cache.heal(amount);
                        }

                        // Emit heal event
                        let _ = self.event_tx.send(GameEvent::EntityHealed {
                            ulid: ulid.clone(),
                            heal_amount: actual_heal,
                            new_hp,
                        });

                        // Emit stat changed event
                        let _ = self.event_tx.send(GameEvent::StatChanged {
                            ulid,
                            stat_type: StatType::HP as i64,
                            new_value: new_hp,
                        });
                    }
                }

                GameRequest::ProjectileHit { attacker_ulid, defender_ulid, damage, projectile_type } => {
                    // Apply damage from projectile hit (called by GDScript after collision)
                    use crate::npc::entity::{StatType, ENTITY_STATS};

                    if let Some(mut stats) = self.entity_stats.get_mut(&defender_ulid) {
                        let current_hp = stats.value().get(StatType::HP);
                        let mut new_hp = (current_hp - damage as f32).max(0.0);

                        // CRITICAL: If HP would be fractional and < 1.0, set to 0.0
                        if new_hp > 0.0 && new_hp < 1.0 {
                            new_hp = 0.0;
                            stats.value_mut().set(StatType::HP, new_hp);
                        } else {
                            stats.value_mut().set(StatType::HP, new_hp);
                        }

                        // Sync to global cache
                        if let Some(mut cache) = ENTITY_STATS.get_mut(&defender_ulid) {
                            cache.take_damage(damage as f32);
                            let cache_hp = cache.get(StatType::HP);
                            if cache_hp > 0.0 && cache_hp < 1.0 {
                                cache.set(StatType::HP, 0.0);
                            }
                        }

                        // Emit damage dealt event
                        let _ = self.event_tx.send(GameEvent::DamageDealt {
                            attacker_ulid: attacker_ulid.clone(),
                            defender_ulid: defender_ulid.clone(),
                            damage,
                        });

                        // Emit entity damaged event (for health bars)
                        let _ = self.event_tx.send(GameEvent::EntityDamaged {
                            ulid: defender_ulid.clone(),
                            damage: damage as f32,
                            new_hp,
                        });

                        // Check if entity should die
                        if new_hp <= 0.0 {
                            let _ = self.event_tx.send(GameEvent::EntityDied {
                                ulid: defender_ulid.clone(),
                            });
                        }
                    }
                }

                GameRequest::AddResources { resource_type, amount } => {
                    // Add resources to Actor's authoritative state
                    if let Some(resource) = self.resources.get_mut(&resource_type) {
                        resource.0 += amount;  // Add to current amount
                        resource.0 = resource.0.min(resource.1);  // Cap at maximum

                        // Emit resource changed event to update UI
                        let _ = self.event_tx.send(GameEvent::ResourceChanged {
                            resource_type,
                            current: resource.0,
                            cap: resource.1,
                            rate: resource.2,
                        });
                    } else {
                        godot_error!("Actor: Resource type {} not found!", resource_type);
                    }
                }

                GameRequest::SpendResources { cost } => {
                    // Check if all resources are available
                    let mut can_afford = true;
                    for (resource_type, amount) in &cost {
                        if let Some(resource) = self.resources.get(resource_type) {
                            if resource.0 < *amount {
                                can_afford = false;
                                break;
                            }
                        } else {
                            can_afford = false;
                            break;
                        }
                    }

                    if can_afford {
                        // Spend resources and emit events
                        for (resource_type, amount) in cost {
                            if let Some(resource) = self.resources.get_mut(&resource_type) {
                                resource.0 -= amount;  // Deduct from current amount
                                resource.0 = resource.0.max(0.0);  // Floor at 0

                                // Emit resource changed event
                                let _ = self.event_tx.send(GameEvent::ResourceChanged {
                                    resource_type,
                                    current: resource.0,
                                    cap: resource.1,
                                    rate: resource.2,
                                });

                                godot_print!("Actor: Spent {} from resource {} (remaining: {}/{})",
                                    amount, resource_type, resource.0, resource.1);
                            }
                        }
                    } else {
                        godot_warn!("Actor: Cannot afford resource cost!");
                    }
                }

                GameRequest::ProcessTurnConsumption => {
                    // Count ONLY player-controlled entities (non-empty player_ulid)
                    // AI entities (empty player_ulid) do not consume food
                    let player_entity_count = self.entity_player_ulids
                        .iter()
                        .filter(|entry| !entry.value().is_empty())  // Filter out AI (empty player_ulid)
                        .count();

                    if player_entity_count > 0 {
                        // Consume 1 food per player-controlled entity
                        let food_cost = player_entity_count as f64;

                        if let Some(food) = self.resources.get_mut(&1) { // Resource type 1 = Food
                            food.0 = (food.0 - food_cost).max(0.0);

                            // Emit resource changed event
                            let _ = self.event_tx.send(GameEvent::ResourceChanged {
                                resource_type: 1,
                                current: food.0,
                                cap: food.1,
                                rate: food.2,
                            });
                        }
                    }
                }

                // === Card Requests ===
                GameRequest::PlaceCard { x, y, ulid, suit, value, card_id, is_custom } => {
                    use crate::card::card::CardData;
                    let card = CardData {
                        ulid,
                        suit,
                        value,
                        card_id,
                        is_custom,
                        state: crate::card::card::CardState::OnBoard,
                        position: Some((x, y)),
                        owner_id: None,  // No owner for placed cards
                    };

                    let success = self.card_registry.place_card(x, y, card);
                    if !success {
                        godot_warn!("Actor: Failed to place card at ({}, {}) - position occupied", x, y);
                    }
                    // Note: We could emit a CardPlaced event here for GDScript to sync visuals
                }

                GameRequest::RemoveCardAt { x, y } => {
                    let _removed = self.card_registry.remove_card_at(x, y);
                    // Could emit CardRemoved event
                }

                GameRequest::RemoveCardByUlid { ulid } => {
                    let _removed = self.card_registry.remove_card_by_ulid(&ulid);
                }

                GameRequest::DetectCombo { center_x, center_y, radius } => {
                    use crate::card::card_combo::{PositionedCard, ComboDetector};

                    // Get cards in radius from the Actor's card registry (SINGLE SOURCE OF TRUTH)
                    let cards_in_radius = self.card_registry.get_cards_in_radius(center_x, center_y, radius);

                    godot_print!("Actor: DetectCombo requested at ({}, {}) radius {} - found {} cards",
                        center_x, center_y, radius, cards_in_radius.len());

                    // Need at least 5 cards for a combo
                    if cards_in_radius.len() < 5 {
                        godot_print!("Actor: Not enough cards for combo (need 5, have {})", cards_in_radius.len());
                        // Could emit a "no combo" event here
                        continue;
                    }

                    // Convert to PositionedCard structs
                    let positioned_cards: Vec<PositionedCard> = cards_in_radius
                        .iter()
                        .enumerate()
                        .map(|(index, (x, y, card))| PositionedCard {
                            card: card.clone(),
                            x: *x,
                            y: *y,
                            index,
                        })
                        .collect();

                    // Detect combo using the spatial poker hand detection
                    let combo_result = ComboDetector::detect_combo(&positioned_cards);

                    godot_print!("Actor: Combo detection result: {:?} (rank: {:?})",
                        combo_result.hand.to_string(), combo_result.hand as i32);

                    // Skip "High Card" (rank 0) - not a real combo
                    if combo_result.hand as i32 == 0 {
                        continue;
                    }

                    // Convert resource bonuses to (resource_type, amount) tuples
                    let resource_bonuses: Vec<(i32, f32)> = combo_result.resource_bonuses
                        .iter()
                        .map(|bonus| (bonus.resource_type as i32, bonus.amount))
                        .collect();

                    // Emit ComboDetected event
                    let _ = self.event_tx.send(GameEvent::ComboDetected {
                        hand_rank: combo_result.hand as i32,
                        hand_name: combo_result.hand.to_string(),
                        card_positions: combo_result.positions.clone(),
                        resource_bonuses,
                    });
                }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::NetworkConnect { url } => {
                //     // Initialize network worker if not already started
                //     if self.network_worker.is_none() {
                //         let config = NetworkWorkerConfig::default();
                //         self.network_worker = Some(start_network_worker(config));
                //     }

                //     // Send connect request to network worker
                //     if let Some(ref worker) = self.network_worker {
                //         worker.connect(url);
                //     }
                // }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::NetworkSend { message } => {
                //     if let Some(ref worker) = self.network_worker {
                //         worker.send_message(message);
                //     } else {
                //         // Network worker not initialized
                //         let _ = self.event_tx.send(GameEvent::NetworkError {
                //             message: "Network worker not initialized".to_string(),
                //         });
                //     }
                // }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::NetworkDisconnect => {
                //     if let Some(ref worker) = self.network_worker {
                //         worker.disconnect();
                //     }
                // }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::IrcConnect { player_name } => {
                //     godot_print!("[IRC] Received IrcConnect request for player: {}", player_name);

                //     // Create network worker and IRC client
                //     godot_print!("[IRC] Starting network worker...");
                //     let worker_config = NetworkWorkerConfig::default();
                //     let worker_handle = start_network_worker(worker_config);

                //     godot_print!("[IRC] Creating IRC client...");
                //     let config = IrcConfig::cityvote(player_name);
                //     godot_print!("[IRC] Connecting to: {}", config.url);
                //     let mut client = IrcClient::new(config, worker_handle);
                //     client.connect();
                //     self.irc_client = Some(client);
                //     godot_print!("[IRC] IRC client created and connecting...");
                // }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::IrcSendMessage { message } => {
                //     if let Some(ref mut client) = self.irc_client {
                //         client.send_channel_message(&message);
                //     } else {
                //         let _ = self.event_tx.send(GameEvent::IrcError {
                //             message: "IRC not connected".to_string(),
                //         });
                //     }
                // }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::IrcJoinChannel { channel } => {
                //     if let Some(ref mut client) = self.irc_client {
                //         client.join_channel(&channel);
                //     }
                // }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::IrcLeaveChannel { channel, message } => {
                //     if let Some(ref mut client) = self.irc_client {
                //         client.leave_channel(&channel, message.as_deref());
                //     }
                // }

                // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
                // GameRequest::IrcDisconnect { message } => {
                //     if let Some(ref mut client) = self.irc_client {
                //         client.disconnect(message.as_deref());
                //         self.irc_client = None;
                //     }
                // }

                _ => {
                    // Unhandled requests (e.g., GetStat which needs synchronous response)
                }
            }
        }
    }

    /// Collect spawn worker results
    fn collect_spawn_results(&mut self) {
        while let Ok(result) = self.spawn_rx.try_recv() {
            match result {
                SpawnWorkResult::Success { ulid, position, entity_type, terrain_type } => {
                    // Update state
                    // Convert terrain_cache::TerrainType to entity::TerrainType
                    use crate::npc::entity::TerrainType as EntityTerrainType;
                    let entity_terrain = match terrain_type {
                        crate::npc::terrain_cache::TerrainType::Water => EntityTerrainType::Water,
                        crate::npc::terrain_cache::TerrainType::Land => EntityTerrainType::Land,
                        crate::npc::terrain_cache::TerrainType::Obstacle => EntityTerrainType::Land, // Default to Land
                    };
                    let entity_data = EntityData::new(ulid.clone(), position, entity_terrain, entity_type.clone());
                    self.entities.insert(ulid.clone(), entity_data);

                    // Clean up pending
                    self.pending_spawns.remove(&position);

                    // Emit event
                    let _ = self.event_tx.send(GameEvent::EntitySpawned {
                        ulid,
                        position,
                        terrain_type: terrain_type as i32,
                        entity_type,
                    });
                }
                SpawnWorkResult::Failed { entity_type, error } => {
                    let _ = self.event_tx.send(GameEvent::SpawnFailed {
                        entity_type,
                        error,
                    });
                }
            }
        }
    }

    /// Collect pathfinding results
    fn collect_pathfinding_results(&mut self) {
        while let Ok(result) = self.path_rx.try_recv() {
            match result {
                PathWorkResult::Success { ulid, path, cost } => {
                    let _ = self.event_tx.send(GameEvent::PathFound {
                        ulid,
                        path,
                        cost,
                    });
                }
                PathWorkResult::Failed { ulid } => {
                    let _ = self.event_tx.send(GameEvent::PathFailed {
                        ulid,
                    });
                }
                PathWorkResult::RandomDestSuccess { ulid, destination } => {
                    let _ = self.event_tx.send(GameEvent::RandomDestFound {
                        ulid,
                        destination,
                        found: true,
                    });
                }
                PathWorkResult::RandomDestFailed { ulid } => {
                    let _ = self.event_tx.send(GameEvent::RandomDestFound {
                        ulid,
                        destination: (0, 0),
                        found: false,
                    });
                }
            }
        }
    }

    /// Collect combat results
    fn collect_combat_results(&mut self) {
        while let Ok(result) = self.combat_rx.try_recv() {
            match result {
                CombatWorkResult::CombatStarted { attacker_ulid, defender_ulid } => {
                    let _ = self.event_tx.send(GameEvent::CombatStarted {
                        attacker_ulid,
                        defender_ulid,
                    });
                }
                CombatWorkResult::AttackExecuted { attacker_ulid } => {
                    // ATTACKING state will be managed in GDScript via animation system
                    // GDScript entities listen for DamageDealt events and manage ATTACKING/HURT states with timers
                    // This keeps state management close to the animation logic
                }
                CombatWorkResult::DamageDealt { attacker_ulid, defender_ulid, damage } => {
                    // CRITICAL: Apply damage to entity_stats (Actor owns this state)
                    if let Some(mut stats) = self.entity_stats.get_mut(&defender_ulid) {
                        use crate::npc::entity::{StatType, ENTITY_STATS};
                        let current_hp = stats.value().get(StatType::HP);
                        let mut new_hp = (current_hp - damage as f32).max(0.0);

                        // CRITICAL: If HP would be fractional and < 1.0, set to 0.0 (entity should die)
                        // This prevents "zombie" entities with 0.1-0.9 HP
                        if new_hp > 0.0 && new_hp < 1.0 {
                            new_hp = 0.0;
                        }

                        stats.value_mut().set(StatType::HP, new_hp);

                        // CRITICAL: Sync to global cache so GDScript sees updated HP
                        if let Some(mut cache) = ENTITY_STATS.get_mut(&defender_ulid) {
                            cache.set(StatType::HP, new_hp);
                        }

                        // Emit event with updated HP
                        let _ = self.event_tx.send(GameEvent::EntityDamaged {
                            ulid: defender_ulid.clone(),
                            damage: damage as f32,
                            new_hp,
                        });

                        // CRITICAL: Check for death immediately after applying damage
                        // This ensures entities die even if combat worker's prediction was wrong
                        if new_hp <= 0.0 {
                            let _ = self.event_tx.send(GameEvent::EntityDied {
                                ulid: defender_ulid.clone(),
                            });
                        }
                    }

                    // HURT state will be managed in GDScript when EntityDamaged event is received
                    // GDScript entities will set HURT state, play hurt animation, then clear it after animation completes

                    // Also emit combat event for visual feedback
                    let _ = self.event_tx.send(GameEvent::DamageDealt {
                        attacker_ulid,
                        defender_ulid,
                        damage,
                    });
                }
                CombatWorkResult::EntityDied { ulid } => {
                    // Set HP to 0 to ensure consistency
                    if let Some(mut stats) = self.entity_stats.get_mut(&ulid) {
                        use crate::npc::entity::{StatType, ENTITY_STATS};
                        stats.value_mut().set(StatType::HP, 0.0);

                        // CRITICAL: Sync to global cache so GDScript sees updated HP
                        if let Some(mut cache) = ENTITY_STATS.get_mut(&ulid) {
                            cache.set(StatType::HP, 0.0);
                        }
                    }

                    let _ = self.event_tx.send(GameEvent::EntityDied {
                        ulid,
                    });
                }
                CombatWorkResult::CombatEnded { attacker_ulid, defender_ulid } => {
                    let _ = self.event_tx.send(GameEvent::CombatEnded {
                        attacker_ulid,
                        defender_ulid,
                    });
                }
                CombatWorkResult::SpawnProjectile {
                    attacker_ulid,
                    attacker_position,
                    target_ulid,
                    target_position,
                    projectile_type,
                    damage,
                } => {
                    godot_print!(
                        "[Rust Actor] Received SpawnProjectile work result, sending event: type={}, damage={}",
                        projectile_type,
                        damage
                    );
                    // Emit projectile spawn event for GDScript to handle visual
                    let _ = self.event_tx.send(GameEvent::SpawnProjectile {
                        attacker_ulid,
                        attacker_position,
                        target_ulid,
                        target_position,
                        projectile_type,
                        damage,
                    });
                }
                CombatWorkResult::ManaConsumed {
                    entity_ulid,
                    mana_cost,
                    new_mana,
                } => {
                    // Update entity mana in Actor's entity_stats (Actor owns HP/Mana state)
                    if let Some(mut stats) = self.entity_stats.get_mut(&entity_ulid) {
                        use crate::npc::entity::{StatType, ENTITY_STATS};
                        stats.value_mut().set(StatType::Mana, new_mana as f32);

                        // Emit StatChanged event for GDScript UI to update mana bar
                        let _ = self.event_tx.send(GameEvent::StatChanged {
                            ulid: entity_ulid.clone(),
                            stat_type: StatType::Mana as i64,
                            new_value: new_mana as f32,
                        });
                    }
                }
                CombatWorkResult::KiteAway {
                    entity_ulid,
                    enemy_position,
                    ideal_distance,
                } => {
                    // KiteAway handles both kiting (positive ideal_distance) and chasing (negative ideal_distance)
                    if let Some(entity_entry) = self.entities.get(&entity_ulid) {
                        let entity_data = entity_entry.value();
                        let entity_pos = entity_data.position;

                        // Convert entity::TerrainType to terrain_cache::TerrainType
                        use crate::npc::entity::TerrainType as EntityTerrainType;
                        use crate::npc::terrain_cache::TerrainType as CacheTerrainType;
                        let cache_terrain = match entity_data.terrain_type {
                            EntityTerrainType::Water => CacheTerrainType::Water,
                            EntityTerrainType::Land => CacheTerrainType::Land,
                        };

                        let target_pos = if ideal_distance < 0 {
                            // Negative ideal_distance = chase toward enemy (melee units)
                            // Pathfind directly to enemy position
                            enemy_position
                        } else {
                            // Positive ideal_distance = kite away from enemy (ranged units)
                            // Calculate escape direction (away from enemy)
                            let dx = entity_pos.0 - enemy_position.0;
                            let dy = entity_pos.1 - enemy_position.1;

                            // Normalize and scale to ideal distance
                            let distance = ((dx * dx + dy * dy) as f32).sqrt();
                            if distance > 0.0 {
                                let norm_x = (dx as f32 / distance * ideal_distance as f32) as i32;
                                let norm_y = (dy as f32 / distance * ideal_distance as f32) as i32;
                                (entity_pos.0 + norm_x, entity_pos.1 + norm_y)
                            } else {
                                entity_pos // Can't escape, stay put
                            }
                        };

                        // Send pathfinding request to worker
                        let work = PathWorkRequest {
                            ulid: entity_ulid.clone(),
                            terrain_type: cache_terrain,
                            start: entity_pos,
                            goal: target_pos,
                            avoid_entities: false, // Prioritize combat movement over collision avoidance
                            entity_positions: None,
                        };

                        let _ = self.path_tx.send(work);
                    }
                }
            }
        }
    }

    /// Collect economy results
    fn collect_economy_results(&mut self) {
        while let Ok(result) = self.economy_rx.try_recv() {
            for (resource_type, current, cap, rate) in result.resource_changes {
                // Update local state
                self.resources.insert(resource_type, (current, cap, rate));

                // Emit event
                let _ = self.event_tx.send(GameEvent::ResourceChanged {
                    resource_type,
                    current,
                    cap,
                    rate,
                });
            }
        }
    }

    // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
    // /// Collect network worker responses
    // fn collect_network_results(&mut self) {
    //     if let Some(ref worker) = self.network_worker {
    //         while let Some(response) = worker.try_recv() {
    //             match response {
    //                 NetworkWorkerResponse::Connected => {
    //                     let _ = self.event_tx.send(GameEvent::NetworkConnected {
    //                         session_id: "connected".to_string(), // TODO: Get actual session ID
    //                     });
    //                 }
    //                 NetworkWorkerResponse::ConnectionFailed { error } => {
    //                     let _ = self.event_tx.send(GameEvent::NetworkConnectionFailed {
    //                         error,
    //                     });
    //                 }
    //                 NetworkWorkerResponse::Disconnected => {
    //                     let _ = self.event_tx.send(GameEvent::NetworkDisconnected);
    //                 }
    //                 NetworkWorkerResponse::MessageReceived { data } => {
    //                     let _ = self.event_tx.send(GameEvent::NetworkMessageReceived {
    //                         data,
    //                     });
    //                 }
    //                 NetworkWorkerResponse::TextReceived { text } => {
    //                     // Convert text to bytes for consistency
    //                     let _ = self.event_tx.send(GameEvent::NetworkMessageReceived {
    //                         data: text.into_bytes(),
    //                     });
    //                 }
    //                 NetworkWorkerResponse::Error { message } => {
    //                     let _ = self.event_tx.send(GameEvent::NetworkError {
    //                         message,
    //                     });
    //                 }
    //                 NetworkWorkerResponse::StateChanged { .. } => {
    //                     // Could emit state change events if needed
    //                 }
    //             }
    //         }
    //     }
    // }

    // DEPRECATED: IRC/WebSocket now handled by GDScript (irc_websocket_client.gd)
    // /// Collect IRC events
    // fn collect_irc_events(&mut self) {
    //     // Process IRC client if it exists
    //     if let Some(ref mut client) = self.irc_client {
    //         // Process network events (must be called regularly)
    //         client.process();

    //         // Collect IRC events
    //         while let Some(event) = client.try_recv_event() {
    //             match event {
    //                 IrcEvent::Connected { ref nickname, ref server } => {
    //                     let _ = self.event_tx.send(GameEvent::IrcConnected {
    //                         nickname: nickname.clone(),
    //                         server: server.clone(),
    //                     });
    //                 }
    //                 IrcEvent::Disconnected { ref reason } => {
    //                     let _ = self.event_tx.send(GameEvent::IrcDisconnected {
    //                         reason: reason.clone(),
    //                     });
    //                 }
    //                 IrcEvent::Joined { ref channel, ref nickname } => {
    //                     // Ensure channel history exists
    //                     self.chat_history
    //                         .entry(channel.clone())
    //                         .or_insert_with(|| ChannelHistory::new(channel, 500));

    //                     // Add system message
    //                     if let Some(mut history) = self.chat_history.get_mut(channel) {
    //                         history.add_message(ChatMessage::system(format!("{} joined", nickname)));
    //                     }

    //                     let _ = self.event_tx.send(GameEvent::IrcJoinedChannel {
    //                         channel: channel.clone(),
    //                         nickname: nickname.clone(),
    //                     });
    //                 }
    //                 IrcEvent::Parted { ref channel, ref nickname, ref message } => {
    //                     // Add system message
    //                     if let Some(mut history) = self.chat_history.get_mut(channel) {
    //                         let msg = if let Some(m) = message {
    //                             format!("{} left ({})", nickname, m)
    //                         } else {
    //                             format!("{} left", nickname)
    //                         };
    //                         history.add_message(ChatMessage::system(msg));
    //                     }

    //                     let _ = self.event_tx.send(GameEvent::IrcLeftChannel {
    //                         channel: channel.clone(),
    //                         nickname: nickname.clone(),
    //                         message: message.clone(),
    //                     });
    //                 }
    //                 IrcEvent::ChannelMessage { ref channel, ref sender, ref message } => {
    //                     // Store message in chat history
    //                     if let Some(mut history) = self.chat_history.get_mut(channel) {
    //                         history.add_message(ChatMessage::channel(sender, message));
    //                     }

    //                     let _ = self.event_tx.send(GameEvent::IrcChannelMessage {
    //                         channel: channel.clone(),
    //                         sender: sender.clone(),
    //                         message: message.clone(),
    //                     });
    //                 }
    //                 IrcEvent::PrivateMessage { ref sender, ref message } => {
    //                     // Store in private message "channel" (use sender as key)
    //                     let pm_channel = format!("PM:{}", sender);
    //                     self.chat_history
    //                         .entry(pm_channel.clone())
    //                         .or_insert_with(|| ChannelHistory::new(&pm_channel, 500));

    //                     if let Some(mut history) = self.chat_history.get_mut(&pm_channel) {
    //                         history.add_message(ChatMessage::private(sender, message));
    //                     }

    //                     let _ = self.event_tx.send(GameEvent::IrcPrivateMessage {
    //                         sender: sender.clone(),
    //                         message: message.clone(),
    //                     });
    //                 }
    //                 IrcEvent::UserJoined { ref channel, ref nickname } => {
    //                     // Add system message
    //                     if let Some(mut history) = self.chat_history.get_mut(channel) {
    //                         history.add_message(ChatMessage::system(format!("{} joined", nickname)));
    //                     }

    //                     let _ = self.event_tx.send(GameEvent::IrcUserJoined {
    //                         channel: channel.clone(),
    //                         nickname: nickname.clone(),
    //                     });
    //                 }
    //                 IrcEvent::UserParted { ref channel, ref nickname, ref message } => {
    //                     // Add system message
    //                     if let Some(mut history) = self.chat_history.get_mut(channel) {
    //                         let msg = if let Some(m) = message {
    //                             format!("{} left ({})", nickname, m)
    //                         } else {
    //                             format!("{} left", nickname)
    //                         };
    //                         history.add_message(ChatMessage::system(msg));
    //                     }

    //                     let _ = self.event_tx.send(GameEvent::IrcUserLeft {
    //                         channel: channel.clone(),
    //                         nickname: nickname.clone(),
    //                         message: message.clone(),
    //                     });
    //                 }
    //                 IrcEvent::UserQuit { ref nickname, ref message } => {
    //                     // Add to all channels (simplified - normally track user presence per channel)
    //                     let quit_msg = if let Some(m) = message {
    //                         format!("{} quit ({})", nickname, m)
    //                     } else {
    //                         format!("{} quit", nickname)
    //                     };

    //                     for mut history in self.chat_history.iter_mut() {
    //                         history.add_message(ChatMessage::system(&quit_msg));
    //                     }

    //                     let _ = self.event_tx.send(GameEvent::IrcUserQuit {
    //                         nickname: nickname.clone(),
    //                         message: message.clone(),
    //                     });
    //                 }
    //                 IrcEvent::Error { ref message } => {
    //                     let _ = self.event_tx.send(GameEvent::IrcError {
    //                         message: message.clone(),
    //                     });
    //                 }
    //                 _ => {
    //                     // Unhandled IRC events
    //                 }
    //             }
    //         }
    //     }
    // }

    /// Tick combat system
    fn tick_combat(&mut self) {
        // Prepare combat work (copy current entity data)
        let combat_snapshot = self.get_combat_snapshot();

        let work = CombatWorkRequest {
            entities_snapshot: combat_snapshot,
        };

        let _ = self.combat_tx.send(work);
    }

    /// Tick economy system
    fn tick_economy(&mut self) {
        // Send current producer/consumer state to worker
        let work = EconomyWorkRequest {
            producers_snapshot: self.producers.clone(),
            consumers_snapshot: self.consumers.clone(),
            current_resources: self.resources.iter()
                .map(|(k, (current, cap, _rate))| (*k, *current, *cap))
                .collect(),
        };

        let _ = self.economy_tx.send(work);
    }

    // === Helper methods to create snapshots ===

    fn get_occupied_positions(&self) -> Vec<(i32, i32)> {
        let mut positions: Vec<(i32, i32)> = self.entities.iter()
            .map(|entry| entry.value().position)
            .collect();

        // Include pending spawns
        positions.extend(self.pending_spawns.iter().copied());
        positions
    }

    fn get_entity_positions(&self) -> HashMap<Vec<u8>, (i32, i32)> {
        self.entities.iter()
            .map(|entry| (entry.key().clone(), entry.value().position))
            .collect()
    }

    fn get_combat_snapshot(&self) -> Vec<CombatEntitySnapshot> {
        self.entities.iter()
            .filter_map(|entry| {
                let ulid = entry.key();
                let entity = entry.value();

                // Get stats from Actor's entity_stats
                if let Some(stats) = self.entity_stats.get(ulid) {
                    use crate::npc::entity::StatType;
                    use crate::npc::entity::TerrainType as EntityTerrainType;
                    use crate::npc::terrain_cache::TerrainType as CacheTerrainType;

                    // Convert entity::TerrainType to terrain_cache::TerrainType
                    let cache_terrain = match entity.terrain_type {
                        EntityTerrainType::Water => CacheTerrainType::Water,
                        EntityTerrainType::Land => CacheTerrainType::Land,
                    };

                    // Get player_ulid for team detection (empty = AI team)
                    let player_ulid = self.entity_player_ulids.get(ulid)
                        .map(|r| r.value().clone())
                        .unwrap_or_else(Vec::new);

                    // Use ceil() for HP to ensure entities with fractional HP (0.1-0.9) are still alive
                    // This prevents entities from appearing dead (hp=0) when they still have <1.0 HP
                    let hp_f32 = stats.value().get(StatType::HP);
                    let hp_ceiled = if hp_f32 > 0.0 { hp_f32.ceil() as i32 } else { 0 };

                    // Same for mana - ceil to ensure fractional mana is still available
                    let mana_f32 = stats.value().get(StatType::Mana);
                    let mana_ceiled = if mana_f32 > 0.0 { mana_f32.ceil() as i32 } else { 0 };

                    Some(CombatEntitySnapshot {
                        ulid: ulid.clone(),
                        player_ulid,
                        position: entity.position,
                        terrain_type: cache_terrain,
                        hp: hp_ceiled,
                        max_hp: stats.value().get(StatType::MaxHP) as i32,
                        mana: mana_ceiled,
                        max_mana: stats.value().get(StatType::MaxMana) as i32,
                        attack: stats.value().get(StatType::Attack) as i32,
                        defense: stats.value().get(StatType::Defense) as i32,
                        range: stats.value().get(StatType::Range) as i32,
                        combat_type: entity.combat_type.to_u8(),
                        projectile_type: entity.projectile_type.to_u8(),
                        combat_range: entity.combat_range,
                        aggro_range: entity.aggro_range,
                    })
                } else {
                    None
                }
            })
            .collect()
    }

    /// Run the Actor's main loop (called on dedicated thread)
    fn run(mut self) {
        const TICK_RATE: Duration = Duration::from_millis(16); // ~60 ticks/sec

        loop {
            let tick_start = Instant::now();

            // Process one tick
            self.tick(TICK_RATE.as_secs_f64());

            // Sleep for remainder of tick interval
            let elapsed = tick_start.elapsed();
            if elapsed < TICK_RATE {
                thread::sleep(TICK_RATE - elapsed);
            }
        }
    }
}

/// Spawn the Actor on a dedicated thread
/// This is the TRUE ACTOR PATTERN - zero shared state, no lock contention
/// Uses crossbeam_channel for proper Actor communication
pub fn spawn_actor_thread(
    request_rx: Receiver<GameRequest>,
    event_tx: Sender<GameEvent>,
) {
    thread::Builder::new()
        .name("game-actor".to_string())
        .spawn(move || {
            let actor = GameActor::new(request_rx, event_tx);
            actor.run(); // Run forever on this dedicated thread
        })
        .expect("Failed to spawn game-actor thread");
}
