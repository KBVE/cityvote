/// Shared terrain cache for efficient pathfinding
///
/// This module provides a thread-safe, Arc-based terrain map that can be shared
/// between ship and ground pathfinding systems. Similar to CardRegistry, it uses
/// efficient data structures for fast lookups during pathfinding.

use std::sync::Arc;
use std::collections::HashMap;
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

/// Chunk coordinate (chunk_x, chunk_y)
pub type ChunkCoord = (i32, i32);

/// Single chunk of terrain data (32x32 tiles)
#[derive(Debug, Clone)]
pub struct TerrainChunk {
    /// Flat array of terrain types for this chunk (1024 bytes)
    /// Row-major order: index = y * CHUNK_SIZE + x
    data: Vec<TerrainType>,
}

impl TerrainChunk {
    /// Create a new chunk filled with water
    pub fn new() -> Self {
        Self {
            data: vec![TerrainType::Water; map_config::CHUNK_SIZE * map_config::CHUNK_SIZE],
        }
    }

    /// Create a chunk with specific terrain data
    pub fn from_data(data: Vec<TerrainType>) -> Self {
        assert_eq!(data.len(), map_config::CHUNK_SIZE * map_config::CHUNK_SIZE);
        Self { data }
    }

    /// Get terrain at local chunk coordinates (0-31)
    #[inline]
    pub fn get(&self, local_x: usize, local_y: usize) -> TerrainType {
        let index = local_y * map_config::CHUNK_SIZE + local_x;
        self.data[index]
    }

    /// Set terrain at local chunk coordinates (0-31)
    #[inline]
    pub fn set(&mut self, local_x: usize, local_y: usize, terrain_type: TerrainType) {
        let index = local_y * map_config::CHUNK_SIZE + local_x;
        self.data[index] = terrain_type;
    }
}

/// Thread-safe terrain cache using sparse chunk-based storage for infinite worlds
pub struct TerrainCache {
    /// Sparse map of chunks (only stores loaded chunks)
    /// Key: (chunk_x, chunk_y), Value: TerrainChunk
    chunks: HashMap<ChunkCoord, TerrainChunk>,
}

impl TerrainCache {
    /// Create a new terrain cache (empty, chunks loaded on demand)
    pub fn new() -> Self {
        Self {
            chunks: HashMap::new(),
        }
    }

    /// Convert tile coordinates to chunk coordinates
    #[inline]
    fn tile_to_chunk(tile_x: i32, tile_y: i32) -> (ChunkCoord, usize, usize) {
        let chunk_x = tile_x.div_euclid(map_config::CHUNK_SIZE as i32);
        let chunk_y = tile_y.div_euclid(map_config::CHUNK_SIZE as i32);
        let local_x = tile_x.rem_euclid(map_config::CHUNK_SIZE as i32) as usize;
        let local_y = tile_y.rem_euclid(map_config::CHUNK_SIZE as i32) as usize;
        ((chunk_x, chunk_y), local_x, local_y)
    }

    /// Load a chunk into the cache
    pub fn load_chunk(&mut self, chunk_x: i32, chunk_y: i32, chunk_data: TerrainChunk) {
        self.chunks.insert((chunk_x, chunk_y), chunk_data);
    }

    /// Unload a chunk from the cache
    pub fn unload_chunk(&mut self, chunk_x: i32, chunk_y: i32) -> Option<TerrainChunk> {
        self.chunks.remove(&(chunk_x, chunk_y))
    }

    /// Check if a chunk is loaded
    pub fn is_chunk_loaded(&self, chunk_x: i32, chunk_y: i32) -> bool {
        self.chunks.contains_key(&(chunk_x, chunk_y))
    }

    /// Get number of loaded chunks
    pub fn loaded_chunk_count(&self) -> usize {
        self.chunks.len()
    }

    /// Set terrain at tile coordinates
    #[inline]
    pub fn set(&mut self, tile_x: i32, tile_y: i32, terrain_type: TerrainType) {
        let ((chunk_x, chunk_y), local_x, local_y) = Self::tile_to_chunk(tile_x, tile_y);

        // Get or create chunk
        let chunk = self.chunks.entry((chunk_x, chunk_y))
            .or_insert_with(TerrainChunk::new);

        chunk.set(local_x, local_y, terrain_type);
    }

    /// Get terrain at tile coordinates (returns Water if chunk not loaded)
    #[inline]
    pub fn get(&self, tile_x: i32, tile_y: i32) -> TerrainType {
        let ((chunk_x, chunk_y), local_x, local_y) = Self::tile_to_chunk(tile_x, tile_y);

        self.chunks
            .get(&(chunk_x, chunk_y))
            .map(|chunk| chunk.get(local_x, local_y))
            .unwrap_or(TerrainType::Water)
    }

    /// Batch update terrain from flat array (for initialization)
    pub fn init_from_flat_array(&mut self, tiles: &[(i32, i32, TerrainType)]) {
        for &(x, y, terrain_type) in tiles {
            self.set(x, y, terrain_type);
        }
    }

    /// Clear all terrain (unload all chunks)
    pub fn clear(&mut self) {
        self.chunks.clear();
    }

    /// Get terrain statistics (for debugging)
    pub fn get_stats(&self) -> TerrainStats {
        let mut water_count = 0;
        let mut land_count = 0;
        let mut obstacle_count = 0;

        for chunk in self.chunks.values() {
            for terrain in &chunk.data {
                match terrain {
                    TerrainType::Water => water_count += 1,
                    TerrainType::Land => land_count += 1,
                    TerrainType::Obstacle => obstacle_count += 1,
                }
            }
        }

        let total_tiles = self.chunks.len() * map_config::CHUNK_SIZE * map_config::CHUNK_SIZE;

        TerrainStats {
            water_count,
            land_count,
            obstacle_count,
            total_tiles,
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

/// Load a chunk into the terrain cache (thread-safe)
pub fn load_terrain_chunk(chunk_x: i32, chunk_y: i32, terrain_data: Vec<TerrainType>) {
    let mut cache = TERRAIN_CACHE.write();
    let chunk = TerrainChunk::from_data(terrain_data);
    cache.load_chunk(chunk_x, chunk_y, chunk);

    #[cfg(feature = "debug_logs")]
    godot::prelude::godot_print!("TerrainCache: Loaded chunk ({}, {})", chunk_x, chunk_y);
}

/// Unload a chunk from the terrain cache (thread-safe)
pub fn unload_terrain_chunk(chunk_x: i32, chunk_y: i32) -> bool {
    let mut cache = TERRAIN_CACHE.write();
    let unloaded = cache.unload_chunk(chunk_x, chunk_y).is_some();

    #[cfg(feature = "debug_logs")]
    if unloaded {
        godot::prelude::godot_print!("TerrainCache: Unloaded chunk ({}, {})", chunk_x, chunk_y);
    }

    unloaded
}

/// Check if a chunk is loaded (thread-safe)
pub fn is_terrain_chunk_loaded(chunk_x: i32, chunk_y: i32) -> bool {
    let cache = TERRAIN_CACHE.read();
    cache.is_chunk_loaded(chunk_x, chunk_y)
}

/// Get number of loaded chunks (thread-safe)
pub fn get_loaded_chunk_count() -> usize {
    let cache = TERRAIN_CACHE.read();
    cache.loaded_chunk_count()
}
