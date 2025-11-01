use super::biomes::{BiomeGenerator, TerrainType};
use super::noise::NoiseGenerator;
use godot::prelude::*;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;

/// Thread-safe cache of noise generators by seed
static NOISE_CACHE: once_cell::sync::Lazy<RwLock<HashMap<i32, Arc<NoiseGenerator>>>> =
    once_cell::sync::Lazy::new(|| RwLock::new(HashMap::new()));

/// Chunk generator bridge to GDScript
#[derive(GodotClass)]
#[class(base=Object)]
pub struct WorldGenerator {
    base: Base<Object>,
    current_seed: i32,
}

#[godot_api]
impl IObject for WorldGenerator {
    fn init(base: Base<Object>) -> Self {
        Self {
            base,
            current_seed: 0,
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
            let x = (idx % CHUNK_SIZE) as i32;
            let y = (idx / CHUNK_SIZE) as i32;
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
}
