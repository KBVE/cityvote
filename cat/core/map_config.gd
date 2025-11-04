extends Node

## Global map configuration constants
## Single source of truth for map dimensions

# INFINITE WORLD: No fixed map size
# Chunks are generated procedurally on-demand based on camera position

# Chunk settings (for performance and fog of war)
const CHUNK_SIZE: int = 32  # 32x32 tiles per chunk
const CHUNK_CACHE_SIZE: int = 100  # Maximum number of chunks kept in memory (LRU cache)
const CHUNK_RENDER_DISTANCE: int = 5  # Number of chunks to render around camera (increased for async loading buffer)

# World generation settings (procedural seed-based generation)
var world_seed: int = 12345  # Default seed, can be changed at runtime

# Tile dimensions (for world coordinate calculations)
const TILE_WIDTH: float = 32.0
const TILE_HEIGHT: float = 28.0

# Legacy bounds constants (for backwards compatibility with bounds checks)
# TODO: Remove bounds checks from pathfinding.gd, play_hand.gd, and main.gd
const MAP_WIDTH: int = 10000  # Arbitrary large value for legacy bounds checks
const MAP_HEIGHT: int = 10000  # Arbitrary large value for legacy bounds checks

# Tile source_id constants (matches TileSet sources in hex.gd)
const SOURCE_ID_WATER: int = 4

# Helper functions

## Convert tile coordinates to chunk coordinates (supports infinite world, negative coords)
func tile_to_chunk(tile_coords: Vector2i) -> Vector2i:
	# Use floor division to handle negative coordinates correctly
	return Vector2i(
		floori(float(tile_coords.x) / CHUNK_SIZE),
		floori(float(tile_coords.y) / CHUNK_SIZE)
	)

## Get top-left tile of a chunk
func chunk_to_tile(chunk_coords: Vector2i) -> Vector2i:
	return Vector2i(chunk_coords.x * CHUNK_SIZE, chunk_coords.y * CHUNK_SIZE)

## Convert world coordinates (pixels) to chunk coordinates
func world_to_chunk(world_pos: Vector2) -> Vector2i:
	var tile_x = floori(world_pos.x / TILE_WIDTH)
	var tile_y = floori(world_pos.y / TILE_HEIGHT)
	return tile_to_chunk(Vector2i(tile_x, tile_y))

## Convert chunk coordinates to world coordinates (top-left corner)
func chunk_to_world(chunk_coords: Vector2i) -> Vector2:
	return Vector2(
		chunk_coords.x * CHUNK_SIZE * TILE_WIDTH,
		chunk_coords.y * CHUNK_SIZE * TILE_HEIGHT
	)

## Get chunks within a radius of a center chunk (for camera visibility)
func get_chunks_in_radius(center_chunk: Vector2i, radius: int) -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []
	for y in range(center_chunk.y - radius, center_chunk.y + radius + 1):
		for x in range(center_chunk.x - radius, center_chunk.x + radius + 1):
			chunks.append(Vector2i(x, y))
	return chunks
