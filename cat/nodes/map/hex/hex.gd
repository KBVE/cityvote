extends Node2D

# Hexmap scene using TileMap

@onready var tile_map: TileMap = $TileMap
@onready var hex_highlight: Sprite2D = $HexHighlight

# Tile type to source_id mapping (matches TileSet sources)
var tile_type_to_source = {
	"grassland0": 0,
	"grassland1": 1,
	"grassland2": 2,
	"grassland3": 3,
	"water": 4,
	"grassland4": 5,
	"grassland5": 6,
	"city1": 7,
	"city2": 8,
	"village1": 9
}

# Preload tile textures for highlight
var tile_textures = {
	0: preload("res://nodes/map/hex/grassland0/grassland0.png"),
	1: preload("res://nodes/map/hex/grassland1/grassland1.png"),
	2: preload("res://nodes/map/hex/grassland2/grassland2.png"),
	3: preload("res://nodes/map/hex/grassland3/grassland3.png"),
	4: preload("res://nodes/map/hex/water/water.png"),
	5: preload("res://nodes/map/hex/grassland4/grassland4.png"),
	6: preload("res://nodes/map/hex/grassland5/grassland5.png"),
	7: preload("res://nodes/map/hex/grassland_city1/grassland_city1.png"),
	8: preload("res://nodes/map/hex/grassland_city2/grassland_city2.png"),
	9: preload("res://nodes/map/hex/grassland_village1/grassland_village1.png")
}

# Map data - stores tile type names
var map_data = []

# Card data - stores cards placed on tiles
var card_data: Dictionary = {}  # tile_coords -> {sprite, suit, value}

# Current hovered tile coordinates
var hovered_tile: Vector2i = Vector2i(-1, -1)

func _ready():
	# Set TileMap quadrant size to match our chunk size (32x32)
	# Default is 16x16, but we want to align with chunk architecture
	tile_map.rendering_quadrant_size = MapConfig.CHUNK_SIZE

	# Initialize a simple test map
	_generate_test_map()
	_render_tiles()

func _generate_test_map():
	# Create map using global MapConfig constants
	var grassland_types = ["grassland0", "grassland1", "grassland2", "grassland3", "grassland4", "grassland5"]
	var map_width = MapConfig.MAP_WIDTH
	var map_height = MapConfig.MAP_HEIGHT

	# Initialize with water everywhere first
	for y in range(map_height):
		var row = []
		for x in range(map_width):
			row.append("water")
		map_data.append(row)

	# Generate multiple continents and islands for variety
	# 2 large continents, 2-3 smaller continents, 3-5 small islands
	print("Hex: Generating continents and islands...")

	# Define landmasses (center_x, center_y, radius, noise_scale)
	var landmasses = [
		# Two large continents (opposite corners)
		{"center": Vector2(map_width * 0.25, map_height * 0.25), "radius": 180.0, "noise": 20.0, "peninsulas": 5, "type": "large_continent"},
		{"center": Vector2(map_width * 0.75, map_height * 0.75), "radius": 180.0, "noise": 20.0, "peninsulas": 5, "type": "large_continent"},

		# Smaller continents (mid-sized landmasses)
		{"center": Vector2(map_width * 0.70, map_height * 0.30), "radius": 100.0, "noise": 15.0, "peninsulas": 4, "type": "small_continent"},
		{"center": Vector2(map_width * 0.30, map_height * 0.70), "radius": 100.0, "noise": 15.0, "peninsulas": 4, "type": "small_continent"},
		{"center": Vector2(map_width * 0.50, map_height * 0.50), "radius": 90.0, "noise": 12.0, "peninsulas": 3, "type": "small_continent"},

		# Small islands (scattered around)
		{"center": Vector2(map_width * 0.15, map_height * 0.60), "radius": 50.0, "noise": 8.0, "peninsulas": 2, "type": "island"},
		{"center": Vector2(map_width * 0.85, map_height * 0.50), "radius": 45.0, "noise": 7.0, "peninsulas": 2, "type": "island"},
		{"center": Vector2(map_width * 0.50, map_height * 0.15), "radius": 40.0, "noise": 6.0, "peninsulas": 2, "type": "island"},
		{"center": Vector2(map_width * 0.60, map_height * 0.85), "radius": 38.0, "noise": 6.0, "peninsulas": 2, "type": "island"},
	]

	print("Hex: Creating ", landmasses.size(), " landmasses (2 large continents, 3 smaller continents, 4 islands)")

	# Generate each landmass
	for landmass in landmasses:
		var center = landmass["center"]
		var base_radius = landmass["radius"]
		var noise_scale = landmass["noise"]
		var peninsula_count = landmass["peninsulas"]

		for y in range(map_height):
			for x in range(map_width):
				# Skip if already land (prevents overlapping erasure)
				if map_data[y][x] != "water":
					continue

				# Distance from landmass center
				var dx = x - center.x
				var dy = y - center.y
				var distance = sqrt(dx * dx + dy * dy)

				# Add noise for irregular coastline
				var noise = sin(x * 0.1 + y * 0.08) * noise_scale + cos(x * 0.08 - y * 0.1) * (noise_scale * 0.8)

				# Create peninsulas and bays
				var angle = atan2(dy, dx)
				var peninsula_noise = sin(angle * float(peninsula_count)) * (noise_scale * 1.2)

				# Combined radius with noise
				var effective_radius = base_radius + noise + peninsula_noise

				# If within radius, make it land
				if distance < effective_radius:
					var grassland = grassland_types[randi() % grassland_types.size()]
					map_data[y][x] = grassland

	print("Hex: Land generation complete")

	# Place special tiles on land using optimized region sampling
	# Instead of scanning ALL tiles, we sample specific regions
	_place_special_tiles_optimized()

