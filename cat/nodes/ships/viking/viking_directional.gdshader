// Viking directional sprite shader with wave motion
// Handles 16-directional sprites (4x4 atlas) with water wave animation
shader_type canvas_item;

// Wave movement parameters
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float wave_amplitude : hint_range(0.0, 20.0) = 1.5;
uniform float sway_amplitude : hint_range(0.0, 10.0) = 1.0;
uniform float wave_frequency : hint_range(0.0, 10.0) = 1.2;
uniform float rotation_amount : hint_range(0.0, 10.0) = 0.8;

// Direction parameter (0-15 for 16 directions)
uniform int direction : hint_range(0, 15) = 0;

// Atlas layout: 4x4 grid (16 sprites)
const int ATLAS_COLS = 4;
const int ATLAS_ROWS = 4;

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
	// Calculate which cell in the atlas based on direction
	int col = direction % ATLAS_COLS;
	int row = direction / ATLAS_COLS;

	// Calculate cell dimensions
	float cell_width = 1.0 / float(ATLAS_COLS);
	float cell_height = 1.0 / float(ATLAS_ROWS);

	// Map UV to the correct cell in the atlas
	// First scale UV to fit within one cell, then offset to the correct cell position
	vec2 cell_uv = vec2(
		(UV.x * cell_width) + (float(col) * cell_width),
		(UV.y * cell_height) + (float(row) * cell_height)
	);

	// Sample the texture at the adjusted UV
	COLOR = texture(TEXTURE, cell_uv);
}
