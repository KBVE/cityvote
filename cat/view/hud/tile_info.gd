extends PanelContainer
class_name TileInfo

@onready var coordinates_label: Label = $MarginContainer/VBoxContainer/CoordinatesLabel
@onready var tile_type_label: Label = $MarginContainer/VBoxContainer/TileTypeLabel
@onready var world_pos_label: Label = $MarginContainer/VBoxContainer/WorldPosLabel
@onready var card_label: Label = $MarginContainer/VBoxContainer/CardLabel
@onready var card_ghost: TextureRect = $CardGhost

# Reference to hex map
var hex_map = null

func _ready() -> void:
	# Start visible for testing
	visible = true

	# Hide card ghost initially
	card_ghost.visible = false

	# Apply Alagard font to all labels
	_apply_fonts()

func _process(_delta: float) -> void:
	if hex_map == null:
		return

	# Get mouse position relative to the viewport, then convert to world coordinates
	var viewport = get_viewport()
	var mouse_screen_pos = viewport.get_mouse_position()

	# Get the camera to convert screen to world coordinates
	var camera = hex_map.get_parent().get_node("Camera2D")
	if camera == null:
		return

	# Convert screen position to world position accounting for camera
	var mouse_world_pos = mouse_screen_pos / camera.zoom + camera.position - (viewport.get_visible_rect().size / camera.zoom / 2)

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

	# Get tile type from hex map
	var tile_type = hex_map.get_tile_type_at_coords(tile_coords)
	var display_name = get_tile_display_name(tile_type)
	tile_type_label.text = "Type: %s" % display_name

	# Update world position
	world_pos_label.text = "World: (%.0f, %.0f)" % [world_pos.x, world_pos.y]

	# Check if tile has a card
	if hex_map.has_card_at_tile(tile_coords):
		var card_data = hex_map.get_card_at_tile(tile_coords)
		_show_card_info(card_data)
	else:
		_hide_card_info()

func get_tile_display_name(tile_type: String) -> String:
	if tile_type.begins_with("grassland"):
		return "Grassland"
	elif tile_type == "water":
		return "Water"
	elif tile_type.begins_with("city"):
		return "City"
	elif tile_type.begins_with("village"):
		return "Village"
	else:
		return tile_type.capitalize()

func _apply_fonts() -> void:
	# Get Alagard font from Cache
	var font = Cache.get_font("alagard")
	if font == null:
		push_warning("TileInfo: Could not load Alagard font from Cache")
		return

	# Apply font to all labels
	var title_label = $MarginContainer/VBoxContainer/TitleLabel
	title_label.add_theme_font_override("font", font)

	coordinates_label.add_theme_font_override("font", font)
	tile_type_label.add_theme_font_override("font", font)
	world_pos_label.add_theme_font_override("font", font)
	card_label.add_theme_font_override("font", font)

func _show_card_info(card_data: Dictionary) -> void:
	# Show card ghost image
	if card_data.has("sprite"):
		var sprite = card_data["sprite"]
		card_ghost.texture = sprite.texture
		card_ghost.visible = true
		card_ghost.modulate = Color(1, 1, 1, 0.8)  # Slightly transparent

	# Show card name
	var card_name = get_card_name(card_data.suit, card_data.value)
	card_label.text = "Card: %s" % card_name
	card_label.visible = true

func _hide_card_info() -> void:
	card_ghost.visible = false
	card_label.text = "Card: --"

func get_card_name(suit: int, value: int) -> String:
	var suit_name = ""
	match suit:
		0:  # Spades
			suit_name = "Spades"
		1:  # Hearts
			suit_name = "Hearts"
		2:  # Diamonds
			suit_name = "Diamonds"
		3:  # Clubs
			suit_name = "Clubs"

	var value_name = ""
	match value:
		1:
			value_name = "Ace"
		11:
			value_name = "Jack"
		12:
			value_name = "Queen"
		13:
			value_name = "King"
		_:
			value_name = str(value)

	return "%s of %s" % [value_name, suit_name]
