shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

#include "res://source/presentation/sea-palette.gdshaderinc"

uniform float clock = 0.0;
uniform vec2 weather = vec2(0.0);
uniform vec2 sea_center = vec2(0.0);
uniform int whirlpool_count = 0;
uniform vec4 whirlpools[32];
varying vec3 world;

float hash_cell(vec2 p) {
    p = fract(p * vec2(.1031, .11369));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

float water_grain(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
               mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    for (int i = 0; i < whirlpool_count; i++) {
        if (distance(world.xz, whirlpools[i].xy) < whirlpools[i].z) discard;
    }

    vec2 sea = world.xz;
    float basin = .5 + .5 * sin(dot(sea, vec2(.175, .16))) * cos(dot(sea, vec2(-.13, .21)));
    vec3 base = mix(vec3(.035, .35, .40), vec3(.060, .455, .475), basin);
    float drift = clock * .44;
    float group = water_grain(sea * .315);
    float ripples = water_grain(sea * .79 + vec2(-drift * .066, drift * .035));
    vec2 bend = sea + vec2((group - .5) * 3.1, (ripples - .5) * 1.4);
    float front = dot(bend, vec2(.89, 1.72)) - drift
        + .56 * sin(dot(sea, vec2(.83, -.32)) + drift * .17);
    float roll = .5 + .5 * sin(front);
    float groups = smoothstep(.24, .72, group * .66 + ripples * .34);
    float fold = smoothstep(.28, .89, .5 + .5 * cos(dot(bend, vec2(1.90, -.45)) + group * 2.6));
    float crest = smoothstep(.83, .99, roll) * fold * groups;
    float rim = smoothstep(.968, 1.0, roll) * crest;
    float crossed = sin(dot(bend, vec2(1.22, -2.93)) + drift * .54);
    float eddy = smoothstep(.94, 1.0, crossed) * (1.0 - fold) * groups * .29;
    base += vec3(.011, .021, .028) * (roll - .44);
    base += vec3(.022, .055, .053) * (crest + eddy);
    base += vec3(.036, .065, .062) * rim;

    vec2 relative = sea - sea_center;
    float sun_lane = abs(relative.x + relative.y * .71 + 2.6 + sin(relative.y * .65) * .45);
    float reflection = (1.0 - smoothstep(.1, 3.1, sun_lane)) * (1.0 - weather.y);
    vec3 glint = mix(vec3(.38, .57, .45), vec3(.65, .51, .27), weather.x);
    vec3 water = mix(sea_weather(base, weather), glint, reflection * (.028 + (.09 + weather.x * .13) * rim));
    ALBEDO = linear_color(water);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
