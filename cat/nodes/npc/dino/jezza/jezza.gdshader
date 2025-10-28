shader_type canvas_item;

uniform sampler2D atlas_texture : hint_default_white;
uniform int frame_index : hint_range(0, 100) = 0;
uniform int animation_row : hint_range(0, 20) = 0;
uniform vec2 frame_size = vec2(128.0, 64.0);
uniform vec2 atlas_size = vec2(2304.0, 960.0);
uniform int frames_per_row : hint_range(1, 20) = 18;

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
