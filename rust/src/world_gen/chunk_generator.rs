use super::biomes::{BiomeGenerator, TerrainType};
use super::noise::NoiseGenerator;
use godot::prelude::*;
use parking_lot::{Mutex, RwLock};
use std::collections::HashMap;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;
use std::thread::{self, JoinHandle};

/// Thread-safe cache of noise generators by seed
pub static NOISE_CACHE: once_cell::sync::Lazy<RwLock<HashMap<i32, Arc<NoiseGenerator>>>> =
    once_cell::sync::Lazy::new(|| RwLock::new(HashMap::new()));

/// Chunk generation request
#[derive(Debug, Clone)]
struct ChunkRequest {
    request_id: u64,
    chunk_x: i32,
    chunk_y: i32,
    seed: i32,
}

/// Chunk generation result
#[derive(Debug, Clone)]
struct ChunkResult {
    request_id: u64,
    chunk_x: i32,
    chunk_y: i32,
    tile_data: Vec<(i32, i32, i32)>, // (x, y, tile_index)
}

/// Chunk generator bridge to GDScript
#[derive(GodotClass)]
#[class(base=Object)]
pub struct WorldGenerator {
    base: Base<Object>,
    current_seed: i32,
    // Async chunk generation
    next_request_id: Arc<Mutex<u64>>,
    request_tx: Arc<Mutex<Option<Sender<ChunkRequest>>>>,
    result_rx: Arc<Mutex<Option<Receiver<ChunkResult>>>>,
    worker_handle: Option<JoinHandle<()>>,
}

#[godot_api]
impl IObject for WorldGenerator {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            current_seed: 0,
            next_request_id: Arc::new(Mutex::new(0)),
            request_tx: Arc::new(Mutex::new(None)),
            result_rx: Arc::new(Mutex::new(None)),
            worker_handle: None,
        }
    }
}

#[godot_api]
impl WorldGenerator {
    /// Set the world seed for generation
    #[func]
    pub fn set_seed(&mut self, seed: i32) {
        self.current_seed = seed;

        // Ensure noise generator exists for this seed
        let mut cache = NOISE_CACHE.write();
        if !cache.contains_key(&seed) {
            cache.insert(seed, Arc::new(NoiseGenerator::new(seed)));
        }
    }

    /// Get the current world seed
    #[func]
    pub fn get_seed(&self) -> i32 {
        self.current_seed
    }

    /// Generate a chunk of terrain data
    ///
    /// # Arguments
    /// * `chunk_x` - Chunk X coordinate
    /// * `chunk_y` - Chunk Y coordinate
    ///
    /// # Returns
    /// Array of Dictionaries, each containing:
    /// - "terrain": String - terrain type name
    /// - "tile_index": int - tile index for atlas (0-9)
    /// - "x": int - local tile X coordinate (0-31)
    /// - "y": int - local tile Y coordinate (0-31)
    #[func]
    pub fn generate_chunk(&self, chunk_x: i32, chunk_y: i32) -> Array<Dictionary> {
        const CHUNK_SIZE: usize = 32;
        const TILE_WIDTH: f32 = 32.0;
        const TILE_HEIGHT: f32 = 28.0;

        // Get noise generator for current seed
        let cache = NOISE_CACHE.read();
        let noise = cache
            .get(&self.current_seed)
            .expect("Noise generator not initialized - call set_seed() first")
            .clone();
        drop(cache);

        // Generate terrain data
        let terrain_data = BiomeGenerator::generate_chunk(
            &noise,
            chunk_x,
            chunk_y,
            CHUNK_SIZE,
            TILE_WIDTH,
            TILE_HEIGHT,
        );

        // Convert to GDScript-friendly format (int-based for performance)
        let mut result = Array::new();

        // Debug: Count terrain types
        let mut water_count = 0;
        let mut land_count = 0;

        for (idx, terrain_type) in terrain_data.iter().enumerate() {
            // Terrain data is stored with outer loop Y, inner loop X
            // So: idx = ty * CHUNK_SIZE + tx
            let x = (idx % CHUNK_SIZE) as i32;  // tx = idx % CHUNK_SIZE
            let y = (idx / CHUNK_SIZE) as i32;  // ty = idx / CHUNK_SIZE
            let tile_index = terrain_type.to_tile_index();

            // Count terrain types (atlas index 4 = water)
            if tile_index == 4 {
                water_count += 1;
            } else {
                land_count += 1;
            }

            // Only send tile_index (int) - no strings for performance
            let mut tile_dict = Dictionary::new();
            tile_dict.set("tile_index", tile_index);
            tile_dict.set("x", x);
            tile_dict.set("y", y);

            result.push(&tile_dict);
        }

        godot_print!(
            "WorldGenerator: Generated chunk ({}, {}) - Water: {}, Land: {}",
            chunk_x,
            chunk_y,
            water_count,
            land_count
        );

        result
    }

