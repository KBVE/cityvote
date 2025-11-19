// Worker thread implementations
// Workers receive snapshots of data, compute results, return via channels

use crossbeam_channel::{Receiver, Sender};
use std::thread;
use std::collections::HashMap;
use godot::prelude::*;

use crate::npc::terrain_cache::TerrainType;

// Re-export combat types from types.rs for convenience (other modules import from workers)
pub use super::types::{CombatEntitySnapshot, CombatWorkRequest, CombatWorkResult};

// ============================================================================
// SPAWN WORKER
// ============================================================================

#[derive(Debug, Clone)]
pub struct SpawnWorkRequest {
    pub entity_type: String,
    pub terrain_type: TerrainType,
    pub preferred_location: (i32, i32),
    pub search_radius: i32,
    pub occupied_positions: Vec<(i32, i32)>, // Snapshot, not DashMap
}

#[derive(Debug, Clone)]
pub enum SpawnWorkResult {
    Success {
        ulid: Vec<u8>,
        position: (i32, i32),
        entity_type: String,
        terrain_type: TerrainType,
    },
    Failed {
        entity_type: String,
        error: String,
    },
}

pub fn spawn_spawn_worker(
    rx: Receiver<SpawnWorkRequest>,
    tx: Sender<SpawnWorkResult>,
) {
    thread::Builder::new()
        .name("spawn-worker".to_string())
        .spawn(move || {
            use crate::npc::terrain_cache;

            loop {
                if let Ok(request) = rx.recv() {
                    // Simple spawn logic: try preferred location first, then spiral search
                    let position_result = find_spawn_position_simple(
                        request.preferred_location,
                        request.search_radius,
                        request.terrain_type,
                        &request.occupied_positions,
                    );

                    let result = match position_result {
                        Some(position) => {
                            // Generate ULID for new entity
                            let ulid_obj = ulid::Ulid::new();
                            let ulid = ulid_obj.to_bytes().to_vec();

                            SpawnWorkResult::Success {
                                ulid,
                                position,
                                entity_type: request.entity_type,
                                terrain_type: request.terrain_type,
                            }
                        }
                        None => SpawnWorkResult::Failed {
                            entity_type: request.entity_type,
                            error: "No valid spawn position found".to_string(),
                        },
                    };

                    let _ = tx.send(result);
                }
            }
        })
        .expect("Failed to spawn spawn-worker thread");
}

/// Simple spawn position finder using snapshots
fn find_spawn_position_simple(
    preferred: (i32, i32),
    radius: i32,
    terrain_type: TerrainType,
    occupied: &[(i32, i32)],
) -> Option<(i32, i32)> {
    use crate::npc::terrain_cache;

    // Check preferred location first
    let terrain = terrain_cache::get_terrain(preferred.0, preferred.1);
    if terrain == terrain_type && !occupied.contains(&preferred) {
        return Some(preferred);
    }

    // Spiral search outward
    for r in 1..=radius {
        for dx in -r..=r {
            for dy in -r..=r {
                let pos = (preferred.0 + dx, preferred.1 + dy);
                let terrain = terrain_cache::get_terrain(pos.0, pos.1);

                if terrain == terrain_type && !occupied.contains(&pos) {
                    return Some(pos);
                }
            }
        }
    }

    None
}

// ============================================================================
// PATHFINDING WORKER POOL
// ============================================================================

#[derive(Debug, Clone)]
pub struct PathWorkRequest {
    pub ulid: Vec<u8>,
    pub terrain_type: TerrainType,
    pub start: (i32, i32),
    pub goal: (i32, i32),
    pub avoid_entities: bool,
    pub entity_positions: Option<HashMap<Vec<u8>, (i32, i32)>>, // Snapshot if avoiding
}

#[derive(Debug, Clone)]
pub enum PathWorkResult {
    Success {
        ulid: Vec<u8>,
        path: Vec<(i32, i32)>,
        cost: f32,
    },
    Failed {
        ulid: Vec<u8>,
    },
    RandomDestSuccess {
        ulid: Vec<u8>,
        destination: (i32, i32),
    },
    RandomDestFailed {
        ulid: Vec<u8>,
    },
}

