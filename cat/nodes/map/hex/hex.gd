extends Node2D

# Hexmap scene using CustomTileRenderer (MultiMeshInstance2D + UV shader)
# Replaces TileMap for ~50-70% better performance

@onready var tile_renderer: CustomTileRenderer = $CustomTileRenderer
@onready var hex_highlight: Sprite2D = $HexHighlight

# Backward compatibility wrapper - exposes tile_renderer as tile_map
# Provides TileMap-compatible API for existing code
class TileMapCompat extends RefCounted:
	var renderer: CustomTileRenderer
	var parent_hex: Node2D  # Reference to parent Hex node

	# Fake TileSet for compatibility
	class FakeTileSet:
		var tile_size: Vector2 = Vector2(32, 28)  # Hex tile size

	var tile_set: FakeTileSet = FakeTileSet.new()

	func _init(r: CustomTileRenderer):
		renderer = r

	func local_to_map(local_pos: Vector2) -> Vector2i:
		return renderer.world_to_tile(local_pos)

	func map_to_local(map_coords: Vector2i) -> Vector2:
		return renderer._tile_to_world_pos(map_coords)

	func get_cell_source_id(layer: int, coords: Vector2i) -> int:
		# Get tile index from parent's get_tile_type_at_coords (now returns int)
		if not parent_hex:
			return -1
		var tile_index = parent_hex.get_tile_type_at_coords(coords)
		# tile_index: 0 = water, 1-6 = grassland variants
		# Return tile_index directly (it IS the source_id)
		return tile_index

	func get_parent() -> Node:
		# Return the parent of the renderer (which is the Hex node)
		return parent_hex

var tile_map: TileMapCompat

