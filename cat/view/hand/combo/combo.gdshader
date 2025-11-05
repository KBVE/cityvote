shader_type canvas_item;

// Combo highlight shader - adds bright glowing effect to entire card
uniform vec4 highlight_color : source_color = vec4(0.3, 1.0, 0.3, 1.0); // Bright green
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.6;

void fragment() {
    vec4 color = texture(TEXTURE, UV);

    // Create pulsing effect
    float pulse = sin(TIME * pulse_speed) * pulse_intensity + (1.0 - pulse_intensity);

    // Apply glow to entire card (not just edges)
    // This makes the highlight very obvious for combo detection
    if (color.a > 0.1) {
        // Add bright green tint with pulsing
        vec4 glowing = mix(color, highlight_color, glow_strength * pulse);
        // Brighten the result
        glowing.rgb *= (1.0 + pulse * 0.5);
        COLOR = glowing;
    } else {
        COLOR = color;
    }
}
