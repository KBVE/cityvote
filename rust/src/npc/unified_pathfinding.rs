use godot::prelude::*;
use crossbeam_queue::SegQueue;
use std::sync::Arc;
use std::thread;
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::cmp::Ordering;
use crate::config::map as map_config;
use once_cell::sync::Lazy;
use crate::npc::terrain_cache;
use crate::npc::terrain_cache::TerrainType;
use crate::npc::entity::EntityData;

/// Hex coordinate (axial coordinates)
pub type HexCoord = (i32, i32);

// ============================================================================
// UNIFIED PATHFINDING SYSTEM
// Single system for both water and land entities
// ============================================================================

/// Pathfinding request (unified for all terrain types)
#[derive(Debug, Clone)]
pub struct PathfindingRequest {
    pub entity_ulid: Vec<u8>,
    pub terrain_type: TerrainType,
    pub start: HexCoord,
    pub goal: HexCoord,
    pub avoid_entities: bool,
}

/// Pathfinding result (unified for all terrain types)
#[derive(Debug, Clone)]
pub struct PathfindingResult {
    pub entity_ulid: Vec<u8>,
    pub path: Vec<HexCoord>,
    pub success: bool,
    pub cost: f32,
}

// NOTE: UnifiedPathfindingBridge is now DEPRECATED for pathfinding
// Only kept alive for terrain cache functionality (hex.gd uses set_world_seed/load_chunk)
// All pathfinding now goes through UnifiedEventBridge Actor
// ENTITY_DATA import REMOVED to avoid lock contention

// Global unified request/result queues
static PATH_REQUESTS: Lazy<Arc<SegQueue<PathfindingRequest>>> = Lazy::new(|| {
    Arc::new(SegQueue::new())
});

static PATH_RESULTS: Lazy<Arc<SegQueue<PathfindingResult>>> = Lazy::new(|| {
    Arc::new(SegQueue::new())
});

// Chunk loading queue (to avoid blocking main thread during chunk loads)
#[derive(Debug, Clone)]
pub struct ChunkLoadRequest {
    pub chunk_coords: (i32, i32),
    pub tiles: Vec<(i32, i32, TerrainType)>,
}

static CHUNK_LOAD_QUEUE: Lazy<Arc<SegQueue<ChunkLoadRequest>>> = Lazy::new(|| {
    Arc::new(SegQueue::new())
});

// Random destination request/result queues (to avoid blocking main thread)
#[derive(Debug, Clone)]
pub struct RandomDestRequest {
    pub entity_ulid: Vec<u8>,
    pub terrain_type: TerrainType,
    pub start: HexCoord,
    pub min_distance: i32,
    pub max_distance: i32,
}

#[derive(Debug, Clone)]
pub struct RandomDestResult {
    pub entity_ulid: Vec<u8>,
    pub destination: Option<HexCoord>,
}

static RANDOM_DEST_REQUESTS: Lazy<Arc<SegQueue<RandomDestRequest>>> = Lazy::new(|| {
    Arc::new(SegQueue::new())
});

static RANDOM_DEST_RESULTS: Lazy<Arc<SegQueue<RandomDestResult>>> = Lazy::new(|| {
    Arc::new(SegQueue::new())
});

// Worker thread management
static WORKER_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
static WORKERS_RUNNING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

// ============================================================================
// HEX GRID GEOMETRY
// ============================================================================

/// Calculate hex distance using axial coordinates
fn hex_distance(a: HexCoord, b: HexCoord) -> f32 {
    let (q1, r1) = a;
    let (q2, r2) = b;

    let dq = (q1 - q2).abs();
    let dr = (r1 - r2).abs();
    let ds = (q1 + r1 - q2 - r2).abs();

    ((dq + dr + ds) / 2) as f32
}

/// Get all 6 neighbors of a hex coordinate
fn hex_neighbors(coord: HexCoord) -> Vec<HexCoord> {
    let (q, r) = coord;
    vec![
        (q + 1, r),     // East
        (q - 1, r),     // West
        (q, r + 1),     // Southeast
        (q, r - 1),     // Northwest
        (q + 1, r - 1), // Northeast
        (q - 1, r + 1), // Southwest
    ]
}

