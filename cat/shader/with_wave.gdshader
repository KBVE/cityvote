// With Wave shader - makes sprites gently bob and sway as if floating on water
shader_type canvas_item;

// Wave movement parameters
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform float wave_amplitude : hint_range(0.0, 20.0) = 3.0;  // Vertical bobbing amount in pixels
uniform float sway_amplitude : hint_range(0.0, 10.0) = 2.0;  // Horizontal swaying amount in pixels
uniform float wave_frequency : hint_range(0.0, 10.0) = 2.0;  // How many waves per cycle

// Rotation parameters
uniform float rotation_amount : hint_range(0.0, 10.0) = 1.5;  // Max rotation in degrees

void vertex() {
	// Create wave motion using sine waves at different frequencies for more natural movement
	float time_offset = TIME * wave_speed;

	// Vertical bobbing (up and down)
	float bob = sin(time_offset * wave_frequency) * wave_amplitude;

	// Horizontal swaying (left and right) - slightly offset from bob for more natural motion
	float sway = sin(time_offset * wave_frequency * 0.7 + 1.5) * sway_amplitude;

	// Apply position offset
	VERTEX.y += bob;
	VERTEX.x += sway;
}

void fragment() {
	// Sample the texture normally
	COLOR = texture(TEXTURE, UV);

	// Optional: slight rotation effect by skewing UV
	// This creates a subtle rocking motion
	float time_offset = TIME * wave_speed;
	float rotation = sin(time_offset * wave_frequency * 0.5) * rotation_amount * 0.01;

	// Apply subtle rotation to UVs for rocking effect
	vec2 centered_uv = UV - vec2(0.5);
	float cos_r = cos(rotation);
	float sin_r = sin(rotation);
	vec2 rotated_uv = vec2(
		centered_uv.x * cos_r - centered_uv.y * sin_r,
		centered_uv.x * sin_r + centered_uv.y * cos_r
	) + vec2(0.5);

	// Use rotated UVs for final texture sample
	COLOR = texture(TEXTURE, rotated_uv);
}
