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
	# Create a 50x50 map with larger water border and varied content
	var grassland_types = ["grassland0", "grassland1", "grassland2", "grassland3", "grassland4", "grassland5"]
	var map_width = 50
	var map_height = 50
	var water_margin = 12  # Thicker water border

	# Initialize with water everywhere first
	for y in range(map_height):
		var row = []
		for x in range(map_width):
			row.append("water")
		map_data.append(row)

	# Fill land area with random grasslands
	for y in range(water_margin, map_height - water_margin):
		for x in range(water_margin, map_width - water_margin):
			var grassland = grassland_types[randi() % grassland_types.size()]
			map_data[y][x] = grassland

	# Place special tiles (1 of each city, 1 village)
	var land_width = map_width - water_margin * 2
	var land_height = map_height - water_margin * 2

	# Place city1 (upper left quadrant)
	var city1_x = water_margin + randi() % int(land_width / 2.0)
	var city1_y = water_margin + randi() % int(land_height / 2.0)
	map_data[city1_y][city1_x] = "city1"

	# Place city2 (lower right quadrant)
	var city2_x = water_margin + int(land_width / 2.0) + randi() % int(land_width / 2.0)
	var city2_y = water_margin + int(land_height / 2.0) + randi() % int(land_height / 2.0)
	map_data[city2_y][city2_x] = "city2"

	# Place village1 (center area)
	var village_x = water_margin + int(land_width / 4.0) + randi() % int(land_width / 2.0)
	var village_y = water_margin + int(land_height / 4.0) + randi() % int(land_height / 2.0)
	map_data[village_y][village_x] = "village1"

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

# Register a card placed on a tile
func place_card_on_tile(tile_coords: Vector2i, card_sprite: Sprite2D, suit: int, value: int) -> void:
	card_data[tile_coords] = {
		"sprite": card_sprite,
		"suit": suit,
		"value": value
	}

# Get card data at tile coordinates
func get_card_at_tile(tile_coords: Vector2i) -> Dictionary:
	if card_data.has(tile_coords):
		return card_data[tile_coords]
	return {}

# Check if tile has a card
func has_card_at_tile(tile_coords: Vector2i) -> bool:
	return card_data.has(tile_coords)