/// Get the two flanking tiles between two neighboring hex coordinates
/// Used to prevent "corner-cutting" in pathfinding
/// Returns None if the coordinates are not neighbors
fn get_flankers(from: HexCoord, to: HexCoord) -> Option<[HexCoord; 2]> {
    let (q, r) = from;
    let dq = to.0 - q;
    let dr = to.1 - r;

    match (dq, dr) {
        ( 1,  0) => Some([(q + 1, r - 1), (q,     r + 1)]), // E:  flankers are NE & SE
        (-1,  0) => Some([(q,     r - 1), (q - 1, r + 1)]), // W:  flankers are NW & SW
        ( 0,  1) => Some([(q + 1, r    ), (q,     r + 1)]), // SE: flankers are E  & SE (axis)
        ( 0, -1) => Some([(q,     r - 1), (q + 1, r    )]), // NW: flankers are NW & E  (axis)
        ( 1, -1) => Some([(q + 1, r    ), (q,     r - 1)]), // NE: flankers are E  & NW
        (-1,  1) => Some([(q - 1, r    ), (q,     r + 1)]), // SW: flankers are W  & SE
        _ => None, // Not neighbors
    }
}

/// Check if coordinate is within reasonable bounds
fn is_in_bounds(coord: HexCoord) -> bool {
    let (q, r) = coord;
    q.abs() < 100000 && r.abs() < 100000
}

// ============================================================================
// UNIFIED A* PATHFINDING
// ============================================================================

/// A* node for priority queue
#[derive(Debug, Clone)]
struct AStarNode {
    coord: HexCoord,
    g_cost: f32,
    h_cost: f32,
}

impl AStarNode {
    fn f_cost(&self) -> f32 {
        self.g_cost + self.h_cost
    }
}

impl PartialEq for AStarNode {
    fn eq(&self, other: &Self) -> bool {
        self.f_cost() == other.f_cost()
    }
}

impl Eq for AStarNode {}

impl PartialOrd for AStarNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for AStarNode {
    fn cmp(&self, other: &Self) -> Ordering {
        other.f_cost().partial_cmp(&self.f_cost()).unwrap_or(Ordering::Equal)
    }
}

/// Unified A* pathfinding with generic walkability checker
fn find_path_astar_generic<F>(
    start: HexCoord,
    goal: HexCoord,
    is_walkable: F,
) -> Option<Vec<HexCoord>>
where
    F: Fn(HexCoord) -> bool,
{
    if !is_in_bounds(start) || !is_in_bounds(goal) {
        return None;
    }

    if !is_walkable(start) || !is_walkable(goal) {
        return None;
    }

    let mut open_set = BinaryHeap::new();
    let mut came_from: HashMap<HexCoord, HexCoord> = HashMap::new();
    let mut g_score: HashMap<HexCoord, f32> = HashMap::new();
    let mut closed_set: HashSet<HexCoord> = HashSet::new();

    g_score.insert(start, 0.0);
    open_set.push(AStarNode {
        coord: start,
        g_cost: 0.0,
        h_cost: hex_distance(start, goal),
    });

    while let Some(current_node) = open_set.pop() {
        let current = current_node.coord;

        if current == goal {
            godot_print!("A* reached goal! came_from has {} entries", came_from.len());
            return Some(reconstruct_path(&came_from, current));
        }

        if closed_set.contains(&current) {
            continue;
        }

        closed_set.insert(current);

        for neighbor in hex_neighbors(current) {
            if closed_set.contains(&neighbor) || !is_walkable(neighbor) {
                continue;
            }

            // NO CORNER-CUTTING: Check flanking tiles to prevent diagonal squeezes
            // Require at least one flanker to be walkable
            if let Some(flankers) = get_flankers(current, neighbor) {
                let flanker1_walkable = is_walkable(flankers[0]);
                let flanker2_walkable = is_walkable(flankers[1]);

                // If BOTH flankers are blocked, disallow this diagonal move
                if !flanker1_walkable && !flanker2_walkable {
                    continue; // Skip this neighbor - would squeeze through corner
                }
            }

            let tentative_g_score = g_score.get(&current).unwrap_or(&f32::MAX) + 1.0;

            if tentative_g_score < *g_score.get(&neighbor).unwrap_or(&f32::MAX) {
                came_from.insert(neighbor, current);
                g_score.insert(neighbor, tentative_g_score);
                open_set.push(AStarNode {
                    coord: neighbor,
                    g_cost: tentative_g_score,
                    h_cost: hex_distance(neighbor, goal),
                });
            }
        }
    }

    None
}

