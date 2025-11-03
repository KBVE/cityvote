shader_type canvas_item;

// Projectile atlas shader (Multi-Row Support)
// Supports multi-row sprite atlas with animation frames
// Each projectile occupies one row and can have multiple animation frames

uniform sampler2D atlas_texture : filter_nearest, repeat_disable;
uniform int projectile_row : hint_range(0, 10) = 0;  // Which row (projectile type)
uniform int frame_index : hint_range(0, 20) = 0;     // Which frame in the animation
uniform int total_rows = 4;       // Total number of rows in atlas (spear, glaive, shadowbolt, firebolt)
uniform int max_frames = 13;      // Maximum frames per row (firebolt has 13 frames)

void fragment() {
	// Calculate atlas dimensions
	float row_height = 1.0 / float(total_rows);
	float frame_width = 1.0 / float(max_frames);

	// Calculate UV offsets for this projectile row and frame
	float u_offset = float(frame_index) * frame_width;
	float v_offset = float(projectile_row) * row_height;

	// Map UV to specific sprite frame in atlas
	// UV.x goes from 0-1 across the frame width
	// UV.y goes from 0-1 across the row height
	vec2 atlas_uv = vec2(
		u_offset + UV.x * frame_width,
		v_offset + UV.y * row_height
	);

	// Sample texture from atlas
	vec4 color = texture(atlas_texture, atlas_uv);

	// Apply modulation (for color tinting, flashing, etc.)
	COLOR = color * COLOR;
}
