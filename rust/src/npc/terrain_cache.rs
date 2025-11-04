/// Shared terrain cache for efficient pathfinding
///
/// This module provides a thread-safe, Arc-based terrain map that can be shared
/// between ship and ground pathfinding systems. Similar to CardRegistry, it uses
/// efficient data structures for fast lookups during pathfinding.

use std::sync::Arc;
use std::sync::atomic::{AtomicI32, Ordering};
// REMOVED: Mutex and VecDeque - no longer needed without LRU tracking
use dashmap::DashMap;
use serde::{Serialize, Deserialize};
use godot::prelude::*;
use crate::config::map as map_config;
// REMOVED: TerrainDb import - database operations disabled to prevent Mutex blocking

/// Terrain types for pathfinding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum TerrainType {
    Water = 0,      // Walkable for ships
    Land = 1,       // Walkable for ground units
    Obstacle = 2,   // Blocked tile
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

    /// Convert from biome TerrainType (world_gen module) to cache TerrainType
    pub fn from_biome_terrain(biome_terrain: &crate::world_gen::biomes::TerrainType) -> Self {
        use crate::world_gen::biomes::TerrainType as BiomeTerrain;
        match biome_terrain {
            BiomeTerrain::Water => TerrainType::Water,
            // All grassland variants are land
            BiomeTerrain::Grassland0 | BiomeTerrain::Grassland1 |
            BiomeTerrain::Grassland2 | BiomeTerrain::Grassland3 |
            BiomeTerrain::Grassland4 | BiomeTerrain::Grassland5 => TerrainType::Land,
        }
    }
}

/// Hex coordinate (axial coordinates: q, r)
pub type HexCoord = (i32, i32);

/// Chunk coordinate (chunk_x, chunk_y)
pub type ChunkCoord = (i32, i32);

/// Single chunk of terrain data (32x32 tiles)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerrainChunk {
    /// Flat array of terrain types for this chunk (1024 bytes)
    /// Row-major order: index = y * CHUNK_SIZE + x
    data: Vec<TerrainType>,
}

impl TerrainChunk {
    /// Create a new chunk filled with obstacles (ungenerated terrain)
    pub fn new() -> Self {
        Self {
            data: vec![TerrainType::Obstacle; map_config::CHUNK_SIZE * map_config::CHUNK_SIZE],
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
        // Bounds check to prevent panic
        if local_x >= map_config::CHUNK_SIZE || local_y >= map_config::CHUNK_SIZE {
            godot_print!(
                "ERROR: TerrainChunk::get - Invalid coordinates: local_x={}, local_y={}, CHUNK_SIZE={}",
                local_x, local_y, map_config::CHUNK_SIZE
            );
            return TerrainType::Obstacle;
        }

        let index = local_y * map_config::CHUNK_SIZE + local_x;

        // Extra paranoid check - should never happen after bounds check above
        if index >= self.data.len() {
            godot_print!(
                "CRITICAL: TerrainChunk::get - Index {} out of bounds (data.len={}), local_x={}, local_y={}",
                index, self.data.len(), local_x, local_y
            );
            return TerrainType::Obstacle;
        }

        self.data[index]
    }

    /// Set terrain at local chunk coordinates (0-31)
    #[inline]
    pub fn set(&mut self, local_x: usize, local_y: usize, terrain_type: TerrainType) {
        // Bounds check to prevent panic
        if local_x >= map_config::CHUNK_SIZE || local_y >= map_config::CHUNK_SIZE {
            godot_print!(
                "ERROR: TerrainChunk::set - Invalid coordinates: local_x={}, local_y={}, CHUNK_SIZE={}",
                local_x, local_y, map_config::CHUNK_SIZE
            );
            return;
        }

        let index = local_y * map_config::CHUNK_SIZE + local_x;
        self.data[index] = terrain_type;
    }
}

/// Thread-safe terrain cache using DashMap for lock-free concurrent access
/// LRU eviction and DB storage REMOVED to prevent ANY Mutex blocking during pathfinding
pub struct TerrainCache {
    /// Hot cache: Recent chunks in memory (DashMap for concurrent access)
    hot_cache: Arc<DashMap<ChunkCoord, TerrainChunk>>,
    /// REMOVED: LRU order tracking (was causing Mutex deadlocks)
    /// REMOVED: SQLite db (was using Mutex, causing blocking)
    /// Current world seed (for procedural generation of missing chunks)
    current_seed: AtomicI32,
}

impl TerrainCache {
    /// Create a new terrain cache (lock-free, in-memory only)
    /// LRU eviction and DB storage disabled - chunks stay in memory (unbounded cache)
    pub fn new() -> Self {
        Self {
            hot_cache: Arc::new(DashMap::new()),
            // REMOVED: lru_order, max_hot_chunks, and db to prevent ALL Mutex blocking
            current_seed: AtomicI32::new(0), // Default seed, will be set by set_seed()
        }
    }

    /// Set the current world seed (for procedural generation)
    pub fn set_seed(&self, seed: i32) {
        self.current_seed.store(seed, Ordering::Relaxed);
    }

