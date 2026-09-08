shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float school_time = 0.0;
uniform vec4 water_tint : source_color = vec4(0.30, 0.61, 0.61, 0.64);
varying float flank;

void vertex() {
    float tail = smoothstep(0.015, 0.18, VERTEX.z);
    float phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
    VERTEX.x += sin(school_time * 5.3 + VERTEX.z * 18.0 + phase) * 0.018 * tail;
    flank = clamp(0.5 + VERTEX.y * 18.0 - VERTEX.x * 2.0, 0.0, 1.0);
}

void fragment() {
    // A modest flank gradient, already tinted by water, keeps volume without dry bright highlights.
    ALBEDO = water_tint.rgb * mix(0.90, 1.03, flank);
    ALPHA = water_tint.a;
    ROUGHNESS = 1.0;
}
