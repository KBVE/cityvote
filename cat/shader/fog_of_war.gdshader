// Fog of War shader - creates thick atmospheric clouds that cover CRT black corners
shader_type canvas_item;
render_mode blend_mix;

// Fog/cloud appearance
uniform vec4 fog_color : source_color = vec4(0.05, 0.05, 0.08, 1.0);
uniform float fog_intensity : hint_range(0.0, 1.0) = 1.0;

// Cloud density and coverage
uniform float density : hint_range(0.0, 1.0) = 0.6;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.5;
uniform float outer_radius : hint_range(0.0, 1.5) = 1.2;
uniform float edge_thickness : hint_range(0.0, 1.0) = 0.4;

// Cloud movement and animation
uniform sampler2D noise_texture : repeat_enable, filter_nearest;
uniform vec2 cloud_speed = vec2(0.015, 0.008);
uniform float cloud_scale : hint_range(0.1, 5.0) = 1.5;
uniform float turbulence : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	// Calculate distance from center
	vec2 centered_uv = UV - vec2(0.5);
	float dist = length(centered_uv);

	// Create base radial fog gradient (covers CRT corners)
	float radial_fog = smoothstep(inner_radius, outer_radius, dist);

	// Sample moving cloud noise
	vec2 cloud_uv = UV * cloud_scale + cloud_speed * TIME;
	float cloud_noise1 = texture(noise_texture, cloud_uv).r;

	// Add second layer of clouds moving in different direction for depth
	vec2 cloud_uv2 = UV * cloud_scale * 1.3 - cloud_speed * 0.7 * TIME;
	float cloud_noise2 = texture(noise_texture, cloud_uv2).r;

	// Combine cloud layers
	float clouds = mix(cloud_noise1, cloud_noise2, 0.5);

	// Convert noise range and add turbulence
	clouds = clamp(clouds * 2.0 - 1.0 + turbulence, 0.0, 1.0);

	// Combine radial fog with clouds
	float fog = radial_fog * density;
	fog = mix(fog, 1.0, clouds * fog * edge_thickness);

	// Ensure corners are fully covered
	fog = max(fog, radial_fog * 0.8);

	// Apply intensity
	fog *= fog_intensity;

	// Output thick cloudy fog
	COLOR = vec4(fog_color.rgb, clamp(fog, 0.0, 1.0));
}
