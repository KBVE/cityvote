/// Centralized configuration constants for the entire game
///
/// IMPORTANT: These values MUST be kept in sync with GDScript:
/// - cat/core/map_config.gd
///
/// This module provides a single source of truth for map dimensions
/// and other global configuration values used across the Rust codebase.

/// Map configuration constants
pub mod map {
    /// INFINITE WORLD: No fixed map dimensions
    /// Chunks are generated procedurally on-demand

    /// Chunk settings
    pub const CHUNK_SIZE: usize = 32;  // 32x32 tiles per chunk
    pub const CHUNK_CACHE_SIZE: usize = 100;  // Maximum chunks in memory (LRU cache)
    pub const CHUNK_RENDER_DISTANCE: i32 = 3;  // Chunks to render around camera

    /// Tile dimensions (legacy - not used for hex grid)
    /// NOTE: These are kept for backward compatibility but hex grid uses fixed spacing below
    pub const TILE_WIDTH: f32 = 32.0;
    pub const TILE_HEIGHT: f32 = 28.0;

    /// Hex grid layout constants (STACKED_OFFSET VERTICAL)
    /// These values must match GDScript's custom_tile_renderer.gd
    pub const HEX_HORIZONTAL_SPACING: f32 = 24.5;  // Horizontal spacing between hex centers
    pub const HEX_VERTICAL_SPACING: f32 = 28.5;    // Vertical spacing between hex centers
    pub const HEX_OFFSET_X: f32 = 16.0;            // Initial X offset for first tile
    pub const HEX_OFFSET_Y: f32 = 28.0;            // Initial Y offset for first tile
    pub const HEX_ODD_COLUMN_OFFSET: f32 = 14.25;  // Odd columns offset UP by this amount

    /// Legacy bounds checking (always returns true for infinite world)
    /// TODO: Remove bounds checks from pathfinding code
    #[inline]
    pub fn is_in_bounds(_x: i32, _y: i32) -> bool {
        true  // Infinite world has no bounds
    }

    /// Legacy constants for spatial_hash, quad_tree, flow_field
    /// TODO: Refactor these systems to work without fixed bounds
    pub const WIDTH: i32 = 10000;
    pub const HEIGHT: i32 = 10000;
    pub const TOTAL_TILES: usize = (WIDTH * HEIGHT) as usize;

    /// Convert tile coordinates to chunk coordinates (supports negative coords)
    #[inline]
    pub fn tile_to_chunk(tile_x: i32, tile_y: i32) -> (i32, i32) {
        (
            tile_x.div_euclid(CHUNK_SIZE as i32),
            tile_y.div_euclid(CHUNK_SIZE as i32),
        )
    }

    /// Get local tile coordinates within a chunk (0-31)
    #[inline]
    pub fn tile_to_local(tile_x: i32, tile_y: i32) -> (usize, usize) {
        (
            tile_x.rem_euclid(CHUNK_SIZE as i32) as usize,
            tile_y.rem_euclid(CHUNK_SIZE as i32) as usize,
        )
    }

    /// Convert chunk coordinates to top-left tile coordinates
    #[inline]
    pub fn chunk_to_tile(chunk_x: i32, chunk_y: i32) -> (i32, i32) {
        (
            chunk_x * CHUNK_SIZE as i32,
            chunk_y * CHUNK_SIZE as i32,
        )
    }
}

/// Pathfinding configuration constants
pub mod pathfinding {
    /// Maximum number of pathfinding iterations before giving up
    pub const MAX_ITERATIONS: usize = 10000;

    /// Heuristic weight for A* pathfinding (higher = faster but less optimal)
    pub const HEURISTIC_WEIGHT: f32 = 1.0;
}
