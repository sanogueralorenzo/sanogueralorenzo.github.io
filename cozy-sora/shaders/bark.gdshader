shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://shared/surface_noise.gdshaderinc"

uniform vec4 bark_tint : source_color = vec4(0.38, 0.31, 0.24, 1.0);
uniform float furrow_scale = 1.0;
varying vec3 world;
varying vec3 world_normal;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float bark_relief(vec2 p) {
    p.x += (noise(p * vec2(2.4, 0.82)) - 0.5) * 0.17;
    float plates = noise(p * vec2(16.0, 2.2));
    float fibres = noise(p * vec2(82.0, 9.0) + 12.0);
    return 0.67 * smoothstep(0.29, 0.69, plates) + 0.33 * fibres;
}

void fragment() {
    vec3 axis = pow(abs(normalize(world_normal)), vec3(4.0));
    axis /= axis.x + axis.y + axis.z;
    float fissures = bark_relief(world.zy * furrow_scale) * axis.x
        + bark_relief(world.xz * furrow_scale) * axis.y
        + bark_relief(world.xy * furrow_scale) * axis.z;
    vec2 patch = vec2(world.x + world.z * 0.73, world.y);
    float lichen = smoothstep(0.55, 0.72, noise(patch * 2.7) * 0.65 + noise(patch * 14.0) * 0.35);
    float flecks = noise(patch * 110.0);
    vec3 open_bark = bark_tint.rgb * (0.44 + fissures * 0.94 + flecks * 0.14);
    ALBEDO = mix(open_bark, vec3(0.20, 0.21, 0.16), lichen * 0.61);
    NORMAL = relief_normal(VERTEX, NORMAL, fissures * 0.0065 + flecks * 0.0006);
    ROUGHNESS = 0.88;
    SPECULAR = 0.24;
}
