extends Node

## ChunkManager - Manages chunk visibility, fog of war, and culling
## Tracks which chunks are visible, explored, and actively rendered

## Signals
signal chunk_revealed(chunk_coords: Vector2i)
signal chunk_hidden(chunk_coords: Vector2i)
signal visible_chunks_changed(visible_chunk_indices: Array)

## Chunk visibility flags (bitwise)
const FLAG_EXPLORED: int = 1 << 0  # 0b001 - Chunk has been explored
const FLAG_VISIBLE: int = 1 << 1   # 0b010 - Chunk is currently visible
const FLAG_REVEALED: int = 1 << 2  # 0b100 - Chunk is revealed (fog disabled)

## Chunk state tracking (100 chunks, indexed 0-99)
## Each byte stores bitwise flags for chunk state
var chunk_states: PackedByteArray = PackedByteArray()

## Helper enum for readability (but we use bitwise ops)
enum ChunkState {
	HIDDEN = 0,                          # 0b000 - Never explored
	EXPLORED = FLAG_EXPLORED,            # 0b001 - Explored but not visible
	VISIBLE = FLAG_EXPLORED | FLAG_VISIBLE,  # 0b011 - Explored and visible
	REVEALED = FLAG_EXPLORED | FLAG_VISIBLE | FLAG_REVEALED  # 0b111 - Fully revealed
}

## Currently visible chunks based on camera position
var visible_chunk_indices: Array = []

## Fog of war enabled (disabled for debugging)
var fog_of_war_enabled: bool = false

## Chunk culling enabled (performance optimization)
var chunk_culling_enabled: bool = true

## Statistics for debugging
var culled_entities_count: int = 0
var active_entities_count: int = 0

## How many chunks around camera to render
var render_radius: int = 2  # Render 2 chunks in each direction from camera

## Last camera chunk position (to avoid recalculating every frame)
var last_camera_chunk: Vector2i = Vector2i(-1, -1)

## References
var camera: Camera2D = null
var tile_map = null  # TileMapCompat wrapper for CustomTileRenderer
var fog_overlay_parent: Node2D = null  # Parent node for fog overlay rects

## Fog overlay rects (one per chunk)
var fog_overlays: Array = []  # Array of ColorRect nodes

func _ready():
	# Initialize all chunks as HIDDEN (0b000)
	chunk_states.resize(MapConfig.TOTAL_CHUNKS)
	for i in range(MapConfig.TOTAL_CHUNKS):
		chunk_states[i] = 0  # All flags off = HIDDEN

	print("ChunkManager: Initialized with ", MapConfig.TOTAL_CHUNKS, " chunks (bitwise flags)")
	print("ChunkManager: FLAG_EXPLORED=0x%02X, FLAG_VISIBLE=0x%02X, FLAG_REVEALED=0x%02X" % [FLAG_EXPLORED, FLAG_VISIBLE, FLAG_REVEALED])
	print("ChunkManager: Fog of war: ", fog_of_war_enabled)

## Set references (called by main scene)
func set_camera(cam: Camera2D) -> void:
	camera = cam
	print("ChunkManager: Camera reference set")

func set_tile_map(tmap) -> void:
	tile_map = tmap
	print("ChunkManager: TileMapCompat reference set")
	_create_fog_overlays()