    /// REMOVED: init_db() - Database completely disabled to prevent Mutex blocking

    /// REMOVED: load_from_db() - Database completely disabled to prevent Mutex blocking

    /// REMOVED: save_to_db() - Database completely disabled to prevent Mutex blocking

    /// Generate a chunk procedurally using the world generator
    /// This is called when a chunk is not found in cache or database
    fn generate_chunk_procedurally(&self, chunk_x: i32, chunk_y: i32) -> Option<TerrainChunk> {
        // Access the world generator's noise cache
        use crate::world_gen::{BiomeGenerator, NoiseGenerator};

        // Get noise generator for current seed
        // NOISE_CACHE is defined in world_gen::chunk_generator
        use crate::world_gen::chunk_generator::NOISE_CACHE;

        let cache = match NOISE_CACHE.try_read() {
            Some(c) => c,
            None => {
                godot::prelude::godot_error!("TerrainCache: Failed to read NOISE_CACHE for procedural generation");
                return None;
            }
        };

        let current_seed = self.current_seed.load(Ordering::Relaxed);
        let noise = match cache.get(&current_seed) {
            Some(n) => n.clone(),
            None => {
                // Noise generator not initialized yet - this is expected during early initialization
                // Return None and let caller handle it (will return Obstacle)
                return None;
            }
        };
        drop(cache);

        // Generate terrain data for this chunk
        // tile_width and tile_height are unused in the hex layout
        let terrain_data = BiomeGenerator::generate_chunk(
            &noise,
            chunk_x,
            chunk_y,
            map_config::CHUNK_SIZE,
            32.0,  // tile_width (unused)
            28.0   // tile_height (unused)
        );

        // Convert to TerrainCache TerrainType
        let cache_terrain: Vec<TerrainType> = terrain_data
            .into_iter()
            .map(|biome_terrain| TerrainType::from_biome_terrain(&biome_terrain))
            .collect();

        godot::prelude::godot_print!(
            "TerrainCache: Generated chunk ({}, {}) procedurally (seed={})",
            chunk_x, chunk_y, current_seed
        );

        Some(TerrainChunk::from_data(cache_terrain))
    }

    /// REMOVED: evict_lru() - LRU eviction disabled to prevent Mutex blocking
    /// Chunks now stay in memory indefinitely (unbounded cache)

    /// REMOVED: touch_chunk() - LRU tracking disabled to prevent Mutex blocking

    /// Convert tile coordinates to chunk coordinates
    #[inline]
    fn tile_to_chunk(tile_x: i32, tile_y: i32) -> (ChunkCoord, usize, usize) {
        let chunk_x = tile_x.div_euclid(map_config::CHUNK_SIZE as i32);
        let chunk_y = tile_y.div_euclid(map_config::CHUNK_SIZE as i32);
        let local_x = tile_x.rem_euclid(map_config::CHUNK_SIZE as i32) as usize;
        let local_y = tile_y.rem_euclid(map_config::CHUNK_SIZE as i32) as usize;
        ((chunk_x, chunk_y), local_x, local_y)
    }

    /// Load a chunk into the hot cache (no eviction - unbounded cache)
    pub fn load_chunk(&self, chunk_x: i32, chunk_y: i32, chunk_data: TerrainChunk) {
        let chunk_coord = (chunk_x, chunk_y);

        // REMOVED: LRU eviction - chunks stay in memory
        // Insert into hot cache (lock-free DashMap operation)
        self.hot_cache.insert(chunk_coord, chunk_data);
    }

    /// Unload a chunk from hot cache (DB save disabled)
    pub fn unload_chunk(&self, chunk_x: i32, chunk_y: i32) -> Option<TerrainChunk> {
        let chunk_coord = (chunk_x, chunk_y);

        // REMOVED: LRU tracking - no Mutex blocking
        // Remove from hot cache (lock-free DashMap operation)
        if let Some((_key, chunk)) = self.hot_cache.remove(&chunk_coord) {
            // DB disabled to prevent blocking
            Some(chunk)
        } else {
            None
        }
    }

    /// Check if a chunk is loaded in hot cache
    pub fn is_chunk_loaded(&self, chunk_x: i32, chunk_y: i32) -> bool {
        self.hot_cache.contains_key(&(chunk_x, chunk_y))
    }

    /// Get number of loaded chunks in hot cache
    pub fn loaded_chunk_count(&self) -> usize {
        self.hot_cache.len()
    }

    /// Set terrain at tile coordinates (with LRU management)
    #[inline]
    pub fn set(&self, tile_x: i32, tile_y: i32, terrain_type: TerrainType) {
        let ((chunk_x, chunk_y), local_x, local_y) = Self::tile_to_chunk(tile_x, tile_y);
        let chunk_coord = (chunk_x, chunk_y);

        // Check if chunk is in hot cache (DashMap allows concurrent modification)
        if let Some(mut chunk_ref) = self.hot_cache.get_mut(&chunk_coord) {
            chunk_ref.set(local_x, local_y, terrain_type);
            drop(chunk_ref); // Release lock
            // NOTE: Don't touch LRU on every write - causes lock contention
            return;
        }

        // Chunk not in hot cache - create new one (DB disabled)
        let mut chunk = TerrainChunk::new();
        chunk.set(local_x, local_y, terrain_type);

        // REMOVED: No LRU eviction - unbounded cache
        self.hot_cache.insert(chunk_coord, chunk);
    }

