extends Node2D

# Hexmap scene using TileMap

@onready var tile_map: TileMap = $TileMap
@onready var hex_highlight: Sprite2D = $HexHighlight

# Tile type to source_id mapping (matches TileSet sources)
var tile_type_to_source = {
	"grassland0": 0,
	"grassland1": 1,
	"grassland2": 2,
	"grassland3": 3
}

# Preload tile textures for highlight
var tile_textures = {
	0: preload("res://nodes/map/hex/grassland0/grassland0.png"),
	1: preload("res://nodes/map/hex/grassland1/grassland1.png"),
	2: preload("res://nodes/map/hex/grassland2/grassland2.png"),
	3: preload("res://nodes/map/hex/grassland3/grassland3.png")
}

# Map data - stores tile type names
var map_data = []

# Current hovered tile coordinates
var hovered_tile: Vector2i = Vector2i(-1, -1)

func _ready():
	# Initialize a simple test map
	_generate_test_map()
	_render_tiles()

func _generate_test_map():
	# Create a 10x10 test grid with all 4 tile types
	var tile_types = ["grassland0", "grassland1", "grassland2", "grassland3"]
	for y in range(10):
		var row = []
		for x in range(10):
			# Use different patterns to show all tiles
			var tile_index = (x + y * 2) % 4
			var tile_type = tile_types[tile_index]
			row.append(tile_type)
		map_data.append(row)

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
		# Valid tile - show highlight with correct texture
		hex_highlight.visible = true

		# Update texture to match the hovered tile
		if source_id in tile_textures:
			hex_highlight.texture = tile_textures[source_id]

		# Convert tile coords back to world position
		var world_pos = tile_map.to_global(tile_map.map_to_local(hovered_tile))
		hex_highlight.global_position = world_pos
	else:
		# No tile - hide highlight
		hex_highlight.visible = false
