extends PanelContainer
class_name TileInfo

@onready var coordinates_label: Label = $MarginContainer/VBoxContainer/CoordinatesLabel
@onready var tile_type_label: Label = $MarginContainer/VBoxContainer/TileTypeLabel
@onready var world_pos_label: Label = $MarginContainer/VBoxContainer/WorldPosLabel

# Reference to hex map
var hex_map = null

func _ready() -> void:
	# Start hidden
	visible = false

func _process(_delta: float) -> void:
	if hex_map == null:
		return

	# Get mouse position in world coordinates
	var mouse_world_pos = hex_map.get_global_mouse_position()

	# Convert to tile coordinates
	var tile_coords = hex_map.tile_map.local_to_map(mouse_world_pos)

	# Check if tile is valid (within bounds)
	if tile_coords.x >= 0 and tile_coords.x < 50 and tile_coords.y >= 0 and tile_coords.y < 50:
		# Valid tile - show info
		visible = true
		update_tile_info(tile_coords, mouse_world_pos)
	else:
		# Outside map - hide
		visible = false

func update_tile_info(tile_coords: Vector2i, world_pos: Vector2) -> void:
	# Update coordinates
	coordinates_label.text = "Coords: (%d, %d)" % [tile_coords.x, tile_coords.y]

	# Get tile type from tilemap
	var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)
	var tile_type = get_tile_type_name(source_id)
	tile_type_label.text = "Type: %s" % tile_type

	# Update world position
	world_pos_label.text = "World: (%.0f, %.0f)" % [world_pos.x, world_pos.y]

func get_tile_type_name(source_id: int) -> String:
	match source_id:
		0:
			return "Grass"
		1:
			return "Forest"
		2:
			return "Mountain"
		3:
			return "Desert"
		4:
			return "Water"
		5:
			return "Snow"
		_:
			return "Unknown"
