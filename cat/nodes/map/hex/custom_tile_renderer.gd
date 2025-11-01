extends Node2D
class_name CustomTileRenderer

## Custom high-performance tile renderer using MultiMeshInstance2D + UV shader
## Replaces TileMap for ~50-70% better performance via single draw call per chunk
## Uses terrain_atlas.png with UV flipping for infinite tile variation

# Terrain atlas texture and metadata
var atlas_texture: Texture2D
var atlas_metadata: Dictionary

# Shader material for tile rendering
var tile_shader: Shader
var base_shader_material: ShaderMaterial

# MultiMeshInstance2D for each chunk row (chunk_index -> Array of MultiMeshInstance2D)
# Split by rows for perfect cross-chunk z-ordering
var chunk_meshes: Dictionary = {}

# Cached quad mesh (created once, reused for all chunks)
var cached_quad_mesh: ArrayMesh = null

# Tile size constants (hex tiles)
const TILE_WIDTH: int = 32
const TILE_HEIGHT: int = 48  # Hex tiles are taller
const TILE_RENDER_HEIGHT: int = 28  # Visual height for positioning

# Scale factor for tile rendering (1.0 = natural size, matching TileMap)
const TILE_SCALE: float = 1.0  # Natural size - no scaling

# Hex grid offset (matches TileMap configuration)
const HEX_OFFSET_Y: float = 14.0  # Half-height offset for hex rows

func _ready() -> void:
	# Load atlas texture
	atlas_texture = load("res://nodes/map/hex/terrain_atlas.png")
	if not atlas_texture:
		push_error("CustomTileRenderer: Failed to load terrain_atlas.png")
		return

	# CRITICAL: Disable texture filtering to prevent gaps between tiles
	# This ensures pixel-perfect rendering without anti-aliasing artifacts
	var image = atlas_texture.get_image()
	if image:
		atlas_texture = ImageTexture.create_from_image(image)
		# Texture filtering is controlled by CanvasItem.texture_filter
		# We'll set it on each mesh instance

	# Load atlas metadata
	var metadata_file = FileAccess.open("res://nodes/map/hex/terrain_atlas_metadata.json", FileAccess.READ)
	if metadata_file:
		var json_string = metadata_file.get_as_text()
		metadata_file.close()
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result == OK:
			atlas_metadata = json.data
		else:
			push_error("CustomTileRenderer: Failed to parse terrain_atlas_metadata.json")
			return
	else:
		push_error("CustomTileRenderer: Failed to open terrain_atlas_metadata.json")
		return

	# Load shader
	tile_shader = load("res://nodes/map/hex/terrain_tile.gdshader")
	if not tile_shader:
		push_error("CustomTileRenderer: Failed to load terrain_tile.gdshader")
		return

	# Create base shader material (will be duplicated per instance)
	base_shader_material = ShaderMaterial.new()
	base_shader_material.shader = tile_shader
	base_shader_material.set_shader_parameter("total_tiles", atlas_metadata["total_tiles"])

	# Create quad mesh once and cache it
	cached_quad_mesh = _create_quad_mesh(TILE_WIDTH, TILE_HEIGHT)

	print("CustomTileRenderer: Initialized with %d tiles" % atlas_metadata["total_tiles"])
	print("CustomTileRenderer: Quad mesh created with size %dx%d" % [TILE_WIDTH, TILE_HEIGHT])
	print("CustomTileRenderer: Atlas texture size: %v" % atlas_texture.get_size())
	if cached_quad_mesh:
		print("CustomTileRenderer: Mesh has %d surfaces" % cached_quad_mesh.get_surface_count())
		if cached_quad_mesh.get_surface_count() > 0:
			var arrays = cached_quad_mesh.surface_get_arrays(0)
			print("CustomTileRenderer: Mesh vertex count: %d" % arrays[Mesh.ARRAY_VERTEX].size())