/// Reconstruct path from A* came_from map
fn reconstruct_path(came_from: &HashMap<HexCoord, HexCoord>, mut current: HexCoord) -> Vec<HexCoord> {
    let mut path = vec![current];
    while let Some(&prev) = came_from.get(&current) {
        path.push(prev);
        current = prev;
    }
    path.reverse();
    godot_print!("reconstruct_path: Built path with {} waypoints: {:?}", path.len(), path);
    path
}

// ============================================================================
// UNIFIED PATHFINDING CORE
// ============================================================================

/// Check if an entity occupies a coordinate (for collision avoidance)
/// DEPRECATED: Always returns false since UnifiedEventBridge handles collision now
fn is_entity_at(_coord: HexCoord, _requesting_ulid: &[u8]) -> bool {
    false
}

/// Unified pathfinding function - works for both water and land entities
pub fn find_path_unified(request: &PathfindingRequest) -> PathfindingResult {
    // DEBUG: Verify start and goal terrain types
    let start_terrain = terrain_cache::get_terrain(request.start.0, request.start.1);
    let goal_terrain = terrain_cache::get_terrain(request.goal.0, request.goal.1);

    godot_print!("find_path_unified: start={:?} (terrain={:?}), goal={:?} (terrain={:?}), requested_terrain={:?}",
        request.start, start_terrain, request.goal, goal_terrain, request.terrain_type);

    // CRITICAL: Reject pathfinding if start terrain is wrong
    if start_terrain != request.terrain_type {
        godot_error!("find_path_unified: START {:?} has terrain {:?} but requested {:?}! Rejecting pathfinding.",
            request.start, start_terrain, request.terrain_type);
        return PathfindingResult {
            entity_ulid: request.entity_ulid.clone(),
            path: vec![],
            success: false,
            cost: 0.0,
        };
    }

    // CRITICAL: Reject pathfinding if goal terrain is wrong
    if goal_terrain != request.terrain_type {
        godot_error!("find_path_unified: GOAL {:?} has terrain {:?} but requested {:?}! Rejecting pathfinding.",
            request.goal, goal_terrain, request.terrain_type);
        return PathfindingResult {
            entity_ulid: request.entity_ulid.clone(),
            path: vec![],
            success: false,
            cost: 0.0,
        };
    }

    let is_walkable = |coord: HexCoord| -> bool {
        // Check terrain type matches
        let terrain = terrain_cache::get_terrain(coord.0, coord.1);
        let terrain_matches = terrain == request.terrain_type;

        if !terrain_matches {
            return false;
        }

        // Optional entity avoidance
        if request.avoid_entities {
            !is_entity_at(coord, &request.entity_ulid)
        } else {
            true
        }
    };

    // Run A* with unified walkability checker
    match find_path_astar_generic(request.start, request.goal, is_walkable) {
        Some(path) => {
            // DEBUG: Validate entire path has correct terrain type
            let mut invalid_tiles = Vec::new();
            for coord in &path {
                let terrain = terrain_cache::get_terrain(coord.0, coord.1);
                if terrain != request.terrain_type {
                    invalid_tiles.push((coord, terrain));
                }
            }

            // CRITICAL: Reject path if it contains invalid terrain tiles
            if !invalid_tiles.is_empty() {
                godot_error!("find_path_unified: Path contains {} INVALID terrain tiles for {:?}! Rejecting path.",
                    invalid_tiles.len(), request.terrain_type);
                for (coord, terrain) in invalid_tiles.iter().take(3) {
                    godot_error!("  -> {:?} has {:?} (expected {:?})", coord, terrain, request.terrain_type);
                }
                // Return failure - this path is invalid!
                return PathfindingResult {
                    entity_ulid: request.entity_ulid.clone(),
                    path: vec![],
                    success: false,
                    cost: 0.0,
                };
            }

            let cost = path.len() as f32;

            // FINAL VERIFICATION: Check start, goal, and last waypoint of path
            if !path.is_empty() {
                let first_waypoint = path[0];
                let last_waypoint = path[path.len() - 1];
                let first_terrain = terrain_cache::get_terrain(first_waypoint.0, first_waypoint.1);
                let last_terrain = terrain_cache::get_terrain(last_waypoint.0, last_waypoint.1);

                if first_terrain != request.terrain_type {
                    godot_error!("find_path_unified: CRITICAL - First waypoint {:?} has terrain {:?} (expected {:?})!",
                        first_waypoint, first_terrain, request.terrain_type);
                    return PathfindingResult {
                        entity_ulid: request.entity_ulid.clone(),
                        path: vec![],
                        success: false,
                        cost: 0.0,
                    };
                }

                if last_terrain != request.terrain_type {
                    godot_error!("find_path_unified: CRITICAL - Last waypoint {:?} has terrain {:?} (expected {:?})!",
                        last_waypoint, last_terrain, request.terrain_type);
                    return PathfindingResult {
                        entity_ulid: request.entity_ulid.clone(),
                        path: vec![],
                        success: false,
                        cost: 0.0,
                    };
                }
            }

            godot_print!("find_path_unified: SUCCESS - found path with {} waypoints", path.len());
            PathfindingResult {
                entity_ulid: request.entity_ulid.clone(),
                path,
                success: true,
                cost,
            }
        }
        None => {
            godot_error!("find_path_unified: FAILED - no path found from {:?} to {:?} (terrain={:?})",
                request.start, request.goal, request.terrain_type);
            PathfindingResult {
                entity_ulid: request.entity_ulid.clone(),
                path: vec![],
                success: false,
                cost: 0.0,
            }
        }
    }
}

