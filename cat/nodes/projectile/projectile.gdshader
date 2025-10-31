shader_type canvas_item;

// Projectile atlas shader
// Selects sprite from horizontal atlas using projectile_index

uniform sampler2D atlas_texture : filter_nearest, repeat_disable;
uniform int projectile_index : hint_range(0, 10) = 0;  // Which projectile to display
uniform int total_projectiles = 2;  // Total number of projectiles in atlas

void fragment() {
	// Calculate UV offset based on projectile index
	float sprite_width = 1.0 / float(total_projectiles);
	float u_offset = float(projectile_index) * sprite_width;

	// Map UV to specific sprite in atlas
	vec2 atlas_uv = vec2(
		u_offset + UV.x * sprite_width,
		UV.y
	);

	// Sample texture from atlas
	vec4 color = texture(atlas_texture, atlas_uv);

	// Apply modulation (for color tinting, flashing, etc.)
	COLOR = color * COLOR;
}
