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

use crate::npc::entity::{EntityData, EntityStats};
use crate::economy::resource_ledger::ResourceType;
use super::types::{GameEvent, GameRequest};
use super::workers::*;

/// Central coordinator that owns all shared state
/// RUNS ON DEDICATED THREAD - No shared state, zero lock contention
pub struct GameActor {
    // === OWNED STATE (Direct ownership, no Arc needed) ===
    entities: DashMap<Vec<u8>, EntityData>,
    entity_stats: DashMap<Vec<u8>, EntityStats>,  // Actor OWNS stats
    pending_spawns: HashSet<(i32, i32)>,

    // === COMMUNICATION (crossbeam_channel for proper Actor pattern) ===
    request_rx: Receiver<GameRequest>,  // Receive requests from Godot
    event_tx: Sender<GameEvent>,        // Send events to Godot

    // Resource state (simplified for now)
    resources: HashMap<i32, (f32, f32, f32)>, // (current, cap, rate)
    producers: Vec<(Vec<u8>, i32, f32, bool)>, // (ulid, resource_type, rate, active)
    consumers: Vec<(Vec<u8>, i32, f32, bool)>,

    // === WORKER CHANNELS ===
    spawn_tx: Sender<SpawnWorkRequest>,
    spawn_rx: Receiver<SpawnWorkResult>,

    path_tx: Sender<PathWorkRequest>,
    path_rx: Receiver<PathWorkResult>,

    combat_tx: Sender<CombatWorkRequest>,
    combat_rx: Receiver<CombatWorkResult>,

    economy_tx: Sender<EconomyWorkRequest>,
    economy_rx: Receiver<EconomyWorkResult>,

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
        let entity_stats = DashMap::new();

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

        let mut actor = Self {
            entities,
            entity_stats,
            pending_spawns: HashSet::new(),

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

                    godot_print!("RandomDest: start={:?}, min={}, max={}", start, min_distance, max_distance);

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

                        godot_print!("  Attempt {}: distance={}, direction={}, offset={}, dest={:?}",
                            attempt, distance, angle_index, rand_offset, dest);

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

                GameRequest::RegisterEntityStats { ulid, entity_type, terrain_type, position } => {
                    use crate::npc::entity::{EntityStats, TerrainType as EntityTerrainType, StatType, ENTITY_STATS};

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

                    // DEBUG: Log ULID registration (full ULID in hex)
                    godot_print!("✅ Registering stats for ULID: {:02x?} (terrain: {})", &ulid, terrain_type);

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
                        let entity_data = EntityData::new(ulid, position, et, entity_type);
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
                        let new_hp = stats.get(StatType::HP);

                        // Sync to global cache
                        if let Some(mut cache) = ENTITY_STATS.get_mut(&ulid) {
                            cache.take_damage(damage);
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
                CombatWorkResult::DamageDealt { attacker_ulid, defender_ulid, damage } => {
                    let _ = self.event_tx.send(GameEvent::DamageDealt {
                        attacker_ulid,
                        defender_ulid,
                        damage,
                    });
                }
                CombatWorkResult::EntityDied { ulid } => {
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

                    Some(CombatEntitySnapshot {
                        ulid: ulid.clone(),
                        position: entity.position,
                        terrain_type: cache_terrain,
                        hp: stats.value().get(StatType::HP) as i32,
                        max_hp: stats.value().get(StatType::MaxHP) as i32,
                        attack: stats.value().get(StatType::Attack) as i32,
                        defense: stats.value().get(StatType::Defense) as i32,
                        range: stats.value().get(StatType::Range) as i32,
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