## Create fog overlay rectangles for each chunk
func _create_fog_overlays() -> void:
	if not tile_map:
		push_error("ChunkManager: Cannot create fog overlays - no tile_map!")
		return

	# Create parent node for overlays (child of tile_map parent)
	fog_overlay_parent = Node2D.new()
	fog_overlay_parent.name = "FogOverlays"
	fog_overlay_parent.z_index = 100  # Render on top of tiles
	tile_map.get_parent().add_child(fog_overlay_parent)

	print("ChunkManager: Creating fog overlays for ", MapConfig.TOTAL_CHUNKS, " chunks")
	print("ChunkManager: Map size: ", MapConfig.MAP_WIDTH, "x", MapConfig.MAP_HEIGHT)
	print("ChunkManager: Chunk grid: ", MapConfig.CHUNKS_WIDE, "x", MapConfig.CHUNKS_TALL)

	# Get tile size
	var tile_size = tile_map.tile_set.tile_size if tile_map.tile_set else Vector2(64, 64)
	print("ChunkManager: Tile size: ", tile_size)

	# Create one ColorRect per chunk
	for chunk_index in range(MapConfig.TOTAL_CHUNKS):
		var chunk_coords = MapConfig.chunk_index_to_coords(chunk_index)

		# Validate chunk coords
		if not MapConfig.is_chunk_in_bounds(chunk_coords):
			push_error("ChunkManager: Chunk index %d generated invalid coords %v" % [chunk_index, chunk_coords])
			continue

		var chunk_start_tile = MapConfig.chunk_to_tile(chunk_coords)

		# Convert to world position
		var world_pos = tile_map.map_to_local(chunk_start_tile)

		# Calculate chunk size in world units
		var chunk_world_size = Vector2(MapConfig.CHUNK_SIZE * tile_size.x, MapConfig.CHUNK_SIZE * tile_size.y)

		# Create ColorRect for fog
		var fog_rect = ColorRect.new()
		fog_rect.position = world_pos - chunk_world_size / 2.0  # Center on tiles
		fog_rect.size = chunk_world_size
		fog_rect.color = Color(0, 0, 0, 1)  # Start black (hidden)
		fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse
		fog_overlay_parent.add_child(fog_rect)
		fog_overlays.append(fog_rect)

		# Debug first and last chunk
		if chunk_index == 0 or chunk_index == MapConfig.TOTAL_CHUNKS - 1:
			print("  Chunk[%d] coords=%v tile=%v world_pos=%v" % [chunk_index, chunk_coords, chunk_start_tile, world_pos])

	print("ChunkManager: Created ", fog_overlays.size(), " fog overlay rectangles")

	# Apply initial visual state (hide overlays if fog disabled)
	_apply_fog_of_war_visual()

## Update visible chunks based on camera position (call each frame or when camera moves)
func update_visible_chunks() -> void:
	if not camera or not tile_map:
		return

	# Get camera position in world space
	var camera_world_pos = camera.position

	# Convert to tile coordinates
	var camera_tile = tile_map.local_to_map(camera_world_pos)

	# Convert to chunk coordinates
	var camera_chunk = MapConfig.tile_to_chunk(camera_tile)

	# Only recalculate if camera moved to a different chunk
	if camera_chunk == last_camera_chunk:
		return

	last_camera_chunk = camera_chunk

	# Calculate visible chunk range
	var new_visible_chunks: Array = []

	for dy in range(-render_radius, render_radius + 1):
		for dx in range(-render_radius, render_radius + 1):
			var chunk_coords = Vector2i(camera_chunk.x + dx, camera_chunk.y + dy)

			# Check if chunk is in bounds
			if MapConfig.is_chunk_in_bounds(chunk_coords):
				var chunk_index = MapConfig.chunk_coords_to_index(chunk_coords)
				new_visible_chunks.append(chunk_index)

	# Check if visible chunks changed
	if new_visible_chunks != visible_chunk_indices:
		var old_count = visible_chunk_indices.size()
		visible_chunk_indices = new_visible_chunks
		print("ChunkManager: Visible chunks changed: %d -> %d (camera chunk: %v)" % [old_count, visible_chunk_indices.size(), camera_chunk])
		visible_chunks_changed.emit(visible_chunk_indices)
		_apply_chunk_culling()

## Reveal a chunk (player explored it)
func reveal_chunk(chunk_coords: Vector2i) -> void:
	if not MapConfig.is_chunk_in_bounds(chunk_coords):
		return

	var chunk_index = MapConfig.chunk_coords_to_index(chunk_coords)
	var current_state = chunk_states[chunk_index]

	# Check if already explored
	if current_state & FLAG_EXPLORED:
		return  # Already explored, nothing to do

	# Set explored flag using bitwise OR
	chunk_states[chunk_index] = current_state | FLAG_EXPLORED

	chunk_revealed.emit(chunk_coords)
	print("ChunkManager: Chunk ", chunk_coords, " revealed (flags: 0x%02X)" % chunk_states[chunk_index])