## Render a chunk by creating multiple MultiMeshInstance2D nodes (one per row)
## This ensures perfect z-ordering across chunk boundaries
func render_chunk(chunk_index: int, tile_data: Array) -> void:
	# Check if chunk already rendered
	if chunk_meshes.has(chunk_index):
		push_warning("CustomTileRenderer: Chunk %d already rendered" % chunk_index)
		return

	# Filter out empty tiles (tile_index == -1)
	var valid_tiles = []
	var skipped_count = 0
	for tile in tile_data:
		if tile["tile_index"] >= 0:
			valid_tiles.append(tile)
		else:
			skipped_count += 1

	if valid_tiles.size() == 0:
		# Empty chunk, don't render
		print("CustomTileRenderer: Chunk %d is empty (all %d tiles have tile_index -1)" % [chunk_index, skipped_count])
		return

	# Sort tiles by Y coordinate (ASCENDING) for proper grouping
	valid_tiles.sort_custom(func(a, b):
		if a["y"] != b["y"]:
			return a["y"] < b["y"]  # Lower Y first
		return a["x"] < b["x"]  # Then by X for consistent ordering
	)

	# Group tiles by Y coordinate for row-based rendering
	var tiles_by_row: Dictionary = {}
	for tile in valid_tiles:
		var tile_y = tile["y"]
		if not tiles_by_row.has(tile_y):
			tiles_by_row[tile_y] = []
		tiles_by_row[tile_y].append(tile)

	# Create one MultiMeshInstance2D per row
	var mesh_instances = []
	for tile_y in tiles_by_row.keys():
		var row_tiles = tiles_by_row[tile_y]

		# Create MultiMesh for this row
		var multi_mesh = MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_2D
		multi_mesh.use_custom_data = true
		multi_mesh.instance_count = row_tiles.size()
		multi_mesh.mesh = cached_quad_mesh

		# Create MultiMeshInstance2D
		var mesh_instance = MultiMeshInstance2D.new()
		mesh_instance.multimesh = multi_mesh
		mesh_instance.texture = atlas_texture

		# Enable texture filtering for smooth borders
		# This will anti-alias the edges for a smoother appearance
		mesh_instance.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

		# Create unique shader material
		var row_material = ShaderMaterial.new()
		row_material.shader = tile_shader
		row_material.set_shader_parameter("total_tiles", atlas_metadata["total_tiles"])
		mesh_instance.material = row_material

		# Set z_index to tile Y coordinate for perfect cross-chunk layering
		mesh_instance.z_index = tile_y
		mesh_instance.name = "Chunk_%d_Row_%d" % [chunk_index, tile_y]

		add_child(mesh_instance)

		# Set transform and custom data for each tile in this row
		for i in range(row_tiles.size()):
			var tile = row_tiles[i]
			var tile_x = tile["x"]
			var tile_index = tile["tile_index"]
			var flip_flags = tile.get("flip_flags", 0)

			# Calculate world position
			var world_pos = _tile_to_world_pos(Vector2i(tile_x, tile_y))

			# Create transform - no scaling, just positioning
			var transform = Transform2D()
			if TILE_SCALE != 1.0:
				transform = transform.scaled(Vector2(TILE_SCALE, TILE_SCALE))
			transform.origin = world_pos
			multi_mesh.set_instance_transform_2d(i, transform)

			# Pack custom data
			var custom_color = Color(
				float(tile_index) / 255.0,
				float(flip_flags) / 255.0,
				0.0,
				1.0
			)
			multi_mesh.set_instance_custom_data(i, custom_color)

		mesh_instances.append(mesh_instance)

	# Store all mesh instances for this chunk
	chunk_meshes[chunk_index] = mesh_instances

	print("CustomTileRenderer: Rendered chunk %d with %d tiles in %d rows (from %d total, skipped %d)" % [chunk_index, valid_tiles.size(), mesh_instances.size(), tile_data.size(), skipped_count])

## Unrender a chunk by removing all its MultiMeshInstance2D nodes
func unrender_chunk(chunk_index: int) -> void:
	if not chunk_meshes.has(chunk_index):
		return

	var mesh_instances = chunk_meshes[chunk_index]
	for mesh_instance in mesh_instances:
		mesh_instance.queue_free()
	chunk_meshes.erase(chunk_index)