// ============================================================================
// UNIFIED RANDOM DESTINATION FINDER
// ============================================================================

/// Find a random reachable destination within range (unified for all terrain types)
fn find_random_destination(
    start: HexCoord,
    terrain_type: TerrainType,
    entity_ulid: &[u8],
    min_distance: i32,
    max_distance: i32,
) -> Option<HexCoord> {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let mut valid_destinations = Vec::new();
    let mut checked_count = 0;
    let mut terrain_mismatch_count = 0;
    let mut occupied_count = 0;
    let mut distance_reject_count = 0;

    // Search in expanding rings
    for distance in min_distance..=max_distance {
        for dx in -distance..=distance {
            for dy in -distance..=distance {
                checked_count += 1;
                let candidate = (start.0 + dx, start.1 + dy);

                // Calculate hex distance using proper axial coordinate formula
                let hex_dist = hex_distance(start, candidate) as i32;

                // Check if within overall distance range
                if hex_dist < min_distance || hex_dist > max_distance {
                    distance_reject_count += 1;
                    continue;
                }

                // Check terrain type matches
                let terrain = terrain_cache::get_terrain(candidate.0, candidate.1);
                let terrain_matches = terrain == terrain_type;

                if !terrain_matches {
                    terrain_mismatch_count += 1;
                    continue;
                }

                // DEPRECATED: Collision check removed (UnifiedEventBridge handles this now)
                // Always consider tiles as not occupied
                valid_destinations.push(candidate);
            }
        }
    }

    godot_print!(
        "find_random_destination: start={:?}, terrain={:?}, range={}-{}, checked={}, distance_rejected={}, terrain_mismatch={}, occupied={}, valid={}",
        start, terrain_type, min_distance, max_distance, checked_count, distance_reject_count, terrain_mismatch_count, occupied_count, valid_destinations.len()
    );

    if valid_destinations.is_empty() {
        None
    } else {
        let idx = rng.gen_range(0..valid_destinations.len());
        let selected = valid_destinations[idx];

        // CRITICAL: Verify selected destination has correct terrain
        let dest_terrain = terrain_cache::get_terrain(selected.0, selected.1);
        if dest_terrain != terrain_type {
            godot_error!("find_random_destination: CRITICAL BUG - Selected destination {:?} has terrain {:?} but requested {:?}!",
                selected, dest_terrain, terrain_type);
            // This should never happen! Log all valid destinations for debugging
            godot_error!("  -> All valid destinations: {:?}", valid_destinations);
            return None; // Don't return invalid destination
        }

        godot_print!("find_random_destination: Selected {:?} (terrain={:?})", selected, dest_terrain);
        Some(selected)
    }
}

