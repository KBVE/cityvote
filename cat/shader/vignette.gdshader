// Simple vignette/fog of war shader for screen edges
shader_type canvas_item;
render_mode blend_mix;

uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float vignette_radius : hint_range(0.0, 1.0) = 0.6;
uniform float vignette_softness : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	// Calculate distance from center
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);

	// Create vignette effect
	float vignette = smoothstep(vignette_radius, vignette_radius + vignette_softness, dist);
	vignette *= vignette_intensity;

	// Apply fog color with vignette alpha
	COLOR = vec4(fog_color.rgb, vignette);
}