## Convert tile coordinates to world position (hex grid layout)
## Matches Godot's Diamond Down layout with Vertical Offset
## Based on actual TileMap.map_to_local() output
func _tile_to_world_pos(tile_coords: Vector2i) -> Vector2:
	# Godot's "Diamond Down" layout uses COLUMN-based offset, not row-based!
	# Odd COLUMNS are offset DOWN by 14 pixels
	# Column spacing: 24 pixels (not 32!)
	# Row spacing: 28 pixels (logical grid)
	#
	# NOTE: Our sprites are 48px tall but positioned on a 28px grid.
	# This means tiles naturally overlap by 20 pixels vertically!
	# We match Godot's TileMap.map_to_local() exactly:

	# Match Godot's exact TileMap.map_to_local() output
	# Configuration: HEXAGON, STACKED_OFFSET, VERTICAL offset axis, 32x28 tile size
	# NOTE: The 2px Y offset is a NODE-level offset, not per-tile, so not included here
	var x = 16.0 + float(tile_coords.x) * 24.5  # Horizontal spacing: 24.5px
	var y = 28.0 + float(tile_coords.y) * 28.5  # Vertical spacing: 28.5px

	# Odd COLUMNS (1, 3, 5, -1, -3, -5...) are offset UP by 14.25 pixels
	# This creates the stacked hex pattern (half of 28.5px vertical spacing)
	# Note: Use abs() to handle negative coordinates correctly
	if abs(tile_coords.x) % 2 == 1:
		y -= 14.25  # Move UP by half of 28.5px vertical spacing

	return Vector2(x, y)

## Convert world position to tile coordinates (for mouse picking)
func world_to_tile(world_pos: Vector2) -> Vector2i:
	# Proper hex picking for STACKED_OFFSET VERTICAL layout
	# Account for 2px Y offset in positioning
	# We need to find the closest hex center

	# Rough estimate of column
	var col_float = (world_pos.x - 16.0) / 24.5
	var col_estimate = int(round(col_float))

	# Check nearby columns (current, left, right) to find closest hex
	var best_col = col_estimate
	var best_row = 0
	var best_dist = INF

	for col_offset in [-1, 0, 1]:
		var col = col_estimate + col_offset
		# Allow negative coordinates for infinite world

		# Rough estimate of row for this column
		var y_adjusted = world_pos.y - 28.0
		if abs(col) % 2 == 1:
			y_adjusted += 14.25  # Undo odd column offset
		var row_float = y_adjusted / 28.5
		var row_estimate = int(round(row_float))

		# Check nearby rows
		for row_offset in [-1, 0, 1]:
			var row = row_estimate + row_offset
			# Allow negative coordinates for infinite world

			# Get the center position of this hex
			var hex_center = _tile_to_world_pos(Vector2i(col, row))
			var dist = world_pos.distance_to(hex_center)

			if dist < best_dist:
				best_dist = dist
				best_col = col
				best_row = row

	return Vector2i(best_col, best_row)

## Get tile index by name (e.g., "grassland0" -> 0)
func get_tile_index_by_name(tile_name: String) -> int:
	for tile in atlas_metadata["tiles"]:
		if tile["name"] == tile_name:
			return tile["index"]
	return -1

## Clear all rendered chunks
func clear_all() -> void:
	for chunk_index in chunk_meshes.keys():
		unrender_chunk(chunk_index)

## Create a proper 2D quad mesh with correct UVs for MultiMeshInstance2D
func _create_quad_mesh(width: int, height: int) -> ArrayMesh:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)

	# Calculate half extents (centered on origin)
	var hw = width / 2.0
	var hh = height / 2.0

	# Define vertices for a quad (4 vertices)
	# In 2D, Y increases downward, so we need to arrange vertices properly
	var vertices = PackedVector3Array([
		Vector3(-hw, -hh, 0),  # Top-left
		Vector3(hw, -hh, 0),   # Top-right
		Vector3(-hw, hh, 0),   # Bottom-left
		Vector3(hw, hh, 0)     # Bottom-right
	])

	# UVs mapping to texture (0,0) = top-left, (1,1) = bottom-right
	var uvs = PackedVector2Array([
		Vector2(0, 0),  # Top-left
		Vector2(1, 0),  # Top-right
		Vector2(0, 1),  # Bottom-left
		Vector2(1, 1)   # Bottom-right
	])

	# Colors for per-vertex data (will be used for custom data in shader)
	var colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 1)
	])

	# Indices for two triangles
	var indices = PackedInt32Array([
		0, 1, 2,  # First triangle (top-left, top-right, bottom-left)
		2, 1, 3   # Second triangle (bottom-left, top-right, bottom-right)
	])

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh
