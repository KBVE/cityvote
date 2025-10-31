/// Flow Field Pathfinding for efficient group movement
///
/// Flow fields are a technique where instead of calculating paths for each unit,
/// you calculate a vector field that points each tile toward the goal.
/// All units can then follow the field simultaneously.
///
/// Perfect for:
/// - RTS-style group movement (100+ units to same destination)
/// - Tower defense enemy waves
/// - Crowd simulation
/// - Flocking behavior
///
/// Benefits over A*:
/// - Calculate once, use for many units: O(n) for field, O(1) per unit
/// - Natural group cohesion
/// - Automatic load balancing (units spread out naturally)
/// - No path replanning needed for dynamic groups
///
/// Time complexity:
/// - Build field: O(n) where n = number of tiles
/// - Query direction: O(1)

use std::collections::VecDeque;
use crate::config::map as map_config;
use crate::npc::terrain_cache;

/// Direction vector (normalized)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Direction {
    pub x: f32,
    pub y: f32,
}

impl Direction {
    pub const ZERO: Direction = Direction { x: 0.0, y: 0.0 };

    pub fn new(x: f32, y: f32) -> Self {
        let len = (x * x + y * y).sqrt();
        if len > 0.0001 {
            Self { x: x / len, y: y / len }
        } else {
            Self::ZERO
        }
    }

    /// Check if direction is zero (no valid path)
    pub fn is_zero(&self) -> bool {
        self.x.abs() < 0.0001 && self.y.abs() < 0.0001
    }
}

/// Cost value for flow field
const IMPASSABLE: u16 = u16::MAX;
const GOAL: u16 = 0;

/// Flow field for a specific goal
pub struct FlowField {
    /// Goal position (tile coordinates)
    goal: (i32, i32),

    /// Cost field: distance from each tile to goal
    /// Uses u16 to save memory (65535 max cost, sufficient for 1024x1024 map)
    cost_field: Vec<u16>,

    /// Flow field: direction from each tile toward goal
    /// Uses Option to indicate impassable tiles (None)
    flow_field: Vec<Option<Direction>>,

    /// Whether this field is for ships (water) or ground units (land)
    for_ships: bool,
}

impl FlowField {
    /// Create new flow field for a goal position
    pub fn new(goal: (i32, i32), for_ships: bool) -> Self {
        let total_tiles = map_config::TOTAL_TILES;

        let mut field = Self {
            goal,
            cost_field: vec![IMPASSABLE; total_tiles],
            flow_field: vec![None; total_tiles],
            for_ships,
        };

        field.calculate();
        field
    }

    /// Convert tile coordinates to flat array index
    #[inline]
    fn coords_to_index(x: i32, y: i32) -> usize {
        ((y << 10) | x) as usize  // Bitwise optimization: y * 1024 + x
    }

    /// Convert flat array index to coordinates
    #[inline]
    fn index_to_coords(index: usize) -> (i32, i32) {
        let index = index as i32;
        (index & 1023, index >> 10)  // x = index % 1024, y = index / 1024
    }

    /// Check if tile is walkable
    fn is_walkable(&self, x: i32, y: i32) -> bool {
        if !map_config::is_in_bounds(x, y) {
            return false;
        }

        if self.for_ships {
            terrain_cache::is_walkable_for_ship(x, y)
        } else {
            terrain_cache::is_walkable_for_npc(x, y)
        }
    }

    /// Get 8-directional neighbors (including diagonals)
    fn get_neighbors(x: i32, y: i32) -> [(i32, i32); 8] {
        [
            (x - 1, y),     // Left
            (x + 1, y),     // Right
            (x, y - 1),     // Up
            (x, y + 1),     // Down
            (x - 1, y - 1), // Top-left
            (x + 1, y - 1), // Top-right
            (x - 1, y + 1), // Bottom-left
            (x + 1, y + 1), // Bottom-right
        ]
    }

