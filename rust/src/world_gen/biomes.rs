use super::noise::NoiseGenerator;
use crate::config::map as map_config;
use serde::{Deserialize, Deserializer, Serialize};

/// Terrain types matching the existing GDScript system
// #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)] !TODO: Serde
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TerrainType {
    Water,
    Grassland0,
    Grassland1,
    Grassland2,
    Grassland3,
    Grassland4,
    Grassland5,
}

impl TerrainType {
    /// Convert terrain type to string for GDScript compatibility
    pub fn to_string(&self) -> &'static str {
        match self {
            TerrainType::Water => "water",
            TerrainType::Grassland0 => "grassland0",
            TerrainType::Grassland1 => "grassland1",
            TerrainType::Grassland2 => "grassland2",
            TerrainType::Grassland3 => "grassland3",
            TerrainType::Grassland4 => "grassland4",
            TerrainType::Grassland5 => "grassland5",
        }
    }

    /// Convert terrain type to atlas tile index (matches terrain_atlas_metadata.json)
    /// Atlas indices: 0=grassland0, 1=grassland1, 2=grassland2, 3=grassland3, 4=water, 5=grassland4, 6=grassland5
    pub fn to_tile_index(&self) -> i32 {
        match self {
            TerrainType::Water => 4,  // Water is at atlas index 4
            TerrainType::Grassland0 => 0,  // Grassland0 is at atlas index 0
            TerrainType::Grassland1 => 1,
            TerrainType::Grassland2 => 2,
            TerrainType::Grassland3 => 3,
            TerrainType::Grassland4 => 5,  // Grassland4 is at atlas index 5 (after water)
            TerrainType::Grassland5 => 6,
        }
    }
}

/// Biome generator using noise values to determine terrain types
pub struct BiomeGenerator;

impl BiomeGenerator {
    /// Determine terrain type based on elevation, temperature, and humidity
    ///
    /// # Arguments
    /// * `noise` - Noise generator for sampling values
    /// * `world_x` - World X coordinate (in world units, not tiles)
    /// * `world_y` - World Y coordinate (in world units, not tiles)
    pub fn get_terrain_type(noise: &NoiseGenerator, world_x: f32, world_y: f32) -> TerrainType {
        let elevation = noise.get_elevation(world_x, world_y);
        let temperature = noise.get_temperature(world_x, world_y);
        let humidity = noise.get_humidity(world_x, world_y);

        // Sea level threshold - anything below this is water
        const SEA_LEVEL: f32 = 0.0;

        if elevation < SEA_LEVEL {
            return TerrainType::Water;
        }

        // Land biomes based on temperature and humidity
        // Map elevation, temperature, and humidity to grassland variants

        // Combine factors to create variety
        let biome_value = (elevation * 0.4 + temperature * 0.3 + humidity * 0.3).clamp(-1.0, 1.0);

        // Map to grassland variants (6 types)
        if biome_value < -0.6 {
            TerrainType::Grassland0
        } else if biome_value < -0.2 {
            TerrainType::Grassland1
        } else if biome_value < 0.2 {
            TerrainType::Grassland2
        } else if biome_value < 0.4 {
            TerrainType::Grassland3
        } else if biome_value < 0.7 {
            TerrainType::Grassland4
        } else {
            TerrainType::Grassland5
        }
    }

    /// Convert tile coordinates to world position using hex grid layout
    /// Matches GDScript's _tile_to_world_pos() from custom_tile_renderer.gd
    ///
    /// Layout: STACKED_OFFSET VERTICAL
    /// Uses constants from config::map for maintainability
    #[inline]
    fn tile_to_hex_world_pos(tile_x: i32, tile_y: i32) -> (f32, f32) {
        let x = map_config::HEX_OFFSET_X + (tile_x as f32) * map_config::HEX_HORIZONTAL_SPACING;
        let mut y = map_config::HEX_OFFSET_Y + (tile_y as f32) * map_config::HEX_VERTICAL_SPACING;

        // Odd columns offset UP by HEX_ODD_COLUMN_OFFSET
        if tile_x % 2 == 1 {
            y -= map_config::HEX_ODD_COLUMN_OFFSET;
        }

        (x, y)
    }

