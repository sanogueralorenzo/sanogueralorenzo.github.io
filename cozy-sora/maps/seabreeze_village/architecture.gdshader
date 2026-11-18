shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shared/surface_noise.gdshaderinc"
#include "res://shared/facade_weathering.gdshaderinc"

uniform vec4 pigment : source_color;
uniform int finish = 0;
varying vec3 world;
varying vec3 world_normal;

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float grain(vec2 p) {
    float twist = noise(p * vec2(2.8, 0.7)) - 0.5;
    return noise(vec2(p.x * 42.0 + twist * 2.6, p.y * 3.5));
}

void fragment() {
    vec3 outward = abs(normalize(world_normal));
    vec2 p = outward.y > 0.61 ? world.xz : vec2(outward.x > outward.z ? world.z : world.x, world.y);
    float rubble = plaster_texture(p);
    float runoff = wall_runoff(p);
    vec3 color = pigment.rgb * (0.82 + rubble * 0.24 - runoff * 0.24);
    float micro = rubble * 0.003;
    float sheen = 0.9;

    if (finish == 1) {
        vec2 board = vec2(p.x / 0.21, p.y / 2.6);
        float line = seam(board.x, 0.028);
        float end = seam(board.y + hash(vec2(floor(board.x), 7.0)), 0.003);
        float fiber = grain(p);
        float shade = hash(vec2(floor(board.x), floor(board.y)));
        color *= 0.68 + shade * 0.28 + fiber * 0.34 - max(line, end) * 0.37;
        micro += fiber * 0.003 - max(line, end) * 0.005;
        sheen = 0.75 + runoff * 0.12;
    }
    if (finish == 2) {
        float track = p.x / 0.19;
        float ridge = pow(0.5 + 0.5 * cos(track * TAU), 7.0);
        ridge = mix(ridge, 0.21, smoothstep(0.18, 0.5, fwidth(track)));
        float oxide = smoothstep(0.37, 0.72, runoff * 0.55 + noise(p * 4.2) * 0.53);
        color = mix(color * (0.78 + ridge * 0.29), vec3(0.12, 0.064, 0.033), oxide * 0.39);
        micro += ridge * 0.017;
        METALLIC = 0.52 - oxide * 0.34;
        sheen = 0.48 + oxide * 0.31;
    }
    if (finish == 3) {
        vec2 tile = UV * vec2(8.95, 7.15);
        float roll = 0.5 + 0.5 * cos(tile.x * TAU);
        roll = mix(roll, 0.5, smoothstep(0.18, 0.5, fwidth(tile.x)));
        float overlap = seam(tile.y, 0.055);
        float firing = hash(floor(tile));
        firing = mix(firing, 0.5, smoothstep(0.14, 0.6, max(fwidth(tile.x), fwidth(tile.y))));
        color *= 0.75 + firing * 0.35 + roll * 0.1 - overlap * 0.25;
        micro += roll * 0.019 - overlap * 0.006;
        sheen = mix(0.48, 0.72, firing);
    }
    if (finish == 4) {
        vec2 block = p * vec2(2.25, 3.55);
        block += vec2(mod(floor(block.y), 2.0) * 0.5, 0.0);
        block += vec2(noise(p * 7.0), noise(p * 8.0 + 13.0)) * 0.12;
        float joint = max(seam(block.x, 0.038), seam(block.y, 0.044));
        float stone = hash(floor(block));
        color = mix(color * (0.61 + stone * 0.61), vec3(0.145, 0.132, 0.11), joint * 0.77);
        micro += stone * 0.004 - joint * 0.012;
    }
    if (finish == 5) {
        float fibre = grain(p * 0.68);
        float node = seam(p.y * 3.5, 0.043);
        color *= 0.87 + fibre * 0.27 - node * 0.32;
        micro += fibre * 0.003 - node * 0.006;
    }
    if (finish == 6) {
        float grit = noise(p * 56.0);
        color *= 0.68 + grit * 0.40;
        micro += grit * 0.0036;
    }
    ALBEDO = color;
    NORMAL = relief_normal(VERTEX, NORMAL, micro);
    ROUGHNESS = sheen;
    SPECULAR = 0.28;
}
