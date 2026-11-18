shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shared/water_waves.gdshaderinc"
varying vec3 world;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float depth_color = 0.5 + 0.5 * sin(world.x * 0.13 + world.z * 0.16);
    ALBEDO = mix(vec3(0.012, 0.033, 0.021), vec3(0.030, 0.062, 0.033), depth_color);
    NORMAL = normalize(mat3(VIEW_MATRIX) * water_normal(world.xz * 1.7, TIME * 0.65, 0.48));
    ROUGHNESS = 0.105;
    SPECULAR = 0.28;
}
