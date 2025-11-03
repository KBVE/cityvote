shader_type canvas_item;

// Social logo atlas shader
// Displays a single logo from a horizontal sprite atlas (64x32)
// Layout: [Discord(32x32) | Twitch(32x32)]

// Logo selection parameter
uniform int logo_index = 0;  // 0 = Discord, 1 = Twitch
uniform int total_logos = 2;
uniform sampler2D atlas_texture;

void fragment() {
    // Calculate horizontal position in atlas
    // Each logo takes up 1/total_logos of the width
    float logo_width = 1.0 / float(total_logos);

    // Calculate UV offset for selected logo
    float uv_offset_x = float(logo_index) * logo_width;

    // Map UV coordinates to the selected logo region
    vec2 atlas_uv = vec2(
        uv_offset_x + (UV.x * logo_width),
        UV.y
    );

    // Sample the atlas texture at the correct position
    vec4 logo_color = texture(atlas_texture, atlas_uv);

    // Calculate circular mask with proper aspect ratio correction
    // Since we're displaying a square region from the atlas, use UV directly
    vec2 centered_uv = UV - vec2(0.5, 0.5);
    float dist = length(centered_uv);
    float radius = 0.5;
    float circle_mask = smoothstep(radius, radius - 0.02, dist);

    // Apply circular mask to alpha
    logo_color.a *= circle_mask;

    COLOR = logo_color;
}
