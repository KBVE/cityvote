use godot::prelude::*;
use dashmap::DashMap;
use crossbeam_queue::SegQueue;
use std::sync::Arc;
use std::thread;
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::cmp::Ordering;
use crate::ui::toast;

/// Map configuration constants (must match MapConfig in GDScript)
///
/// IMPORTANT: These values MUST be kept in sync with:
/// - cat/core/map_config.gd (GDScript autoload)
///
/// Current map size: 200x150 = 30,000 tiles
pub mod map_config {
    pub const MAP_WIDTH: i32 = 200;
    pub const MAP_HEIGHT: i32 = 150;
    pub const MAP_TOTAL_TILES: usize = (MAP_WIDTH * MAP_HEIGHT) as usize; // 30,000
}

/// Tile types for pathfinding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TileType {
    Water,      // Walkable for ships
    Land,       // Not walkable for ships
    Obstacle,   // Blocked tile
}

impl TileType {
    pub fn is_walkable_for_ship(&self) -> bool {
        matches!(self, TileType::Water)
    }
}

/// Hex coordinate (axial coordinates)
pub type HexCoord = (i32, i32);

/// Ship state flags (bitwise)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ShipState {
    pub flags: u8,
}

impl ShipState {
    pub const IDLE: u8 = 0b0000_0001;        // Ship is idle, can accept commands
    pub const MOVING: u8 = 0b0000_0010;      // Ship is moving along a path
    pub const PATHFINDING: u8 = 0b0000_0100; // Pathfinding request in progress
    pub const BLOCKED: u8 = 0b0000_1000;     // Ship is blocked (cannot move)

    pub fn new() -> Self {
        Self { flags: Self::IDLE }
    }

    pub fn is_idle(&self) -> bool {
        self.flags & Self::IDLE != 0
    }

    pub fn is_moving(&self) -> bool {
        self.flags & Self::MOVING != 0
    }

    pub fn is_pathfinding(&self) -> bool {
        self.flags & Self::PATHFINDING != 0
    }

    pub fn set_idle(&mut self) {
        self.flags = Self::IDLE;
    }

    pub fn set_moving(&mut self) {
        self.flags = (self.flags & !Self::IDLE) | Self::MOVING;
    }

    pub fn set_pathfinding(&mut self) {
        self.flags |= Self::PATHFINDING;
    }

    pub fn clear_pathfinding(&mut self) {
        self.flags &= !Self::PATHFINDING;
    }

    pub fn can_accept_path_request(&self) -> bool {
        // Can accept new requests if idle or just pathfinding (not moving)
        !self.is_moving() && !self.is_pathfinding()
    }
}

/// Ship data stored in Rust
#[derive(Debug, Clone)]
pub struct ShipData {
    pub position: HexCoord,
    pub state: ShipState,
}

/// Request for pathfinding
#[derive(Debug, Clone)]
pub struct PathRequest {
    pub ship_ulid: Vec<u8>,  // 16-byte ULID for ship identification
    pub start: HexCoord,
    pub goal: HexCoord,
    pub avoid_ships: bool,  // Whether to avoid other ships
}

/// Result of pathfinding
#[derive(Debug, Clone)]
pub struct PathResult {
    pub ship_ulid: Vec<u8>,  // 16-byte ULID for ship identification
    pub path: Vec<HexCoord>,
    pub success: bool,
    pub cost: f32,
}

/// Tile update for incremental map sync
#[derive(Debug, Clone)]
pub struct TileUpdate {
    pub coord: HexCoord,
    pub tile_type: TileType,
}

/// Global map cache (thread-safe)
static MAP_CACHE: once_cell::sync::Lazy<Arc<DashMap<HexCoord, TileType>>> =
    once_cell::sync::Lazy::new(|| Arc::new(DashMap::new()));

/// Ship data cache (position + state, thread-safe)
/// Ship tracking using ULID (16-byte Vec<u8>) as key
static SHIP_DATA: once_cell::sync::Lazy<Arc<DashMap<Vec<u8>, ShipData>>> =
    once_cell::sync::Lazy::new(|| Arc::new(DashMap::new()));

/// Request queue (GDScript → Rust)
static PATH_REQUESTS: once_cell::sync::Lazy<Arc<SegQueue<PathRequest>>> =
    once_cell::sync::Lazy::new(|| Arc::new(SegQueue::new()));

/// Result queue (Rust → GDScript)
static PATH_RESULTS: once_cell::sync::Lazy<Arc<SegQueue<PathResult>>> =
    once_cell::sync::Lazy::new(|| Arc::new(SegQueue::new()));

