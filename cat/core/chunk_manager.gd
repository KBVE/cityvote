extends Node

## ChunkManager - Manages chunk visibility, fog of war, and culling
## Tracks which chunks are visible, explored, and actively rendered
## INFINITE WORLD: Uses sparse storage (Dictionary) instead of fixed array

## Signals
signal chunk_revealed(chunk_coords: Vector2i)
signal chunk_hidden(chunk_coords: Vector2i)
signal visible_chunks_changed(visible_chunks: Array[Vector2i])
signal chunk_requested(chunk_coords: Vector2i)  # Request chunk generation from HexMap

## Chunk visibility flags (bitwise)
const FLAG_EXPLORED: int = 1 << 0  # 0b001 - Chunk has been explored
const FLAG_VISIBLE: int = 1 << 1   # 0b010 - Chunk is currently visible
const FLAG_REVEALED: int = 1 << 2  # 0b100 - Chunk is revealed (fog disabled)

## Chunk state tracking (SPARSE - only stores loaded chunks)
## Key: Vector2i (chunk coords), Value: int (bitwise flags)
var chunk_states: Dictionary = {}

## Helper enum for readability (but we use bitwise ops)
enum ChunkState {
	HIDDEN = 0,                          # 0b000 - Never explored
	EXPLORED = FLAG_EXPLORED,            # 0b001 - Explored but not visible
	VISIBLE = FLAG_EXPLORED | FLAG_VISIBLE,  # 0b011 - Explored and visible
	REVEALED = FLAG_EXPLORED | FLAG_VISIBLE | FLAG_REVEALED  # 0b111 - Fully revealed
}

## Currently visible chunks based on camera position (sparse array of Vector2i coords)
var visible_chunks: Array[Vector2i] = []

## Fog of war enabled (disabled for debugging)
var fog_of_war_enabled: bool = false

## Chunk culling enabled (performance optimization)
var chunk_culling_enabled: bool = true

## Statistics for debugging
var culled_entities_count: int = 0
var active_entities_count: int = 0

## How many chunks around camera to render
var render_radius: int = 5  # Render 5 chunks in each direction from camera (async loading buffer)

## Last camera chunk position (to avoid recalculating every frame)
var last_camera_chunk: Vector2i = Vector2i(-1, -1)

## References
var camera: Camera2D = null
var chunk_pool: ChunkPool = null  # Reference to ChunkPool singleton

func _ready():
	pass  # Initialized successfully

## Set references (called by main scene)
func set_camera(cam: Camera2D) -> void:
	camera = cam

func set_chunk_pool(pool: ChunkPool) -> void:
	chunk_pool = pool

## Update visible chunks based on camera position (call each frame or when camera moves)
func update_visible_chunks() -> void:
	if not camera:
		return

	# Get camera position in world space
	var camera_world_pos = camera.position

	# Convert to chunk coordinates
	var camera_chunk = MapConfig.world_to_chunk(camera_world_pos)

	# Only recalculate if camera moved to a different chunk
	if camera_chunk == last_camera_chunk:
		return

	last_camera_chunk = camera_chunk

	# Calculate visible chunks in radius (infinite world - no bounds checking)
	var new_visible_chunks = MapConfig.get_chunks_in_radius(camera_chunk, render_radius)

	# Check if visible chunks changed
	if new_visible_chunks != visible_chunks:
		visible_chunks = new_visible_chunks
		visible_chunks_changed.emit(visible_chunks)
		_request_missing_chunks()
		_apply_chunk_culling()

## Request generation of chunks that aren't loaded yet
func _request_missing_chunks() -> void:
	if not chunk_pool:
		return

	for chunk_coords in visible_chunks:
		if not chunk_pool.is_chunk_loaded(chunk_coords):
			# Request chunk generation
			chunk_requested.emit(chunk_coords)

## Reveal a chunk (player explored it)
func reveal_chunk(chunk_coords: Vector2i) -> void:
	# Get current state (default to 0 if not in dictionary)
	var current_state = chunk_states.get(chunk_coords, 0)

	# Check if already explored
	if current_state & FLAG_EXPLORED:
		return  # Already explored, nothing to do

	# Set explored flag using bitwise OR
	chunk_states[chunk_coords] = current_state | FLAG_EXPLORED

	chunk_revealed.emit(chunk_coords)

## Reveal a chunk by tile coordinates
func reveal_chunk_at_tile(tile_coords: Vector2i) -> void:
	var chunk_coords = MapConfig.tile_to_chunk(tile_coords)
	reveal_chunk(chunk_coords)

## Reveal all loaded chunks (disable fog of war)
func reveal_all_chunks() -> void:
	for chunk_coords in chunk_states.keys():
		# Set explored and revealed flags
		chunk_states[chunk_coords] = FLAG_EXPLORED | FLAG_REVEALED

## Apply chunk culling - update visibility flags for loaded chunks
func _apply_chunk_culling() -> void:
	if not fog_of_war_enabled:
		return

	# Update chunk visibility flags for all loaded chunks
	for chunk_coords in chunk_states.keys():
		var is_in_view = chunk_coords in visible_chunks
		var current_flags = chunk_states[chunk_coords]

		# Only update if chunk is explored
		if current_flags & FLAG_EXPLORED:
			if is_in_view:
				# Set visible flag using bitwise OR
				chunk_states[chunk_coords] = current_flags | FLAG_VISIBLE
			else:
				# Clear visible flag using bitwise AND with NOT
				chunk_states[chunk_coords] = current_flags & ~FLAG_VISIBLE

## Get chunk flags (raw bitwise value)
func get_chunk_flags(chunk_coords: Vector2i) -> int:
	return chunk_states.get(chunk_coords, 0)

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

## Check if a tile is in a visible chunk (for entity culling)
func is_tile_in_visible_chunk(tile_coords: Vector2i) -> bool:
	if not chunk_culling_enabled:
		return true

	var chunk = MapConfig.tile_to_chunk(tile_coords)
	return chunk in visible_chunks

## Get statistics
func get_culling_stats() -> Dictionary:
	return {
		"visible_chunks": visible_chunks.size(),
		"loaded_chunks": chunk_states.size(),
		"culling_enabled": chunk_culling_enabled,
		"render_radius": render_radius
	}