pub fn spawn_pathfinding_pool(
    rx: Receiver<PathWorkRequest>,
    tx: Sender<PathWorkResult>,
    pool_size: usize,
) {
    for i in 0..pool_size {
        let rx_clone = rx.clone();
        let tx_clone = tx.clone();

        thread::Builder::new()
            .name(format!("pathfinding-worker-{}", i))
            .spawn(move || {
                loop {
                    if let Ok(request) = rx_clone.recv() {
                        // Call actual A* pathfinding
                        use crate::npc::unified_pathfinding;

                        let pathfinding_request = unified_pathfinding::PathfindingRequest {
                            entity_ulid: request.ulid.clone(),
                            start: request.start,
                            goal: request.goal,
                            terrain_type: request.terrain_type,
                            avoid_entities: request.avoid_entities,
                        };

                        let pathfinding_result = unified_pathfinding::find_path_unified(&pathfinding_request);

                        let result = if pathfinding_result.success && !pathfinding_result.path.is_empty() {
                            PathWorkResult::Success {
                                ulid: request.ulid,
                                path: pathfinding_result.path,
                                cost: pathfinding_result.cost,
                            }
                        } else {
                            PathWorkResult::Failed {
                                ulid: request.ulid,
                            }
                        };

                        let _ = tx_clone.send(result);
                    }
                }
            })
            .expect("Failed to spawn pathfinding worker");
    }
}

// ============================================================================
// COMBAT WORKER
// ============================================================================

// NOTE: Combat types moved to types.rs to avoid duplication

pub fn spawn_combat_worker(
    rx: Receiver<CombatWorkRequest>,
    tx: Sender<CombatWorkResult>,
) {
    thread::Builder::new()
        .name("combat-worker".to_string())
        .spawn(move || {
            // Active combat instances (attacker_ulid -> combat state)
            let mut active_combats: HashMap<Vec<u8>, CombatInstance> = HashMap::new();

            loop {
                if let Ok(request) = rx.recv() {
                    // Process combat for all entities in snapshot
                    process_combat_tick(&request.entities_snapshot, &mut active_combats, &tx);
                }
            }
        })
        .expect("Failed to spawn combat worker");
}

/// Combat instance tracking for a single attacker
struct CombatInstance {
    defender_ulid: Vec<u8>,
    time_since_last_attack: f32,
    attack_interval: f32,
}

impl CombatInstance {
    fn new(defender_ulid: Vec<u8>, attack_interval: f32) -> Self {
        Self {
            defender_ulid,
            time_since_last_attack: attack_interval, // Allow immediate first attack
            attack_interval,
        }
    }

    fn can_attack(&self) -> bool {
        self.time_since_last_attack >= self.attack_interval
    }

    fn reset_attack_timer(&mut self) {
        self.time_since_last_attack = 0.0;
    }

    fn tick(&mut self, delta: f32) {
        self.time_since_last_attack += delta;
    }
}

/// Process one combat tick for all entities
fn process_combat_tick(
    entities: &[CombatEntitySnapshot],
    active_combats: &mut HashMap<Vec<u8>, CombatInstance>,
    tx: &Sender<CombatWorkResult>,
) {
    // Tick interval (should match Actor's combat tick rate of 0.5s)
    const TICK_DELTA: f32 = 0.5;

    // Tick all active combats
    for combat in active_combats.values_mut() {
        combat.tick(TICK_DELTA);
    }

    // Build quick lookup maps
    let entity_map: HashMap<&Vec<u8>, &CombatEntitySnapshot> =
        entities.iter().map(|e| (&e.ulid, e)).collect();

    // Process each entity
    for attacker in entities {
        // Skip dead entities
        if attacker.hp <= 0 {
            continue;
        }

        // Check if already in combat
        if let Some(combat) = active_combats.get_mut(&attacker.ulid) {
            // Combat exists - check if defender still valid
            if let Some(defender) = entity_map.get(&combat.defender_ulid) {
                let defender_alive = defender.hp > 0;

                if !defender_alive {
                    // Defender died - end combat
                    let _ = tx.send(CombatWorkResult::CombatEnded {
                        attacker_ulid: attacker.ulid.clone(),
                        defender_ulid: combat.defender_ulid.clone(),
                    });
                    // Remove from active combats (will happen after loop)
                } else {
                    // Check if still in range (entities might have moved)
                    let distance = hex_distance(attacker.position, defender.position);
                    let in_range = distance <= attacker.combat_range;

                    // Check combat type for chase vs disengage behavior
                    const MELEE: u8 = 1 << 0;
                    let is_melee = attacker.combat_type & MELEE != 0;

                    if in_range && combat.can_attack() {
                        // In range and can attack - execute attack
                        execute_attack(attacker, defender, tx);
                        combat.reset_attack_timer();
                    } else if !in_range {
                        // Out of range behavior depends on combat type
                        if is_melee {
                            // Melee units chase their target (pathfind toward enemy)
                            let _ = tx.send(CombatWorkResult::KiteAway {
                                entity_ulid: attacker.ulid.clone(),
                                enemy_position: defender.position,
                                ideal_distance: -1, // Negative = chase toward (not away)
                            });
                        } else {
                            // Ranged units disengage when out of range
                            let _ = tx.send(CombatWorkResult::CombatEnded {
                                attacker_ulid: attacker.ulid.clone(),
                                defender_ulid: combat.defender_ulid.clone(),
                            });
                        }
                    }
                }
            } else {
                // Defender no longer exists - end combat
                let _ = tx.send(CombatWorkResult::CombatEnded {
                    attacker_ulid: attacker.ulid.clone(),
                    defender_ulid: combat.defender_ulid.clone(),
                });
            }
        } else {
            // Not in combat - search for targets
            if let Some(target_ulid) = find_closest_enemy(attacker, entities) {
                // Found enemy in range - start combat
                let combat = CombatInstance::new(target_ulid.clone(), 1.5); // 1.5s attack interval
                active_combats.insert(attacker.ulid.clone(), combat);

                // Queue combat started event
                let _ = tx.send(CombatWorkResult::CombatStarted {
                    attacker_ulid: attacker.ulid.clone(),
                    defender_ulid: target_ulid,
                });
            }
        }
    }

    // Clean up combats where defender is dead or out of range
    // This removes the combat instance after CombatEnded events have been sent
    active_combats.retain(|attacker_ulid, combat| {
        // Find attacker and defender
        let attacker_opt = entity_map.get(attacker_ulid);
        let defender_opt = entity_map.get(&combat.defender_ulid);

        // Keep combat only if both exist, defender is alive, and in range
        if let (Some(attacker), Some(defender)) = (attacker_opt, defender_opt) {
            if defender.hp <= 0 {
                return false; // Defender dead
            }
            let distance = hex_distance(attacker.position, defender.position);
            distance <= attacker.combat_range // Keep only if in range
        } else {
            false // Either attacker or defender missing
        }
    });
}