    /// Generate terrain type for a single tile (for pathfinding/queries)
    ///
    /// # Arguments
    /// * `world_x` - World X coordinate in pixels
    /// * `world_y` - World Y coordinate in pixels
    ///
    /// # Returns
    /// i32 - atlas tile index (0-3,5-6 = grassland variants, 4 = water)
    #[func]
    pub fn get_terrain_at(&self, world_x: f32, world_y: f32) -> i32 {
        // Get noise generator for current seed
        let cache = NOISE_CACHE.read();
        let noise = cache
            .get(&self.current_seed)
            .expect("Noise generator not initialized - call set_seed() first");

        let terrain_type = BiomeGenerator::get_terrain_type(noise, world_x, world_y);
        terrain_type.to_tile_index()
    }

    /// Check if a tile is water (for pathfinding)
    ///
    /// # Arguments
    /// * `world_x` - World X coordinate in pixels
    /// * `world_y` - World Y coordinate in pixels
    ///
    /// # Returns
    /// bool - true if water, false otherwise
    #[func]
    pub fn is_water(&self, world_x: f32, world_y: f32) -> bool {
        let cache = NOISE_CACHE.read();
        let noise = cache
            .get(&self.current_seed)
            .expect("Noise generator not initialized - call set_seed() first");

        let terrain_type = BiomeGenerator::get_terrain_type(noise, world_x, world_y);
        terrain_type == TerrainType::Water
    }

    /// Check if a tile is land (for pathfinding)
    ///
    /// # Arguments
    /// * `world_x` - World X coordinate in pixels
    /// * `world_y` - World Y coordinate in pixels
    ///
    /// # Returns
    /// bool - true if land, false otherwise
    #[func]
    pub fn is_land(&self, world_x: f32, world_y: f32) -> bool {
        !self.is_water(world_x, world_y)
    }

    /// Get elevation value at world coordinates (for advanced queries)
    ///
    /// # Arguments
    /// * `world_x` - World X coordinate in pixels
    /// * `world_y` - World Y coordinate in pixels
    ///
    /// # Returns
    /// float - elevation value from -1.0 to 1.0
    #[func]
    pub fn get_elevation(&self, world_x: f32, world_y: f32) -> f32 {
        let cache = NOISE_CACHE.read();
        let noise = cache
            .get(&self.current_seed)
            .expect("Noise generator not initialized - call set_seed() first");

        noise.get_elevation(world_x, world_y)
    }

