shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform float clock = 0.0;
uniform float storm = 0.0;
uniform int whirlpool_count = 0;
uniform vec4 whirlpools[32];
varying vec3 world;

vec3 linear_color(vec3 color) {
    return mix(color / 12.92, pow((color + vec3(.055)) / 1.055, vec3(2.4)), step(vec3(.04045), color));
}

void vertex() {
    world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    for (int i = 0; i < whirlpool_count; i++) {
        if (distance(world.xz, whirlpools[i].xy) < whirlpools[i].z) discard;
    }

    vec2 sea = world.xz;
    float basin = .5 + .5 * sin(sea.x * .14 + sea.y * .18) * sin(sea.y * .19 - sea.x * .12);
    float drift = clock * mix(.37, .72, storm);
    float swell = sin(sea.x * .68 + sea.y * .94 - drift + sin(sea.y * .48 + sea.x * .13) * .93);
    float crossing = sin(sea.x * .43 - sea.y * 1.13 + drift * .39);
    float crest = smoothstep(.75, .98, swell * .78 + crossing * .22);
    float gaps = smoothstep(.18, .88, sin(sea.x * .59 - sea.y * .28 + drift * .20));
    vec3 deep = mix(vec3(.025, .34, .39), vec3(.039, .19, .31), storm);
    vec3 light = mix(vec3(.056, .48, .48), vec3(.12, .34, .44), storm);
    vec3 water = mix(deep, light, basin);
    water += vec3(.06, .115, .105) * crest * gaps;
    ALBEDO = linear_color(water);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