## Reveal a chunk by tile coordinates
func reveal_chunk_at_tile(tile_coords: Vector2i) -> void:
	var chunk_coords = MapConfig.tile_to_chunk(tile_coords)
	reveal_chunk(chunk_coords)

## Reveal all chunks (disable fog of war)
func reveal_all_chunks() -> void:
	for i in range(MapConfig.TOTAL_CHUNKS):
		# Set explored and revealed flags
		chunk_states[i] = FLAG_EXPLORED | FLAG_REVEALED
	print("ChunkManager: All chunks revealed")

## Apply chunk culling - hide tiles in non-visible chunks
func _apply_chunk_culling() -> void:
	if not tile_map or not fog_of_war_enabled:
		return

	# Update chunk visibility flags
	for i in range(MapConfig.TOTAL_CHUNKS):
		var is_in_view = i in visible_chunk_indices
		var current_flags = chunk_states[i]

		# Only update if chunk is explored
		if current_flags & FLAG_EXPLORED:
			if is_in_view:
				# Set visible flag using bitwise OR
				chunk_states[i] = current_flags | FLAG_VISIBLE
			else:
				# Clear visible flag using bitwise AND with NOT
				chunk_states[i] = current_flags & ~FLAG_VISIBLE

	# Apply visual effects (modulate tiles based on state)
	_apply_fog_of_war_visual()

## Apply fog of war visual effects using ColorRect overlays
func _apply_fog_of_war_visual() -> void:
	if fog_overlays.size() != MapConfig.TOTAL_CHUNKS:
		return

	# If fog of war is disabled, hide all overlays
	if not fog_of_war_enabled:
		for fog_rect in fog_overlays:
			fog_rect.visible = false
		return

	# Iterate through all chunks and update fog overlay colors
	for chunk_index in range(MapConfig.TOTAL_CHUNKS):
		var flags = chunk_states[chunk_index]
		var fog_rect = fog_overlays[chunk_index]

		# Determine fog color and visibility based on flags (bitwise checks)
		if not (flags & FLAG_EXPLORED):
			# Not explored = completely black
			fog_rect.color = Color(0, 0, 0, 1)
			fog_rect.visible = true
		elif flags & FLAG_VISIBLE:
			# Visible = no fog (transparent or hidden)
			fog_rect.visible = false
		else:
			# Explored but not visible = dark gray semi-transparent
			fog_rect.color = Color(0, 0, 0, 0.5)
			fog_rect.visible = true

## Get chunk flags (raw bitwise value)
func get_chunk_flags(chunk_coords: Vector2i) -> int:
	if not MapConfig.is_chunk_in_bounds(chunk_coords):
		return 0

	var chunk_index = MapConfig.chunk_coords_to_index(chunk_coords)
	return chunk_states[chunk_index]

## Check if chunk is visible (bitwise flag check)
func is_chunk_visible(chunk_coords: Vector2i) -> bool:
	var flags = get_chunk_flags(chunk_coords)
	return (flags & FLAG_VISIBLE) != 0

## Check if chunk is explored (bitwise flag check)
func is_chunk_explored(chunk_coords: Vector2i) -> bool:
	var flags = get_chunk_flags(chunk_coords)
	return (flags & FLAG_EXPLORED) != 0

## Toggle fog of war
func set_fog_of_war_enabled(enabled: bool) -> void:
	fog_of_war_enabled = enabled
	if not enabled:
		reveal_all_chunks()
		_apply_fog_of_war_visual()
	print("ChunkManager: Fog of war ", "enabled" if enabled else "disabled")

## Check if a tile is in a visible chunk (for entity culling)
func is_tile_in_visible_chunk(tile_coords: Vector2i) -> bool:
	if not chunk_culling_enabled:
		return true

	var chunk = MapConfig.tile_to_chunk(tile_coords)
	var chunk_index = MapConfig.chunk_coords_to_index(chunk)
	return chunk_index in visible_chunk_indices

## Get statistics for entity culling (call after EntityManager.update_entities)
func get_culling_stats() -> Dictionary:
	return {
		"visible_chunks": visible_chunk_indices.size(),
		"total_chunks": MapConfig.TOTAL_CHUNKS,
		"culling_enabled": chunk_culling_enabled,
		"render_radius": render_radius
	}
