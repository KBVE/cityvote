// Fog of War shader - creates atmospheric fog around screen edges
// Designed to layer on top of CRT shader
shader_type canvas_item;
render_mode blend_mix;

uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float fog_intensity : hint_range(0.0, 1.0) = 0.8;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.6;
uniform float outer_radius : hint_range(0.0, 1.5) = 1.0;
uniform float softness : hint_range(0.0, 1.0) = 0.3;

// Optional noise for atmospheric effect
uniform bool enable_noise = false;
uniform sampler2D noise_texture;
uniform float noise_strength : hint_range(0.0, 0.5) = 0.1;
uniform float noise_speed : hint_range(0.0, 2.0) = 0.1;

void fragment() {
	// Calculate distance from center
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv);

	// Create radial fog gradient
	float fog = smoothstep(inner_radius, outer_radius, dist);

	// Add optional atmospheric noise
	if (enable_noise) {
		vec2 noise_uv = UV + vec2(TIME * noise_speed * 0.1, TIME * noise_speed * 0.05);
		float noise = texture(noise_texture, noise_uv).r;
		fog += (noise - 0.5) * noise_strength;
	}

	// Apply softness
	fog = smoothstep(0.0, softness, fog);

	// Apply intensity
	fog *= fog_intensity;

	// Output fog with alpha
	COLOR = vec4(fog_color.rgb, fog);
}
