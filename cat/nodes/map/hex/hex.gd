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

	# Create organic island using distance from center with noise
	var center_x = map_width / 2.0
	var center_y = map_height / 2.0
	var base_radius = MapConfig.ISLAND_BASE_RADIUS

	for y in range(map_height):
		for x in range(map_width):
			# Distance from center
			var dx = x - center_x
			var dy = y - center_y
			var distance = sqrt(dx * dx + dy * dy)

			# Add noise for irregular coastline
			# Use position-based pseudo-random for consistent generation
			var noise = sin(x * 0.5 + y * 0.3) * 3.0 + cos(x * 0.3 - y * 0.4) * 2.5

			# Create some peninsulas and bays
			var angle = atan2(dy, dx)
			var peninsula_noise = sin(angle * float(MapConfig.PENINSULA_COUNT)) * 4.0

			# Combined radius with noise
			var effective_radius = base_radius + noise + peninsula_noise

			# If within radius, make it land
			if distance < effective_radius:
				var grassland = grassland_types[randi() % grassland_types.size()]
				map_data[y][x] = grassland

	# Place special tiles on land (find valid land tiles first)
	var land_tiles = []
	for y in range(map_height):
		for x in range(map_width):
			if map_data[y][x] != "water":
				land_tiles.append(Vector2i(x, y))

	if land_tiles.size() >= 3:
		# Place city1 (northern part of island)
		var north_tiles = land_tiles.filter(func(t): return t.y < map_height / 3)
		if north_tiles.size() > 0:
			var city1_tile = north_tiles[randi() % north_tiles.size()]
			map_data[city1_tile.y][city1_tile.x] = "city1"

		# Place city2 (southern part of island)
		var south_tiles = land_tiles.filter(func(t): return t.y > map_height * 2 / 3)
		if south_tiles.size() > 0:
			var city2_tile = south_tiles[randi() % south_tiles.size()]
			map_data[city2_tile.y][city2_tile.x] = "city2"

		# Place village1 (center of island)
		var center_tiles = land_tiles.filter(func(t): return abs(t.y - center_y) < map_height / 4 and abs(t.x - center_x) < map_width / 4)
		if center_tiles.size() > 0:
			var village_tile = center_tiles[randi() % center_tiles.size()]
			map_data[village_tile.y][village_tile.x] = "village1"

func _render_tiles():
	# Render tiles using TileMap API
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			var tile_type = map_data[y][x]
			if tile_type in tile_type_to_source:
				var source_id = tile_type_to_source[tile_type]
				# set_cell(layer, coords, source_id, atlas_coords, alternative_tile)
				tile_map.set_cell(0, Vector2i(x, y), source_id, Vector2i(0, 0))

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
func place_card_on_tile(tile_coords: Vector2i, card_sprite: Node2D, suit: int, value: int) -> void:
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

	# Generate ULID for the card
	var ulid = UlidManager.register_entity(card_sprite, UlidManager.TYPE_CARD, {
		"suit": suit,
		"value": value,
		"card_id": card_id,
		"position": {"x": tile_coords.x, "y": tile_coords.y}
	})

	# Determine if this is a custom card
	var is_custom = false
	if card_sprite is PooledCard:
		is_custom = card_sprite.is_custom

	# Register with Rust CardRegistry
	var card_registry = get_node("/root/CardRegistryBridge")
	if card_registry:
		var success = card_registry.place_card(tile_coords.x, tile_coords.y, ulid, suit, value, is_custom, card_id)
		if not success:
			push_error("Hex: Failed to register card with Rust CardRegistry at (%d, %d)" % [tile_coords.x, tile_coords.y])

	card_data[tile_coords] = {
		"sprite": card_sprite,
		"suit": suit,
		"value": value,
		"card_id": card_id,
		"ulid": ulid
	}

# Get card data at tile coordinates
func get_card_at_tile(tile_coords: Vector2i) -> Dictionary:
	if card_data.has(tile_coords):
		return card_data[tile_coords]
	return {}

# Check if tile has a card
func has_card_at_tile(tile_coords: Vector2i) -> bool:
	return card_data.has(tile_coords)
