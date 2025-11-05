// Worker thread implementations
// Workers receive snapshots of data, compute results, return via channels

use crossbeam_channel::{Receiver, Sender};
use std::thread;
use std::collections::HashMap;

use crate::npc::terrain_cache::TerrainType;

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

#[derive(Debug, Clone)]
pub struct CombatWorkRequest {
    pub entities_snapshot: Vec<CombatEntitySnapshot>,
}

#[derive(Debug, Clone)]
pub struct CombatEntitySnapshot {
    pub ulid: Vec<u8>,
    pub position: (i32, i32),
    pub terrain_type: TerrainType,
    pub hp: i32,
    pub max_hp: i32,
    pub attack: i32,
    pub defense: i32,
    pub range: i32,
}

#[derive(Debug, Clone)]
pub enum CombatWorkResult {
    CombatStarted {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
    },
    DamageDealt {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
        damage: i32,
    },
    EntityDied {
        ulid: Vec<u8>,
    },
    CombatEnded {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
    },
}

pub fn spawn_combat_worker(
    rx: Receiver<CombatWorkRequest>,
    tx: Sender<CombatWorkResult>,
) {
    thread::Builder::new()
        .name("combat-worker".to_string())
        .spawn(move || {
            loop {
                if let Ok(request) = rx.recv() {
                    // Process combat for all entities in snapshot
                    // TODO: Implement combat tick logic
                    // For now, just sleep to simulate work
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
            }
        })
        .expect("Failed to spawn combat worker");
}

// ============================================================================
// ECONOMY WORKER
// ============================================================================

#[derive(Debug, Clone)]
pub struct EconomyWorkRequest {
    pub producers_snapshot: Vec<(Vec<u8>, i32, f32, bool)>, // (ulid, resource_type, rate, active)
    pub consumers_snapshot: Vec<(Vec<u8>, i32, f32, bool)>,
    pub current_resources: Vec<(i32, f32, f32)>, // (type, current, cap)
}

#[derive(Debug, Clone)]
pub struct EconomyWorkResult {
    pub resource_changes: Vec<(i32, f32, f32, f32)>, // (type, current, cap, rate)
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
                        let producer_rate: f32 = request
                            .producers_snapshot
                            .iter()
                            .filter(|(_, rt, _, active)| *rt == resource_type && *active)
                            .map(|(_, _, rate, _)| rate)
                            .sum();

                        let consumer_rate: f32 = request
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
