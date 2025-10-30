use godot::prelude::*;
use dashmap::DashMap;
use crossbeam_queue::SegQueue;
use std::sync::Arc;
use std::thread;
use std::collections::{BinaryHeap, HashMap, HashSet};
use std::cmp::Ordering;
use crate::ui::toast;

/// Map configuration constants (must match MapConfig in GDScript)
pub mod map_config {
    pub const MAP_WIDTH: i32 = 200;
    pub const MAP_HEIGHT: i32 = 150;
    pub const MAP_TOTAL_TILES: usize = (MAP_WIDTH * MAP_HEIGHT) as usize; // 30,000
}

/// Tile types for ground NPC pathfinding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TileType {
    Water,      // Not walkable for ground NPCs
    Land,       // Walkable for ground NPCs
    Obstacle,   // Blocked tile
}

impl TileType {
    pub fn is_walkable_for_npc(&self) -> bool {
        matches!(self, TileType::Land)
    }
}

/// Hex coordinate (axial coordinates)
pub type HexCoord = (i32, i32);

/// NPC state flags (bitwise) - matches NPC.State enum in GDScript
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NpcState {
    pub flags: u8,
}

impl NpcState {
    pub const IDLE: u8 = 0b0000_0001;        // NPC is idle
    pub const MOVING: u8 = 0b0000_0010;      // NPC is moving
    pub const PATHFINDING: u8 = 0b0000_0100; // Pathfinding in progress
    pub const BLOCKED: u8 = 0b0000_1000;     // NPC is blocked
    pub const INTERACTING: u8 = 0b0001_0000; // NPC is interacting
    pub const DEAD: u8 = 0b0010_0000;        // NPC is dead

    pub fn new() -> Self {
        Self { flags: Self::IDLE }
    }

    pub fn is_idle(&self) -> bool {
        self.flags & Self::IDLE != 0
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
}

/// Check if coordinate is within map bounds
fn is_in_bounds(coord: HexCoord) -> bool {
    let (q, r) = coord;
    q >= 0 && q < map_config::MAP_WIDTH && r >= 0 && r < map_config::MAP_HEIGHT
}

/// Get hex neighbors (6 directions in axial coordinates)
fn hex_neighbors(coord: HexCoord) -> Vec<HexCoord> {
    let (q, r) = coord;
    vec![
        (q + 1, r),     // East
        (q + 1, r - 1), // Northeast
        (q, r - 1),     // Northwest
        (q - 1, r),     // West
        (q - 1, r + 1), // Southwest
        (q, r + 1),     // Southeast
    ]
    .into_iter()
    .filter(|&coord| is_in_bounds(coord))
    .collect()
}

/// Manhattan distance heuristic for hex grid
fn heuristic(a: HexCoord, b: HexCoord) -> i32 {
    let (q1, r1) = a;
    let (q2, r2) = b;
    let s1 = -q1 - r1;
    let s2 = -q2 - r2;
    ((q1 - q2).abs() + (r1 - r2).abs() + (s1 - s2).abs()) / 2
}

/// A* node for priority queue
#[derive(Debug, Clone, Eq, PartialEq)]
struct PathNode {
    coord: HexCoord,
    f_score: i32,
}

impl Ord for PathNode {
    fn cmp(&self, other: &Self) -> Ordering {
        other.f_score.cmp(&self.f_score)
    }
}

impl PartialOrd for PathNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Pathfinding request
#[derive(Debug, Clone)]
struct PathRequest {
    npc_id: u64,
    start: HexCoord,
    goal: HexCoord,
}

/// Pathfinding result
#[derive(Debug, Clone)]
pub struct PathResult {
    pub npc_id: u64,
    pub path: Vec<HexCoord>,
    pub success: bool,
}

/// A* pathfinding algorithm
fn find_path(
    start: HexCoord,
    goal: HexCoord,
    tile_map: &HashMap<HexCoord, TileType>,
) -> Option<Vec<HexCoord>> {
    let mut open_set = BinaryHeap::new();
    let mut came_from: HashMap<HexCoord, HexCoord> = HashMap::new();
    let mut g_score: HashMap<HexCoord, i32> = HashMap::new();
    let mut closed_set: HashSet<HexCoord> = HashSet::new();

    g_score.insert(start, 0);
    open_set.push(PathNode {
        coord: start,
        f_score: heuristic(start, goal),
    });

    while let Some(PathNode { coord: current, .. }) = open_set.pop() {
        if current == goal {
            // Reconstruct path
            let mut path = vec![current];
            let mut current = current;
            while let Some(&prev) = came_from.get(&current) {
                path.push(prev);
                current = prev;
            }
            path.reverse();
            return Some(path);
        }

        if closed_set.contains(&current) {
            continue;
        }
        closed_set.insert(current);

        let current_g = *g_score.get(&current).unwrap_or(&i32::MAX);

        for neighbor in hex_neighbors(current) {
            // Check if tile is walkable for ground NPCs
            let tile_type = tile_map.get(&neighbor).copied().unwrap_or(TileType::Obstacle);
            if !tile_type.is_walkable_for_npc() {
                continue;
            }

            let tentative_g = current_g + 1;
            let neighbor_g = *g_score.get(&neighbor).unwrap_or(&i32::MAX);

            if tentative_g < neighbor_g {
                came_from.insert(neighbor, current);
                g_score.insert(neighbor, tentative_g);
                let f_score = tentative_g + heuristic(neighbor, goal);
                open_set.push(PathNode {
                    coord: neighbor,
                    f_score,
                });
            }
        }
    }

    None // No path found
}

/// Global pathfinding system for ground NPCs
#[derive(GodotClass)]
#[class(base=Node)]
pub struct NpcPathfindingSystem {
    #[base]
    base: Base<Node>,

