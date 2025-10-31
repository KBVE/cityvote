/// Centralized configuration constants for the entire game
///
/// IMPORTANT: These values MUST be kept in sync with GDScript:
/// - cat/core/map_config.gd
///
/// This module provides a single source of truth for map dimensions
/// and other global configuration values used across the Rust codebase.

/// Map configuration constants
pub mod map {
    /// Map dimensions: 1024x1024 tiles = 1,048,576 tiles total
    pub const WIDTH: i32 = 1024;
    pub const HEIGHT: i32 = 1024;
    pub const TOTAL_TILES: usize = (WIDTH * HEIGHT) as usize;  // 1,048,576

    /// Chunk settings: 32x32 chunks = 1024 chunks total (power of 2 for bitwise optimization)
    pub const CHUNK_SIZE: i32 = 32;
    pub const CHUNKS_WIDE: i32 = WIDTH / CHUNK_SIZE;  // 32
    pub const CHUNKS_TALL: i32 = HEIGHT / CHUNK_SIZE;  // 32
    pub const TOTAL_CHUNKS: usize = (CHUNKS_WIDE * CHUNKS_TALL) as usize;  // 1024

    /// Check if tile coordinates are within map bounds
    #[inline]
    pub fn is_in_bounds(x: i32, y: i32) -> bool {
        x >= 0 && x < WIDTH && y >= 0 && y < HEIGHT
    }

    /// Convert tile coordinates to chunk coordinates
    #[inline]
    pub fn tile_to_chunk(x: i32, y: i32) -> (i32, i32) {
        (x / CHUNK_SIZE, y / CHUNK_SIZE)
    }

    /// Convert chunk coordinates to linear chunk index (0-1023)
    /// Uses bitwise optimization: chunk_y * 32 + chunk_x becomes (chunk_y << 5) | chunk_x
    #[inline]
    pub fn chunk_to_index(chunk_x: i32, chunk_y: i32) -> usize {
        ((chunk_y << 5) | chunk_x) as usize
    }

    /// Convert linear chunk index back to chunk coordinates
    /// Uses bitwise optimization: index % 32 becomes index & 31, index / 32 becomes index >> 5
    #[inline]
    pub fn index_to_chunk(index: usize) -> (i32, i32) {
        let index = index as i32;
        (index & 31, index >> 5)
    }
}

/// Pathfinding configuration constants
pub mod pathfinding {
    /// Maximum number of pathfinding iterations before giving up
    pub const MAX_ITERATIONS: usize = 10000;

    /// Heuristic weight for A* pathfinding (higher = faster but less optimal)
    pub const HEURISTIC_WEIGHT: f32 = 1.0;
}
