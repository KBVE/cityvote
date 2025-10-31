shader_type canvas_item;

// Terrain Tile Shader with Hex Masking and UV Flipping
// Clips tiles to hexagonal shape to prevent overlap
//
// Uses MultiMesh custom data (passed via COLOR):
//   - COLOR.r: tile_index (0-9 for 10 tiles)
//   - COLOR.g: flip_flags (0-7 for transformations)
//     - bit 0: flip horizontal
//     - bit 1: flip vertical
//     - bit 2: transpose (swap X/Y for 90° rotation)

uniform int total_tiles = 10;  // Total tiles in atlas
uniform vec2 atlas_size_px = vec2(320.0, 48.0);  // Atlas texture size in pixels
uniform vec2 tile_size_px = vec2(32.0, 48.0);    // Size of one tile in pixels
uniform int pad_px = 2;  // Padding around each tile region to prevent bleeding

varying flat int v_tile_index;
varying flat int v_flip_flags;

void vertex() {
	// Read per-instance parameters from INSTANCE_CUSTOM (MultiMesh custom data)
	// Add 0.5 before int() to properly round (avoids precision loss from float)
	v_tile_index = int(INSTANCE_CUSTOM.r * 255.0 + 0.5);
	v_flip_flags = int(INSTANCE_CUSTOM.g * 255.0 + 0.5);
}

// Hexagon SDF mask for our diamond-down hex layout
// Returns 1.0 inside hex, 0.0 outside, with smooth edge
float hex_mask(vec2 uv01) {
	// Map UV (0..1) to centered coordinates (-1..1)
	vec2 p = uv01 * 2.0 - 1.0;

	// For FLAT-TOP hexagon (Godot's "Diamond Down" layout)
	// Our logical hex is 32x28 but sprite is 32x48 (extra for tall features)
	// We want to mask to the logical hex footprint only

	// The sprite is centered, and we need to account for the aspect ratio
	// Logical hex: 32px wide, 28px tall
	// Sprite quad: 32px wide, 48px tall
	// In UV space, the hex occupies full width but only 28/48 = 0.583 of height
	// Since p ranges from -1 to 1 (total span of 2), we need to adjust Y scaling

	// Y needs to be compressed to account for sprite being taller than hex
	p.y *= 48.0/28.0;  // Scale Y by sprite_height/hex_height to compress to hex footprint

	// Flat-top hexagon SDF (horizontal orientation) - PROPER 6-SIDED
	// This is the correct orientation for Godot's STACKED_OFFSET VERTICAL layout
	// A proper hexagon has 6 sides, not 4
	const float k = 0.57735026919; // 1/sqrt(3) = tan(30°)

	p = abs(p); // Mirror to first quadrant for symmetry

	// Flat-top hexagon is defined by 3 constraints (due to symmetry):
	// 1. Left/right vertical edges: |x| <= width
	// 2. Top-left/top-right diagonal edges: k*x + y <= height
	// 3. Bottom-left/bottom-right diagonal edges: k*x - y <= height

	// Combine all three constraints (all 6 sides)
	float d = max(
		max(p.x - 1.0, k * p.x + p.y - 1.0),  // Right side and top-right diagonal
		k * p.x - p.y - 1.0                    // Bottom-right diagonal
	);

	// Return 1.0 inside, 0.0 outside
	// Tighter smoothstep for sharper hex borders (flushed appearance)
	// Transition range: 0.01 units for clean but anti-aliased edges
	return smoothstep(0.01, -0.01, d);
}

void fragment() {
	// Start with local UV (0-1 within the tile)
	vec2 local_uv = UV;

	// Extract flip flags
	bool flip_h = (v_flip_flags & 1) != 0;      // bit 0
	bool flip_v = (v_flip_flags & 2) != 0;      // bit 1
	bool transpose = (v_flip_flags & 4) != 0;   // bit 2

	// Apply transpose (swap X and Y) - creates 90° rotation effect
	if (transpose) {
		local_uv = vec2(local_uv.y, local_uv.x);
	}

	// Apply horizontal flip
	if (flip_h) {
		local_uv.x = 1.0 - local_uv.x;
	}

	// Apply vertical flip
	if (flip_v) {
		local_uv.y = 1.0 - local_uv.y;
	}

	// Calculate atlas UV - SIMPLIFIED (without padding for debugging)
	float tile_width = 1.0 / float(total_tiles);
	float u_offset = float(v_tile_index) * tile_width;

	vec2 atlas_uv = vec2(
		u_offset + local_uv.x * tile_width,
		local_uv.y
	);

	// Sample texture from atlas
	vec4 color = texture(TEXTURE, atlas_uv);

	// No overlay - just show the tiles as-is with their natural sprite artwork
	COLOR = color;

	// Discard fully transparent pixels
	if (COLOR.a < 0.001) {
		discard;
	}
}