/// Find the closest enemy within attack range
fn find_closest_enemy(
    attacker: &CombatEntitySnapshot,
    entities: &[CombatEntitySnapshot],
) -> Option<Vec<u8>> {
    let mut closest_enemy: Option<(Vec<u8>, i32)> = None;

    for defender in entities {
        // Skip self
        if defender.ulid == attacker.ulid {
            continue;
        }

        // Skip dead entities
        if defender.hp <= 0 {
            continue;
        }

        // Team detection: Compare player_ulid
        // - Empty player_ulid = AI team (all AI entities are allies)
        // - Same non-empty player_ulid = same player's entities (allies)
        // - Different player_ulids = enemies
        let attacker_is_ai = attacker.player_ulid.is_empty();
        let defender_is_ai = defender.player_ulid.is_empty();

        // If both are AI, they're allies - skip
        if attacker_is_ai && defender_is_ai {
            continue;
        }

        // If both belong to the same player, they're allies - skip
        if !attacker_is_ai && !defender_is_ai && attacker.player_ulid == defender.player_ulid {
            continue;
        }

        // Check if in aggro range (use aggro_range for enemy detection, not combat_range)
        // combat_range is used for actual attacking, aggro_range is for detecting enemies
        let distance = hex_distance(attacker.position, defender.position);
        if distance > attacker.aggro_range {
            continue;
        }

        // Update closest if this is closer
        match &closest_enemy {
            None => closest_enemy = Some((defender.ulid.clone(), distance)),
            Some((_, prev_distance)) => {
                if distance < *prev_distance {
                    closest_enemy = Some((defender.ulid.clone(), distance));
                }
            }
        }
    }

    closest_enemy.map(|(ulid, _)| ulid)
}