/// Worker thread pool running flag
static WORKERS_RUNNING: once_cell::sync::Lazy<Arc<std::sync::atomic::AtomicBool>> =
    once_cell::sync::Lazy::new(|| Arc::new(std::sync::atomic::AtomicBool::new(false)));

/// A* node for priority queue
#[derive(Debug, Clone)]
struct AStarNode {
    coord: HexCoord,
    g_cost: f32,  // Cost from start
    h_cost: f32,  // Heuristic to goal
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
        // Reverse ordering for min-heap
        other.f_cost().partial_cmp(&self.f_cost()).unwrap_or(Ordering::Equal)
    }
}

/// Check if coordinate is within map bounds
fn is_in_bounds(coord: HexCoord) -> bool {
    let (q, r) = coord;
    q >= 0 && q < map_config::MAP_WIDTH && r >= 0 && r < map_config::MAP_HEIGHT
}

/// Hex distance (Manhattan distance on hex grid)
fn hex_distance(a: HexCoord, b: HexCoord) -> f32 {
    let (q1, r1) = a;
    let (q2, r2) = b;
    ((q1 - q2).abs() + (r1 - r2).abs() + ((q1 + r1) - (q2 + r2)).abs()) as f32 / 2.0
}

/// Get hex neighbors (6 directions) - only returns valid in-bounds neighbors
fn hex_neighbors(coord: HexCoord) -> Vec<HexCoord> {
    let (q, r) = coord;
    vec![
        (q + 1, r),
        (q - 1, r),
        (q, r + 1),
        (q, r - 1),
        (q + 1, r - 1),
        (q - 1, r + 1),
    ]
    .into_iter()
    .filter(|&neighbor| is_in_bounds(neighbor))
    .collect()
}