# Tile type to tile_index mapping (matches atlas order)
var tile_type_to_index = {
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

# Card data - stores cards placed on tiles
var card_data: Dictionary = {}  # tile_coords -> {sprite, suit, value}

# Current hovered tile coordinates
var hovered_tile: Vector2i = Vector2i(-1, -1)

# Camera reference for chunk culling
var camera: Camera2D = null

# References to managers
var chunk_manager = null  # ChunkManager reference
var chunk_pool: ChunkPool = null  # ChunkPool instance

# Rust world generator
var world_generator = null  # WorldGenerator instance (from Rust)

# Track which chunks are currently rendered
var rendered_chunks: Dictionary = {}  # chunk_coords (Vector2i) -> Array[MultiMeshInstance2D]

# Chunk rendering settings
var chunk_render_distance: int = MapConfig.CHUNK_RENDER_DISTANCE
var last_camera_chunk: Vector2i = Vector2i(-999, -999)  # Track which chunk camera was in

# Performance optimization settings
var max_chunks_per_frame: int = 8  # Limit chunk renders per frame to avoid lag spikes (increased for smoother loading)
var max_chunk_generations_per_frame: int = 2  # Limit chunk generations per frame to avoid blocking
var chunk_render_queue: Array = []  # Queue for deferred chunk rendering
var chunk_generation_queue: Array = []  # Queue for deferred chunk generation

# Signal emitted when initial chunks around camera are fully rendered
signal initial_chunks_ready()
var initial_chunks_loaded: bool = false

func _ready():
	# Initialize backward-compatible tile_map wrapper
	tile_map = TileMapCompat.new(tile_renderer)
	tile_map.parent_hex = self

	# Initialize ChunkPool
	chunk_pool = ChunkPool.new()
	add_child(chunk_pool)

	# Initialize Rust WorldGenerator
	world_generator = ClassDB.instantiate("WorldGenerator")
	if world_generator:
		world_generator.set_seed(MapConfig.world_seed)
		print("Hex: WorldGenerator initialized with seed: ", MapConfig.world_seed)
	else:
		push_error("Hex: Failed to instantiate WorldGenerator! Make sure Rust extension is loaded.")

	print("Hex: Infinite world initialized. Chunks will generate on-demand.")

## Set chunk manager reference and connect signals
func set_chunk_manager(manager) -> void:
	chunk_manager = manager
	if chunk_manager:
		chunk_manager.chunk_requested.connect(_on_chunk_requested)
		print("Hex: ChunkManager connected")

## Handle chunk generation requests from ChunkManager
func _on_chunk_requested(chunk_coords: Vector2i) -> void:
	if not world_generator:
		push_error("Hex: Cannot generate chunk - WorldGenerator not initialized!")
		return

	# Check if already loaded or queued
	if chunk_pool.is_chunk_loaded(chunk_coords):
		return

	# Check if already in generation queue
	for queued_chunk in chunk_generation_queue:
		if queued_chunk == chunk_coords:
			return

	# Add to generation queue
	chunk_generation_queue.append(chunk_coords)

## Generate a single chunk (called from queue processor)
func _generate_chunk(chunk_coords: Vector2i) -> void:
	# Generate chunk using Rust (source of truth - uses hex grid coordinates)
	var tile_data = world_generator.generate_chunk(chunk_coords.x, chunk_coords.y)

	if not tile_data or tile_data.size() != MapConfig.CHUNK_SIZE * MapConfig.CHUNK_SIZE:
		push_error("Hex: Chunk generation failed for %s" % chunk_coords)
		return

	# Load into pool
	var chunk = chunk_pool.load_chunk(chunk_coords, tile_data)

	# Load chunk into pathfinding terrain caches (for both ship and NPC pathfinding)
	if has_node("/root/ShipPathfindingBridge"):
		get_node("/root/ShipPathfindingBridge").load_chunk(chunk_coords, tile_data)
	if has_node("/root/NpcPathfindingBridge"):
		get_node("/root/NpcPathfindingBridge").load_chunk(chunk_coords, tile_data)

	# Queue for rendering
	chunk_render_queue.append({
		"chunk_coords": chunk_coords,
		"render": true
	})

	print("Hex: Chunk %s generated and queued for render (%d tiles)" % [chunk_coords, tile_data.size()])

func _process(delta: float) -> void:
	# OPTIMIZATION: Process queued chunk generation (limit per frame to avoid lag spikes)
	_process_chunk_generation_queue()

	# OPTIMIZATION: Process queued chunk renders (limit per frame to avoid lag spikes)
	_process_chunk_queue()

	# NOTE: Chunk visibility updates are now handled by ChunkManager.update_visible_chunks()
	# which is called from main.gd's _process() function

	# Handle mouse hover highlight
	var mouse_pos = get_global_mouse_position()
	var tile_coords = tile_renderer.world_to_tile(mouse_pos)

	if tile_coords != hovered_tile:
		hovered_tile = tile_coords
		_update_highlight()

## Process queued chunk generation to spread work across frames
func _process_chunk_generation_queue() -> void:
	var chunks_generated_this_frame = 0

	while chunk_generation_queue.size() > 0 and chunks_generated_this_frame < max_chunk_generations_per_frame:
		var chunk_coords = chunk_generation_queue.pop_front()
		_generate_chunk(chunk_coords)
		chunks_generated_this_frame += 1

## Process queued chunk renders to spread work across frames
func _process_chunk_queue() -> void:
	var chunks_rendered_this_frame = 0

	while chunk_render_queue.size() > 0 and chunks_rendered_this_frame < max_chunks_per_frame:
		var chunk_data = chunk_render_queue.pop_front()
		var render = chunk_data["render"]

		# Get chunk coordinates
		if not chunk_data.has("chunk_coords"):
			push_error("Hex: Invalid chunk_data format - missing chunk_coords")
			continue

		var chunk_coords: Vector2i = chunk_data["chunk_coords"]

		if render:
			_render_chunk_immediate(chunk_coords)
		else:
			_unrender_chunk_immediate(chunk_coords)

		chunks_rendered_this_frame += 1

	# Check if initial chunks are done loading
	if not initial_chunks_loaded and chunk_render_queue.size() == 0 and rendered_chunks.size() > 0:
		initial_chunks_loaded = true
		print("Hex: Initial chunks loaded (%d chunks rendered). Emitting initial_chunks_ready signal." % rendered_chunks.size())
		initial_chunks_ready.emit()

## Set the camera reference for chunk culling
func set_camera(cam: Camera2D) -> void:
	camera = cam
	if camera:
		var camera_tile = tile_renderer.world_to_tile(camera.global_position)
		last_camera_chunk = MapConfig.tile_to_chunk(camera_tile)
		print("Hex: Camera reference set at position ", camera.global_position)
		print("Hex: Camera in chunk ", last_camera_chunk)
		print("Hex: Enabling camera-based chunk culling with render distance: ", chunk_render_distance, " chunks")
		# NOTE: Chunk rendering is now handled by ChunkManager via chunk_requested signals
		# The old _update_visible_chunks() is no longer used for initial rendering
	else:
		push_warning("Hex: Camera is null, cannot render chunks!")

# LEGACY FUNCTIONS REMOVED - Chunk visibility now handled by ChunkManager
# Old _update_visible_chunks() and _is_in_queue() removed in favor of signal-based system

## Render a specific chunk by index (immediate, used by queue processor)
## Render a chunk immediately (called from queue processor)
func _render_chunk_immediate(chunk_coords: Vector2i) -> void:
	# Get chunk data from pool
	var chunk = chunk_pool.get_chunk(chunk_coords)
	if not chunk:
		push_error("Hex: Cannot render chunk %s - not loaded in pool!" % chunk_coords)
		return

	var chunk_start = MapConfig.chunk_to_tile(chunk_coords)
	var tile_data_array = []

	# Debug: Count terrain types in received data
	var water_count = 0
	var land_count = 0

	# Convert chunk terrain_data to render format (int-based)
	for tile_dict in chunk.terrain_data:
		var local_x = tile_dict["x"]
		var local_y = tile_dict["y"]
		var tile_index = tile_dict["tile_index"]  # Atlas index: 0-3,5-6 = grassland, 4 = water

		# Count terrain types (atlas index 4 = water)
		if tile_index == 4:
			water_count += 1
		else:
			land_count += 1

		# Calculate world tile coordinates
		var world_x = chunk_start.x + local_x
		var world_y = chunk_start.y + local_y

		# Skip water tiles (atlas index 4) - they're transparent, water shader shows underneath
		if tile_index == 4:
			continue

		tile_data_array.append({
			"x": world_x,
			"y": world_y,
			"tile_index": tile_index,
			"flip_flags": 0  # No flipping for now
		})

	print("Hex: Chunk %s - Received Water: %d, Land: %d, Rendering: %d tiles" % [chunk_coords, water_count, land_count, tile_data_array.size()])

	# Render chunk via CustomTileRenderer (using a unique chunk index)
	# For infinite world, we'll use a hash of chunk coords as the index
	var chunk_hash = _chunk_coords_to_hash(chunk_coords)
	tile_renderer.render_chunk(chunk_hash, tile_data_array)

	# Track as rendered
	rendered_chunks[chunk_coords] = true

## Unrender a specific chunk by coordinates (immediate)
func _unrender_chunk_immediate(chunk_coords: Vector2i) -> void:
	var chunk_hash = _chunk_coords_to_hash(chunk_coords)
	tile_renderer.unrender_chunk(chunk_hash)
	rendered_chunks.erase(chunk_coords)
	print("Hex: Unrendered chunk %s" % chunk_coords)

## Convert chunk coordinates to a unique hash for renderer indexing
func _chunk_coords_to_hash(chunk_coords: Vector2i) -> int:
	# Simple hash: combine x and y with bitwise operations
	# This works for infinite coordinates (positive and negative)
	return (chunk_coords.y << 16) | (chunk_coords.x & 0xFFFF)

## Helper function to convert terrain string to tile index
# Query function to get tile at specific coordinates (queries chunk pool)
# Returns atlas tile_index (int): 0-3,5-6 = grassland variants, 4 = water
func get_tile_at(x: int, y: int) -> int:
	if not world_generator:
		return 4  # Default to water if no generator (atlas index 4)

	# Get proper world position using tile renderer's conversion (accounts for hex staggering)
	var world_pos = tile_renderer._tile_to_world_pos(Vector2i(x, y))
	return world_generator.get_terrain_at(world_pos.x, world_pos.y)

# Get tile type from coordinates
# Returns atlas tile_index (int): 0-3,5-6 = grassland variants, 4 = water
func get_tile_type_at_coords(coords: Vector2i) -> int:
	return get_tile_at(coords.x, coords.y)

func _update_highlight():
	# Get tile index at hovered coordinates (atlas index: 0-3,5-6 = grassland, 4 = water)
	var tile_index = get_tile_type_at_coords(hovered_tile)

	# Valid tile with loaded texture - show highlight
	if tile_index >= 0 and tile_index in tile_textures:
		hex_highlight.visible = true
		hex_highlight.texture = tile_textures[tile_index]

		# Convert tile coords to world position
		var world_pos = tile_renderer._tile_to_world_pos(hovered_tile)
		hex_highlight.global_position = world_pos

		# Set z-index above tiles but below entities
		hex_highlight.z_index = hovered_tile.y + Cache.Z_INDEX_HEX_HIGHLIGHT_OFFSET

		# Keep sprite centered (default for Sprite2D)
		hex_highlight.centered = true
	else:
		# No tile or texture not loaded - hide highlight
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
		card_id = card_sprite.card_id
	elif card_sprite.material and card_sprite.material is ShaderMaterial:
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
func _validate_joker_terrain(tile_coords: Vector2i, card_id: int) -> bool:
	var tile_index = get_tile_type_at_coords(tile_coords)
	# Atlas index 4 = water, all others (0-3, 5-6) = grassland variants
	var is_water = (tile_index == 4)
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
			push_warning("Hex: Unknown joker card_id %d, allowing placement" % card_id)

	return true

# Optimized special tile placement using chunk-based scanning
# OLD FUNCTIONS REMOVED - Special tiles now handled in procedural generation