// ============================================================================
// UNIFIED WORKER POOL
// ============================================================================

/// Worker thread function
fn worker_thread() {
    loop {
        // Check if workers should stop
        if !WORKERS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
            break;
        }

        let mut did_work = false;

        // Process pathfinding requests (highest priority)
        if let Some(request) = PATH_REQUESTS.pop() {
            let result = find_path_unified(&request);
            PATH_RESULTS.push(result);
            did_work = true;
        }

        // Process random destination requests (medium priority)
        if let Some(request) = RANDOM_DEST_REQUESTS.pop() {
            let destination = find_random_destination(
                request.start,
                request.terrain_type,
                &request.entity_ulid,
                request.min_distance,
                request.max_distance,
            );
            RANDOM_DEST_RESULTS.push(RandomDestResult {
                entity_ulid: request.entity_ulid,
                destination,
            });
            did_work = true;
        }

        // Process chunk loads (lowest priority, but prevents blocking main thread)
        if let Some(chunk_request) = CHUNK_LOAD_QUEUE.pop() {
            let cache = terrain_cache::get_terrain_cache();
            for (x, y, terrain_type) in chunk_request.tiles {
                cache.set(x, y, terrain_type);
            }
            did_work = true;
        }

        if !did_work {
            // No work to do, sleep briefly
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    }
}

/// Start worker threads
pub fn start_workers(thread_count: usize) {
    let count = thread_count.max(1);

    // Only start if not already running
    if WORKERS_RUNNING.swap(true, std::sync::atomic::Ordering::Relaxed) {
        return; // Already running
    }

    WORKER_COUNT.store(count, std::sync::atomic::Ordering::Relaxed);

    for i in 0..count {
        thread::Builder::new()
            .name(format!("pathfinding-worker-{}", i))
            .spawn(worker_thread)
            .expect("Failed to spawn pathfinding worker thread");
    }

    godot_print!("UnifiedPathfinding: Started {} worker threads", count);
}

/// Stop worker threads
pub fn stop_workers() {
    WORKERS_RUNNING.store(false, std::sync::atomic::Ordering::Relaxed);
    godot_print!("UnifiedPathfinding: Stopping worker threads");
}

// ============================================================================
// PUBLIC API
// ============================================================================

/// Convert terrain_cache::TerrainType to entity::TerrainType
fn to_entity_terrain_type(cache_type: TerrainType) -> crate::npc::entity::TerrainType {
    match cache_type {
        TerrainType::Water => crate::npc::entity::TerrainType::Water,
        TerrainType::Land | TerrainType::Obstacle => crate::npc::entity::TerrainType::Land,
    }
}

/// Register entity position (now uses worker thread for writes)
pub fn update_entity_position(ulid: Vec<u8>, position: HexCoord, terrain_type: TerrainType) {
    // Check if entity exists (lock-free read)
    if super::entity_worker::entity_exists(&ulid) {
        // Queue position update (lock-free write to SegQueue)
        super::entity_worker::queue_update_position(ulid, position);
    } else {
        // Create new entity and queue insertion
        let entity_terrain_type = to_entity_terrain_type(terrain_type);
        let entity = EntityData::new(ulid.clone(), position, entity_terrain_type, "unknown".to_string());
        super::entity_worker::queue_insert_entity(ulid, entity);
    }
}

/// Remove entity from tracking (now uses worker thread for writes)
pub fn remove_entity(ulid: &[u8]) {
    super::entity_worker::queue_remove_entity(ulid.to_vec());
}

