extends PanelContainer
class_name TileInfo

@onready var coordinates_label: Label = $MarginContainer/VBoxContainer/CoordinatesLabel
@onready var tile_type_label: Label = $MarginContainer/VBoxContainer/TileTypeLabel
@onready var world_pos_label: Label = $MarginContainer/VBoxContainer/WorldPosLabel
@onready var card_label: Label = $MarginContainer/VBoxContainer/CardLabel
@onready var ulid_label: Label = $MarginContainer/VBoxContainer/ULIDLabel

# CardGhost is a pooled card for displaying card preview
var card_ghost = null  # PooledCard instance

# Reference to hex map
var hex_map = null

func _ready() -> void:
	# Start visible for testing
	visible = true

	# Connect to language change signal
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

	# Create a pooled card for the ghost preview (reused, not destroyed)
	card_ghost = Cluster.acquire("playing_card")
	if card_ghost:
		# Mark as dynamic - this card needs to update frequently via shader parameters
		card_ghost.is_dynamic = true

		# Add as sibling to match the old CardGhost position (deferred to avoid setup conflicts)
		get_parent().call_deferred("add_child", card_ghost)
		card_ghost.name = "CardGhost"
		card_ghost.position = Vector2(1155, 485)  # Center of old TextureRect (1110+45, 440+45)
		card_ghost.scale = Vector2(0.94, 0.94)  # Scale to fit ~90px (96 * 0.94)
		card_ghost.z_index = 101
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

	# Check if tile is valid using MapConfig
	if MapConfig.is_tile_in_bounds(tile_coords):
		# Valid tile - show info
		visible = true
		update_tile_info(tile_coords, mouse_world_pos)
	else:
		# Outside map - hide
		visible = false

func update_tile_info(tile_coords: Vector2i, world_pos: Vector2) -> void:
	# Update coordinates
	var coords_label = I18n.translate("tile_info.coords")
	coordinates_label.text = "%s: (%d, %d)" % [coords_label, tile_coords.x, tile_coords.y]

	# Get tile type from hex map
	var tile_type = hex_map.get_tile_type_at_coords(tile_coords)
	var display_name = get_tile_display_name(tile_type)
	var type_label = I18n.translate("tile_info.type")
	tile_type_label.text = "%s: %s" % [type_label, display_name]

	# Update world position
	var world_label = I18n.translate("tile_info.world")
	world_pos_label.text = "%s: (%.0f, %.0f)" % [world_label, world_pos.x, world_pos.y]

	# Check if tile has a card
	if hex_map.has_card_at_tile(tile_coords):
		var card_data = hex_map.get_card_at_tile(tile_coords)
		_show_card_info(card_data)
	else:
		_hide_card_info()

func get_tile_display_name(tile_type: String) -> String:
	if tile_type.begins_with("grassland"):
		return I18n.translate("tile.grassland")
	elif tile_type == "water":
		return I18n.translate("tile.water")
	elif tile_type.begins_with("city"):
		return I18n.translate("tile.city")
	elif tile_type.begins_with("village"):
		return I18n.translate("tile.village")
	else:
		return tile_type.capitalize()

func _apply_fonts() -> void:
	# Get Alagard font from Cache
	var font = Cache.get_font_for_current_language()
	if font == null:
		push_warning("TileInfo: Could not load Alagard font from Cache")
		return

	# Apply font to all labels and update title text
	var title_label = $MarginContainer/VBoxContainer/TitleLabel
	title_label.add_theme_font_override("font", font)
	title_label.text = I18n.translate("tile_info.title")

	coordinates_label.add_theme_font_override("font", font)
	tile_type_label.add_theme_font_override("font", font)
	world_pos_label.add_theme_font_override("font", font)
	card_label.add_theme_font_override("font", font)
	ulid_label.add_theme_font_override("font", font)

func _on_language_changed(_new_language: int) -> void:
	# Refresh fonts when language changes
	_apply_fonts()
	# Note: The labels will update automatically through update_tile_info()
	# which is called every frame in _process()

func _show_card_info(card_data: Dictionary) -> void:
	# Show card ghost image using PooledCard
	if card_ghost and card_data.has("card_id") and card_data["card_id"] != null:
		var card_id = card_data["card_id"]

		# Set shader parameter on the duplicated material (not instance parameter)
		if card_ghost.material and card_ghost.material is ShaderMaterial:
			card_ghost.material.set_shader_parameter("card_id", card_id)

		card_ghost.visible = true
		card_ghost.modulate = Color(1, 1, 1, 0.8)  # Slightly transparent

	# Show card name
	var card_name = get_card_name_from_data(card_data)
	var card_label_text = I18n.translate("tile_info.card")
	card_label.text = "%s: %s" % [card_label_text, card_name]
	card_label.visible = true

	# Show ULID if available
	var ulid_label_text = I18n.translate("tile_info.ulid")
	if card_data.has("ulid"):
		var ulid_hex = UlidManager.to_hex(card_data["ulid"])
		# Show abbreviated ULID (first 8 chars)
		ulid_label.text = "%s: %s..." % [ulid_label_text, ulid_hex.substr(0, 8)]
		ulid_label.visible = true
	else:
		ulid_label.text = "%s: --" % ulid_label_text
		ulid_label.visible = true

func get_card_name_from_data(card_data: Dictionary) -> String:
	# Use card_id if available for accurate naming (handles custom cards)
	if card_data.has("card_id"):
		var card_id = card_data["card_id"]
		if card_id == CardAtlas.CARD_VIKINGS:
			return I18n.translate("card.custom.viking")
		elif card_id == CardAtlas.CARD_DINO:
			return I18n.translate("card.custom.dino")
		elif card_id >= 0 and card_id < CardAtlas.STANDARD_CARD_COUNT:
			# Calculate suit and value from card_id
			var suit = card_id / CardAtlas.CARDS_PER_SUIT
			var value = (card_id % CardAtlas.CARDS_PER_SUIT) + 1
			return get_card_name(suit, value)

	# Fallback to suit/value if card_id not available
	if card_data.has("suit") and card_data.has("value"):
		return get_card_name(card_data["suit"], card_data["value"])

	return I18n.translate("card.custom.generic")

func _hide_card_info() -> void:
	if card_ghost:
		card_ghost.visible = false
	var card_label_text = I18n.translate("tile_info.card")
	var ulid_label_text = I18n.translate("tile_info.ulid")
	card_label.text = "%s: --" % card_label_text
	ulid_label.text = "%s: --" % ulid_label_text

func get_card_name(suit: int, value: int) -> String:
	# Check if it's a custom card (suit = -1, value = -1)
	if suit == -1 and value == -1:
		return I18n.translate("card.custom.generic")

	var suit_name = ""
	match suit:
		0:  # Clubs
			suit_name = I18n.translate("card.suit.clubs")
		1:  # Diamonds
			suit_name = I18n.translate("card.suit.diamonds")
		2:  # Hearts
			suit_name = I18n.translate("card.suit.hearts")
		3:  # Spades
			suit_name = I18n.translate("card.suit.spades")

	var value_name = ""
	match value:
		1:
			value_name = I18n.translate("card.value.ace")
		11:
			value_name = I18n.translate("card.value.jack")
		12:
			value_name = I18n.translate("card.value.queen")
		13:
			value_name = I18n.translate("card.value.king")
		_:
			value_name = str(value)

	# Handle Chinese language which doesn't use "of"
	var of_text = I18n.translate("card.of")
	if of_text == "":
		return "%s%s" % [value_name, suit_name]
	else:
		return "%s %s %s" % [value_name, of_text, suit_name]
