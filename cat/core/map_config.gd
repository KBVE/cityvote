extends Node

## Global map configuration constants
## Single source of truth for map dimensions

# Map dimensions (1024x1024 = 1,048,576 tiles, 1024 chunks of 32x32)
const MAP_WIDTH: int = 1024
const MAP_HEIGHT: int = 1024
const MAP_TOTAL_TILES: int = MAP_WIDTH * MAP_HEIGHT  # 1,048,576 tiles

# Chunk settings (for performance and fog of war)
const CHUNK_SIZE: int = 32  # 32x32 tiles per chunk
const CHUNKS_WIDE: int = MAP_WIDTH / CHUNK_SIZE  # 32 chunks
const CHUNKS_TALL: int = MAP_HEIGHT / CHUNK_SIZE  # 32 chunks
const TOTAL_CHUNKS: int = CHUNKS_WIDE * CHUNKS_TALL  # 1024 chunks

# Map generation settings
const ISLAND_BASE_RADIUS: float = 256.0  # Larger island to match bigger map
const LAND_NOISE_SCALE: float = 4.0
const PENINSULA_COUNT: int = 6  # More peninsulas for variety

# Tile source_id constants (matches TileSet sources in hex.gd)
const SOURCE_ID_WATER: int = 4

# Helper functions
static func is_tile_in_bounds(tile_coords: Vector2i) -> bool:
	return tile_coords.x >= 0 and tile_coords.x < MAP_WIDTH and \
	       tile_coords.y >= 0 and tile_coords.y < MAP_HEIGHT

static func get_map_center() -> Vector2:
	return Vector2(MAP_WIDTH / 2.0, MAP_HEIGHT / 2.0)

## Chunk helper functions

## Convert tile coordinates to chunk coordinates
static func tile_to_chunk(tile_coords: Vector2i) -> Vector2i:
	return Vector2i(tile_coords.x / CHUNK_SIZE, tile_coords.y / CHUNK_SIZE)

## Convert chunk coordinates to chunk index (0-99)
static func chunk_coords_to_index(chunk_coords: Vector2i) -> int:
	return chunk_coords.y * CHUNKS_WIDE + chunk_coords.x

## Convert chunk index to chunk coordinates
static func chunk_index_to_coords(chunk_index: int) -> Vector2i:
	return Vector2i(chunk_index % CHUNKS_WIDE, chunk_index / CHUNKS_WIDE)

## Get top-left tile of a chunk
static func chunk_to_tile(chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE)

## Check if chunk coordinates are valid
static func is_chunk_in_bounds(chunk_coords: Vector2i) -> bool:
	return chunk_coords.x >= 0 and chunk_coords.x < CHUNKS_WIDE and \
	       chunk_coords.y >= 0 and chunk_coords.y < CHUNKS_TALL
