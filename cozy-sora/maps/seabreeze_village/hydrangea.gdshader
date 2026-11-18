shader_type spatial;
render_mode cull_disabled, diffuse_burley;

varying vec3 pigment;

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float gust = sin(TIME * 1.6 + world.x * 0.9 + world.z * 1.1);
    float bend = VERTEX.y * VERTEX.y * 0.016;
    VERTEX.xz += bend * vec2(gust, sin(TIME * 1.2 + world.z * 0.7));
    pigment = COLOR.rgb;
}

void fragment() {
    float leaf = step(0.0, UV.y);
    float across = abs(UV.x);
    float trunk = 1.0 - smoothstep(0.015, 0.025 + fwidth(UV.x), across);
    float vein_distance = abs(sin((UV.y - 0.25 * across) * 28.0));
    float veins = (1.0 - smoothstep(0.025, 0.14 + fwidth(UV.y) * 28.0, vein_distance)) * (1.0 - across);
    vec3 green = pigment * (0.86 + 0.30 * trunk + 0.15 * veins);
    ALBEDO = mix(pigment, green, leaf);
    ROUGHNESS = mix(0.81, 0.51, leaf);
    SPECULAR = 0.28;
    BACKLIGHT = ALBEDO * vec3(0.42, 0.55, 0.21);
}
