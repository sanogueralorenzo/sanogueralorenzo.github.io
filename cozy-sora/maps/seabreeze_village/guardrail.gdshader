shader_type spatial;
render_mode cull_disabled;
#include "res://shared/surface_noise.gdshaderinc"

void fragment() {
    vec2 p = UV;
    float fleck = noise(p * 170.0);
    float streak = noise(p * vec2(27.0, 2.6));
    float lap = min(fract(p.x / 3.0), 1.0 - fract(p.x / 3.0));
    float oxide = smoothstep(0.50, 0.79, streak + 0.16 * fleck)
        * (0.07 + 0.48 * exp(-lap * 70.0) + 0.25 * exp(-p.y * 19.0));
    vec3 zinc = vec3(0.43, 0.47, 0.48) * (0.87 + 0.22 * fleck + 0.09 * streak);
    ALBEDO = mix(zinc, vec3(0.22, 0.10, 0.042), oxide);
    ROUGHNESS = 0.38 + fleck * 0.14 + oxide * 0.35;
    METALLIC = 0.79 - oxide * 0.57;
}
