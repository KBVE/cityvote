shader_type canvas_item;

// Card atlas shader
// Displays a single card from a 13x5 grid atlas (1248x720)
// Rows 0-3: Standard suits (clubs, diamonds, hearts, spades)
// Row 4: Custom cards (vikings-53, dino-54)

// Card selection parameters (instance uniform for per-instance values)
instance uniform int card_id = 0;  // 0-51 for standard, 52-53 for custom

// Atlas dimensions
const float COLS = 13.0;
const float ROWS = 5.0;

void fragment() {
    // Calculate which card to display
    float col = mod(float(card_id), COLS);
    float row = floor(float(card_id) / COLS);

    // Calculate UV offset and scale for this card
    vec2 uv_scale = vec2(1.0 / COLS, 1.0 / ROWS);
    vec2 uv_offset = vec2(col / COLS, row / ROWS);

    // Flip V coordinate for MeshInstance2D (QuadMesh has inverted Y compared to Sprite2D)
    vec2 flipped_uv = vec2(UV.x, 1.0 - UV.y);

    // Sample the texture at the correct position
    vec2 atlas_uv = uv_offset + (flipped_uv * uv_scale);
    vec4 card = texture(TEXTURE, atlas_uv);

    COLOR = card;
}
