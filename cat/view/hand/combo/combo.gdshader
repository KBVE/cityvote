shader_type canvas_item;

// Combo highlight shader - adds green outline to hex tiles
uniform vec4 outline_color : source_color = vec4(0.0, 1.0, 0.0, 1.0); // Green
uniform float outline_width : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.3;

void fragment() {
    vec4 color = texture(TEXTURE, UV);

    // Calculate distance to edge for outline
    vec2 size = vec2(textureSize(TEXTURE, 0));
    vec2 pixel_uv = UV * size;

    // Check if we're near the edge
    float edge_dist = min(
        min(pixel_uv.x, size.x - pixel_uv.x),
        min(pixel_uv.y, size.y - pixel_uv.y)
    );

    // Create pulsing effect
    float pulse = sin(TIME * pulse_speed) * pulse_intensity + (1.0 - pulse_intensity);

    // Apply outline
    if (edge_dist < outline_width && color.a > 0.1) {
        // Mix original color with outline color based on edge distance
        float outline_strength = smoothstep(outline_width, 0.0, edge_dist);
        COLOR = mix(color, outline_color, outline_strength * pulse);
    } else {
        COLOR = color;
    }
}