func _render_tiles():
	# Render tiles using TileMap API with chunk-aware batching
	# Process tiles chunk by chunk for better cache performance
	print("Hex: Starting tile render (", MapConfig.MAP_WIDTH, "x", MapConfig.MAP_HEIGHT, " = ", MapConfig.MAP_TOTAL_TILES, " tiles)")
	print("Hex: Using ", MapConfig.TOTAL_CHUNKS, " chunks (", MapConfig.CHUNKS_WIDE, "x", MapConfig.CHUNKS_TALL, ")")

	var tiles_rendered = 0

	# Render chunk by chunk for better memory locality
	for chunk_y in range(MapConfig.CHUNKS_TALL):
		for chunk_x in range(MapConfig.CHUNKS_WIDE):
			# Get chunk's top-left tile
			var chunk_start = MapConfig.chunk_to_tile(Vector2i(chunk_x, chunk_y))

			# Render all tiles in this chunk
			for local_y in range(MapConfig.CHUNK_SIZE):
				var y = chunk_start.y + local_y
				if y >= map_data.size():
					break

				for local_x in range(MapConfig.CHUNK_SIZE):
					var x = chunk_start.x + local_x
					if x >= map_data[y].size():
						break

					var tile_type = map_data[y][x]
					if tile_type in tile_type_to_source:
						var source_id = tile_type_to_source[tile_type]
						# set_cell(layer, coords, source_id, atlas_coords, alternative_tile)
						tile_map.set_cell(0, Vector2i(x, y), source_id, Vector2i(0, 0))
						tiles_rendered += 1

	print("Hex: Rendered ", tiles_rendered, " tiles across ", MapConfig.TOTAL_CHUNKS, " chunks")

# Query function to get tile at specific coordinates
func get_tile_at(x: int, y: int) -> String:
	if y >= 0 and y < map_data.size() and x >= 0 and x < map_data[y].size():
		return map_data[y][x]
	return ""

# Get tile type from TileMap coordinates
func get_tile_type_at_coords(coords: Vector2i) -> String:
	var source_id = tile_map.get_cell_source_id(0, coords)
	for tile_type in tile_type_to_source:
		if tile_type_to_source[tile_type] == source_id:
			return tile_type
	return ""

func _process(delta):
	# Get mouse position in world coordinates
	var mouse_pos = get_global_mouse_position()

	# Convert world position to tile map coordinates
	var tile_coords = tile_map.local_to_map(tile_map.to_local(mouse_pos))

	# Check if the tile coordinates changed
	if tile_coords != hovered_tile:
		hovered_tile = tile_coords
		_update_highlight()

