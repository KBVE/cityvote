use godot::prelude::*;
use super::biomes::BiomeGenerator;
use super::noise::NoiseGenerator;

/// Helper class to find optimal city locations
/// Exposed to GDScript for initial world setup
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct CityLocationFinder {
    base: Base<RefCounted>,
}

#[godot_api]
impl CityLocationFinder {
    /// Find a coastal location for the origin city
    /// Returns Vector2i with tile coordinates
    ///
    /// # Arguments
    /// * `seed` - World seed (same as used for terrain generation)
    /// * `search_radius` - How many chunks to search (2-3 recommended)
    #[func]
    pub fn find_coastal_location(seed: i64, search_radius: i32) -> Vector2i {
        let noise = NoiseGenerator::new(seed as i32);
        let (tile_x, tile_y) = BiomeGenerator::find_coastal_city_location(&noise, search_radius);

        godot_print!(
            "CityLocationFinder: Found coastal location at tile ({}, {})",
            tile_x,
            tile_y
        );

        Vector2i::new(tile_x, tile_y)
    }

    /// Convert tile coordinates to world position
    /// This matches the hex grid layout used by the game
    #[func]
    pub fn tile_to_world_pos(tile_coords: Vector2i) -> Vector2 {
        use crate::config::map as map_config;

        let tile_x = tile_coords.x;
        let tile_y = tile_coords.y;

        let x = map_config::HEX_OFFSET_X + (tile_x as f32) * map_config::HEX_HORIZONTAL_SPACING;
        let mut y = map_config::HEX_OFFSET_Y + (tile_y as f32) * map_config::HEX_VERTICAL_SPACING;

        // Odd columns offset UP
        if tile_x.abs() % 2 == 1 {
            y -= map_config::HEX_ODD_COLUMN_OFFSET;
        }

        Vector2::new(x, y)
    }
}
