shader_type canvas_item;

// Atlas texture containing all flags
uniform sampler2D atlas_texture : filter_nearest;

// UV region for the specific flag in the atlas (normalized 0-1)
// x = left, y = top, z = width, w = height
uniform vec4 flag_region = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	// Map the fragment UV to the atlas region
	vec2 atlas_uv = flag_region.xy + (UV * flag_region.zw);

	// Sample the atlas texture at the mapped UV
	vec4 color = texture(atlas_texture, atlas_uv);

	// Output the color
	COLOR = color;
}
