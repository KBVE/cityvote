use godot::prelude::*;
use super::entity::{EntityData, ENTITY_DATA};
use super::terrain_cache::{self, TerrainType as CacheTerrainType};
use super::entity::TerrainType as EntityTerrainType;
use dashmap::DashSet;
use once_cell::sync::Lazy;
use crossbeam_queue::SegQueue;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;

type HexCoord = (i32, i32);

/// Track positions that have pending spawns (not yet in ENTITY_DATA due to worker thread)
/// This prevents duplicate position assignments during rapid spawn bursts
pub(super) static PENDING_SPAWNS: Lazy<DashSet<HexCoord>> = Lazy::new(|| DashSet::new());

/// Spawn request structure
#[derive(Debug, Clone)]
pub struct SpawnRequest {
    pub entity_type: String,
    pub terrain_type: CacheTerrainType,
    pub preferred_location: Option<HexCoord>,
    pub search_radius: i32,
}

/// Spawn request queue (GDScript -> Worker thread)
static SPAWN_REQUESTS: Lazy<Arc<SegQueue<SpawnRequest>>> = Lazy::new(|| Arc::new(SegQueue::new()));

/// Spawn result queue (Worker thread -> GDScript)
static SPAWN_RESULTS: Lazy<Arc<SegQueue<SpawnResult>>> = Lazy::new(|| Arc::new(SegQueue::new()));

/// Worker thread running flag
static SPAWN_WORKER_RUNNING: AtomicBool = AtomicBool::new(false);

/// Result of a spawn attempt
#[derive(Debug, Clone)]
pub struct SpawnResult {
    pub ulid: Vec<u8>,
    pub entity_type: String,
    pub position: HexCoord,
    pub terrain_type: CacheTerrainType,
    pub success: bool,
    pub error_message: String,
}

/// Validate if a location is suitable for spawning
fn is_valid_spawn_location(pos: HexCoord, terrain_type: CacheTerrainType) -> bool {
    // Check terrain matches
    let terrain = terrain_cache::get_terrain(pos.0, pos.1);
    if terrain != terrain_type {
        return false;
    }

    // Check not occupied by another entity
    let occupied = ENTITY_DATA.iter().any(|entry| {
        entry.value().position == pos
    });

    if occupied {
        return false;
    }

    // Check not pending spawn (race condition protection)
    !PENDING_SPAWNS.contains(&pos)
}

/// Validate and atomically reserve a spawn location
/// Returns true if the location was valid and successfully reserved
fn try_reserve_spawn_location(pos: HexCoord, terrain_type: CacheTerrainType) -> bool {
    // Check if already pending
    if PENDING_SPAWNS.contains(&pos) {
        godot_print!("  -> Position {:?} already pending spawn (in PENDING_SPAWNS)", pos);
        return false;
    }

    // Check terrain matches
    let terrain = terrain_cache::get_terrain(pos.0, pos.1);
    if terrain != terrain_type {
        godot_print!("  -> Position {:?} has wrong terrain type", pos);
        return false;
    }

    // Check not occupied by another entity
    let occupied_count = ENTITY_DATA.iter().filter(|entry| entry.value().position == pos).count();
    if occupied_count > 0 {
        godot_print!("  -> Position {:?} occupied by {} entities in ENTITY_DATA", pos, occupied_count);
        return false;
    }

    // CRITICAL: Atomically insert into pending spawns
    // DashSet::insert() returns true if value was newly inserted
    let inserted = PENDING_SPAWNS.insert(pos);
    if inserted {
        godot_print!("  -> Successfully reserved position {:?} (PENDING_SPAWNS size: {})", pos, PENDING_SPAWNS.len());
    } else {
        godot_print!("  -> Failed to reserve position {:?} (race condition - already in PENDING_SPAWNS)", pos);
    }
    inserted
}

/// Calculate hex distance between two coordinates
fn hex_distance(a: HexCoord, b: HexCoord) -> f32 {
    let dq = (a.0 - b.0).abs() as f32;
    let dr = (a.1 - b.1).abs() as f32;
    let ds = (a.0 + a.1 - b.0 - b.1).abs() as f32;
    ((dq + dr + ds) / 2.0).max(dq.max(dr))
}

/// Find a valid spawn location near a preferred position
/// CRITICAL: Atomically reserves the position before returning
fn find_nearby_spawn_location(
    preferred: HexCoord,
    terrain_type: CacheTerrainType,
    search_radius: i32,
) -> Option<HexCoord> {
    // Search in expanding rings around preferred location
    for distance in 0..=search_radius {
        for dx in -distance..=distance {
            for dy in -distance..=distance {
                let candidate = (preferred.0 + dx, preferred.1 + dy);

                // Check if within radius (hex distance)
                if hex_distance(preferred, candidate) > distance as f32 {
                    continue;
                }

                // CRITICAL: Atomically validate and reserve position
                if try_reserve_spawn_location(candidate, terrain_type) {
                    return Some(candidate);
                }
            }
        }
    }

    None
}