/// Request pathfinding
pub fn request_path(request: PathfindingRequest) {
    PATH_REQUESTS.push(request);
}

/// Get pathfinding result (non-blocking)
pub fn get_result() -> Option<PathfindingResult> {
    PATH_RESULTS.pop()
}

/// Get statistics
/// DEPRECATED: entity_count always returns 0 (UnifiedEventBridge tracks entities now)
pub fn get_stats() -> (usize, usize, usize) {
    let entity_count = 0; // ENTITY_DATA removed
    let pending_requests = PATH_REQUESTS.len();
    let pending_results = PATH_RESULTS.len();
    (entity_count, pending_requests, pending_results)
}

// ============================================================================
// GODOT BRIDGE - UNIFIED
// ============================================================================

/// Unified pathfinding bridge for Godot
#[derive(GodotClass)]
#[class(base=Node)]
pub struct UnifiedPathfindingBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for UnifiedPathfindingBridge {
    fn init(base: Base<Node>) -> Self {
        godot_print!("UnifiedPathfindingBridge initialized!");
        Self { base }
    }

    fn ready(&mut self) {
        godot_print!("UnifiedPathfindingBridge ready!");
        // DON'T set_process - GDScript will poll for results instead
    }
}

#[godot_api]
impl UnifiedPathfindingBridge {
    /// Poll for a single pathfinding result (non-blocking)
    /// Returns null if no results available, otherwise returns Dictionary with:
    /// - entity_ulid: PackedByteArray
    /// - path: Array[Dictionary] with {q, r} coords
    /// - success: bool
    /// - cost: float
    #[func]
    fn poll_result(&mut self) -> Variant {
        if let Some(result) = get_result() {
            // Convert path to GDScript array
            let mut path_array = Array::new();
            for (q, r) in result.path {
                let mut coord = Dictionary::new();
                coord.set("q", q);
                coord.set("r", r);
                path_array.push(&coord);
            }

            // Convert ULID to PackedByteArray
            let entity_ulid = PackedByteArray::from(&result.entity_ulid[..]);

            // Create result dictionary
            let mut result_dict = Dictionary::new();
            result_dict.set("entity_ulid", entity_ulid);
            result_dict.set("path", path_array);
            result_dict.set("success", result.success);
            result_dict.set("cost", result.cost);

            result_dict.to_variant()
        } else {
            Variant::nil()
        }
    }

    /// Update entity position
    #[func]
    fn update_entity_position(&mut self, entity_ulid: PackedByteArray, q: i32, r: i32, terrain_type_int: i32) {
        let ulid_bytes: Vec<u8> = entity_ulid.to_vec();
        let terrain_type = match terrain_type_int {
            0 => TerrainType::Water,
            _ => TerrainType::Land, // Default to land for unknown types
        };
        update_entity_position(ulid_bytes, (q, r), terrain_type);
    }

    /// Remove entity from tracking
    #[func]
    fn remove_entity(&mut self, entity_ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = entity_ulid.to_vec();
        remove_entity(&ulid_bytes);
    }

    /// Request pathfinding
    #[func]
    fn request_path(
        &mut self,
        entity_ulid: PackedByteArray,
        terrain_type_int: i32,
        start_q: i32,
        start_r: i32,
        goal_q: i32,
        goal_r: i32,
        avoid_entities: bool,
    ) {
        let ulid_bytes: Vec<u8> = entity_ulid.to_vec();
        let terrain_type = match terrain_type_int {
            0 => TerrainType::Water,
            _ => TerrainType::Land, // Default to land for unknown types
        };

        let request = PathfindingRequest {
            entity_ulid: ulid_bytes,
            terrain_type,
            start: (start_q, start_r),
            goal: (goal_q, goal_r),
            avoid_entities,
        };

        request_path(request);
    }

    /// Start worker threads
    #[func]
    fn start_workers(&mut self, thread_count: i32) {
        start_workers(thread_count.max(1) as usize);
    }

    /// Stop worker threads
    #[func]
    fn stop_workers(&mut self) {
        stop_workers();
    }