func _update_highlight():
	# Check if there's a tile at the hovered coordinates
	var source_id = tile_map.get_cell_source_id(0, hovered_tile)

	if source_id != -1:
		# Update texture to match the hovered tile
		if source_id in tile_textures:
			# Valid tile with loaded texture - show highlight
			hex_highlight.visible = true
			hex_highlight.texture = tile_textures[source_id]

			# Convert tile coords back to world position
			var world_pos = tile_map.to_global(tile_map.map_to_local(hovered_tile))
			hex_highlight.global_position = world_pos
		else:
			# Tile exists but texture not loaded yet (cities/villages) - hide highlight
			hex_highlight.visible = false
	else:
		# No tile - hide highlight
		hex_highlight.visible = false

# Register a card placed on a tile (accepts PooledCard which is now MeshInstance2D)
func place_card_on_tile(tile_coords: Vector2i, card_sprite: Node2D, suit: int, value: int) -> bool:
	# Check if tile is already occupied (GDScript check first)
	if card_data.has(tile_coords):
		push_warning("Hex: Tile (%d, %d) is already occupied! Cannot place card." % [tile_coords.x, tile_coords.y])
		return false

	# Get card_id from the sprite (works for both standard and custom cards)
	var card_id = -1
	if card_sprite is PooledCard:
		# Access the card_id property directly from PooledCard
		card_id = card_sprite.card_id
	elif card_sprite.material and card_sprite.material is ShaderMaterial:
		# Fallback: try to get from material shader parameter
		card_id = card_sprite.material.get_shader_parameter("card_id")
		if card_id == null:
			card_id = -1

	# Determine if this is a custom card
	var is_custom = false
	if card_sprite is PooledCard:
		is_custom = card_sprite.is_custom

	# Check terrain requirements for joker cards (custom cards)
	if is_custom and card_id >= 52:
		if not _validate_joker_terrain(tile_coords, card_id):
			return false  # Terrain validation failed

	# Generate ULID for the card
	var ulid = UlidManager.register_entity(card_sprite, UlidManager.TYPE_CARD, {
		"suit": suit,
		"value": value,
		"card_id": card_id,
		"position": {"x": tile_coords.x, "y": tile_coords.y}
	})

	# Register with Rust CardRegistry (double-check on Rust side)
	var card_registry = get_node("/root/CardRegistryBridge")
	if card_registry:
		var success = card_registry.place_card(tile_coords.x, tile_coords.y, ulid, suit, value, is_custom, card_id)
		if not success:
			push_error("Hex: Failed to register card with Rust CardRegistry at (%d, %d) - tile occupied" % [tile_coords.x, tile_coords.y])
			return false

	card_data[tile_coords] = {
		"sprite": card_sprite,
		"suit": suit,
		"value": value,
		"card_id": card_id,
		"ulid": ulid
	}

	return true

# Get card data at tile coordinates
func get_card_at_tile(tile_coords: Vector2i) -> Dictionary:
	if card_data.has(tile_coords):
		return card_data[tile_coords]
	return {}

# Check if tile has a card
func has_card_at_tile(tile_coords: Vector2i) -> bool:
	return card_data.has(tile_coords)

# Validate joker card terrain requirements
# Returns true if valid, false if invalid (shows error toast)
func _validate_joker_terrain(tile_coords: Vector2i, card_id: int) -> bool:
	# Get tile terrain type
	var source_id = tile_map.get_cell_source_id(0, tile_coords)
	var is_water = (source_id == MapConfig.SOURCE_ID_WATER)
	var is_land = not is_water

	# Check terrain requirements per joker type
	match card_id:
		52:  # Viking Special - requires water
			if not is_water:
				push_warning("Hex: Viking joker requires water tile! Tile (%d, %d) is land." % [tile_coords.x, tile_coords.y])
				Toast.show_toast(I18n.translate("ui.hand.joker_requires_water"), 3.0)
				return false
		53:  # Dino Special (Jezza) - requires land
			if not is_land:
				push_warning("Hex: Jezza joker requires land tile! Tile (%d, %d) is water." % [tile_coords.x, tile_coords.y])
				Toast.show_toast(I18n.translate("ui.hand.joker_requires_land"), 3.0)
				return false
		_:
			# Unknown joker - allow placement anywhere
			push_warning("Hex: Unknown joker card_id %d, allowing placement" % card_id)

	return true

