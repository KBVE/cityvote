// Atmospheric smoke/fog shader - creates light wispy clouds at edges
shader_type canvas_item;

// Noise texture
uniform sampler2D noise_texture : repeat_enable, filter_nearest;
// Fog density
uniform float density : hint_range(0.0, 1.0) = 0.25;
// Fog speed
uniform vec2 speed = vec2(0.02, 0.01);
// Edge gradient
uniform float inner_radius : hint_range(0.0, 1.0) = 0.4;
uniform float outer_radius : hint_range(0.0, 1.5) = 1.0;

void fragment() {
	// Calculate distance from center for edge gradient
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv);

	// Create radial gradient (more fog at edges)
	float edge_gradient = smoothstep(inner_radius, outer_radius, dist);

	// Make the fog slowly move
	vec2 uv = UV + speed * TIME;
	// Sample the noise texture
	float noise = texture(noise_texture, uv).r;
	// Convert the noise from the (0.0, 1.0) range to the (-1.0, 1.0) range
	// and clamp it between 0.0 and 1.0 again
	float fog = clamp(noise * 2.0 - 1.0, 0.0, 1.0);

	// Apply the fog effect with edge gradient
	COLOR.a *= fog * density * edge_gradient;
}