    /// Tile map (shared across all NPCs)
    tile_map: Arc<DashMap<HexCoord, TileType>>,

    /// Request queue
    request_queue: Arc<SegQueue<PathRequest>>,

    /// Result map
    result_map: Arc<DashMap<u64, PathResult>>,

    /// Worker thread handle
    worker_handle: Option<thread::JoinHandle<()>>,
}

#[godot_api]
impl INode for NpcPathfindingSystem {
    fn init(base: Base<Node>) -> Self {
        let tile_map: Arc<DashMap<HexCoord, TileType>> = Arc::new(DashMap::new());
        let request_queue: Arc<SegQueue<PathRequest>> = Arc::new(SegQueue::new());
        let result_map: Arc<DashMap<u64, PathResult>> = Arc::new(DashMap::new());

        // Spawn worker thread
        let tile_map_clone = Arc::clone(&tile_map);
        let request_queue_clone = Arc::clone(&request_queue);
        let result_map_clone = Arc::clone(&result_map);

        let worker_handle = thread::spawn(move || {
            loop {
                if let Some(request) = request_queue_clone.pop() {
                    // Convert DashMap to HashMap for pathfinding
                    let tile_map_snapshot: HashMap<_, _> =
                        tile_map_clone.iter().map(|entry| (*entry.key(), *entry.value())).collect();

                    let path = find_path(request.start, request.goal, &tile_map_snapshot);

                    let result = PathResult {
                        npc_id: request.npc_id,
                        path: path.clone().unwrap_or_default(),
                        success: path.is_some(),
                    };

                    result_map_clone.insert(request.npc_id, result);
                } else {
                    thread::sleep(std::time::Duration::from_millis(10));
                }
            }
        });

        Self {
            base,
            tile_map,
            request_queue,
            result_map,
            worker_handle: Some(worker_handle),
        }
    }
}

#[godot_api]
impl NpcPathfindingSystem {
    /// Set tile type at coordinate
    #[func]
    pub fn set_tile(&mut self, q: i32, r: i32, tile_type: i32) {
        let tile = match tile_type {
            0 => TileType::Land,
            1 => TileType::Water,
            _ => TileType::Obstacle,
        };
        self.tile_map.insert((q, r), tile);
    }

    /// Request pathfinding for an NPC
    #[func]
    pub fn request_path(&mut self, npc_id: u64, start_q: i32, start_r: i32, goal_q: i32, goal_r: i32) {
        let request = PathRequest {
            npc_id,
            start: (start_q, start_r),
            goal: (goal_q, goal_r),
        };
        self.request_queue.push(request);
    }

    /// Check if path is ready for NPC
    #[func]
    pub fn is_path_ready(&self, npc_id: u64) -> bool {
        self.result_map.contains_key(&npc_id)
    }

    /// Get path result for NPC
    #[func]
    pub fn get_npc_path(&mut self, npc_id: u64) -> Array<Vector2i> {
        if let Some((_, result)) = self.result_map.remove(&npc_id) {
            let mut path_array = Array::new();
            for (q, r) in result.path {
                path_array.push(Vector2i::new(q, r));
            }
            path_array
        } else {
            Array::new()
        }
    }

    /// Clear all pathfinding data
    #[func]
    pub fn clear_all(&mut self) {
        self.tile_map.clear();
        self.result_map.clear();
        // Note: Can't clear SegQueue, but old requests will be processed and discarded
    }
}
