shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shared/surface_noise.gdshaderinc"

uniform vec4 glass_tint : source_color = vec4(0.31, 0.38, 0.39, 1.0);
varying vec3 world;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 outward = abs(mat3(INV_VIEW_MATRIX) * NORMAL);
    vec2 pane = vec2(outward.x > outward.z ? world.z : world.x, world.y);
    float mottling = noise(pane * vec2(5.6, 0.77));
    float dust = smoothstep(0.42, 0.73, mottling);
    float room = 0.72 + 0.16 * noise(pane * vec2(7.9, 0.36) + 6.0);
    ALBEDO = glass_tint.rgb * room * (0.47 + 0.21 * dust);
    ROUGHNESS = mix(0.115, 0.235, dust);
    METALLIC = 0.32;
    SPECULAR = 0.5;
}
