/// Shared terrain cache for efficient pathfinding
///
/// This module provides a thread-safe, Arc-based terrain map that can be shared
/// between ship and ground pathfinding systems. Similar to CardRegistry, it uses
/// efficient data structures for fast lookups during pathfinding.

use std::sync::Arc;
use parking_lot::RwLock;
use crate::config::map as map_config;

/// Terrain types for pathfinding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TerrainType {
    Water,      // Walkable for ships
    Land,       // Walkable for ground units
    Obstacle,   // Blocked tile
}

impl TerrainType {
    /// Check if terrain is walkable for ships
    pub fn is_walkable_for_ship(&self) -> bool {
        matches!(self, TerrainType::Water)
    }

    /// Check if terrain is walkable for ground NPCs
    pub fn is_walkable_for_npc(&self) -> bool {
        matches!(self, TerrainType::Land)
    }

    /// Convert from GDScript tile type string
    pub fn from_string(tile_type: &str) -> Self {
        match tile_type {
            "water" => TerrainType::Water,
            _ => TerrainType::Land, // Everything else is land
        }
    }
}

/// Hex coordinate (axial coordinates: q, r)
pub type HexCoord = (i32, i32);

/// Convert 2D coordinates to 1D array index for flat storage
/// Uses bitwise optimization: y * 1024 + x becomes (y << 10) | x
#[inline]
fn coords_to_index(x: i32, y: i32) -> usize {
    ((y << 10) | x) as usize
}

/// Convert 1D array index back to 2D coordinates
#[inline]
fn index_to_coords(index: usize) -> (i32, i32) {
    let index = index as i32;
    (index & 1023, index >> 10)
}

/// Thread-safe terrain cache using flat array storage for maximum performance
pub struct TerrainCache {
    /// Flat array of terrain types (1,048,576 bytes = 1MB)
    /// Uses row-major order: index = y * WIDTH + x
    terrain: Vec<TerrainType>,
}

impl TerrainCache {
    /// Create a new terrain cache (all water by default)
    pub fn new() -> Self {
        Self {
            terrain: vec![TerrainType::Water; map_config::TOTAL_TILES],
        }
    }

    /// Set terrain at coordinates (bounds-checked)
    #[inline]
    pub fn set(&mut self, x: i32, y: i32, terrain_type: TerrainType) {
        if map_config::is_in_bounds(x, y) {
            let index = coords_to_index(x, y);
            self.terrain[index] = terrain_type;
        }
    }

    /// Get terrain at coordinates (bounds-checked, returns Water if out of bounds)
    #[inline]
    pub fn get(&self, x: i32, y: i32) -> TerrainType {
        if map_config::is_in_bounds(x, y) {
            let index = coords_to_index(x, y);
            self.terrain[index]
        } else {
            TerrainType::Water
        }
    }

    /// Get terrain at coordinates (unchecked, unsafe but faster)
    /// SAFETY: Caller must ensure coordinates are in bounds
    #[inline]
    pub unsafe fn get_unchecked(&self, x: i32, y: i32) -> TerrainType {
        let index = coords_to_index(x, y);
        *self.terrain.get_unchecked(index)
    }

    /// Batch update terrain from flat array (for initialization)
    pub fn init_from_flat_array(&mut self, tiles: &[(i32, i32, TerrainType)]) {
        for &(x, y, terrain_type) in tiles {
            self.set(x, y, terrain_type);
        }
    }

    /// Clear all terrain (reset to water)
    pub fn clear(&mut self) {
        self.terrain.fill(TerrainType::Water);
    }

    /// Get terrain statistics (for debugging)
    pub fn get_stats(&self) -> TerrainStats {
        let mut water_count = 0;
        let mut land_count = 0;
        let mut obstacle_count = 0;

        for terrain in &self.terrain {
            match terrain {
                TerrainType::Water => water_count += 1,
                TerrainType::Land => land_count += 1,
                TerrainType::Obstacle => obstacle_count += 1,
            }
        }

        TerrainStats {
            water_count,
            land_count,
            obstacle_count,
            total_tiles: self.terrain.len(),
        }
    }
}

/// Statistics about terrain distribution
#[derive(Debug, Clone)]
pub struct TerrainStats {
    pub water_count: usize,
    pub land_count: usize,
    pub obstacle_count: usize,
    pub total_tiles: usize,
}

/// Global terrain cache (thread-safe with Arc + RwLock)
static TERRAIN_CACHE: once_cell::sync::Lazy<Arc<RwLock<TerrainCache>>> =
    once_cell::sync::Lazy::new(|| Arc::new(RwLock::new(TerrainCache::new())));

/// Get read-only access to the terrain cache
pub fn get_terrain_cache() -> Arc<RwLock<TerrainCache>> {
    Arc::clone(&TERRAIN_CACHE)
}

/// Initialize terrain cache from GDScript map data
pub fn init_terrain_cache(tiles: Vec<(i32, i32, String)>) {
    let mut cache = TERRAIN_CACHE.write();
    cache.clear();

    godot::prelude::godot_print!("TerrainCache: Initializing with {} tiles", tiles.len());

    let terrain_tiles: Vec<(i32, i32, TerrainType)> = tiles
        .into_iter()
        .map(|(x, y, tile_type)| (x, y, TerrainType::from_string(&tile_type)))
        .collect();

    cache.init_from_flat_array(&terrain_tiles);

    let stats = cache.get_stats();
    godot::prelude::godot_print!(
        "TerrainCache: Initialized - Water: {}, Land: {}, Obstacles: {}, Total: {}",
        stats.water_count,
        stats.land_count,
        stats.obstacle_count,
        stats.total_tiles
    );
}

/// Get terrain at coordinates (thread-safe)
pub fn get_terrain(x: i32, y: i32) -> TerrainType {
    let cache = TERRAIN_CACHE.read();
    cache.get(x, y)
}

/// Check if coordinate is walkable for ships
pub fn is_walkable_for_ship(x: i32, y: i32) -> bool {
    get_terrain(x, y).is_walkable_for_ship()
}

/// Check if coordinate is walkable for ground NPCs
pub fn is_walkable_for_npc(x: i32, y: i32) -> bool {
    get_terrain(x, y).is_walkable_for_npc()
}