    /// Generate a full chunk of terrain data
    ///
    /// # Arguments
    /// * `noise` - Noise generator
    /// * `chunk_x` - Chunk X coordinate (chunk coordinates, not tiles)
    /// * `chunk_y` - Chunk Y coordinate (chunk coordinates, not tiles)
    /// * `chunk_size` - Size of chunk in tiles (typically 32)
    /// * `tile_width` - Width of a single tile in world units (typically 32, but unused - hex layout uses 24.5px)
    /// * `tile_height` - Height of a single tile in world units (typically 28, but unused - hex layout uses 28.5px)
    ///
    /// # Returns
    /// Flat array of terrain types (row-major order, chunk_size * chunk_size)
    pub fn generate_chunk(
        noise: &NoiseGenerator,
        chunk_x: i32,
        chunk_y: i32,
        chunk_size: usize,
        _tile_width: f32,  // Unused - hex layout has fixed spacing
        _tile_height: f32, // Unused - hex layout has fixed spacing
    ) -> Vec<TerrainType> {
        let mut terrain = Vec::with_capacity(chunk_size * chunk_size);

        // Calculate top-left tile coordinates for this chunk
        let chunk_tile_x = chunk_x * chunk_size as i32;
        let chunk_tile_y = chunk_y * chunk_size as i32;

        for ty in 0..chunk_size {
            for tx in 0..chunk_size {
                // Calculate absolute tile coordinates
                let tile_x = chunk_tile_x + tx as i32;
                let tile_y = chunk_tile_y + ty as i32;

                // Convert tile coordinates to hex world position
                let (world_x, world_y) = Self::tile_to_hex_world_pos(tile_x, tile_y);

                let terrain_type = Self::get_terrain_type(noise, world_x, world_y);
                terrain.push(terrain_type);
            }
        }

        terrain
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chunk_generation_determinism() {
        let noise = NoiseGenerator::new(12345);

        let chunk1 = BiomeGenerator::generate_chunk(&noise, 0, 0, 32, 32.0, 28.0);
        let chunk2 = BiomeGenerator::generate_chunk(&noise, 0, 0, 32, 32.0, 28.0);

        assert_eq!(chunk1, chunk2);
    }

    #[test]
    fn test_different_chunks_are_different() {
        let noise = NoiseGenerator::new(12345);

        let chunk1 = BiomeGenerator::generate_chunk(&noise, 0, 0, 32, 32.0, 28.0);
        let chunk2 = BiomeGenerator::generate_chunk(&noise, 1, 0, 32, 32.0, 28.0);

        assert_ne!(chunk1, chunk2);
    }

    #[test]
    fn test_chunk_size() {
        let noise = NoiseGenerator::new(12345);
        let chunk = BiomeGenerator::generate_chunk(&noise, 0, 0, 32, 32.0, 28.0);

        assert_eq!(chunk.len(), 32 * 32);
    }

    #[test]
    fn test_terrain_type_strings() {
        assert_eq!(TerrainType::Water.to_string(), "water");
        assert_eq!(TerrainType::Grassland0.to_string(), "grassland0");
        assert_eq!(TerrainType::Grassland5.to_string(), "grassland5");
    }

    #[test]
    fn test_terrain_type_tile_indices() {
        // Verify atlas index mapping (matches terrain_atlas_metadata.json)
        assert_eq!(TerrainType::Water.to_tile_index(), 4);  // Water at atlas index 4
        assert_eq!(TerrainType::Grassland0.to_tile_index(), 0);  // Grassland0 at atlas index 0
        assert_eq!(TerrainType::Grassland5.to_tile_index(), 6);  // Grassland5 at atlas index 6
    }
}