    /// Start async chunk generation worker thread
    #[func]
    pub fn start_async_worker(&mut self) {
        if self.worker_handle.is_some() {
            godot_warn!("WorldGenerator: Async worker already running");
            return;
        }

        let (request_tx, request_rx) = channel();
        let (result_tx, result_rx) = channel();

        *self.request_tx.lock() = Some(request_tx);
        *self.result_rx.lock() = Some(result_rx);

        // Spawn worker thread
        let worker_handle = thread::spawn(move || {
            loop {
                match request_rx.recv() {
                    Ok(request) => {
                        const CHUNK_SIZE: usize = 32;
                        const TILE_WIDTH: f32 = 32.0;
                        const TILE_HEIGHT: f32 = 28.0;

                        // Get noise generator for this seed
                        let cache = NOISE_CACHE.read();
                        let noise = match cache.get(&request.seed) {
                            Some(n) => n.clone(),
                            None => {
                                godot_error!("WorldGenerator: Noise generator not found for seed {}", request.seed);
                                continue;
                            }
                        };
                        drop(cache);

                        // Generate terrain data
                        let terrain_data = BiomeGenerator::generate_chunk(
                            &noise,
                            request.chunk_x,
                            request.chunk_y,
                            CHUNK_SIZE,
                            TILE_WIDTH,
                            TILE_HEIGHT,
                        );

                        // FIX: Populate terrain cache directly here instead of round-tripping through Godot
                        use crate::npc::terrain_cache;
                        let cache = terrain_cache::get_terrain_cache();

                        let mut water_count = 0;
                        let mut land_count = 0;

                        // Convert to flat format (x, y, tile_index) AND populate cache
                        let mut tile_data = Vec::with_capacity(CHUNK_SIZE * CHUNK_SIZE);
                        for (idx, terrain_type) in terrain_data.iter().enumerate() {
                            let local_x = (idx % CHUNK_SIZE) as i32;
                            let local_y = (idx / CHUNK_SIZE) as i32;
                            let tile_index = terrain_type.to_tile_index();

                            // Calculate world coordinates
                            let world_x = request.chunk_x * CHUNK_SIZE as i32 + local_x;
                            let world_y = request.chunk_y * CHUNK_SIZE as i32 + local_y;

                            // Populate terrain cache directly (DashMap allows concurrent writes)
                            let cache_terrain = terrain_cache::TerrainType::from_biome_terrain(terrain_type);
                            cache.set(world_x, world_y, cache_terrain);

                            if cache_terrain == terrain_cache::TerrainType::Water {
                                water_count += 1;
                            } else {
                                land_count += 1;
                            }

                            tile_data.push((local_x, local_y, tile_index));
                        }

                        godot_print!("WorldGenerator: Generated chunk ({}, {}) - {} tiles ({} water, {} land)",
                            request.chunk_x, request.chunk_y, tile_data.len(), water_count, land_count);

                        // Send result back
                        let result = ChunkResult {
                            request_id: request.request_id,
                            chunk_x: request.chunk_x,
                            chunk_y: request.chunk_y,
                            tile_data,
                        };

                        if result_tx.send(result).is_err() {
                            godot_error!("WorldGenerator: Failed to send chunk result");
                            break;
                        }
                    }
                    Err(_) => {
                        // Worker thread shutting down
                        break;
                    }
                }
            }
        });

        self.worker_handle = Some(worker_handle);
    }

    /// Request async chunk generation
    /// Returns request_id for tracking
    #[func]
    pub fn request_chunk_async(&mut self, chunk_x: i32, chunk_y: i32) -> i64 {
        let request_tx = self.request_tx.lock();
        let tx = match request_tx.as_ref() {
            Some(tx) => tx,
            None => {
                godot_error!("WorldGenerator: Async worker not started - call start_async_worker() first");
                return -1;
            }
        };

        // Generate request ID
        let mut next_id = self.next_request_id.lock();
        let request_id = *next_id;
        *next_id += 1;
        drop(next_id);

        // Send request
        let request = ChunkRequest {
            request_id,
            chunk_x,
            chunk_y,
            seed: self.current_seed,
        };

        if tx.send(request).is_err() {
            godot_error!("WorldGenerator: Failed to send chunk request");
            return -1;
        }

        request_id as i64
    }

    /// Poll for completed chunk results
    /// Returns null if no results available, otherwise returns Dictionary with:
    /// - "chunk_x": int
    /// - "chunk_y": int
    /// - "tile_data": Array of Dictionaries (x, y, tile_index)
    #[func]
    pub fn poll_chunk_results(&self) -> Variant {
        let result_rx = self.result_rx.lock();
        let rx = match result_rx.as_ref() {
            Some(rx) => rx,
            None => return Variant::nil(),
        };

        // Try to receive without blocking
        match rx.try_recv() {
            Ok(result) => {
                // Convert to GDScript format
                let mut dict = Dictionary::new();
                dict.set("chunk_x", result.chunk_x);
                dict.set("chunk_y", result.chunk_y);

                let mut tile_array = Array::new();
                for (x, y, tile_index) in result.tile_data {
                    let mut tile_dict = Dictionary::new();
                    tile_dict.set("x", x);
                    tile_dict.set("y", y);
                    tile_dict.set("tile_index", tile_index);
                    tile_array.push(&tile_dict);
                }
                dict.set("tile_data", tile_array);

                dict.to_variant()
            }
            Err(_) => Variant::nil(),
        }
    }

    /// Stop async worker thread
    #[func]
    pub fn stop_async_worker(&mut self) {
        // Drop the sender to signal worker to stop
        *self.request_tx.lock() = None;

        // Wait for worker to finish
        if let Some(handle) = self.worker_handle.take() {
            let _ = handle.join();
            godot_print!("WorldGenerator: Async worker stopped");
        }
    }
}