/// Find a random valid spawn location in the world
/// CRITICAL: Atomically reserves the position before returning
fn find_random_spawn_location(
    center: HexCoord,
    terrain_type: CacheTerrainType,
    search_radius: i32,
) -> Option<HexCoord> {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let mut valid_locations = Vec::new();

    // Search in area around center (but DON'T reserve yet)
    for dx in -search_radius..=search_radius {
        for dy in -search_radius..=search_radius {
            let candidate = (center.0 + dx, center.1 + dy);

            if is_valid_spawn_location(candidate, terrain_type) {
                valid_locations.push(candidate);
            }
        }
    }

    if valid_locations.is_empty() {
        return None;
    }

    // Try to reserve one of the valid locations
    // Keep trying random locations until one succeeds (race condition protection)
    for _ in 0..valid_locations.len() {
        let idx = rng.gen_range(0..valid_locations.len());
        let candidate = valid_locations[idx];

        // CRITICAL: Atomically reserve the position
        if try_reserve_spawn_location(candidate, terrain_type) {
            return Some(candidate);
        }

        // If reservation failed (race condition), try another location
        valid_locations.swap_remove(idx);

        if valid_locations.is_empty() {
            break;
        }
    }

    None
}

/// Initialize spawn worker thread
pub fn initialize_spawn_worker() {
    if SPAWN_WORKER_RUNNING.swap(true, Ordering::SeqCst) {
        return; // Already running
    }

    thread::Builder::new()
        .name("spawn_worker".to_string())
        .spawn(|| {
            godot_print!("Spawn worker thread started");

            while SPAWN_WORKER_RUNNING.load(Ordering::SeqCst) {
                // Process spawn requests from the queue
                while let Some(request) = SPAWN_REQUESTS.pop() {
                    let result = process_spawn_request(request);
                    SPAWN_RESULTS.push(result);
                }

                // Sleep briefly to avoid spinning
                thread::sleep(std::time::Duration::from_micros(100));
            }

            godot_print!("Spawn worker thread stopped");
        })
        .expect("Failed to start spawn worker thread");
}

/// Process a single spawn request (called by worker thread)
fn process_spawn_request(request: SpawnRequest) -> SpawnResult {
    let entity_type = request.entity_type;
    let terrain_type = request.terrain_type;
    let search_radius = request.search_radius;

    godot_print!("process_spawn_request: type={}, terrain={:?}, preferred={:?}, radius={}",
        entity_type, terrain_type, request.preferred_location, search_radius);

    // Find valid spawn location (atomically reserved by the search functions)
    let spawn_pos = if let Some(preferred) = request.preferred_location {
        // Try preferred location first (atomically reserve if valid)
        if try_reserve_spawn_location(preferred, terrain_type) {
            godot_print!("  -> Using preferred location: {:?}", preferred);
            Some(preferred)
        } else {
            // Find nearby valid location (atomically reserves position)
            godot_print!("  -> Preferred location invalid, searching nearby...");
            find_nearby_spawn_location(preferred, terrain_type, search_radius)
        }
    } else {
        // Find random valid location around world origin (atomically reserves position)
        godot_print!("  -> No preferred location, searching random...");
        find_random_spawn_location((0, 0), terrain_type, search_radius)
    };

    let Some(position) = spawn_pos else {
        godot_error!("process_spawn_request: Failed to find valid spawn location for {} (terrain={:?})", entity_type, terrain_type);
        return SpawnResult {
            ulid: vec![],
            entity_type,
            position: (0, 0),
            terrain_type,
            success: false,
            error_message: "No valid spawn location found".to_string(),
        };
    };

    // Position is already reserved by the search functions above
    // (no need for redundant PENDING_SPAWNS.insert() here)

    // Generate ULID for entity
    let ulid_obj = ulid::Ulid::new();
    let ulid = ulid_obj.to_bytes().to_vec();

    // Convert CacheTerrainType to EntityTerrainType
    let entity_terrain_type = match terrain_type {
        CacheTerrainType::Water => EntityTerrainType::Water,
        CacheTerrainType::Land => EntityTerrainType::Land,
        CacheTerrainType::Obstacle => {
            godot_error!("process_spawn_request: Cannot spawn on Obstacle terrain!");
            // CRITICAL: Clean up pending spawn reservation before returning error
            PENDING_SPAWNS.remove(&position);
            return SpawnResult {
                ulid: vec![],
                entity_type,
                position,
                terrain_type,
                success: false,
                error_message: "Cannot spawn on obstacle terrain".to_string(),
            };
        }
    };

    // Create entity data in Rust using the proper constructor
    let entity_data = EntityData::new(
        ulid.clone(),
        position,
        entity_terrain_type,
        entity_type.clone(),
    );

    // CRITICAL: Insert entity directly into ENTITY_DATA (we're already in a worker thread)
    // This must happen BEFORE removing from PENDING_SPAWNS to prevent race conditions
    ENTITY_DATA.insert(ulid.clone(), entity_data);
    godot_print!("  -> Inserted into ENTITY_DATA (total entities: {})", ENTITY_DATA.len());

    // CRITICAL: Remove position from pending spawns AFTER entity is in ENTITY_DATA
    // This ensures subsequent spawns see the entity and avoid the position
    let removed = PENDING_SPAWNS.remove(&position);
    godot_print!("  -> Removed from PENDING_SPAWNS: {} (remaining: {})", removed.is_some(), PENDING_SPAWNS.len());

    godot_print!("process_spawn_request: SUCCESS - Spawned {} at {:?} (ulid={:02x}{:02x}...)",
        entity_type, position, ulid[0], ulid[1]);

    SpawnResult {
        ulid,
        entity_type,
        position,
        terrain_type,
        success: true,
        error_message: String::new(),
    }
}