/// A* pathfinding on hex grid
fn find_path_astar(request: &PathRequest) -> PathResult {
    let start = request.start;
    let goal = request.goal;

    // Validate coordinates are in bounds
    if !is_in_bounds(start) {
        toast::send_message(format!("Ship pathfinding: start coord {:?} out of bounds!", start));
        return PathResult {
            ship_ulid: request.ship_ulid.clone(),
            path: vec![],
            success: false,
            cost: 0.0,
        };
    }
    if !is_in_bounds(goal) {
        toast::send_message(format!("Ship pathfinding: goal coord {:?} out of bounds!", goal));
        return PathResult {
            ship_ulid: request.ship_ulid.clone(),
            path: vec![],
            success: false,
            cost: 0.0,
        };
    }

    // Check if start and goal are walkable
    if !is_tile_walkable(start) || !is_tile_walkable(goal) {
        return PathResult {
            ship_ulid: request.ship_ulid.clone(),
            path: vec![],
            success: false,
            cost: 0.0,
        };
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

        // Goal reached
        if current == goal {
            return reconstruct_path(&came_from, current, request.ship_ulid.clone());
        }

        // Already processed
        if closed_set.contains(&current) {
            continue;
        }

        closed_set.insert(current);

        // Explore neighbors
        for neighbor in hex_neighbors(current) {
            if closed_set.contains(&neighbor) {
                continue;
            }

            if !is_tile_walkable(neighbor) {
                continue;
            }

            // Check ship collision avoidance
            if request.avoid_ships && is_ship_at(neighbor) && neighbor != goal {
                continue;
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

    // No path found
    // Optional: Send toast notification for debugging
    // toast::send_message(format!("Ship: No path found from {:?} to {:?}", start, goal));

    PathResult {
        ship_ulid: request.ship_ulid.clone(),
        path: vec![],
        success: false,
        cost: 0.0,
    }
}

/// Reconstruct path from A* came_from map
fn reconstruct_path(came_from: &HashMap<HexCoord, HexCoord>, mut current: HexCoord, ship_ulid: Vec<u8>) -> PathResult {
    let mut path = vec![current];
    let mut cost = 0.0;

    while let Some(&prev) = came_from.get(&current) {
        path.push(prev);
        cost += 1.0;
        current = prev;
    }

    path.reverse();

    PathResult {
        ship_ulid,
        path,
        success: true,
        cost,
    }
}

/// Check if tile is walkable
fn is_tile_walkable(coord: HexCoord) -> bool {
    MAP_CACHE
        .get(&coord)
        .map(|tile| tile.is_walkable_for_ship())
        .unwrap_or(false)
}

/// Check if ship is at position
fn is_ship_at(coord: HexCoord) -> bool {
    SHIP_DATA.iter().any(|entry| entry.value().position == coord)
}

/// Worker thread function
fn pathfinding_worker() {
    loop {
        // Check if we should stop
        if !WORKERS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
            break;
        }

        // Process requests
        if let Some(request) = PATH_REQUESTS.pop() {
            let ship_ulid = request.ship_ulid.clone();
            let result = find_path_astar(&request);

            // Clear pathfinding flag when result is ready
            if let Some(mut data) = SHIP_DATA.get_mut(&ship_ulid) {
                data.state.clear_pathfinding();
            }

            PATH_RESULTS.push(result);
        } else {
            // No requests, sleep briefly to avoid busy-waiting
            thread::sleep(std::time::Duration::from_millis(1));
        }
    }
}

/// Public API: Initialize map cache with full map data
pub fn init_map_cache(tiles: Vec<(HexCoord, TileType)>) {
    godot_print!("Pathfinding: Initializing map cache with {} tiles", tiles.len());

    // Validate tile count matches expected map size
    let expected_tiles = map_config::MAP_TOTAL_TILES;
    if tiles.len() != expected_tiles {
        godot_error!(
            "Pathfinding: Map size mismatch! Expected {} tiles ({}x{}), got {}",
            expected_tiles,
            map_config::MAP_WIDTH,
            map_config::MAP_HEIGHT,
            tiles.len()
        );
    }

    MAP_CACHE.clear();
    for (coord, tile_type) in tiles {
        MAP_CACHE.insert(coord, tile_type);
    }
    godot_print!("Pathfinding: Map cache initialized!");
}

/// Public API: Update tiles incrementally (dirty tiles only)
pub fn update_tiles(updates: Vec<TileUpdate>) {
    for update in updates {
        MAP_CACHE.insert(update.coord, update.tile_type);
    }
}

/// Public API: Update ship position and state
pub fn update_ship_position(ship_ulid: Vec<u8>, coord: HexCoord) {
    SHIP_DATA.entry(ship_ulid.clone()).and_modify(|data| {
        data.position = coord;
    }).or_insert(ShipData {
        position: coord,
        state: ShipState::new(), // Defaults to IDLE
    });
}

/// Public API: Set ship state to MOVING
pub fn set_ship_moving(ship_ulid: Vec<u8>) {
    if let Some(mut data) = SHIP_DATA.get_mut(&ship_ulid) {
        data.state.set_moving();
    }
}

/// Public API: Set ship state to IDLE
pub fn set_ship_idle(ship_ulid: Vec<u8>) {
    if let Some(mut data) = SHIP_DATA.get_mut(&ship_ulid) {
        data.state.set_idle();
    }
}

/// Public API: Check if ship can accept path request
pub fn can_ship_accept_path_request(ship_ulid: Vec<u8>) -> bool {
    SHIP_DATA.get(&ship_ulid)
        .map(|data| data.state.can_accept_path_request())
        .unwrap_or(true) // If ship doesn't exist yet, allow request
}

/// Public API: Remove ship
pub fn remove_ship(ship_ulid: Vec<u8>) {
    SHIP_DATA.remove(&ship_ulid);
}

/// Public API: Request pathfinding (with state checking)
pub fn request_path(request: PathRequest) {
    // Mark ship as pathfinding
    if let Some(mut data) = SHIP_DATA.get_mut(&request.ship_ulid) {
        data.state.set_pathfinding();
    }

    PATH_REQUESTS.push(request);
}

/// Public API: Get result (non-blocking)
pub fn get_result() -> Option<PathResult> {
    PATH_RESULTS.pop()
}

/// Public API: Start worker threads
pub fn start_workers(thread_count: usize) {
    if WORKERS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
        godot_print!("Pathfinding: Workers already running!");
        return;
    }

    godot_print!("Pathfinding: Starting {} worker threads...", thread_count);
    WORKERS_RUNNING.store(true, std::sync::atomic::Ordering::Relaxed);

    for i in 0..thread_count {
        thread::Builder::new()
            .name(format!("pathfinding_worker_{}", i))
            .spawn(pathfinding_worker)
            .expect("Failed to spawn pathfinding worker");
    }

    godot_print!("Pathfinding: Workers started!");
}

/// Public API: Stop worker threads
pub fn stop_workers() {
    godot_print!("Pathfinding: Stopping workers...");
    WORKERS_RUNNING.store(false, std::sync::atomic::Ordering::Relaxed);
}

/// Public API: Get statistics
pub fn get_stats() -> (usize, usize, usize) {
    (
        MAP_CACHE.len(),
        SHIP_DATA.len(),
        PATH_REQUESTS.len(),
    )
}