    /// Request random destination (ASYNC - queues request for worker thread)
    #[func]
    fn request_random_destination(
        &mut self,
        entity_ulid: PackedByteArray,
        terrain_type_int: i32,
        start_q: i32,
        start_r: i32,
        min_distance: i32,
        max_distance: i32,
    ) {
        let ulid_bytes: Vec<u8> = entity_ulid.to_vec();
        let terrain_type = match terrain_type_int {
            0 => TerrainType::Water,
            _ => TerrainType::Land,
        };

        let request = RandomDestRequest {
            entity_ulid: ulid_bytes,
            terrain_type,
            start: (start_q, start_r),
            min_distance,
            max_distance,
        };

        RANDOM_DEST_REQUESTS.push(request);
    }

    /// Poll for random destination result (non-blocking)
    /// Returns Dictionary with {entity_ulid, destination: {q, r}, found: bool}
    /// or Variant::nil() if no results available
    #[func]
    fn poll_random_dest_result(&mut self) -> Variant {
        if let Some(result) = RANDOM_DEST_RESULTS.pop() {
            let mut dict = Dictionary::new();
            dict.set("entity_ulid", PackedByteArray::from(&result.entity_ulid[..]));

            if let Some((q, r)) = result.destination {
                let mut dest_dict = Dictionary::new();
                dest_dict.set("q", q);
                dest_dict.set("r", r);
                dict.set("destination", dest_dict);
                dict.set("found", true);
            } else {
                dict.set("found", false);
            }

            dict.to_variant()
        } else {
            Variant::nil()
        }
    }

    /// Set world seed for procedural terrain generation
    /// IMPORTANT: Call this before any pathfinding to ensure terrain cache can generate chunks on-demand
    #[func]
    fn set_world_seed(&mut self, seed: i32) {
        terrain_cache::set_terrain_seed(seed);
        godot_print!("UnifiedPathfindingBridge: Set world seed to {}", seed);
    }

    /// Get statistics
    #[func]
    fn get_stats(&self) -> Dictionary {
        let (entity_count, pending_requests, pending_results) = get_stats();
        let mut dict = Dictionary::new();
        dict.set("entities", entity_count as i32);
        dict.set("pending_requests", pending_requests as i32);
        dict.set("pending_results", pending_results as i32);
        dict
    }

    /// Initialize terrain cache with map data
    #[func]
    fn init_map(&mut self, tiles: Array<Dictionary>) {
        let mut tile_vec = Vec::new();
        for i in 0..tiles.len() {
            if let Some(dict) = tiles.get(i) {
                let q: i32 = dict.get("q").and_then(|v| v.try_to::<i32>().ok()).unwrap_or(0);
                let r: i32 = dict.get("r").and_then(|v| v.try_to::<i32>().ok()).unwrap_or(0);
                let tile_type_str: GString = dict.get("type")
                    .and_then(|v| v.try_to::<GString>().ok())
                    .unwrap_or_else(|| "land".into());

                tile_vec.push((q, r, tile_type_str.to_string()));
            }
        }

        terrain_cache::init_terrain_cache(tile_vec);
        godot_print!("UnifiedPathfindingBridge: Terrain cache initialized with {} tiles", tiles.len());
    }