    /// Calculate cost for moving to neighbor
    fn neighbor_cost(dx: i32, dy: i32) -> u16 {
        if dx != 0 && dy != 0 {
            14 // Diagonal (approximately sqrt(2) * 10)
        } else {
            10 // Cardinal direction
        }
    }

    /// Calculate cost field using Dijkstra-like wave expansion
    fn calculate_cost_field(&mut self) {
        let goal_index = Self::coords_to_index(self.goal.0, self.goal.1);

        // Check if goal is valid
        if !self.is_walkable(self.goal.0, self.goal.1) {
            return; // Goal is impassable, field remains all IMPASSABLE
        }

        // Initialize goal
        self.cost_field[goal_index] = GOAL;

        // Wave expansion from goal
        let mut queue = VecDeque::new();
        queue.push_back(self.goal);

        while let Some((x, y)) = queue.pop_front() {
            let current_cost = self.cost_field[Self::coords_to_index(x, y)];

            // Check all neighbors
            for (nx, ny) in Self::get_neighbors(x, y) {
                if !self.is_walkable(nx, ny) {
                    continue;
                }

                let neighbor_index = Self::coords_to_index(nx, ny);
                let move_cost = Self::neighbor_cost(nx - x, ny - y);
                let new_cost = current_cost.saturating_add(move_cost);

                // Update if we found a better path
                if new_cost < self.cost_field[neighbor_index] {
                    self.cost_field[neighbor_index] = new_cost;
                    queue.push_back((nx, ny));
                }
            }
        }
    }

    /// Calculate flow field from cost field
    fn calculate_flow_field(&mut self) {
        for y in 0..map_config::HEIGHT {
            for x in 0..map_config::WIDTH {
                let index = Self::coords_to_index(x, y);

                // Skip impassable or goal tiles
                if self.cost_field[index] == IMPASSABLE || self.cost_field[index] == GOAL {
                    continue;
                }

                // Find neighbor with lowest cost
                let mut best_neighbor = None;
                let mut best_cost = self.cost_field[index];

                for (nx, ny) in Self::get_neighbors(x, y) {
                    if !map_config::is_in_bounds(nx, ny) {
                        continue;
                    }

                    let neighbor_index = Self::coords_to_index(nx, ny);
                    let neighbor_cost = self.cost_field[neighbor_index];

                    if neighbor_cost < best_cost {
                        best_cost = neighbor_cost;
                        best_neighbor = Some((nx, ny));
                    }
                }

                // Calculate direction to best neighbor
                if let Some((nx, ny)) = best_neighbor {
                    let dx = (nx - x) as f32;
                    let dy = (ny - y) as f32;
                    self.flow_field[index] = Some(Direction::new(dx, dy));
                }
            }
        }
    }

    /// Calculate both cost and flow fields
    fn calculate(&mut self) {
        self.calculate_cost_field();
        self.calculate_flow_field();
    }

    /// Get flow direction at tile coordinates
    pub fn get_direction(&self, x: i32, y: i32) -> Option<Direction> {
        if !map_config::is_in_bounds(x, y) {
            return None;
        }

        let index = Self::coords_to_index(x, y);
        self.flow_field[index]
    }

    /// Get cost at tile coordinates
    pub fn get_cost(&self, x: i32, y: i32) -> Option<u16> {
        if !map_config::is_in_bounds(x, y) {
            return None;
        }

        let index = Self::coords_to_index(x, y);
        let cost = self.cost_field[index];

        if cost == IMPASSABLE {
            None
        } else {
            Some(cost)
        }
    }

    /// Check if position is reachable from goal
    pub fn is_reachable(&self, x: i32, y: i32) -> bool {
        self.get_cost(x, y).is_some()
    }

    /// Get goal position
    pub fn goal(&self) -> (i32, i32) {
        self.goal
    }

    /// Get field statistics
    pub fn stats(&self) -> FlowFieldStats {
        let mut reachable_tiles = 0;
        let mut impassable_tiles = 0;

        for &cost in &self.cost_field {
            if cost == IMPASSABLE {
                impassable_tiles += 1;
            } else {
                reachable_tiles += 1;
            }
        }

        FlowFieldStats {
            goal: self.goal,
            reachable_tiles,
            impassable_tiles,
            total_tiles: self.cost_field.len(),
        }
    }
}

/// Statistics about flow field coverage
#[derive(Debug, Clone)]
pub struct FlowFieldStats {
    pub goal: (i32, i32),
    pub reachable_tiles: usize,
    pub impassable_tiles: usize,
    pub total_tiles: usize,
}

/// Flow field cache for reusing calculated fields
pub struct FlowFieldCache {
    /// Cache of flow fields by goal position
    /// Key: (goal_x, goal_y, for_ships)
    cache: std::collections::HashMap<(i32, i32, bool), FlowField>,

    /// Maximum cached fields (LRU eviction)
    max_cache_size: usize,

    /// Access order for LRU
    access_order: VecDeque<(i32, i32, bool)>,
}

impl FlowFieldCache {
    /// Create new flow field cache
    pub fn new(max_cache_size: usize) -> Self {
        Self {
            cache: std::collections::HashMap::new(),
            max_cache_size,
            access_order: VecDeque::new(),
        }
    }

    /// Get or create flow field for goal
    pub fn get_or_create(&mut self, goal: (i32, i32), for_ships: bool) -> &FlowField {
        let key = (goal.0, goal.1, for_ships);

        // Update access order
        if let Some(pos) = self.access_order.iter().position(|&k| k == key) {
            self.access_order.remove(pos);
        }
        self.access_order.push_back(key);

        // Evict oldest if cache is full
        if !self.cache.contains_key(&key) && self.cache.len() >= self.max_cache_size {
            if let Some(oldest) = self.access_order.pop_front() {
                self.cache.remove(&oldest);
            }
        }

        // Get or create field
        self.cache.entry(key).or_insert_with(|| FlowField::new(goal, for_ships))
    }

    /// Clear cache
    pub fn clear(&mut self) {
        self.cache.clear();
        self.access_order.clear();
    }

    /// Get cache statistics
    pub fn stats(&self) -> CacheStats {
        CacheStats {
            cached_fields: self.cache.len(),
            max_cache_size: self.max_cache_size,
        }
    }
}

/// Cache statistics
#[derive(Debug, Clone)]
pub struct CacheStats {
    pub cached_fields: usize,
    pub max_cache_size: usize,
}

/// Global flow field cache (thread-safe)
use parking_lot::RwLock;
use std::sync::Arc;

static FLOW_FIELD_CACHE: once_cell::sync::Lazy<Arc<RwLock<FlowFieldCache>>> =
    once_cell::sync::Lazy::new(|| Arc::new(RwLock::new(FlowFieldCache::new(16))));

/// Get or create flow field for goal
pub fn get_flow_field(goal: (i32, i32), for_ships: bool) -> Direction {
    let mut cache = FLOW_FIELD_CACHE.write();
    let field = cache.get_or_create(goal, for_ships);

    // Return direction from current position
    // Note: This is a simplified API. In practice, you'd pass current position.
    field.get_direction(goal.0, goal.1).unwrap_or(Direction::ZERO)
}

/// Clear flow field cache
pub fn clear_flow_field_cache() {
    let mut cache = FLOW_FIELD_CACHE.write();
    cache.clear();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_flow_field_direction() {
        // This test would need terrain cache to be initialized
        // Skipping for now as it requires integration with game systems
    }

    #[test]
    fn test_direction_normalization() {
        let dir = Direction::new(3.0, 4.0);
        let len = (dir.x * dir.x + dir.y * dir.y).sqrt();
        assert!((len - 1.0).abs() < 0.001); // Should be normalized
    }
}
