shader_type canvas_item;

// King Shader - Displays animated sprites from atlas
// Atlas: 1280x999 (9 rows, varying frame counts per row)
// Frame size: 160x111 pixels

uniform sampler2D atlas_texture : hint_default_white;
uniform int frame_index : hint_range(0, 20) = 0;
uniform int animation_row : hint_range(0, 8) = 0;
uniform vec2 frame_size = vec2(160.0, 111.0);
uniform vec2 atlas_size = vec2(1280.0, 999.0);
uniform int frames_per_row : hint_range(1, 8) = 8;

void fragment() {
	// Calculate which frame in the row
	float frame_x = mod(float(frame_index), float(frames_per_row));
	float frame_y = float(animation_row);

	// Calculate UV offset for this frame
	vec2 uv_offset = vec2(frame_x, frame_y) * (frame_size / atlas_size);

	// Calculate UV scale to show only one frame
	vec2 uv_scale = frame_size / atlas_size;

	// Transform UV coordinates
	vec2 uv = UV * uv_scale + uv_offset;

	// Sample the texture
	vec4 color = texture(atlas_texture, uv);

	COLOR = color;
}
