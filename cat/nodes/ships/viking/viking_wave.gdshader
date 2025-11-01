// Viking wave motion shader
// Only handles water wave animation - does NOT remap UVs
// Direction switching is handled by AtlasTexture region updates
shader_type canvas_item;

// Wave movement parameters
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float wave_amplitude : hint_range(0.0, 20.0) = 1.5;
uniform float sway_amplitude : hint_range(0.0, 10.0) = 1.0;
uniform float wave_frequency : hint_range(0.0, 10.0) = 1.2;

void vertex() {
	// Create wave motion using sine waves
	float time_offset = TIME * wave_speed;

	// Vertical bobbing (up and down)
	float bob = sin(time_offset * wave_frequency) * wave_amplitude;

	// Horizontal swaying (left and right)
	float sway = sin(time_offset * wave_frequency * 0.7 + 1.5) * sway_amplitude;

	// Apply position offset
	VERTEX.y += bob;
	VERTEX.x += sway;
}

void fragment() {
	// Pass through texture as-is (AtlasTexture already handles region)
	COLOR = texture(TEXTURE, UV);
}
