extends Node

## Card Atlas Meshes Generator
## Pre-generates QuadMesh instances with baked UV coordinates for each card in the atlas
## This allows static cards to use mesh swapping instead of shader parameters
## Memory efficient: ~200 bytes per mesh vs ~5KB per duplicated material

# Atlas configuration
const ATLAS_COLS: int = 13  # Cards per row (Ace through King)
const ATLAS_ROWS: int = 5   # Rows (4 suits + custom cards)
const TOTAL_CARDS: int = 54 # 52 standard + 2 custom

# Mesh cache - populated at _ready()
var card_meshes: Dictionary = {}  # card_id -> QuadMesh

# Texture reference (same as shader uses)
var card_atlas_texture: Texture2D

func _ready() -> void:
	# Load the card atlas texture
	card_atlas_texture = load("res://nodes/cards/playing/card_atlas.png")
	if not card_atlas_texture:
		push_error("CardAtlasMeshes: Failed to load card_atlas.png!")
		return

	# Pre-generate all 54 card meshes
	_generate_all_meshes()
	print("CardAtlasMeshes: Generated %d card meshes" % card_meshes.size())

## Generate all card meshes with baked UV coordinates
func _generate_all_meshes() -> void:
	for card_id in range(TOTAL_CARDS):
		card_meshes[card_id] = _create_mesh_for_card(card_id)

## Create an ArrayMesh with UV coordinates baked for specific card_id
func _create_mesh_for_card(card_id: int) -> ArrayMesh:
	# Calculate position in atlas
	var col = card_id % ATLAS_COLS
	var row = card_id / ATLAS_COLS

	# Atlas texture dimensions
	var tex_w := float(card_atlas_texture.get_width())   # 1248
	var tex_h := float(card_atlas_texture.get_height())  # 720

	# Original UV region in atlas (before inset)
	var u0 := float(col) / float(ATLAS_COLS)
	var v0 := float(row) / float(ATLAS_ROWS)
	var u1 := u0 + 1.0 / float(ATLAS_COLS)
	var v1 := v0 + 1.0 / float(ATLAS_ROWS)

	# No inset needed when using nearest-neighbor filtering (texture_filter=0)
	# Inset is only required when using linear filtering to prevent bleeding
	var inset_px := 0.0  # No inset with nearest filtering
	var du := inset_px / tex_w
	var dv := inset_px / tex_h

	u0 += du
	v0 += dv
	u1 -= du
	v1 -= dv

	# Create ArrayMesh with custom UV coordinates
	# Note: We use ArrayMesh instead of QuadMesh to have full control over UVs
	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)

	# Vertices (quad corners) - match QuadMesh layout exactly
	# QuadMesh centers at origin with size/2 offsets
	var half_width = 96.0 / 2.0  # 48
	var half_height = 144.0 / 2.0  # 72

	var vertices = PackedVector3Array([
		Vector3(-half_width, -half_height, 0),  # Top-left
		Vector3(half_width, -half_height, 0),   # Top-right
		Vector3(-half_width, half_height, 0),   # Bottom-left
		Vector3(half_width, half_height, 0)     # Bottom-right
	])

	# UV coordinates for this specific card
	# No Y-flip needed - using direct texture coordinates
	var uvs = PackedVector2Array([
		Vector2(u0, v0),  # Top-left
		Vector2(u1, v0),  # Top-right
		Vector2(u0, v1),  # Bottom-left
		Vector2(u1, v1)   # Bottom-right
	])

	# Debug first card
	if card_id == 0:
		print("CardAtlasMeshes: Card 0 (Ace of Clubs) UVs (with %fpx inset):" % inset_px)
		print("  Original: u0=%f, v0=%f, u1=%f, v1=%f" % [u0 - du, v0 - dv, u1 + du, v1 + dv])
		print("  Inset:    u0=%f, v0=%f, u1=%f, v1=%f" % [u0, v0, u1, v1])
		print("  UV corners (Y-flipped): ", uvs)

	# Indices (two triangles forming a quad)
	var indices = PackedInt32Array([
		0, 1, 2,  # First triangle
		2, 1, 3   # Second triangle
	])

	# Normals (all pointing toward camera)
	var normals = PackedVector3Array([
		Vector3(0, 0, 1),
		Vector3(0, 0, 1),
		Vector3(0, 0, 1),
		Vector3(0, 0, 1)
	])

	# Build the surface array
	surface_array[Mesh.ARRAY_VERTEX] = vertices
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_NORMAL] = normals
	surface_array[Mesh.ARRAY_INDEX] = indices

	# Create the mesh
	var array_mesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)

	# For MeshInstance2D, we need to return the ArrayMesh directly
	# (QuadMesh is just a convenience class, ArrayMesh gives us full control)
	return array_mesh

## Get pre-generated mesh for a card_id
func get_mesh(card_id: int) -> Mesh:
	if card_meshes.has(card_id):
		return card_meshes[card_id]
	else:
		push_error("CardAtlasMeshes: Invalid card_id %d (valid range: 0-%d)" % [card_id, TOTAL_CARDS - 1])
		return card_meshes.get(0, null)  # Fallback to Ace of Clubs

## Get the card atlas texture (for setting on MeshInstance2D)
func get_texture() -> Texture2D:
	return card_atlas_texture
