/// Spatial Hash Grid for fast entity proximity queries
///
/// A spatial hash divides the world into a grid of cells. Each entity is placed
/// in one or more cells based on its position. This allows O(1) queries for
/// "which entities are near position X" instead of checking all entities.
///
/// Perfect for:
/// - Finding entities within radius
/// - Collision detection
/// - Rendering culling
/// - AI perception queries

use std::collections::HashMap;
use parking_lot::RwLock;
use std::sync::Arc;
use crate::config::map as map_config;

/// Entity ID type (can be ULID, instance ID, etc.)
pub type EntityId = u64;

/// 2D position (world coordinates)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Position {
    pub x: f32,
    pub y: f32,
}

impl Position {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }

    pub fn distance_to(&self, other: &Position) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        (dx * dx + dy * dy).sqrt()
    }

    pub fn distance_squared_to(&self, other: &Position) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        dx * dx + dy * dy
    }
}

/// Cell coordinates in the spatial hash grid
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct CellCoord {
    x: i32,
    y: i32,
}

/// Spatial hash configuration
pub struct SpatialHashConfig {
    /// Size of each cell (in world units)
    /// Smaller = more cells, finer queries, more memory
    /// Larger = fewer cells, coarser queries, less memory
    /// Recommended: Average entity size * 2
    pub cell_size: f32,

    /// Map bounds (0,0) to (max_x, max_y)
    pub max_x: f32,
    pub max_y: f32,
}

impl Default for SpatialHashConfig {
    fn default() -> Self {
        Self {
            cell_size: 64.0,  // 64 world units per cell (2 tiles @ 32px each)
            max_x: (map_config::WIDTH * 32) as f32,   // Map width in pixels
            max_y: (map_config::HEIGHT * 32) as f32,  // Map height in pixels
        }
    }
}

/// Spatial hash grid for fast spatial queries
pub struct SpatialHash {
    /// Grid of cells, each containing entity IDs
    cells: HashMap<CellCoord, Vec<EntityId>>,

    /// Entity positions (for distance calculations)
    entity_positions: HashMap<EntityId, Position>,

    /// Configuration
    config: SpatialHashConfig,
}

impl SpatialHash {
    /// Create new spatial hash with default config
    pub fn new() -> Self {
        Self::with_config(SpatialHashConfig::default())
    }

    /// Create new spatial hash with custom config
    pub fn with_config(config: SpatialHashConfig) -> Self {
        Self {
            cells: HashMap::new(),
            entity_positions: HashMap::new(),
            config,
        }
    }

    /// Convert world position to cell coordinate
    #[inline]
    fn world_to_cell(&self, pos: &Position) -> CellCoord {
        CellCoord {
            x: (pos.x / self.config.cell_size).floor() as i32,
            y: (pos.y / self.config.cell_size).floor() as i32,
        }
    }

    /// Insert or update entity position
    pub fn insert(&mut self, entity_id: EntityId, position: Position) {
        // Remove from old cell if entity exists
        if let Some(old_pos) = self.entity_positions.get(&entity_id) {
            let old_cell = self.world_to_cell(old_pos);
            if let Some(cell_entities) = self.cells.get_mut(&old_cell) {
                cell_entities.retain(|&id| id != entity_id);
            }
        }

        // Add to new cell
        let cell = self.world_to_cell(&position);
        self.cells.entry(cell).or_insert_with(Vec::new).push(entity_id);
        self.entity_positions.insert(entity_id, position);
    }

    /// Remove entity from spatial hash
    pub fn remove(&mut self, entity_id: EntityId) {
        if let Some(pos) = self.entity_positions.remove(&entity_id) {
            let cell = self.world_to_cell(&pos);
            if let Some(cell_entities) = self.cells.get_mut(&cell) {
                cell_entities.retain(|&id| id != entity_id);
            }
        }
    }

    /// Query entities within radius of a position
    pub fn query_radius(&self, center: &Position, radius: f32) -> Vec<EntityId> {
        let mut result = Vec::new();
        let radius_squared = radius * radius;

        // Calculate cell range to check
        let cell_center = self.world_to_cell(center);
        let cell_radius = (radius / self.config.cell_size).ceil() as i32;

        // Check all cells in range
        for dy in -cell_radius..=cell_radius {
            for dx in -cell_radius..=cell_radius {
                let cell = CellCoord {
                    x: cell_center.x + dx,
                    y: cell_center.y + dy,
                };

                if let Some(entities) = self.cells.get(&cell) {
                    for &entity_id in entities {
                        if let Some(entity_pos) = self.entity_positions.get(&entity_id) {
                            if center.distance_squared_to(entity_pos) <= radius_squared {
                                result.push(entity_id);
                            }
                        }
                    }
                }
            }
        }

        result
    }