    /// Load a chunk of tiles into the terrain cache (incremental)
    /// NOW ASYNC: Queues chunk for background processing to avoid blocking main thread
    #[func]
    fn load_chunk(&mut self, chunk_coords: Vector2i, tile_data: Array<Dictionary>) {
        // Calculate chunk offset for converting local to global coordinates
        let chunk_offset_x = chunk_coords.x * map_config::CHUNK_SIZE as i32;
        let chunk_offset_y = chunk_coords.y * map_config::CHUNK_SIZE as i32;

        // Process tile data (convert Dictionary array to Rust types)
        // This happens on main thread but is much faster than updating the cache
        let mut tiles_to_set: Vec<(i32, i32, TerrainType)> = Vec::with_capacity(tile_data.len() as usize);

        for i in 0..tile_data.len() {
            if let Some(dict) = tile_data.get(i) {
                // x, y are LOCAL coordinates within the chunk (0-31)
                let local_x: i32 = dict.get("x").and_then(|v| v.try_to::<i32>().ok()).unwrap_or(0);
                let local_y: i32 = dict.get("y").and_then(|v| v.try_to::<i32>().ok()).unwrap_or(0);

                // Convert to GLOBAL tile coordinates
                let global_x = chunk_offset_x + local_x;
                let global_y = chunk_offset_y + local_y;

                // FIX: WorldGenerator sends "tile_index" not "tile_type" (see chunk_generator.rs:364)
                let tile_index: i32 = dict.get("tile_index").and_then(|v| v.try_to::<i32>().ok()).unwrap_or(1);

                // Convert tile_index to TerrainType
                // Atlas indices: 0-3 = grassland variants, 4 = water, 5-6 = grassland variants
                // See biomes.rs:33-43 for tile_index mapping
                let terrain_type = if tile_index == 4 {
                    TerrainType::Water
                } else {
                    TerrainType::Land
                };

                tiles_to_set.push((global_x, global_y, terrain_type));
            }
        }

        // Queue chunk for async processing by worker threads
        let request = ChunkLoadRequest {
            chunk_coords: (chunk_coords.x, chunk_coords.y),
            tiles: tiles_to_set,
        };
        CHUNK_LOAD_QUEUE.push(request);

        #[cfg(feature = "debug_logs")]
        godot_print!("UnifiedPathfindingBridge: Queued chunk {:?} for async loading ({} tiles)",
            chunk_coords, tile_data.len());
    }

    /// Check if tile is walkable for given terrain type
    #[func]
    fn is_tile_walkable(&self, terrain_type_int: i32, q: i32, r: i32) -> bool {
        let terrain = terrain_cache::get_terrain(q, r);
        match terrain_type_int {
            0 => terrain == TerrainType::Water,
            1 => terrain == TerrainType::Land,
            _ => false,
        }
    }

    /// Simple synchronous pathfinding - no entity tracking, no worker threads
    /// GDScript calls this directly when an entity needs a path
    /// Returns Array of Vector2i with waypoints, or empty array if no path found
    #[func]
    fn find_path_simple(
        &self,
        start_q: i32,
        start_r: i32,
        goal_q: i32,
        goal_r: i32,
        terrain_type_int: i32,
    ) -> Array<Vector2i> {
        let terrain_type = match terrain_type_int {
            0 => TerrainType::Water,
            1 => TerrainType::Land,
            _ => {
                godot_print!("find_path_simple: Invalid terrain_type {}", terrain_type_int);
                return Array::new();
            }
        };

        let start = (start_q, start_r);
        let goal = (goal_q, goal_r);

        // Verify start and goal are walkable
        let start_terrain = terrain_cache::get_terrain(start.0, start.1);
        let goal_terrain = terrain_cache::get_terrain(goal.0, goal.1);

        if start_terrain != terrain_type {
            godot_print!(
                "find_path_simple: Start {:?} has terrain {:?} but requested {:?}",
                start, start_terrain, terrain_type
            );
            return Array::new();
        }

        if goal_terrain != terrain_type {
            godot_print!(
                "find_path_simple: Goal {:?} has terrain {:?} but requested {:?}",
                goal, goal_terrain, terrain_type
            );
            return Array::new();
        }

        // Run A* pathfinding (synchronously, no worker thread)
        let path = find_path_astar_generic(
            start,
            goal,
            |coord| {
                let terrain = terrain_cache::get_terrain(coord.0, coord.1);
                terrain == terrain_type
            },
        );

        // Convert path to Godot Array<Vector2i>
        let mut result = Array::new();
        if let Some(path_vec) = path {
            for (q, r) in path_vec {
                result.push(Vector2i::new(q, r));
            }
            godot_print!(
                "find_path_simple: Found path from {:?} to {:?} with {} waypoints",
                start, goal, result.len()
            );
        } else {
            godot_print!("find_path_simple: No path found from {:?} to {:?}", start, goal);
        }

        result
    }
}
