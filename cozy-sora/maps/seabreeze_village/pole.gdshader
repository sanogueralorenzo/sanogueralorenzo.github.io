shader_type spatial;
#include "res://shared/surface_noise.gdshaderinc"
varying vec3 world;
void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 face = vec2(world.x + world.z, world.y);
    float runoff = noise(face * vec2(12.0, 0.75));
    float pores = noise(face * 95.0);
    float base = 1.0 - smoothstep(0.02, 0.34, UV.y);
    ALBEDO = mix(vec3(0.255, 0.246, 0.216), vec3(0.34, 0.34, 0.313), runoff);
    ALBEDO *= 0.87 + pores * 0.21 - base * 0.055;
    ROUGHNESS = 0.87;
}