    /// Query entities in a rectangular area
    pub fn query_rect(&self, min: &Position, max: &Position) -> Vec<EntityId> {
        let mut result = Vec::new();

        let min_cell = self.world_to_cell(min);
        let max_cell = self.world_to_cell(max);

        for y in min_cell.y..=max_cell.y {
            for x in min_cell.x..=max_cell.x {
                let cell = CellCoord { x, y };
                if let Some(entities) = self.cells.get(&cell) {
                    for &entity_id in entities {
                        if let Some(entity_pos) = self.entity_positions.get(&entity_id) {
                            if entity_pos.x >= min.x && entity_pos.x <= max.x &&
                               entity_pos.y >= min.y && entity_pos.y <= max.y {
                                result.push(entity_id);
                            }
                        }
                    }
                }
            }
        }

        result
    }

    /// Find nearest entity to a position (within optional max radius)
    pub fn find_nearest(&self, center: &Position, max_radius: Option<f32>) -> Option<(EntityId, f32)> {
        let search_radius = max_radius.unwrap_or(self.config.cell_size * 4.0);
        let entities = self.query_radius(center, search_radius);

        let mut nearest: Option<(EntityId, f32)> = None;

        for entity_id in entities {
            if let Some(entity_pos) = self.entity_positions.get(&entity_id) {
                let dist = center.distance_to(entity_pos);
                if let Some(max_r) = max_radius {
                    if dist > max_r {
                        continue;
                    }
                }

                if nearest.is_none() || dist < nearest.unwrap().1 {
                    nearest = Some((entity_id, dist));
                }
            }
        }

        nearest
    }

    /// Get entity position
    pub fn get_position(&self, entity_id: EntityId) -> Option<Position> {
        self.entity_positions.get(&entity_id).copied()
    }

    /// Clear all entities
    pub fn clear(&mut self) {
        self.cells.clear();
        self.entity_positions.clear();
    }

    /// Get statistics
    pub fn stats(&self) -> SpatialHashStats {
        let total_entities = self.entity_positions.len();
        let total_cells = self.cells.len();
        let avg_entities_per_cell = if total_cells > 0 {
            total_entities as f32 / total_cells as f32
        } else {
            0.0
        };

        SpatialHashStats {
            total_entities,
            total_cells,
            avg_entities_per_cell,
        }
    }
}

/// Statistics about the spatial hash
#[derive(Debug, Clone)]
pub struct SpatialHashStats {
    pub total_entities: usize,
    pub total_cells: usize,
    pub avg_entities_per_cell: f32,
}

/// Thread-safe spatial hash (global instance)
static SPATIAL_HASH: once_cell::sync::Lazy<Arc<RwLock<SpatialHash>>> =
    once_cell::sync::Lazy::new(|| Arc::new(RwLock::new(SpatialHash::new())));

/// Get global spatial hash instance
pub fn get_spatial_hash() -> Arc<RwLock<SpatialHash>> {
    Arc::clone(&SPATIAL_HASH)
}

/// Initialize spatial hash with custom config
pub fn init_spatial_hash(config: SpatialHashConfig) {
    let mut hash = SPATIAL_HASH.write();
    *hash = SpatialHash::with_config(config);
}

/// Insert entity into global spatial hash
pub fn insert_entity(entity_id: EntityId, position: Position) {
    let mut hash = SPATIAL_HASH.write();
    hash.insert(entity_id, position);
}

/// Remove entity from global spatial hash
pub fn remove_entity(entity_id: EntityId) {
    let mut hash = SPATIAL_HASH.write();
    hash.remove(entity_id);
}

/// Query entities within radius
pub fn query_radius(center: Position, radius: f32) -> Vec<EntityId> {
    let hash = SPATIAL_HASH.read();
    hash.query_radius(&center, radius)
}

/// Find nearest entity
pub fn find_nearest(center: Position, max_radius: Option<f32>) -> Option<(EntityId, f32)> {
    let hash = SPATIAL_HASH.read();
    hash.find_nearest(&center, max_radius)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spatial_hash_basic() {
        let mut hash = SpatialHash::new();

        // Insert entities
        hash.insert(1, Position::new(100.0, 100.0));
        hash.insert(2, Position::new(150.0, 150.0));
        hash.insert(3, Position::new(500.0, 500.0));

        // Query near first entity
        let results = hash.query_radius(&Position::new(100.0, 100.0), 100.0);
        assert!(results.contains(&1));
        assert!(results.contains(&2));
        assert!(!results.contains(&3));
    }

    #[test]
    fn test_entity_update() {
        let mut hash = SpatialHash::new();

        hash.insert(1, Position::new(100.0, 100.0));
        hash.insert(1, Position::new(200.0, 200.0)); // Move entity

        let results = hash.query_radius(&Position::new(100.0, 100.0), 50.0);
        assert!(!results.contains(&1)); // Should not find at old position
    }
}