# Optimized special tile placement using chunk-based scanning
# Instead of scanning ALL tiles, we use chunk-based random sampling
# This gives good coverage without full O(n) scan
func _place_special_tiles_optimized():
	var map_width = MapConfig.MAP_WIDTH
	var map_height = MapConfig.MAP_HEIGHT

	print("Hex: Placing special tiles using optimized chunk-based sampling...")

	# Use chunk-based sampling to find land tiles efficiently
	# Sample ~10% of chunks to build a representative land tile set
	var land_tile_samples = _sample_land_tiles_by_chunks()

	if land_tile_samples.size() == 0:
		push_warning("Hex: No land tiles found for special tile placement!")
		return

	print("Hex: Sampled ", land_tile_samples.size(), " land tiles from chunk-based search")

	# Place city1 in north region (top 1/3 of map)
	var north_tiles = land_tile_samples.filter(func(t): return t.y < map_height / 3)
	if north_tiles.size() > 0:
		var city1_tile = north_tiles[randi() % north_tiles.size()]
		map_data[city1_tile.y][city1_tile.x] = "city1"
		print("Hex: Placed city1 at (", city1_tile.x, ", ", city1_tile.y, ")")

	# Place city2 in south region (bottom 1/3 of map)
	var south_tiles = land_tile_samples.filter(func(t): return t.y > map_height * 2 / 3)
	if south_tiles.size() > 0:
		var city2_tile = south_tiles[randi() % south_tiles.size()]
		map_data[city2_tile.y][city2_tile.x] = "city2"
		print("Hex: Placed city2 at (", city2_tile.x, ", ", city2_tile.y, ")")

	# Place village1 in center region (middle 1/4 of map)
	var center_x = map_width / 2
	var center_y = map_height / 2
	var quarter_width = map_width / 4
	var quarter_height = map_height / 4

	var center_tiles = land_tile_samples.filter(func(t):
		return abs(t.y - center_y) < quarter_height and abs(t.x - center_x) < quarter_width
	)
	if center_tiles.size() > 0:
		var village1_tile = center_tiles[randi() % center_tiles.size()]
		map_data[village1_tile.y][village1_tile.x] = "village1"
		print("Hex: Placed village1 at (", village1_tile.x, ", ", village1_tile.y, ")")

	print("Hex: Special tile placement complete")

# Sample land tiles using chunk-based approach
# Only scans a subset of chunks to build representative sample
# Much faster than full map scan: O(sample_size) instead of O(map_size)
func _sample_land_tiles_by_chunks() -> Array[Vector2i]:
	var land_tiles: Array[Vector2i] = []

	# Sample 10% of chunks (1024 total chunks -> ~100 sampled)
	var chunks_to_sample = max(100, MapConfig.TOTAL_CHUNKS / 10)
	var chunk_width = MapConfig.CHUNKS_WIDE
	var chunk_height = MapConfig.CHUNKS_TALL

	for i in range(chunks_to_sample):
		# Random chunk
		var chunk_x = randi() % chunk_width
		var chunk_y = randi() % chunk_height

		# Get chunk's top-left tile position
		var chunk_start = MapConfig.chunk_to_tile(Vector2i(chunk_x, chunk_y))

		# Sample a few tiles from this chunk (not all 32x32)
		var samples_per_chunk = 10
		for j in range(samples_per_chunk):
			var local_x = randi() % MapConfig.CHUNK_SIZE
			var local_y = randi() % MapConfig.CHUNK_SIZE

			var x = chunk_start.x + local_x
			var y = chunk_start.y + local_y

			# Check bounds
			if y < map_data.size() and x < map_data[y].size():
				# If land, add to samples
				if map_data[y][x] != "water":
					land_tiles.append(Vector2i(x, y))

	return land_tiles