/// Queue a spawn request (called from GDScript)
pub fn queue_spawn_request(
    entity_type: String,
    terrain_type: CacheTerrainType,
    preferred_location: Option<HexCoord>,
    search_radius: i32,
) {
    SPAWN_REQUESTS.push(SpawnRequest {
        entity_type,
        terrain_type,
        preferred_location,
        search_radius,
    });
}

/// Get a spawn result from the queue (called from GDScript)
pub fn get_spawn_result() -> Option<SpawnResult> {
    SPAWN_RESULTS.pop()
}

// ============================================================================
// GODOT BRIDGE
// ============================================================================

#[derive(GodotClass)]
#[class(base=Node)]
pub struct EntitySpawnBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for EntitySpawnBridge {
    fn init(base: Base<Node>) -> Self {
        godot_print!("EntitySpawnBridge initialized!");
        // Start the spawn worker thread
        initialize_spawn_worker();
        Self { base }
    }

    fn process(&mut self, _delta: f64) {
        // Poll spawn results and emit signals
        while let Some(result) = get_spawn_result() {
            self.base_mut().emit_signal(
                "spawn_completed",
                &[
                    result.success.to_variant(),
                    PackedByteArray::from(result.ulid.as_slice()).to_variant(),
                    result.position.0.to_variant(),
                    result.position.1.to_variant(),
                    (match result.terrain_type {
                        CacheTerrainType::Water => 0,
                        CacheTerrainType::Land => 1,
                        CacheTerrainType::Obstacle => 2,
                    }).to_variant(),
                    GString::from(result.entity_type.as_str()).to_variant(),
                    GString::from(result.error_message.as_str()).to_variant(),
                ],
            );
        }
    }
}

#[godot_api]
impl EntitySpawnBridge {
    /// Signal emitted when a spawn request completes
    /// Args: success (bool), ulid (PackedByteArray), position_q (int), position_r (int),
    ///       terrain_type (int), entity_type (String), error_message (String)
    #[signal]
    fn spawn_completed(
        success: bool,
        ulid: PackedByteArray,
        position_q: i32,
        position_r: i32,
        terrain_type: i32,
        entity_type: GString,
        error_message: GString,
    );

    /// Queue a spawn request (async, non-blocking)
    ///
    /// # Arguments
    /// * `entity_type` - Type of entity to spawn ("viking", "jezza", etc.)
    /// * `terrain_type_int` - 0=Water, 1=Land
    /// * `preferred_q` - Optional preferred Q coordinate (use -999999 for none)
    /// * `preferred_r` - Optional preferred R coordinate (use -999999 for none)
    /// * `search_radius` - Radius to search for valid spawn location
    ///
    /// The result will be emitted via the `spawn_completed` signal
    #[func]
    pub fn spawn_entity(
        &self,
        entity_type: GString,
        terrain_type_int: i32,
        preferred_q: i32,
        preferred_r: i32,
        search_radius: i32,
    ) {
        let entity_type_str = entity_type.to_string();

        let terrain_type = match terrain_type_int {
            0 => CacheTerrainType::Water,
            1 => CacheTerrainType::Land,
            _ => {
                godot_error!("Invalid terrain_type: {}", terrain_type_int);
                return;
            }
        };

        let preferred_location = if preferred_q != -999999 && preferred_r != -999999 {
            Some((preferred_q, preferred_r))
        } else {
            None
        };

        // Queue the spawn request (worker thread will process it)
        queue_spawn_request(
            entity_type_str,
            terrain_type,
            preferred_location,
            search_radius,
        );
        // Result will be emitted via spawn_completed signal
    }

    /// Check if a location is valid for spawning
    #[func]
    pub fn is_valid_spawn_location(&self, q: i32, r: i32, terrain_type_int: i32) -> bool {
        let terrain_type = match terrain_type_int {
            0 => CacheTerrainType::Water,
            1 => CacheTerrainType::Land,
            _ => return false,
        };

        is_valid_spawn_location((q, r), terrain_type)
    }
}
