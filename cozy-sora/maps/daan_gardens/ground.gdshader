shader_type spatial;
render_mode specular_disabled;
#include "res://shared/surface_noise.gdshaderinc"

varying vec3 world;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world.xz;
    float clover = noise(p * 0.76) * 0.55 + noise(p * 2.65) * 0.45;
    float moisture = noise(p * 0.14) * 0.64 + noise(p * 0.47 + 17.0) * 0.36;
    float roots = noise(p * 18.0);
    float grit = noise(p * 69.0 + 21.0);
    float thin = smoothstep(0.49, 0.73, clover + 0.12 * roots) * (1.0 - moisture);
    vec3 sod = mix(vec3(0.29, 0.34, 0.19), vec3(0.37, 0.46, 0.25), moisture);
    vec3 soil = vec3(0.37, 0.32, 0.235) * (0.71 + 0.30 * roots);
    ALBEDO = pow(mix(sod, soil, thin) * (0.82 + 0.23 * roots + 0.14 * grit), vec3(2.2));
    NORMAL = relief_normal(VERTEX, NORMAL, roots * 0.004 + grit * 0.0018);
    ROUGHNESS = 0.94;
}
