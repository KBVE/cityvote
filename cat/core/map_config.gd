extends Node

## Global map configuration constants
## Single source of truth for map dimensions

# Map dimensions
const MAP_WIDTH: int = 80
const MAP_HEIGHT: int = 65
const MAP_TOTAL_TILES: int = MAP_WIDTH * MAP_HEIGHT  # 5200 tiles

# Map generation settings
const ISLAND_BASE_RADIUS: float = 20.0
const LAND_NOISE_SCALE: float = 3.0
const PENINSULA_COUNT: int = 3

# Tile source_id constants (matches TileSet sources in hex.gd)
const SOURCE_ID_WATER: int = 4

# Helper functions
static func is_tile_in_bounds(tile_coords: Vector2i) -> bool:
	return tile_coords.x >= 0 and tile_coords.x < MAP_WIDTH and \
	       tile_coords.y >= 0 and tile_coords.y < MAP_HEIGHT

static func get_map_center() -> Vector2:
	return Vector2(MAP_WIDTH / 2.0, MAP_HEIGHT / 2.0)