/// Execute an attack between two entities
fn execute_attack(
    attacker: &CombatEntitySnapshot,
    defender: &CombatEntitySnapshot,
    tx: &Sender<CombatWorkResult>,
) {
    // CombatType flags (using bit shifts for readability)
    const MELEE: u8 = 1 << 0;   // 1
    const BOW: u8 = 1 << 2;     // 4
    const MAGIC: u8 = 1 << 3;   // 8

    // Mana cost for magic attacks
    const MAGIC_MANA_COST: i32 = 15;

    // Check combat type
    let is_melee = attacker.combat_type & MELEE != 0;
    let is_bow = attacker.combat_type & BOW != 0;
    let is_magic = attacker.combat_type & MAGIC != 0;

    // Check mana availability for magic attacks
    if is_magic && attacker.mana < MAGIC_MANA_COST {
        // Not enough mana - attack fails silently
        // Could emit a "NotEnoughMana" event in the future
        return;
    }

    // Calculate damage (simple: attack - defense, min 1)
    let raw_damage = attacker.attack - defender.defense;
    let damage = raw_damage.max(1);

    // Consume mana for magic attacks
    if is_magic {
        let new_mana = attacker.mana - MAGIC_MANA_COST;
        let _ = tx.send(CombatWorkResult::ManaConsumed {
            entity_ulid: attacker.ulid.clone(),
            mana_cost: MAGIC_MANA_COST,
            new_mana,
        });
    }

    // Notify that attacker is executing attack animation
    let _ = tx.send(CombatWorkResult::AttackExecuted {
        attacker_ulid: attacker.ulid.clone(),
    });

    // For ranged combat (BOW or MAGIC), spawn projectile instead of instant damage
    if is_bow || is_magic {
        godot_print!(
            "[Rust Combat] Spawning projectile: attacker={:02x?}, target={:02x?}, type={}, damage={}",
            &attacker.ulid[..8],
            &defender.ulid[..8],
            attacker.projectile_type,
            damage
        );
        let _ = tx.send(CombatWorkResult::SpawnProjectile {
            attacker_ulid: attacker.ulid.clone(),
            attacker_position: attacker.position,
            target_ulid: defender.ulid.clone(),
            target_position: defender.position,
            projectile_type: attacker.projectile_type,
            damage,
        });

        // Kiting behavior: If enemy is too close, move away to ideal distance
        // Ideal distance for ranged units: 60% of max range (allows flexibility)
        let distance = hex_distance(attacker.position, defender.position);
        let ideal_distance = (attacker.combat_range as f32 * 0.6).ceil() as i32;
        let min_safe_distance = (attacker.combat_range as f32 * 0.4).ceil() as i32;

        if distance < min_safe_distance {
            // Too close - kite away
            let _ = tx.send(CombatWorkResult::KiteAway {
                entity_ulid: attacker.ulid.clone(),
                enemy_position: defender.position,
                ideal_distance,
            });
        }
    } else {
        // Melee combat - instant damage
        let _ = tx.send(CombatWorkResult::DamageDealt {
            attacker_ulid: attacker.ulid.clone(),
            defender_ulid: defender.ulid.clone(),
            damage,
        });

        // Check if defender will die
        let new_hp = defender.hp - damage;
        if new_hp <= 0 {
            let _ = tx.send(CombatWorkResult::EntityDied {
                ulid: defender.ulid.clone(),
            });
        }
    }
}

/// Calculate hex distance using cube coordinates
fn hex_distance(a: (i32, i32), b: (i32, i32)) -> i32 {
    let (ax, ay) = a;
    let (bx, by) = b;

    let dx = (ax - bx).abs();
    let dy = (ay - by).abs();

    // Convert axial to cube coordinates
    let az = -ax - ay;
    let bz = -bx - by;
    let dz = (az - bz).abs();

    dx.max(dy).max(dz)
}

// ============================================================================
// ECONOMY WORKER
// ============================================================================

#[derive(Debug, Clone)]
pub struct EconomyWorkRequest {
    pub producers_snapshot: Vec<(Vec<u8>, i64, f64, bool)>, // (ulid, resource_type, rate, active)
    pub consumers_snapshot: Vec<(Vec<u8>, i64, f64, bool)>,
    pub current_resources: Vec<(i64, f64, f64)>, // (type, current, cap)
}

#[derive(Debug, Clone)]
pub struct EconomyWorkResult {
    pub resource_changes: Vec<(i64, f64, f64, f64)>, // (type, current, cap, rate)
}

pub fn spawn_economy_worker(
    rx: Receiver<EconomyWorkRequest>,
    tx: Sender<EconomyWorkResult>,
) {
    thread::Builder::new()
        .name("economy-worker".to_string())
        .spawn(move || {
            loop {
                if let Ok(request) = rx.recv() {
                    // Calculate resource changes based on producers/consumers
                    let mut changes = Vec::new();

                    for (resource_type, current, cap) in request.current_resources {
                        // Calculate net rate
                        let producer_rate: f64 = request
                            .producers_snapshot
                            .iter()
                            .filter(|(_, rt, _, active)| *rt == resource_type && *active)
                            .map(|(_, _, rate, _)| rate)
                            .sum();

                        let consumer_rate: f64 = request
                            .consumers_snapshot
                            .iter()
                            .filter(|(_, rt, _, active)| *rt == resource_type && *active)
                            .map(|(_, _, rate, _)| rate)
                            .sum();

                        let net_rate = producer_rate - consumer_rate;

                        // Apply change (1 second delta)
                        let new_current = (current + net_rate).clamp(0.0, cap);

                        changes.push((resource_type, new_current, cap, net_rate));
                    }

                    let result = EconomyWorkResult {
                        resource_changes: changes,
                    };

                    let _ = tx.send(result);
                }
            }
        })
        .expect("Failed to spawn economy worker");
}