    /// Get terrain at tile coordinates (checks hot cache + SQLite/IndexedDB, returns Obstacle if not found)
    /// Unloaded chunks should block pathfinding to prevent entities from pathing through ungenerated terrain
    #[inline]
    pub fn get(&self, tile_x: i32, tile_y: i32) -> TerrainType {
        let ((chunk_x, chunk_y), local_x, local_y) = Self::tile_to_chunk(tile_x, tile_y);
        let chunk_coord = (chunk_x, chunk_y);

        // Check hot cache first (fast path) - DashMap allows concurrent reads!
        if let Some(chunk_ref) = self.hot_cache.get(&chunk_coord) {
            let terrain = chunk_ref.get(local_x, local_y);
            drop(chunk_ref); // Release read lock
            // NOTE: Don't touch LRU on every read - causes lock contention during pathfinding
            // LRU is only updated on chunk loads/writes
            return terrain;
        }

        // Not in hot cache - chunk needs to be loaded
        // For now, return Obstacle to block pathfinding through unloaded chunks
        // In the future, could load from DB here, but that would require &mut self
        TerrainType::Obstacle
    }

    /// Batch update terrain from flat array (for initialization)
    pub fn init_from_flat_array(&self, tiles: &[(i32, i32, TerrainType)]) {
        for &(x, y, terrain_type) in tiles {
            self.set(x, y, terrain_type);
        }
    }

    /// Clear all terrain (hot cache only - DB disabled)
    pub fn clear(&self) {
        self.hot_cache.clear();
        // REMOVED: LRU and DB operations
        godot::prelude::godot_print!("TerrainCache: Cleared all terrain data (hot cache)");
    }

    /// Get terrain statistics (for debugging - only counts hot cache for performance)
    pub fn get_stats(&self) -> TerrainStats {
        let mut water_count = 0;
        let mut land_count = 0;
        let mut obstacle_count = 0;

        for chunk_ref in self.hot_cache.iter() {
            for terrain in &chunk_ref.value().data {
                match terrain {
                    TerrainType::Water => water_count += 1,
                    TerrainType::Land => land_count += 1,
                    TerrainType::Obstacle => obstacle_count += 1,
                }
            }
        }

        let total_tiles = self.hot_cache.len() * map_config::CHUNK_SIZE * map_config::CHUNK_SIZE;

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

/// Global terrain cache (thread-safe with Arc + DashMap for lock-free reads)
static TERRAIN_CACHE: once_cell::sync::Lazy<Arc<TerrainCache>> =
    once_cell::sync::Lazy::new(|| Arc::new(TerrainCache::new()));

/// Get reference to the terrain cache
/// Note: DashMap inside allows concurrent reads without blocking
pub fn get_terrain_cache() -> Arc<TerrainCache> {
    Arc::clone(&TERRAIN_CACHE)
}

/// Initialize terrain cache from GDScript map data
pub fn init_terrain_cache(tiles: Vec<(i32, i32, String)>) {
    let cache = TERRAIN_CACHE.as_ref();

    // Only clear cache if we're initializing with actual data
    // For infinite worlds (0 tiles), preserve existing chunk data
    if !tiles.is_empty() {
        cache.clear();
    }

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

/// Set the world seed for procedural generation
/// This must be called before pathfinding to ensure consistent terrain generation
pub fn set_terrain_seed(seed: i32) {
    TERRAIN_CACHE.set_seed(seed);
}

/// Get terrain at coordinates (thread-safe, lock-free reads with DashMap)
pub fn get_terrain(x: i32, y: i32) -> TerrainType {
    TERRAIN_CACHE.get(x, y)
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
    let chunk = TerrainChunk::from_data(terrain_data);
    TERRAIN_CACHE.load_chunk(chunk_x, chunk_y, chunk);

    #[cfg(feature = "debug_logs")]
    godot::prelude::godot_print!("TerrainCache: Loaded chunk ({}, {})", chunk_x, chunk_y);
}

/// Unload a chunk from the terrain cache (thread-safe)
pub fn unload_terrain_chunk(chunk_x: i32, chunk_y: i32) -> bool {
    let unloaded = TERRAIN_CACHE.unload_chunk(chunk_x, chunk_y).is_some();

    #[cfg(feature = "debug_logs")]
    if unloaded {
        godot::prelude::godot_print!("TerrainCache: Unloaded chunk ({}, {})", chunk_x, chunk_y);
    }

    unloaded
}

/// Check if a chunk is loaded (thread-safe)
pub fn is_terrain_chunk_loaded(chunk_x: i32, chunk_y: i32) -> bool {
    TERRAIN_CACHE.is_chunk_loaded(chunk_x, chunk_y)
}

/// Get number of loaded chunks (thread-safe)
pub fn get_loaded_chunk_count() -> usize {
    TERRAIN_CACHE.loaded_chunk_count()
}
